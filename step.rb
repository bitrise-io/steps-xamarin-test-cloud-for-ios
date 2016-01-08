require 'optparse'
require 'pathname'

require_relative 'xamarin-builder/builder'

# -----------------------
# --- Constants
# -----------------------

@mdtool = "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\""
@nuget = '/Library/Frameworks/Mono.framework/Versions/Current/bin/nuget'

@work_dir = ENV['BITRISE_SOURCE_DIR']
@result_log_path = File.join(@work_dir, 'TestResult.xml')

# -----------------------
# --- Functions
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
  return false if value == false || value.nil? || value =~ (/^(false|f|no|n|0)$/i)
  fail_with_message("Invalid value for Boolean: \"#{value}\"")
end

# -----------------------
# --- Main
# -----------------------

#
# Parse options
options = {
    project: nil,
    configuration: nil,
    platform: nil,
    clean_build: true,
    api_key: nil,
    user: nil,
    devices: nil,
    async: true,
    series: 'master',
    parallelization: nil,
    other_parameters: nil
}

parser = OptionParser.new do |opts|
  opts.banner = 'Usage: step.rb [options]'
  opts.on('-s', '--project path', 'Project path') { |s| options[:project] = s unless s.to_s == '' }
  opts.on('-c', '--configuration config', 'Configuration') { |c| options[:configuration] = c unless c.to_s == '' }
  opts.on('-p', '--platform platform', 'Platform') { |p| options[:platform] = p unless p.to_s == '' }
  opts.on('-i', '--clean build', 'Clean build') { |i| options[:clean_build] = false unless to_bool(i) }
  opts.on('-a', '--api key', 'Api key') { |a| options[:api_key] = a unless a.to_s == '' }
  opts.on('-u', '--user user', 'User') { |u| options[:user] = u unless u.to_s == '' }
  opts.on('-d', '--devices devices', 'Devices') { |d| options[:devices] = d unless d.to_s == '' }
  opts.on('-y', '--async async', 'Async') { |y| options[:async] = false unless to_bool(y) }
  opts.on('-r', '--series series', 'Series') { |r| options[:series] = r unless r.to_s == '' }
  opts.on('-l', '--parallelization parallelization', 'Parallelization') { |l| options[:parallelization] = l unless l.to_s == '' }
  opts.on('-g', '--sign parameters', 'Sign') { |g| options[:sign_parameters] = g unless g.to_s == '' }
  opts.on('-m', '--other parameters', 'Other') { |m| options[:other_parameters] = m unless m.to_s == '' }
  opts.on('-h', '--help', 'Displays Help') do
    exit
  end
end
parser.parse!

#
# Print options
puts
puts '========== Configs =========='
puts " * project: #{options[:project]}"
puts " * configuration: #{options[:configuration]}"
puts " * platform: #{options[:platform]}"
puts " * clean_build: #{options[:clean_build]}"
puts ' * api_key: ***'
puts " * user: #{options[:user]}"
puts " * devices: #{options[:devices]}"
puts " * async: #{options[:async]}"
puts " * series: #{options[:series]}"
puts " * parallelization: #{options[:parallelization]}"
puts " * other_parameters: #{options[:other_parameters]}"

#
# Validate options
fail_with_message('No project file found') unless options[:project] && File.exist?(options[:project])
fail_with_message('configuration not specified') unless options[:configuration]
fail_with_message('platform not specified') unless options[:platform]
fail_with_message('api_key not specified') unless options[:api_key]
fail_with_message('user not specified') unless options[:user]
fail_with_message('devices not specified') unless options[:devices]

#
# Main
projects_to_test = []

if File.extname(options[:project]) == '.sln'
  analyzer = SolutionAnalyzer.new(options[:project])

  projects = analyzer.collect_projects(options[:configuration], options[:platform])
  test_projects = analyzer.collect_test_projects(options[:configuration], options[:platform])

  projects.each do |project|

    next if project[:api] != MONOTOUCH_API_NAME && project[:api] != XAMARIN_IOS_API_NAME

    test_projects.each do |test_project|
      referred_project_ids = ProjectAnalyzer.new(test_project[:path]).parse_referred_project_ids
      referred_project_ids.each do |project_id|
        puts
        puts "#{project_id} - #{project[:id]}"

        if project_id == project[:id]
          projects_to_test << {
              project: project,
              test_project: test_project,
          }
        end
      end
    end
  end
