require 'xcodeproj'
require 'fileutils'

module FrameworkGenerate
  class Target
    attr_accessor :name, :platforms, :language, :info_plist, :bundle_id, :header, :include_files, :exclude_files, :resource_files, :dependencies, :type, :pre_build_scripts, :post_build_scripts, :test_target, :is_safe_for_extensions, :enable_code_coverage, :launch_arguments, :environment_variables

    def initialize(name = nil, platforms = nil, language = nil, info_plist = nil, bundle_id = nil, header = nil, include_files = nil, exclude_files = nil, resource_files = nil, dependencies = nil, type = :framework, pre_build_scripts = nil, post_build_scripts = nil, test_target = nil, is_safe_for_extensions = false, enable_code_coverage = false, launch_arguments = nil, environment_variables = nil)
      @name = name
      @platforms = platforms
      @language = language
      @info_plist = info_plist
      @bundle_id = bundle_id
      @header = header
      @include_files = include_files
      @exclude_files = exclude_files
      @resource_files = resource_files
      @dependencies = dependencies
      @type = type
      @pre_build_scripts = pre_build_scripts
      @post_build_scripts = post_build_scripts
      @test_target = test_target
      @is_safe_for_extensions = is_safe_for_extensions
      @enable_code_coverage = enable_code_coverage
      @launch_arguments = launch_arguments
      @environment_variables = environment_variables

      yield(self) if block_given?
    end

    def to_s
      "Target<#{name}, #{info_plist}, #{bundle_id}, #{header}, #{include_files}, #{exclude_files}, #{dependencies}, #{type}, #{test_target}, #{is_safe_for_extensions}, #{enable_code_coverage}>"
    end

    def target_build_settings(settings)
      settings.delete('CODE_SIGN_IDENTITY')
      settings.delete('CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING')
      settings.delete('CLANG_WARN_COMMA')
      settings.delete('CLANG_WARN_NON_LITERAL_NULL_CONVERSION')
      settings.delete('CLANG_WARN_OBJC_LITERAL_CONVERSION')
      settings.delete('CLANG_WARN_RANGE_LOOP_ANALYSIS')
      settings.delete('CLANG_WARN_STRICT_PROTOTYPES')

      settings['INFOPLIST_FILE'] = @info_plist
      settings['PRODUCT_BUNDLE_IDENTIFIER'] = @bundle_id
      settings['APPLICATION_EXTENSION_API_ONLY'] = @is_safe_for_extensions ? 'YES' : 'NO'
      settings['SUPPORTED_PLATFORMS'] = FrameworkGenerate::Platform.supported_platforms(@platforms)

      macos = FrameworkGenerate::Platform.find_platform(@platforms, :macos)
      unless macos.nil?
        settings['MACOSX_DEPLOYMENT_TARGET'] = FrameworkGenerate::Platform.deployment_target(macos)
        settings['FRAMEWORK_SEARCH_PATHS[sdk=macosx*]'] = FrameworkGenerate::Platform.search_paths(macos)
      end

      ios = FrameworkGenerate::Platform.find_platform(@platforms, :ios)
      unless ios.nil?
        settings['IPHONEOS_DEPLOYMENT_TARGET'] = FrameworkGenerate::Platform.deployment_target(ios)
        settings['FRAMEWORK_SEARCH_PATHS[sdk=iphone*]'] = FrameworkGenerate::Platform.search_paths(ios)
      end

      watchos = FrameworkGenerate::Platform.find_platform(@platforms, :watchos)
      unless watchos.nil?
        settings['WATCHOS_DEPLOYMENT_TARGET'] = FrameworkGenerate::Platform.deployment_target(watchos)
        settings['FRAMEWORK_SEARCH_PATHS[sdk=watch*]'] = FrameworkGenerate::Platform.search_paths(watchos)
      end

      tvos = FrameworkGenerate::Platform.find_platform(@platforms, :tvos)
      unless tvos.nil?
        settings['TVOS_DEPLOYMENT_TARGET'] = FrameworkGenerate::Platform.deployment_target(tvos)
        settings['FRAMEWORK_SEARCH_PATHS[sdk=appletv*]'] = FrameworkGenerate::Platform.search_paths(tvos)
      end

      settings['SWIFT_VERSION'] = @language.version

      settings
    end

    def find_group(project, path)
      folder_path = File.dirname(path)
      project.main_group.find_subpath(folder_path, true)
    end

    def add_framework_header(project, target)
      return if @header.nil?
      header_path = @header
      header_file_group = find_group(project, header_path)
      header_file = header_file_group.new_reference(header_path)
      header_build_file = target.headers_build_phase.add_file_reference(header_file, true)
      header_build_file.settings ||= {}
      header_build_file.settings['ATTRIBUTES'] = ['Public']
    end

    def add_info_plist(project)
      info_plist_path = @info_plist
      info_plist_group = find_group(project, info_plist_path)
      has_info_plist = info_plist_group.find_file_by_path(info_plist_path)

      info_plist_group.new_reference(@info_plist) unless has_info_plist
    end

    def add_supporting_files(project, target)
      add_info_plist(project)
      return if target.test_target_type?
      add_framework_header(project, target)
    end

    def reject_excluded_files(exclude_files, path)
      exclude_files.each do |files_to_exclude|
        files_to_exclude.each do |file_to_exclude|
          return true if File.fnmatch(file_to_exclude, path)
        end
      end

      false
    end

    def add_source_files(project, target)
      exclude_files = if @exclude_files.nil?
                        []
                      else
                        @exclude_files.map do |files|
                          Dir[files]
                        end
                      end

      source_files = @include_files.map do |files|
        Dir[files].reject do |path|
          reject_excluded_files(exclude_files, path)
        end
      end

      source_files.each do |file_directory|
        file_directory.each do |path|
          source_file_group = find_group(project, path)
          has_source_file = source_file_group.find_file_by_path(path)
          unless has_source_file
            source_file = source_file_group.new_reference(path)
            target.source_build_phase.add_file_reference(source_file, true)
          end
        end
      end
    end

    def append_framework_extension(framework)
      return framework if File.extname(framework) == '.framework'

      "#{framework}.framework"
    end

    def add_dependencies(project, target)
      return if @dependencies.nil?

      dependency_names = @dependencies.map do |dependency|
        append_framework_extension(dependency)
      end

      frameworks = dependency_names.reject do |name|
        !project.products.any? { |x| x.path == name }
      end

      frameworks = frameworks.map do |name|
        project.products.find { |x| x.path == name }
      end

      frameworks.each do |path|
        target.frameworks_build_phase.add_file_reference(path, true)
      end
    end

    def copy_carthage_frameworks(project, build_phase, scripts_directory)
      script_file_name = 'copy-carthage-frameworks.sh'
      script_file_path = File.join(File.dirname(__FILE__), script_file_name)

      if scripts_directory.nil?
        script_file = File.open(script_file_path)

        build_phase.shell_script = script_file.read

        script_file.close
      else
        script_path = File.join(Dir.pwd, scripts_directory, script_file_name)
        dirname = File.dirname(script_path)
        FileUtils.mkdir_p(dirname) unless File.directory?(dirname)

        FileUtils.cp(script_file_path, script_path, preserve: true)

        xcode_path = File.join('${SRCROOT}', scripts_directory, script_file_name)
        build_phase.shell_script = " exec \"#{xcode_path}\""
      end

      add_framework_to_copy_phase(project, build_phase)
    end

    def third_party_frameworks?(project)
      return if @dependencies.nil?

      dependency_names = @dependencies.map do |dependency|
        append_framework_extension(dependency)
      end

      frameworks = dependency_names.reject do |name|
        project.products.any? { |x| x.path == name }
      end

      frameworks.length > 0
    end

    def add_framework_to_copy_phase(project, build_phase)
      return if @dependencies.nil?

      dependency_names = @dependencies.map do |dependency|
        append_framework_extension(dependency)
      end

      frameworks = dependency_names.reject do |name|
        project.products.any? { |x| x.path == name }
      end

      frameworks.each do |path|
        build_phase.input_paths << path
      end
    end

    def add_resource_files(project, target)
      return if @resource_files.nil?

      files = @resource_files.map do |files|
        Dir[files]
      end

      files.each do |file_directory|
        file_directory.each do |path|
          file_group = find_group(project, path)
          has_file = file_group.find_file_by_path(path)
          unless has_file
            file = file_group.new_reference(path)
            target.resources_build_phase.add_file_reference(file, true)
          end
        end
      end
    end

    def add_build_scripts(target, scripts)
      return if scripts.nil?

      scripts.each do |script|
        build_phase = target.new_shell_script_build_phase(script.name)
        build_phase.shell_script = script.script
        build_phase.input_paths = script.inputs
      end
    end

    def add_pre_build_scripts(target)
      add_build_scripts(target, @pre_build_scripts)
    end

    def add_post_build_scripts(target)
      add_build_scripts(target, @post_build_scripts)
    end

    def add_launch_arguments(launch_action)
      return if @launch_arguments.nil?

      command_line_arguments = @launch_arguments.map do |launch_arguement|
        { argument: launch_arguement, enabled: true }
      end

      launch_action.command_line_arguments = Xcodeproj::XCScheme::CommandLineArguments.new(command_line_arguments)
    end

    def add_environment_variables(launch_action)
      return if @environment_variables.nil?

      environment_variables = @environment_variables.map do |key, value|
        { key: key, value: value, enabled: true }
      end

      launch_action.environment_variables = Xcodeproj::XCScheme::EnvironmentVariables.new(environment_variables)
    end

    def create(project, language, scripts_directory)
      name = @name
      type = @type

      # Target
      target = project.new(Xcodeproj::Project::Object::PBXNativeTarget)
      project.targets << target
      target.name = name
      target.product_name = name
      target.product_type = Xcodeproj::Constants::PRODUCT_TYPE_UTI[type]
      target.build_configuration_list = Xcodeproj::Project::ProjectHelper.configuration_list(project, :osx, nil, type, language.type)

      # Pre build script
      add_pre_build_scripts(target)

      add_supporting_files(project, target)
      add_source_files(project, target)

      target.build_configurations.each do |configuration|
        target_build_settings(configuration.build_settings)
      end

      # Product
      product = project.products_group.new_product_ref_for_target(name, type)
      target.product_reference = product

      # Build phases

      target.build_phases << project.new(Xcodeproj::Project::Object::PBXResourcesBuildPhase)
      target.build_phases << project.new(Xcodeproj::Project::Object::PBXFrameworksBuildPhase)

      # Post build script
      add_post_build_scripts(target)

      # Dependencies
      add_dependencies(project, target)

      # Resource files
      add_resource_files(project, target)

      # Copy frameworks to test target
      if target.test_target_type? && third_party_frameworks?(project)
        build_phase = target.new_shell_script_build_phase('Copy Carthage Frameworks')
        copy_carthage_frameworks(project, build_phase, scripts_directory)
      end

      target
    end
  end
end
