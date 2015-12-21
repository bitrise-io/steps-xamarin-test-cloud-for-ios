require 'pathname'
require 'fileutils'

@mdtool = "\"/Applications/Xamarin Studio.app/Contents/MacOS/mdtool\""

def clean_project!(builder, project, configuration, platform, is_test)
  # clean project
  params = []
  case builder
  when 'xbuild'
    params << 'xbuild'
    params << "\"#{project}\""
    params << '/t:Clean'
    params << "/p:Configuration=\"#{configuration}\""
    params << "/p:Platform=\"#{platform}\"" unless is_test
  when 'mdtool'
    params << "#{@mdtool}"
    params << '-v build'
    params << "\"#{project}\""
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

def build_project!(builder, project, configuration, platform)
  # Build project
  output_path = File.join('bin', platform, configuration)

  params = []
  case builder
  when 'xbuild'
    params << 'xbuild'
    params << "\"#{project}\""
    params << '/t:Build'
    params << "/p:Configuration=\"#{configuration}\""
    params << "/p:Platform=\"#{platform}\""
    params << "/p:OutputPath=\"#{output_path}/\""
  when 'mdtool'
    params << "#{@mdtool}"
    params << '-v build'
    params << "\"#{project}\""
    params << "--configuration:\"#{configuration}|#{platform}\""
    params << '--target:Build'
  else
    fail_with_message('Invalid build tool detected')
  end

  puts "#{params.join(' ')}"
  system("#{params.join(' ')}")
  fail_with_message('Build failed') unless $?.success?

  # Get the build path
  project_directory = File.dirname(project)
  File.join(project_directory, output_path)
end


def archive_project!(builder, project, configuration, platform)
  output_path = File.join('bin', platform, configuration)

  params = []
  case builder
  when 'xbuild'
    params << 'xbuild'
    params << "\"#{project}\""
    params << '/t:Build'
    params << "/p:Configuration=\"#{configuration}\""
    params << "/p:Platform=\"#{platform}\""
    params << '/p:BuildIpa=true'
    params << "/p:OutputPath=\"#{output_path}/\""
  when 'mdtool'
    params << "#{@mdtool}"
    params << '-v build'
    params << "\"#{project}\""
    params << "--configuration:\"#{configuration}|#{platform}\""
    params << '--target:Build'
  else
    fail_with_message('Invalid build tool detected')
  end

  puts "#{params.join(' ')}"
  system("#{params.join(' ')}")
  fail_with_message('Build failed') unless $?.success?

  if builder.eql? 'mdtool'
    project_directory = File.dirname(project)
    app = Dir[File.join(project_directory, 'bin', platform, configuration, '/*.app')].first
    fail_with_message('No generated app file found') unless app
    app = Pathname.new(app).realpath.to_s
    app_name = File.basename(app, '.*')
    app_path = File.dirname(app)
    ipa_path = File.join(app_path, "#{app_name}.ipa")

    unless File.exist? ipa_path
      puts
      puts '==> Packaging application'
      puts "xcrun -sdk iphoneos PackageApplication -v \"#{app}\" -o \"#{ipa_path}\""
      system("xcrun -sdk iphoneos PackageApplication -v #{app} -o #{ipa_path}")
      fail_with_message('Failed to create .ipa from .app') unless $?.success?
    end
  end

  export_ipa_and_dsym(project, configuration, platform)
end

def export_ipa_and_dsym(project, configuration, platform)
  project_dir = File.dirname(project)
  ipa = Dir[File.join(project_dir, '/**/', 'bin', platform, configuration, '/*.ipa')].first
  fail_with_message('No generated ipa file found') unless ipa

  ipa_path = Pathname.new(ipa).realpath.to_s
  ipa_dir = File.dirname(ipa_path)
  puts "(i) ipa found at path: #{ipa_path}, dir: #{ipa_dir}"

  dsym = Dir["#{ipa_dir}/*.app.dSYM"].first
  dsym_path = Pathname.new(dsym).realpath.to_s if dsym
  puts "(i) dsym found at path: #{dsym}"

  return ipa_path, dsym_path
end