else
  analyzer = ProjectAnalyzer.new(options[:project])
  project = analyzer.analyze(options[:configuration], options[:platform])

  solution_path = analyzer.parse_solution_path
  analyzer = SolutionAnalyzer.new(solution_path)

  test_projects = analyzer.collect_test_projects(options[:configuration], options[:platform])

  test_projects.each do |test_project|
    referred_project_ids = ProjectAnalyzer.new(test_project[:path]).parse_referred_project_ids
    referred_project_ids.each do |project_id|
      if project_id == project[:id]
        projects_to_test << {
            project: project,
            test_project: test_project,
        }
      end
    end
  end
end

fail 'No project and related test project found' if projects_to_test.count == 0

projects_to_test.each do |project_to_test|
  project = project_to_test[:project]
  test_project = project_to_test[:test_project]

  puts
  puts " ** project to test: #{project[:path]}"
  puts " ** related test project: #{test_project[:path]}"

  builder = Builder.new(project[:path], project[:configuration], project[:platform])
  test_builder = Builder.new(test_project[:path], test_project[:configuration], test_project[:platform])

  if options[:clean_build]
    builder.clean!
    test_builder.clean!
  end

  #
  # Build project
  puts
  puts "==> Building project: #{project[:path]}"

  built_projects = builder.build!

  ipa_path = ''
  dsym_path = ''

  built_projects.each do |built_project|
    if built_project[:api] == MONOTOUCH_API_NAME || built_project[:api] == XAMARIN_IOS_API_NAME && built_project[:build_ipa]
      ipa_path = builder.export_ipa(built_project[:output_path])
      puts "  (i) ipa_path: #{ipa_path}"

      dsym_path = builder.export_dsym(built_project[:output_path])
      puts "  (i) dsym_path: #{dsym_path}"
    end
  end

  #
  # Build UITest
  puts
  puts "==> Building test project: #{test_project}"

  built_test_projects = test_builder.build!

  assembly_dir = ''

  built_test_projects.each do |built_test_project|
    if built_test_project[:api] == XAMARIN_UITEST_API
      dll_path = test_builder.export_dll(built_test_project[:output_path])
      assembly_dir = File.dirname(dll_path)
      puts "  (i) dll_path: #{dll_path}"
    end

  end

  #
  # Get test cloud path
  test_cloud = Dir[File.join(@work_dir, '/**/packages/Xamarin.UITest.*/tools/test-cloud.exe')].last
  fail_with_message('No test-cloud.exe found') unless test_cloud
  puts "  (i) test_cloud path: #{test_cloud}"

  #
  # Build Request
  request = "mono #{test_cloud} submit #{ipa_path} #{options[:api_key]}"
  request += " --user #{options[:user]}"
  request += " --assembly-dir #{assembly_dir}"
  request += " --devices #{options[:devices]}"
  request += ' --async' if options[:async]
  request += " --series #{options[:series]}" if options[:series]
  request += " --dsym #{dsym_path}" if dsym_path
  request += " --nunit-xml #{@result_log_path}"
  request += ' --fixture-chunk' if options[:parallelization] == 'by_test_fixture'
  request += ' --test-chunk' if options[:parallelization] == 'by_test_chunk'
  request += " #{options[:other_parameters]}" if options[:other_parameters]

  puts
  puts "request: #{request}"
  system(request)

  unless $?.success?
    file = File.open(@result_log_path)
    contents = file.read
    file.close

    puts
    puts "result: #{contents}"
    puts

    fail_with_message("#{command} -- failed")
  end
end

#
# Set output envs
puts
puts '(i) The result is: succeeded'
system('envman add --key BITRISE_XAMARIN_TEST_RESULT --value succeeded')

puts
puts "(i) The test log is available at: #{@result_log_path}"
system("envman add --key BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT --value #{@result_log_path}") if @result_log_path
