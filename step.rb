require 'optparse'
require 'pathname'

@mdtool = "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\""
@mono = '/Library/Frameworks/Mono.framework/Versions/Current/bin/mono'
@nuget = '/Library/Frameworks/Mono.framework/Versions/Current/bin/nuget'

# -----------------------
# --- functions
# -----------------------

def fail_with_message(message)
  system('envman add --key BITRISE_XAMARIN_TEST_RESULT --value failed')

  puts "\e[31m#{message}\e[0m"
  exit(1)
end

def error_with_message(message)
  puts "\e[31m#{message}\e[0m"
end

def get_related_solutions(project_path)
  project_name = File.basename(project_path)
  project_dir = File.dirname(project_path)
  root_dir = File.dirname(project_dir)
  solutions = Dir[File.join(root_dir, '/**/*.sln')]
  return [] unless solutions

  related_solutions = []
  solutions.each do |solution|
    File.readlines(solution).join("\n").scan(/Project\(\"[^\"]*\"\)\s*=\s*\"[^\"]*\",\s*\"([^\"]*.csproj)\"/).each do |match|
      a_project = match[0].strip.gsub(/\\/, '/')
      a_project_name = File.basename(a_project)

      related_solutions << solution if a_project_name == project_name
    end
  end

  return related_solutions
end

def archive_project!(builder, project_path, configuration, platform)
  # Build project
  output_path = File.join('bin', platform, configuration)

  params = []
  case builder
  when 'xbuild'
    params << "\"#{builder}\""
    params << "\"#{project_path}\""
    params << '/t:Build'
    params << "/p:Configuration=\"#{configuration}\""
    params << "/p:Platform=\"#{platform}\""
    params << "/p:BuildIpa=\"true\""
    params << "/p:OutputPath=\"#{output_path}/\""
  when 'mdtool'
    params << "#{@mdtool}"
    params << '-v build'
    params << "\"#{project_path}\""
    params << "--configuration:\"#{configuration}|#{platform}\""
    params << '--target:Build'
  else
    fail_with_message('Invalid build tool detected')
  end

  puts "#{params.join(' ')}"
  system("#{params.join(' ')}")
  fail_with_message('Build failed') unless $?.success?

  # Get the build path
  project_directory = File.dirname(project_path)
  build_path = File.join(project_directory, output_path)

  # Get the ipa path
  ipa_path = ''
  if builder.eql? 'mdtool'
    app_file = Pathname.new(Dir[File.join(build_path, '/**/*.app')].first).realpath.to_s
    app_name = File.basename(app_file, '.*')
    app_directory = File.dirname(app_file)
    ipa_path = File.join(app_directory, "#{app_name}.ipa")

    puts
    puts '==> Packaging application'
    puts "xcrun -sdk iphoneos PackageApplication -v \"#{app_file}\" -o \"#{ipa_path}\""
    system("xcrun -sdk iphoneos PackageApplication -v #{app_file} -o #{ipa_path}")
    fail_with_message('Failed to create .ipa from .app') unless $?.success?
  else
    ipa_path = Dir[File.join(build_path, '/**/*.ipa')].first
  end

  # Get dSYM path
  dsym_path = Dir[File.join("#{build_path}", '/**/*.app.dSYM')].first

  return ipa_path, dsym_path
end

def build_project!(builder, project_path, configuration, platform)
  # Build project
  output_path = File.join('bin', platform, configuration)

  params = []
  case builder
  when 'xbuild'
    params << 'xbuild'
    params << "\"#{project_path}\""
    params << '/t:Build'
    params << "/p:Configuration=\"#{configuration}\""
    params << "/p:Platform=\"#{platform}\""
    params << "/p:OutputPath=\"#{output_path}/\""
  when 'mdtool'
    params << "#{@mdtool}"
    params << '-v build'
    params << "\"#{project_path}\""
    params << "--configuration:\"#{configuration}\"|\"#{platform}\""
    params << '--target:Build'
  else
    fail_with_message('Invalid build tool detected')
  end

  puts "#{params.join(' ')}"
  system("#{params.join(' ')}")
  fail_with_message('Build failed') unless $?.success?

  # Get the build path
  project_directory = File.dirname(project_path)
  File.join(project_directory, output_path)
end

def clean_project!(builder, project_path, configuration, platform, is_test)
  # clean project
  params = []
  case builder
  when 'xbuild'
    params << 'xbuild'
    params << "\"#{project_path}\""
    params << '/t:Clean'
    params << "/p:Configuration=\"#{configuration}\""
    params << "/p:Platform=\"#{platform}\"" unless is_test
  when 'mdtool'
    params << "#{@mdtool}"
    params << '-v build'
    params << "\"#{project_path}\""
    params << '--target:Clean'
    param_configuration = "--configuration:\"#{configuration}\""
    param_configuration += "|\"#{platform}\"" unless is_test
    params << param_configuration
  else
    fail_with_message('Invalid build tool detected')
  end

  puts "#{params.join(' ')}"
  system("#{params.join(' ')}")
  fail_with_message('Clean failed') unless $?.success?
end

# -----------------------
# --- main
# -----------------------

#
# Input validation
options = {
  project: nil,
  test_project: nil,
  configuration: nil,
  platform: nil,
  builder: nil,
  clean_build: true,
  api_key: nil,
  user: nil,
  devices: nil,
  app_name: nil,
  async: nil,
  category: nil,
  fixture: nil,
  series: nil,
  parallelization: nil
}

parser = OptionParser.new do|opts|
  opts.banner = 'Usage: step.rb [options]'
  opts.on('-s', '--project path', 'Project path') { |s| options[:project] = s unless s.to_s == '' }
  opts.on('-t', '--test project', 'Test project') { |t| options[:test_project] = t unless t.to_s == '' }
  opts.on('-c', '--configuration config', 'Configuration') { |c| options[:configuration] = c unless c.to_s == '' }
  opts.on('-p', '--platform platform', 'Platform') { |p| options[:platform] = p unless p.to_s == '' }
  opts.on('-b', '--builder builder', 'Builder') { |b| options[:builder] = b unless b.to_s == '' }
  opts.on('-i', '--clean build', 'Clean build') { |i| options[:clean_build] = false if i.to_s == 'no' }
  opts.on('-a', '--api key', 'Api key') { |a| options[:api_key] = a unless a.to_s == '' }
  opts.on('-u', '--user user', 'User') { |u| options[:user] = u unless u.to_s == '' }
  opts.on('-d', '--devices devices', 'Devices') { |d| options[:devices] = d unless d.to_s == '' }
  opts.on('-n', '--app name', 'App name') { |n| options[:app_name] = n unless n.to_s == '' }
  opts.on('-y', '--async async', 'Async') { |y| options[:async] = y unless y.to_s == '' }
  opts.on('-e', '--category category', 'Category') { |e| options[:category] = e unless e.to_s == '' }
  opts.on('-f', '--fixture fixture', 'Fixture') { |f| options[:fixture] = f unless f.to_s == '' }
  opts.on('-r', '--series series', 'Series') { |r| options[:series] = r unless r.to_s == '' }
  opts.on('-l', '--parallelization parallelization', 'Parallelization') { |l| options[:parallelization] = l unless l.to_s == '' }
  opts.on('-h', '--help', 'Displays Help') do
    exit
  end
end
parser.parse!

fail_with_message('No project file found') unless options[:project] && File.exist?(options[:project])
fail_with_message('No test_project file found') unless options[:test_project] && File.exist?(options[:test_project])
fail_with_message('configuration not specified') unless options[:configuration]
fail_with_message('platform not specified') unless options[:platform]
fail_with_message('api_key not specified') unless options[:api_key]
fail_with_message('user not specified') unless options[:user]
fail_with_message('devices not specified') unless options[:devices]

#
# Print configs
puts
puts '========== Configs =========='
puts " * project: #{options[:project]}"
puts " * test_project: #{options[:test_project]}"
puts " * configuration: #{options[:configuration]}"
puts " * platform: #{options[:platform]}"
puts " * builder: #{options[:builder]}"
puts " * clean_build: #{options[:clean_build]}"
puts " * api_key: #{options[:api_key]}"
puts " * user: #{options[:user]}"
puts " * devices: #{options[:devices]}"
puts " * app_name: #{options[:app_name]}"
puts " * async: #{options[:async]}"
puts " * category: #{options[:category]}"
puts " * fixture: #{options[:fixture]}"
puts " * series: #{options[:series]}"
puts " * parallelization: #{options[:parallelization]}"

#
# Restoring nuget packages
puts ''
puts '==> Restoring nuget packages'
project_solutions = get_related_solutions(options[:project])
puts "No solution found for project: #{options[:project]}, terminating nuget restore..." if project_solutions.empty?

test_project_solutions = get_related_solutions(options[:test_project])
puts "No solution found for project: #{options[:test_project]}, terminating nuget restore..." if test_project_solutions.empty?

solutions = project_solutions | test_project_solutions
solutions.each do |solution|
  puts "(i) solution: #{solution}"
  puts "#{@nuget} restore #{solution}"
  system("#{@nuget} restore #{solution}")
  error_with_message('Failed to restore nuget package') unless $?.success?
end

if options[:clean_build]
  #
  # Cleaning the project
  puts
  puts "==> Cleaning project: #{options[:project]}"
  clean_project!(options[:builder], options[:project], options[:configuration], options[:platform], false)

  puts
  puts "==> Cleaning test project: #{options[:test_project]}"
  clean_project!(options[:builder], options[:test_project], options[:configuration], options[:platform], true)
end

#
# Archive project
puts
puts "==> Archive project: #{options[:project]}"
ipa_path, dsym_path = archive_project!(options[:builder], options[:project], options[:configuration], options[:platform])
fail_with_message('Failed to locate ipa path') unless ipa_path && File.exist?(ipa_path)
puts "  (i) ipa_path path: #{ipa_path}"
puts "  (i) dsym_path path: #{dsym_path}"

#
# Build UITest
puts
puts "==> Building test project: #{options[:test_project]}"
assembly_dir = build_project!(options[:builder], options[:test_project], options[:configuration], options[:platform])
fail_with_message('failed to get test assembly path') unless assembly_dir && File.exist?(assembly_dir)
options[:dsym] = dsym_path if dsym_path && File.exist?(dsym_path)

#
# Get test cloud path
project_dir = File.dirname(options[:project])
root_dir = File.dirname(project_dir)
test_clouds = Dir[File.join(root_dir, 'packages/Xamarin.UITest.*/tools/test-cloud.exe')]
fail_with_message('No test-cloud.exe found') unless test_clouds && !test_clouds.empty?
fail_with_message('No test-cloud.exe found') unless File.exist?(test_clouds.first)
test_cloud = test_clouds.first
puts "  (i) test_cloud path: #{test_cloud}"

work_dir = ENV['BITRISE_SOURCE_DIR']
result_log = File.join(work_dir, 'TestResult.xml')

#
# Build Request
request = "mono #{test_cloud} submit #{ipa_path} #{options[:api_key]}"
request += " --user #{options[:user]}"
request += " --assembly-dir #{assembly_dir}"
request += " --devices #{options[:devices]}"
request += " --app-name \"#{options[:app_name]}\"" if options[:app_name]
request += ' --async' if options[:async] && options[:async].eql?('yes')
request += " --category #{options[:category]}" if options[:category]
request += " --fixture #{options[:fixture]}" if options[:fixture]
request += " --series #{options[:series]}" if options[:series]
request += " --dsym #{options[:dsym]}" if options[:dsym]
request += " --nunit-xml #{result_log}"
if options[:parallelization]
  request += ' --fixture-chunk' if options[:parallelization] == 'by_test_fixture'
  request += ' --test-chunk' if options[:parallelization] == 'by_test_chunk'
end

puts
puts "request: #{request}"
system(request)
test_success = $?.success?

if test_success
  puts
  puts '(i) The result is: succeeded'
  system('envman add --key BITRISE_XAMARIN_TEST_RESULT --value succeeded') if work_dir

  puts
  puts "(i) The test log is available at: #{result_log}"
  system("envman add --key BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT --value #{result_log}") if work_dir
else
  puts
  puts "(i) The test log is available at: #{result_log}"
  system("envman add --key BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT --value #{result_log}") if work_dir

  fail_with_message('test failed')
end
