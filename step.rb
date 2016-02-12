require 'optparse'
require 'fileutils'
require 'tmpdir'

require_relative 'xamarin-builder/builder'

# -----------------------
# --- Constants
# -----------------------

@deploy_dir = ENV['BITRISE_DEPLOY_DIR']
@result_log_path = './TestResult.xml'

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

def export_dsym(archive_path)
  puts
  puts "\e[34Exporting dSYM from archive at path #{archive_path}\e[0m"

  archive_dsyms_folder = File.join(archive_path, 'dSYMs')
  app_dsym_paths = Dir[File.join(archive_dsyms_folder, '*.app.dSYM')]
  app_dsym_paths.each do |app_dsym_path|
    puts "dSym found at path: #{app_dsym_path}"
  end

  if app_dsym_paths.count == 0
    puts "\e[33mNo dSym found\e[0m"
  elsif app_dsym_paths.count > 1
    puts "\e[33mMultiple dSyms found\e[0m"
  else
    return app_dsym_paths.first
  end

  nil
end

def export_xcarchive(export_options, path)
  puts
  puts "\e[34mExporting IPA from archive at path #{path}\e[0m"
  export_options_path = export_options
  unless export_options_path
    puts
    puts 'Generating export options...'

    #  Bundle install
    current_dir = File.expand_path(File.dirname(__FILE__))
    gemfile_path = File.join(current_dir, 'Gemfile')

    bundle_install_command = [
      "BUNDLE_GEMFILE=#{gemfile_path}",
      "bundle install"
    ]
    puts
    puts "\e[34m#{bundle_install_command.join(' ')}\e[0m"
    success = system(bundle_install_command.join(' '))
    fail_with_message('Failed to create export options (required gem install failed)') unless $?.success?

    #  Bundle exec
    export_options_path = File.join(@deploy_dir, 'export_options.plist')
    export_options_generator = File.join(current_dir, 'generate_export_options.rb')

    bundle_exec_command = ["BUNDLE_GEMFILE=#{gemfile_path} bundle exec ruby #{export_options_generator}"]
    bundle_exec_command << "-o \"#{export_options_path}\""
    bundle_exec_command << "-a \"#{path}\""

    puts
    puts "\e[34m#{bundle_exec_command.join(' ')}\e[0m"
    success = system(bundle_exec_command.join(' '))
    fail_with_message('Failed to create export options (required gem install failed)') unless $?.success?
  end

  # Export ipa
  temp_dir = Dir.mktmpdir('_bitrise_')

  export_command = [
    "xcodebuild",
    "-exportArchive",
    "-archivePath \"#{path}\"",
    "-exportPath \"#{temp_dir}\"",
    "-exportOptionsPlist \"#{export_options_path}\""
  ]
  puts
  puts "\e[34m#{export_command.join(' ')}\e[0m"
  success = system(export_command.join(' '))
  fail_with_message('Failed to export IPA') unless $?.success?

  temp_ipa_path = Dir[File.join(temp_dir, '*.ipa')].first
  fail_with_message('No generated ipa found') unless temp_ipa_path

  ipa_name = File.basename(temp_ipa_path)
  ipa_path = File.join(@deploy_dir, ipa_name)
  FileUtils.cp(temp_ipa_path, ipa_path)

  ipa_path
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

builder = Builder.new(options[:project], options[:configuration], options[:platform], 'ios')
begin
  builder.build
  builder.build_test
rescue => ex
  fail_with_message("Build failed: #{ex}")
end

builder.generated_files.each do |_, project_output|
  if project_output[:xcarchive] && project_output[:uitests] && project_output[:uitests].length > 0
    ipa_path = export_xcarchive(options[:export_options], project_output[:xcarchive])
    dsym_path = export_dsym(project_output[:xcarchive])

    raise 'No UITests found' if project_output[:uitests].size == 0
    project_output[:uitests].each do |dll_path|
      assembly_dir = File.dirname(dll_path)

      puts ""
      puts "\e[34mUploading #{ipa_path} with #{dll_path}"

      #
      # Get test cloud path
      test_cloud = Dir['./**/packages/Xamarin.UITest.*/tools/test-cloud.exe'].last
      fail_with_message("Can't find test-cloud.exe") unless test_cloud

      #
      # Build Request
      request = [
        "mono \"#{test_cloud}\"",
        "submit \"#{ipa_path}\"",
        options[:api_key],
        "--assembly-dir \"#{assembly_dir}\"",
        "--nunit-xml \"#{@result_log_path}\"",
        "--user #{options[:user]}",
        "--devices \"#{options[:devices]}\""
      ]
      request << '--async' if options[:async]
      request << "--dsym \"#{dsym_path}\"" if dsym_path
      request << "--series \"#{options[:series]}\"" if options[:series]
      request << '--fixture-chunk' if options[:parallelization] == 'by_test_fixture'
      request << '--test-chunk' if options[:parallelization] == 'by_test_chunk'
      request << "#{options[:other_parameters]}" if options[:other_parameters]

      puts "  #{request.join(' ')}"
      system(request.join(' '))

      unless $?.success?
        file = File.open(@result_log_path)
        contents = file.read
        file.close

        puts
        puts contents
        fail_with_message("Failed to upload to Xamarin Test Cloud")
      end

      #
      # Set output envs
      system('envman add --key BITRISE_XAMARIN_TEST_RESULT --value succeeded')
      system("envman add --key BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT --value #{@result_log_path}") if @result_log_path

      puts "  \e[32mXamarin Test Cloud deploy succeeded\e[0m"
      puts "  Logs are available at path: #{@result_log_path}"
    end
  end
end
