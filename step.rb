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

def to_bool(value)
  return true if value == true || value =~ (/^(true|t|yes|y|1)$/i)
  return false if value == false || value.nil? || value == '' || value =~ (/^(false|f|no|n|0)$/i)
  fail_with_message("Invalid value for Boolean: \"#{value}\"")
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
    params << 'xbuild'
    params << "\"#{project_path}\""
    params << '/t:Build'
    params << "/p:Configuration=\"#{configuration}\""
    params << "/p:Platform=\"#{platform}\""
    params << '/p:BuildIpa=true'
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
    system("xcrun -sdk iphoneos PackageApplication -v \"#{app_file}\" -o \"#{ipa_path}\"")
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
    params << "--configuration:\"#{configuration}|#{platform}\"" unless is_test
    params << "--configuration:\"#{configuration}\"" if is_test
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
  test_cloud_api_key: nil,
  xamarin_user: nil,
  test_cloud_devices: nil,
  test_cloud_app_name: nil,
  test_cloud_is_async: true,
  test_cloud_category: nil,
  test_cloud_fixture: nil,
  test_cloud_series: nil,
  test_cloud_parallelization: nil
}

parser = OptionParser.new do|opts|
  opts.banner = 'Usage: step.rb [options]'
  opts.on('-s', '--project path', 'Project path') { |s| options[:project] = s unless s.to_s == '' }
  opts.on('-t', '--test project', 'Test project') { |t| options[:test_project] = t unless t.to_s == '' }
  opts.on('-c', '--configuration config', 'Configuration') { |c| options[:configuration] = c unless c.to_s == '' }
  opts.on('-p', '--platform platform', 'Platform') { |p| options[:platform] = p unless p.to_s == '' }
  opts.on('-b', '--builder builder', 'Builder') { |b| options[:builder] = b unless b.to_s == '' }
  opts.on('-i', '--clean build', 'Clean build') { |i| options[:clean_build] = false if to_bool(i) == false }
  opts.on('-a', '--api key', 'Api key') { |a| options[:test_cloud_api_key] = a unless a.to_s == '' }
  opts.on('-u', '--xamarin_user xamarin_user', 'User') { |u| options[:xamarin_user] = u unless u.to_s == '' }
  opts.on('-d', '--test_cloud_devices test_cloud_devices', 'Devices') { |d| options[:test_cloud_devices] = d unless d.to_s == '' }
  opts.on('-n', '--app name', 'App name') { |n| options[:test_cloud_app_name] = n unless n.to_s == '' }
  opts.on('-y', '--test_cloud_is_async test_cloud_is_async', 'Async') { |y| options[:test_cloud_is_async] = false if to_bool(y) == false }
  opts.on('-e', '--test_cloud_category test_cloud_category', 'Category') { |e| options[:test_cloud_category] = e unless e.to_s == '' }
  opts.on('-f', '--test_cloud_fixture test_cloud_fixture', 'Fixture') { |f| options[:test_cloud_fixture] = f unless f.to_s == '' }
  opts.on('-r', '--test_cloud_series test_cloud_series', 'Series') { |r| options[:test_cloud_series] = r unless r.to_s == '' }
  opts.on('-l', '--test_cloud_parallelization test_cloud_parallelization', 'Parallelization') { |l| options[:test_cloud_parallelization] = l unless l.to_s == '' }
  opts.on('-h', '--help', 'Displays Help') do
    exit
  end
end
parser.parse!

fail_with_message('No project file found') unless options[:project] && File.exist?(options[:project])
fail_with_message('No test_project file found') unless options[:test_project] && File.exist?(options[:test_project])
fail_with_message('configuration not specified') unless options[:configuration]
fail_with_message('platform not specified') unless options[:platform]
fail_with_message('test_cloud_api_key not specified') unless options[:test_cloud_api_key]
fail_with_message('xamarin_user not specified') unless options[:xamarin_user]
fail_with_message('test_cloud_devices not specified') unless options[:test_cloud_devices]

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
puts ' * test_cloud_api_key: ***'
puts " * xamarin_user: #{options[:xamarin_user]}"
puts " * test_cloud_devices: #{options[:test_cloud_devices]}"
puts " * test_cloud_app_name: #{options[:test_cloud_app_name]}"
puts " * test_cloud_is_async: #{options[:test_cloud_is_async]}"
puts " * test_cloud_category: #{options[:test_cloud_category]}"
puts " * test_cloud_fixture: #{options[:test_cloud_fixture]}"
puts " * test_cloud_series: #{options[:test_cloud_series]}"
puts " * test_cloud_parallelization: #{options[:test_cloud_parallelization]}"

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
request = "#{@mono} #{test_cloud} submit #{ipa_path} #{options[:test_cloud_api_key]}"
request += " --user #{options[:xamarin_user]}"
request += " --assembly-dir #{assembly_dir}"
request += " --devices #{options[:test_cloud_devices]}"
request += " --app-name \"#{options[:test_cloud_app_name]}\"" if options[:test_cloud_app_name]
request += ' --async' if options[:test_cloud_is_async]
request += " --category #{options[:test_cloud_category]}" if options[:test_cloud_category]
request += " --fixture #{options[:test_cloud_fixture]}" if options[:test_cloud_fixture]
request += " --series #{options[:test_cloud_series]}" if options[:test_cloud_series]
request += " --dsym #{options[:dsym]}" if options[:dsym]
request += " --nunit-xml #{result_log}"
if options[:test_cloud_parallelization]
  request += ' --fixture-chunk' if options[:test_cloud_parallelization] == 'by_test_fixture'
  request += ' --test-chunk' if options[:test_cloud_parallelization] == 'by_test_chunk'
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
