# frozen_string_literal: true
# 只在私有临时目录验证部署位置传递、卸载边界和共享叶；系统登记函数全部使用替身。
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'shellwords'

class PackageInstallLocationTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  REAL_PACKAGES = %w[JobsRunAuthorizer JobsRunAuthorizationRevoker JobsIPAResigner JobsPathCopier JobsTerminalOpener JobsFlutterTools JobsIOSTools JobsFileCreator].freeze

  def definitions(package)
    File.read(File.join(ROOT, package, 'Scripts/ManageExtension.zsh')).sub(/^(?:manager_)?main "\$@"\s*\z/, '')
  end

  def execute(source, *args, env: {})
    Open3.capture3(env, '/bin/zsh', '-c', source, 'fixture', *args)
  end

  def fixture_environment(directory)
    { 'HOME' => directory, 'JOBS_LOCATION_FIXTURE_ROOT' => directory,
      'JOBS_FINDER_APPLICATIONS_DIR' => File.join(directory, 'Applications'), 'NO_COLOR' => '1' }
  end

  def deployment_stubs
    <<~'ZSH'
      manager_load_deployment() { return 0; }
      jobs_deployment_app_path() {
        if [[ "${JOBS_FINDER_INSTALL_LOCATION:-build}" == applications ]]; then
          print -r -- "$JOBS_FINDER_APPLICATIONS_DIR/Jobs自定义右键菜单.app/Contents/Applications/${1:t}"
        else
          print -r -- "$1"
        fi
      }
      jobs_deployment_validate_app() {
        [[ "$1" == "$JOBS_LOCATION_FIXTURE_ROOT"/* && -d "$1" && ! -L "$1" ]] || return 97
      }
      jobs_deployment_has_other_enabled() { return "${JOBS_LOCATION_OTHER_ENABLED:-1}"; }
      jobs_deployment_unregister_app() { print -r -- "UNREGISTER=$1"; }
      jobs_deployment_uninstall() {
        [[ "$1" == "$JOBS_LOCATION_FIXTURE_ROOT"/Applications/Jobs自定义右键菜单.app/Contents/Applications/Jobs*.app ]] || return 97
        print -r -- "DELETE=$1"
        /bin/rm -r -- "$1"
      }
      manager_restart_finder() { print -r -- REFRESH; }
      run_uninstall_operation() { manager_uninstall_selected_application; }
    ZSH
  end

  def test_all_package_parsers_accept_both_locations_and_reject_unknown_before_dispatch
    Dir.glob(File.join(ROOT, 'Jobs*', 'Scripts/ManageExtension.zsh')).each do |path|
      package = File.basename(File.dirname(File.dirname(path)))
      source = definitions(package) + <<~'ZSH'
        manager_open_gui() { print -r -- "GUI=$JOBS_FINDER_INSTALL_LOCATION"; }
        open_management_panel() { print -r -- "GUI=$JOBS_FINDER_INSTALL_LOCATION"; }
        manager_main() { manager_parse_options "$@" || return $?; manager_open_gui; }
      ZSH
      entry = package == 'JobsFileCreator' ? 'main "$@"' : 'manager_main "$@"'
      %w[build applications].each do |location|
        output, error, result = execute(source + "\n#{entry}\n", '--install-location', location)
        assert result.success?, "#{package}: #{error}"
        assert_includes output, "GUI=#{location}"
      end
      output, error, result = execute(source + "\n#{entry}\n", '--install-location', 'elsewhere')
      assert_equal 2, result.exitstatus, "#{package}: #{error}"
      refute_includes output, 'GUI='
    end
  end

  def test_missing_selected_app_is_a_noop_for_every_real_package
    Dir.mktmpdir('jobs-package-missing-') do |dir|
      FileUtils.mkdir_p(File.join(dir, 'Applications'))
      REAL_PACKAGES.each do |package|
        config = File.join(dir, 'Library/Application Support/JobsFinderExtensions/flutter-tools-features.conf')
        FileUtils.mkdir_p(File.dirname(config))
        File.write(config, 'run,package-ios')
        source = definitions(package) + deployment_stubs + <<~'ZSH'
          MANAGER_ENTRY_DIR="$HOME/Package"
          PROJECT_DIR="$HOME/Package"
          JOBS_FINDER_INSTALL_LOCATION=applications
          jobs_deployment_validate_app() { print -u2 unexpected-validation; return 97; }
          manager_uninstall_selected_application
        ZSH
        output, error, result = execute(source, env: fixture_environment(dir))
        assert result.success?, "#{package}: #{error}"
        assert_includes output, '无需卸载'
        refute_includes output, 'DELETE='
        assert_equal 'run,package-ios', File.read(config)
      end
    end
  end

  def test_inactive_selected_copy_does_not_modify_shared_configuration_or_build_copy
    Dir.mktmpdir('jobs-package-inactive-') do |dir|
      app = File.join(dir, 'Applications/Jobs自定义右键菜单.app/Contents/Applications/JobsFlutterTools.app')
      build = File.join(dir, 'Package/work/DerivedData/Build/Products/Debug/JobsFlutterTools.app')
      config = File.join(dir, 'Library/Application Support/JobsFinderExtensions/flutter-tools-features.conf')
      [app, build, File.dirname(config)].each { |path| FileUtils.mkdir_p(path) }
      File.write(config, 'run,package-ios')
      source = definitions('JobsFlutterTools') + deployment_stubs + <<~'ZSH'
        MANAGER_ENTRY_DIR="$HOME/Package"
        JOBS_FINDER_INSTALL_LOCATION=applications
        MANAGER_REQUESTED_FEATURES=package-ios
        manager_uninstall_selected_application
      ZSH
      output, error, result = execute(source, env: fixture_environment(dir).merge('JOBS_LOCATION_OTHER_ENABLED' => '0'))
      assert result.success?, error
      refute File.exist?(app)
      assert File.directory?(build)
      assert_equal 'run,package-ios', File.read(config)
      refute_includes output, 'REFRESH'
    end
  end

  def test_shared_partial_uninstall_keeps_app_and_last_leaf_removes_only_selected_app
    Dir.mktmpdir('jobs-package-shared-') do |dir|
      app = File.join(dir, 'Applications/Jobs自定义右键菜单.app/Contents/Applications/JobsFlutterTools.app')
      build = File.join(dir, 'Package/work/DerivedData/Build/Products/Debug/JobsFlutterTools.app')
      config = File.join(dir, 'Library/Application Support/JobsFinderExtensions/flutter-tools-features.conf')
      [app, build, File.dirname(config)].each { |path| FileUtils.mkdir_p(path) }
      File.write(config, 'run,package-ios')
      source = definitions('JobsFlutterTools') + deployment_stubs + <<~'ZSH'
        MANAGER_ENTRY_DIR="$HOME/Package"
        JOBS_FINDER_INSTALL_LOCATION=applications
        MANAGER_REQUESTED_FEATURES="$1"
        manager_uninstall_selected_application
      ZSH
      output, error, result = execute(source, 'package-ios', env: fixture_environment(dir))
      assert result.success?, error
      assert File.directory?(app)
      assert_equal 'run', File.read(config)
      refute_includes output, 'DELETE='
      output, error, result = execute(source, 'run', env: fixture_environment(dir))
      assert result.success?, error
      refute File.exist?(app)
      assert File.directory?(build)
      refute File.exist?(config)
      assert_includes output, "DELETE=#{app}"
    end
  end

  def test_total_manager_explicit_built_app_path_targets_that_build_only
    Dir.mktmpdir('jobs-package-root-build-') do |dir|
      registered = File.join(dir, 'Total/work/JobsPathCopierDerivedData/Build/Products/Debug/JobsPathCopier.app')
      standalone = File.join(dir, 'Package/work/DerivedData/Build/Products/Debug/JobsPathCopier.app')
      applications = File.join(dir, 'Applications/Jobs自定义右键菜单.app/Contents/Applications/JobsPathCopier.app')
      [registered, standalone, applications].each { |path| FileUtils.mkdir_p(path) }
      source = definitions('JobsPathCopier') + deployment_stubs + <<~'ZSH'
        MANAGER_ENTRY_DIR="$HOME/Package"
        JOBS_FINDER_INSTALL_LOCATION=build
        JOBS_FINDER_BUILT_APP_PATH="$1"
        manager_uninstall_selected_application
      ZSH
      output, error, result = execute(source, registered, env: fixture_environment(dir))
      assert result.success?, error
      refute File.exist?(registered)
      assert File.directory?(standalone)
      assert File.directory?(applications)
      assert_includes output, "UNREGISTER=#{registered}"
    end
  end

  def test_query_failure_preserves_every_file
    Dir.mktmpdir('jobs-package-query-error-') do |dir|
      app = File.join(dir, 'Applications/Jobs自定义右键菜单.app/Contents/Applications/JobsIOSTools.app')
      FileUtils.mkdir_p(app)
      source = definitions('JobsIOSTools') + deployment_stubs + <<~'ZSH'
        MANAGER_ENTRY_DIR="$HOME/Package"
        JOBS_FINDER_INSTALL_LOCATION=applications
        manager_uninstall_selected_application
      ZSH
      output, error, result = execute(source, env: fixture_environment(dir).merge('JOBS_LOCATION_OTHER_ENABLED' => '2'))
      assert_equal 2, result.exitstatus, error
      assert File.directory?(app)
      refute_includes output, 'DELETE='
      refute_includes output, 'REFRESH'
    end
  end
  def test_aggregate_backends_remove_only_the_selected_location_and_keep_remaining_leaves
    %w[JobsProjectTools JobsDesktopTools].each do |package|
      Dir.mktmpdir('jobs-aggregate-location-') do |dir|
        project = package == 'JobsProjectTools'
        operation = project ? 'ManageProjectTools.zsh' : 'ManageDesktopTools.zsh'
        scripts = File.join(dir, package, 'Scripts')
        FileUtils.mkdir_p(scripts)
        FileUtils.mkdir_p(File.join(dir, 'Applications'))
        app = File.join(dir, 'Applications/Jobs自定义右键菜单.app/Contents/Applications', "#{package}.app")
        build = File.join(dir, package, 'work/DerivedData/Build/Products/Debug', "#{package}.app")
        FileUtils.mkdir_p([app, build])
        config = File.join(dir, 'Library/Application Support', package, 'EnabledFeatures.txt')
        FileUtils.mkdir_p(File.dirname(config))
        leaves = project ? %w[vscode_opener git-pull] : %w[ios-simulator-create hidden-files-toggle]
        File.write(config, leaves.join(','))
        module_path = File.join(scripts, '【MacOS】AppDeployment.zsh/【MacOS】AppDeployment.zsh')
        FileUtils.mkdir_p(File.dirname(module_path))
        File.write(module_path, deployment_stubs + <<~'ZSH')
          jobs_deployment_enabled_extension_paths() { return 0; }
          jobs_deployment_rollback() { return 0; }
        ZSH
        source = File.read(File.join(ROOT, package, 'Scripts', operation)).sub(/^main "\$@"\s*\z/, '')
        # 所有非文件操作均使用替身；实际rm也只能作用于上面创建的App夹具。
        source += <<~'ZSH'
          retire_legacy() { return 0; }
          retire_terminal_git_menu() { return 0; }
          retire_legacy_proxy() { return 0; }
          retire_legacy_rollback() { return 0; }
          extension_is_enabled() { return 1; }
          main "$@"
        ZSH
        fixture = File.join(scripts, operation)
        File.write(fixture, source)
        environment = fixture_environment(dir).merge('JOBS_SKIP_FINDER_RESTART' => '1')
        output, error, result = Open3.capture3(environment, '/bin/zsh', fixture, 'uninstall', leaves[0], '--install-location', 'applications', *[project ? nil : '--non-interactive'].compact)
        assert result.success?, "#{package}: #{output} #{error}"
        assert File.directory?(app), package
        assert_equal leaves[1], File.read(config), package
        output, error, result = Open3.capture3(environment, '/bin/zsh', fixture, 'uninstall', leaves[1], '--install-location', 'applications', *[project ? nil : '--non-interactive'].compact)
        assert result.success?, "#{package}: #{output} #{error}"
        refute File.exist?(app), package
        assert File.directory?(build), package
      end
    end
  end

  def test_shared_installation_failure_restores_configuration_bytes_permissions_and_absence
    %w[JobsIOSTools JobsFlutterTools].each do |package|
      [false, true].each do |had_configuration|
        Dir.mktmpdir('jobs-package-config-rollback-') do |dir|
          suffix = package == 'JobsIOSTools' ? 'JobsIOSTools/EnabledFeatures.txt' : 'JobsFinderExtensions/flutter-tools-features.conf'
          config = File.join(dir, 'Library/Application Support', suffix)
          FileUtils.mkdir_p(File.dirname(config))
          if had_configuration
            File.write(config, 'previous-value')
            File.chmod(0o640, config)
          end
          source = definitions(package) + <<~'ZSH'
            jobs_deployment_rollback() { print -r -- APP_ROLLBACK; }
            manager_capture_install_configuration || exit $?
            print -nr -- new-value > "$MANAGER_DEPLOYMENT_CONFIG"
            manager_record_install_configuration || exit $?
            /bin/false
            manager_rollback_install_deployment
          ZSH
          output, error, result = execute(source, env: fixture_environment(dir))
          refute result.success?, error
          assert_includes output, 'APP_ROLLBACK'
          if had_configuration
            assert_equal 'previous-value', File.read(config)
            assert_equal 0o640, File.stat(config).mode & 0o777
          else
            refute File.exist?(config)
          end
        end
      end
    end
  end

  def test_shared_installation_rollback_preserves_external_configuration_edit
    Dir.mktmpdir('jobs-package-config-concurrent-') do |dir|
      config = File.join(dir, 'Library/Application Support/JobsFinderExtensions/flutter-tools-features.conf')
      FileUtils.mkdir_p(File.dirname(config))
      File.write(config, 'original')
      source = definitions('JobsFlutterTools') + <<~'ZSH'
        jobs_deployment_rollback() { return 0; }
        manager_capture_install_configuration || exit $?
        print -nr -- published > "$MANAGER_DEPLOYMENT_CONFIG"
        manager_record_install_configuration || exit $?
        print -nr -- external-change > "$MANAGER_DEPLOYMENT_CONFIG"
        /bin/false
        manager_rollback_install_deployment
      ZSH
      _output, error, result = execute(source, env: fixture_environment(dir))
      refute result.success?
      assert_equal 'external-change', File.read(config)
      assert_includes error, '配置已被外部修改'
    end
  end

  def test_installation_exit_trap_runs_after_registration_step_and_preserves_failure
    (REAL_PACKAGES - ['JobsFileCreator']).each do |package|
      Dir.mktmpdir('jobs-package-worker-trap-') do |dir|
        source = definitions(package)
        injection = <<~'ZSH'
          # 本夹具仅保留真实worker子Shell和部署编排，构建及系统操作全部替换。
          main() {
            APP_PATH="$HOME/Package/JobsFixture.app"
            manager_deploy_built_application
            print -r -- REGISTER_AFTER_DEPLOY
            return 7
          }
        ZSH
        needle = "main \"$@\"\n)\n}"
        assert_includes source, needle, package
        source = source.sub(needle, injection + needle)
        source += <<~'ZSH'
          manager_load_deployment() { return 0; }
          jobs_deployment_install() { print -r -- DEPLOY; }
          jobs_deployment_app_path() { print -r -- "$1"; }
          jobs_deployment_retire_other_copies() { print -r -- RETIRE; }
          manager_stop_previous_hosts() { print -r -- STOP_HOST; }
          jobs_deployment_rollback() { print -r -- ROLLBACK; }
          run_install_operation
        ZSH
        output, error, result = execute(source, env: fixture_environment(dir))
        assert_equal 7, result.exitstatus, "#{package}: #{error}"
        phases = %w[DEPLOY RETIRE]
        phases << 'STOP_HOST' if %w[JobsFlutterTools JobsTerminalOpener JobsPathCopier].include?(package)
        phases += %w[REGISTER_AFTER_DEPLOY ROLLBACK]
        assert_equal phases, output.lines.map(&:chomp), package
      end
    end
  end

  def test_file_creator_worker_pipeline_failure_restores_deployment_and_releases_only_its_lock
    Dir.mktmpdir('jobs-file-creator-worker-trap-') do |dir|
      source = definitions('JobsFileCreator') + <<~'ZSH'
        PROJECT_DIR="$HOME/Package"
        MANAGER_SKIP_RESTART=1
        perform_operation() {
          jobs_deployment_rollback() { print -r -- FILE_CREATOR_ROLLBACK; }
          exit 7
        }
        run_worker
      ZSH
      environment = fixture_environment(dir).merge('TMPDIR' => "#{dir}/")
      output, error, result = execute(source, env: environment)
      assert_equal 7, result.exitstatus, error
      assert_includes output, 'FILE_CREATOR_ROLLBACK'
      refute File.exist?(File.join(dir, 'Package/work/.manager-lock'))
    end
  end

  def test_cleanup_option_requires_applications_install_before_any_business_in_every_package
    Dir.mktmpdir('jobs-package-cleanup-options-') do |dir|
      Dir.glob(File.join(ROOT, 'Jobs*', 'Scripts/ManageExtension.zsh')).each do |path|
        package = File.basename(File.dirname(File.dirname(path)))
        source = definitions(package) + <<~'ZSH'
          manager_open_gui() { print -r -- "GUI_CLEANUP=$JOBS_FINDER_CLEANUP_BUILD_PRODUCTS"; }
          open_management_panel() { print -r -- "GUI_CLEANUP=$JOBS_FINDER_CLEANUP_BUILD_PRODUCTS"; }
          manager_validate_existing_configuration() { return 0; }
          run_install_operation() { print -r -- "BUSINESS_CLEANUP=$JOBS_FINDER_CLEANUP_BUILD_PRODUCTS"; }
          run_uninstall_operation() { print -r -- unexpected-uninstall; }
          run_worker() { print -r -- "BUSINESS_CLEANUP=$JOBS_FINDER_CLEANUP_BUILD_PRODUCTS"; }
        ZSH
        source += package == 'JobsFileCreator' ? "\nmain \"$@\"\n" : "\nmanager_main \"$@\"\n"
        environment = fixture_environment(dir).merge('JOBS_FINDER_CLEANUP_BUILD_PRODUCTS' => '0')
        output, error, result = execute(source, '--action', 'install', '--install-location', 'applications', '--cleanup-build-products', '--non-interactive', env: environment)
        assert result.success?, "#{package}: #{error}"
        assert_includes output, 'BUSINESS_CLEANUP=1', package
        [%w[--action install --install-location build], %w[--action uninstall --install-location applications], %w[--action uninstall --install-location build]].each do |arguments|
          output, error, result = execute(source, *arguments, '--cleanup-build-products', '--non-interactive', env: environment)
          assert_equal 2, result.exitstatus, "#{package}: #{error}"
          refute_includes output, 'BUSINESS_CLEANUP='
          refute_includes output, 'GUI_CLEANUP='
        end
      end
    end
  end

  def test_cleanup_runs_after_commit_and_failure_keeps_install_success_for_every_actual_package
    Dir.mktmpdir('jobs-package-cleanup-after-commit-') do |dir|
      REAL_PACKAGES.each do |package|
        source = definitions(package) + <<~'ZSH'
          MANAGER_ENTRY_DIR="$HOME/Package"
          PROJECT_DIR="$HOME/Package"
          MANAGER_DEPLOYMENT_BUILT_APP_PATH="$HOME/Package/work/DerivedData/Build/Products/Debug/$1.app"
          jobs_deployment_commit() { print -r -- COMMIT; }
          manager_release_install_configuration() { return 0; }
          jobs_deployment_cleanup_build_products() {
            print -r -- "CLEANUP=${(j:|:)@}"
            return 17
          }
          jobs_deployment_rollback() { return 0; }
          manager_commit_deployment
        ZSH
        output, error, result = execute(source, package, env: fixture_environment(dir).merge('JOBS_FINDER_CLEANUP_BUILD_PRODUCTS' => '1'))
        assert result.success?, "#{package}: #{error}"
        assert_equal 'COMMIT', output.lines.first.chomp, package
        assert_includes output, "CLEANUP=#{dir}/Package/work/DerivedData/Build/Products/Debug/#{package}.app|#{dir}/Package/work/DerivedData|", package
        assert_includes error, 'App 已安装成功，但清除此轮构建产物失败', package
        output, error, result = execute(source, package, env: fixture_environment(dir).merge('JOBS_FINDER_CLEANUP_BUILD_PRODUCTS' => '0'))
        assert result.success?, "#{package}: #{error}"
        assert_equal "COMMIT\n", output, package
        refute_includes error, '清除此轮构建产物失败', package
      end
    end
  end

  def test_aggregate_cleanup_flags_are_rejected_before_loading_deployment_or_running_business
    %w[JobsProjectTools JobsDesktopTools].each do |package|
      project = package == 'JobsProjectTools'
      filename = project ? 'ManageProjectTools.zsh' : 'ManageDesktopTools.zsh'
      source = File.read(File.join(ROOT, package, 'Scripts', filename)).sub(/^main "\$@"\s*\z/, '')
      parser = project ? 'parse_operation' : 'prepare_context'
      source += "\n#{parser} \"$@\"\n"
      leaf = project ? 'vscode_opener' : 'hidden-files-toggle'
      [['install', 'build'], ['uninstall', 'applications'], ['uninstall', 'build']].each do |operation, location|
        output, error, result = execute(source, operation, leaf, '--install-location', location, '--cleanup-build-products')
        assert_equal 2, result.exitstatus, "#{package}: #{error}"
        assert_includes error, '仅安装到应用程序目录时允许清除此轮构建产物', package
        refute_includes output, '来源'
      end
    end
  end

  def test_gui_uses_external_binary_cache_and_forwards_cleanup_without_writing_bundle
    Dir.mktmpdir('jobs-manager-external-cache-') do |dir|
      package = File.join(dir, '联合App资源包')
      scripts = File.join(package, 'Scripts')
      cache = File.join(dir, 'Library/Caches/JobsFinderExtensions/Management')
      FileUtils.mkdir_p([scripts, cache])
      entry = File.join(scripts, 'ManageExtension.zsh')
      File.write(entry, '# fixture')
      File.write(File.join(scripts, 'ManagementPanel.swift'), '// fixture source is read from bundle')
      binary = File.join(cache, 'ManagementPanel')
      File.write(binary, "#!/bin/zsh\n/usr/bin/printf '%s\\0' \"$@\"\n")
      File.chmod(0o755, binary)
      helper = File.read(File.join(ROOT, 'Scripts/FinderManagerGUI.zsh'))
      output, error, result = execute(helper + "\njobs_launch_finder_manager_gui \"$1\" file-create install 1\n", entry,
                                      env: fixture_environment(dir).merge('JOBS_FINDER_MANAGER_CACHE_DIR' => cache, 'JOBS_FINDER_INSTALL_LOCATION' => 'applications', 'JOBS_FINDER_CLEANUP_BUILD_PRODUCTS' => '1'))
      assert result.success?, error
      assert_equal ['--manager', entry, '--action', 'install', '--install-location', 'applications', '--cleanup-build-products', '--scope', 'file-create'], output.split("\0")
      refute File.exist?(File.join(package, 'work'))
      assert_equal '// fixture source is read from bundle', File.read(File.join(scripts, 'ManagementPanel.swift'))
    end
  end

  def test_aggregate_cleanup_failure_is_a_warning_and_keeps_committed_install_success
    %w[JobsProjectTools JobsDesktopTools].each do |package|
      filename = package == 'JobsProjectTools' ? 'ManageProjectTools.zsh' : 'ManageDesktopTools.zsh'
      source = File.read(File.join(ROOT, package, 'Scripts', filename)).sub(/^main "\$@"\s*\z/, '')
      source += <<~'ZSH'
        PROJECT_ROOT="$HOME/Package"
        BUILT_APP_PATH="$PROJECT_ROOT/work/DerivedData/Build/Products/Debug/$1.app"
        JOBS_FINDER_CLEANUP_BUILD_PRODUCTS=1
        jobs_deployment_cleanup_build_products() {
          print -r -- "CLEANUP=${(j:|:)@}"
          return 17
        }
        cleanup_committed_build_products
      ZSH
      Dir.mktmpdir('jobs-aggregate-cleanup-failed-') do |dir|
        output, error, result = execute(source, package, env: fixture_environment(dir))
        assert result.success?, "#{package}: #{error}"
        assert_includes output, "CLEANUP=#{dir}/Package/work/DerivedData/Build/Products/Debug/#{package}.app|#{dir}/Package/work/DerivedData|", package
        assert_includes error, 'App 已安装成功，但清除此轮构建产物失败', package
      end
    end
  end

  def test_standalone_installation_only_stops_validated_exact_hosts_and_skips_unknown_same_name
    %w[JobsFlutterTools JobsTerminalOpener JobsPathCopier JobsFileCreator].each do |package|
      Dir.mktmpdir('jobs-verified-host-stop-') do |dir|
        built = File.join(dir, 'Package with 空格/work/DerivedData/Build/Products/Debug', "#{package}.app")
        selected = File.join(dir, 'Applications/Jobs自定义右键菜单.app/Contents/Applications', "#{package}.app")
        previous = File.join(dir, 'Applications', "#{package}.app")
        [built, selected, previous].each { |path| FileUtils.mkdir_p(path) }
        source = definitions(package) + <<~'ZSH'
          MANAGER_DEPLOYMENT_BUILT_APP_PATH="$1"
          APP_PATH="$2"
          FAKE_PREVIOUS_APP="$3"
          FAKE_HOST_NAME="$4"
          JOBS_DEPLOYMENT_PREVIOUS_APPS=("$3")
          jobs_deployment_applications_root() { print -r -- "$HOME/Applications"; }
          jobs_deployment_validate_app() { [[ -d "$1" && "${1:t}" == "$FAKE_HOST_NAME.app" ]]; }
          manager_host_process_records() {
            print -r -- "444441 $MANAGER_DEPLOYMENT_BUILT_APP_PATH/Contents/MacOS/$FAKE_HOST_NAME"
            print -r -- "444442 $APP_PATH/Contents/MacOS/$FAKE_HOST_NAME"
            print -r -- "444443 $FAKE_PREVIOUS_APP/Contents/MacOS/$FAKE_HOST_NAME"
            print -r -- "444444 $HOME/unknown/$FAKE_HOST_NAME.app/Contents/MacOS/$FAKE_HOST_NAME"
            print -r -- "$$ $APP_PATH/Contents/MacOS/$FAKE_HOST_NAME"
          }
          manager_signal_host_termination() { print -r -- "TERMINATE=$1"; }
          manager_wait_host_termination() { print -r -- "WAIT=$1"; }
          manager_stop_previous_hosts
        ZSH
        output, error, result = execute(source, built, selected, previous, package, env: fixture_environment(dir))
        assert result.success?, "#{package}: #{error}"
        assert_equal %w[444441 444442 444443], output.scan(/^TERMINATE=(\d+)$/).flatten, package
        assert_equal %w[444441 444442 444443], output.scan(/^WAIT=(\d+)$/).flatten, package
        refute_includes output, 'TERMINATE=444444'
      end
    end
  end

  def test_every_entry_accepts_independent_cleanup_and_keeps_stop_request_without_interrupting_current_host
    Dir.mktmpdir('jobs-package-independent-cleanup-') do |dir|
      stop = File.join(dir, '停止 this batch.request')
      File.write(stop, 'stop')
      Dir.glob(File.join(ROOT, 'Jobs*', 'Scripts/ManageExtension.zsh')).each do |path|
        package = File.basename(File.dirname(File.dirname(path)))
        source = definitions(package) + <<~'ZSH'
          manager_choose_action() { return 0; }
          manager_validate_existing_configuration() { print -u2 unexpected-config; return 97; }
          manager_cleanup_existing_build_products() { print -r -- "CLEANUP=$JOBS_FINDER_INSTALL_LOCATION|$JOBS_FINDER_CLEANUP_BUILD_PRODUCTS|$JOBS_FINDER_STOP_REQUEST_FILE"; }
          run_cleanup_operation() { manager_cleanup_existing_build_products; }
          run_install_operation() { print -u2 unexpected-install; return 97; }
          run_uninstall_operation() { print -u2 unexpected-uninstall; return 97; }
          run_worker() { print -u2 unexpected-worker; return 97; }
        ZSH
        source += package == 'JobsFileCreator' ? "\nmain \"$@\"\n" : "\nmanager_main \"$@\"\n"
        output, error, result = execute(source, '--action', 'cleanup', '--install-location', 'applications', '--stop-request-file', stop, '--non-interactive', env: fixture_environment(dir))
        assert result.success?, "#{package}: #{error}"
        assert_includes output, "CLEANUP=applications|0|#{stop}", package
        assert_includes output, '正在清理构建产物', package
        assert_equal 'stop', File.read(stop), package
        [['--install-location', 'build'], ['--install-location', 'applications', '--cleanup-build-products']].each do |arguments|
          output, error, result = execute(source, '--action', 'cleanup', *arguments, '--non-interactive', env: fixture_environment(dir))
          assert_equal 2, result.exitstatus, "#{package}: #{error}"
          refute_includes output, 'CLEANUP=', package
        end
        output, error, result = execute(source, '--action', 'cleanup', '--install-location', 'applications', '--features', 'not-this-package', '--non-interactive', env: fixture_environment(dir))
        assert_equal 2, result.exitstatus, "#{package}: #{error}"
        refute_includes output, 'CLEANUP=', package
      end
    end
  end

  def test_all_entry_parsers_reject_missing_or_relative_stop_files_before_business
    Dir.glob(File.join(ROOT, 'Jobs*', 'Scripts/ManageExtension.zsh')).each do |path|
      package = File.basename(File.dirname(File.dirname(path)))
      source = definitions(package)
      source += package == 'JobsFileCreator' ? "\nparse_options \"$@\"\n" : "\nmanager_parse_options \"$@\"\n"
      %w[install uninstall cleanup].each do |action|
        [['--stop-request-file', '/tmp/jobs batch.stop'], ['--stop-request-file=/tmp/jobs batch.stop']].each do |arguments|
          output, error, result = execute(source + "\nprint -r -- \"STOP=$JOBS_FINDER_STOP_REQUEST_FILE\"\n", '--action', action, '--install-location', 'applications', *arguments)
          assert result.success?, "#{package}: #{error}"
          assert_includes output, 'STOP=/tmp/jobs batch.stop', package
        end
      end
      [%w[--stop-request-file], ['--stop-request-file', ''], %w[--stop-request-file relative], ['--stop-request-file=']].each do |arguments|
        output, error, result = execute(source, '--action', 'install', *arguments)
        assert_equal 2, result.exitstatus, "#{package}: #{output} #{error}"
      end
    end
  end

  def test_actual_cleanup_helpers_pass_only_the_selected_build_root_and_preserve_blocked_status
    REAL_PACKAGES.each do |package|
      Dir.mktmpdir('jobs-package-cleanup-boundary-') do |dir|
        built = File.join(dir, "Total with 空格/work/#{package}DerivedData/Build/Products/Debug/#{package}.app")
        source = definitions(package) + <<~'ZSH'
          MANAGER_ENTRY_DIR="$HOME/Package"
          PROJECT_DIR="$HOME/Package"
          JOBS_FINDER_BUILT_APP_PATH="$1"
          JOBS_FINDER_INSTALL_LOCATION=applications
          MANAGER_ACTION=cleanup
          manager_load_deployment() { return 0; }
          jobs_deployment_cleanup_existing_build_products() {
            print -r -- "EXISTING=${(j:|:)@}"
            print -u2 -r -- $'JOBS_MANAGER_BLOCKED\tapp-management\t77'
            return 77
          }
          manager_validate_existing_configuration() { print -u2 unexpected-config; return 97; }
          jobs_deployment_install() { print -u2 unexpected-deploy; return 97; }
          jobs_deployment_rollback() { print -u2 unexpected-rollback; return 97; }
          manager_restart_finder() { print -u2 unexpected-restart; return 97; }
          manager_cleanup_existing_build_products
        ZSH
        output, error, result = execute(source, built, env: fixture_environment(dir))
        assert_equal 77, result.exitstatus, "#{package}: #{error}"
        assert_includes output, "EXISTING=#{built}|#{File.dirname(File.dirname(File.dirname(File.dirname(built))))}|com.jobs.", package
        assert_includes error, "JOBS_MANAGER_BLOCKED\tapp-management\t77", package
        refute_includes error, 'unexpected-', package
        refute File.exist?(File.join(dir, 'Library')), package
        refute File.exist?(File.join(dir, 'Package')), package
      end
    end
  end

  def test_forwarding_entries_preserve_cleanup_scope_stop_file_and_blocked_result
    Dir.mktmpdir('jobs-package-forward-cleanup-') do |dir|
      stop = File.join(dir, '停止 batch.request')
      Dir.glob(File.join(ROOT, 'Jobs*', 'Scripts/ManageExtension.zsh')).each do |path|
        package = File.basename(File.dirname(File.dirname(path)))
        source = definitions(package)
        next unless source.include?('run_feature_operation() {') || source.include?('run_flutter_operation() {')
        target = if source.include?('run_flutter_operation() {')
                   File.join(dir, 'JobsFlutterTools/Scripts/ManageExtension.zsh')
                 elsif source.include?('ManageDesktopTools.zsh')
                   File.join(dir, 'JobsDesktopTools/Scripts/ManageDesktopTools.zsh')
                 else
                   File.join(dir, 'JobsProjectTools/Scripts/ManageProjectTools.zsh')
                 end
        FileUtils.mkdir_p(File.dirname(target))
        File.write(target, <<~'ZSH')
          print -r -- "LOCATION=$JOBS_FINDER_INSTALL_LOCATION|$JOBS_FINDER_STOP_REQUEST_FILE"
          printf 'ARG=%s\n' "$@"
          exit 77
        ZSH
        source += <<~'ZSH'
          manager_parse_options --action cleanup --install-location applications --stop-request-file "$2" --non-interactive || exit $?
          MANAGER_ENTRY_DIR="$HOME/$1"
          run_cleanup_operation
        ZSH
        output, error, result = execute(source, package, stop, env: fixture_environment(dir))
        assert_equal 77, result.exitstatus, "#{package}: #{error}"
        assert_includes output, "LOCATION=applications|#{stop}", package
        arguments = output.scan(/^ARG=(.*)$/).flatten
        assert_includes arguments, 'cleanup', package
        assert_equal stop, arguments[arguments.index('--stop-request-file') + 1], package
        allowed = File.read(path)[/local allowed=\(([^)]*)\)/, 1]&.split || File.read(path)[/extra=\(\) allowed=\(([^)]*)\)/, 1].split
        operation_index = arguments.index('cleanup')
        actual_leaves = if arguments.first == '--action'
                          arguments[arguments.index('--features') + 1].split(',')
                        else
                          arguments[(operation_index + 1)..].take_while { |argument| !argument.start_with?('--') }
                        end
        assert_equal allowed.sort, actual_leaves.sort, package
      end
    end
  end

  def test_every_entry_drops_previous_stop_request_and_preserves_own_scope_in_fresh_gui
    Dir.mktmpdir('jobs-package-forward-root-stop-') do |dir|
      manager = File.join(dir, 'Scripts/ManageFinderExtensions.zsh')
      FileUtils.mkdir_p(File.dirname(manager))
      File.write(manager, "printf 'ARG=%s\\n' \"$@\"\nprint -r -- \"STOP_ENV=$JOBS_FINDER_STOP_REQUEST_FILE\"\n")
      Dir.glob(File.join(ROOT, 'Jobs*', 'Scripts/ManageExtension.zsh')).each do |path|
        package = File.basename(File.dirname(File.dirname(path)))
        source = definitions(package)
        source += if package == 'JobsFileCreator'
                    <<~'ZSH'
                      parse_options --action cleanup --install-location applications --stop-request-file="$2" || exit $?
                      PROJECT_DIR="$HOME/$1"
                      open_management_panel
                    ZSH
                  else
                    <<~'ZSH'
                      manager_parse_options --action cleanup --install-location applications --stop-request-file="$2" || exit $?
                      MANAGER_ENTRY_DIR="$HOME/$1"
                      manager_open_gui
                    ZSH
                  end
        stop = File.join(dir, 'stop request')
        output, error, result = execute(source, package, stop, env: fixture_environment(dir))
        assert result.success?, "#{package}: #{error}"
        arguments = output.scan(/^ARG=(.*)$/).flatten
        assert_equal 'cleanup', arguments[arguments.index('--action') + 1], package
        refute_includes arguments, '--stop-request-file', package
        assert_includes output, "STOP_ENV=\n", package
        scope = package == 'JobsFileCreator' ? 'file-create' : File.read(path)[/MANAGER_UI_SCOPE="([^"]+)"/, 1]
        assert_equal scope, arguments[arguments.index('--scope') + 1], package
      end
    end
  end

  def test_aggregate_cleanup_bypasses_all_installation_state_and_preserves_real_result
    %w[JobsProjectTools JobsDesktopTools].each do |package|
      project = package == 'JobsProjectTools'
      filename = project ? 'ManageProjectTools.zsh' : 'ManageDesktopTools.zsh'
      leaf = project ? 'vscode_opener' : 'hidden-files-toggle'
      [0, 1, 77].each do |exit_code|
        Dir.mktmpdir('jobs-aggregate-cleanup-only-') do |dir|
          scripts = File.join(dir, package, 'Scripts')
          FileUtils.mkdir_p(scripts)
          module_path = File.join(scripts, '【MacOS】AppDeployment.zsh/【MacOS】AppDeployment.zsh')
          FileUtils.mkdir_p(File.dirname(module_path))
          File.write(module_path, <<~'ZSH')
            jobs_deployment_app_path() { print -r -- "$HOME/Applications/${1:t}"; }
            jobs_deployment_cleanup_existing_build_products() {
              print -r -- "ONLY_CLEANUP=${(j:|:)@}"
              print -r -- "STOP=$JOBS_FINDER_STOP_REQUEST_FILE"
              return "$JOBS_FIXTURE_CLEANUP_RESULT"
            }
            jobs_deployment_rollback() { print -u2 unexpected-rollback; return 97; }
            jobs_deployment_install() { print -u2 unexpected-install; return 97; }
          ZSH
          source = File.read(File.join(ROOT, package, 'Scripts', filename)).sub(/^main "\$@"\s*\z/, '')
          source += <<~'ZSH'
            read_configuration() { print -u2 unexpected-config; return 97; }
            install_features() { print -u2 unexpected-install; return 97; }
            uninstall_features() { print -u2 unexpected-uninstall; return 97; }
            main "$@"
          ZSH
          fixture = File.join(scripts, filename)
          File.write(fixture, source)
          stop = File.join(dir, 'stop')
          File.write(stop, 'stop')
          env = fixture_environment(dir).merge('JOBS_FIXTURE_CLEANUP_RESULT' => exit_code.to_s)
          args = ['cleanup', leaf, '--install-location', 'applications', '--stop-request-file', stop]
          args << '--non-interactive' unless project
          output, error, result = Open3.capture3(env, '/bin/zsh', fixture, *args)
          assert_equal exit_code, result.exitstatus, "#{package}: #{output} #{error}"
          assert_equal 1, output.scan(/^ONLY_CLEANUP=/).size, package
          assert_includes output, "ONLY_CLEANUP=#{File.realpath(File.join(dir, package))}/work/DerivedData/Build/Products/Debug/#{package}.app|#{File.realpath(File.join(dir, package))}/work/DerivedData|", package
          assert_includes output, "STOP=#{stop}", package
          refute_includes error, 'unexpected-', package
          refute File.exist?(File.join(dir, package, 'work')), package
          refute File.exist?(File.join(dir, 'Library')), package
          assert_equal 'stop', File.read(stop), package
          invalids = [['cleanup', leaf, '--install-location', 'build'], ['cleanup', leaf, '--install-location', 'applications', '--cleanup-build-products'], ['install', leaf, '--stop-request-file', 'relative'], ['install', leaf, '--stop-request-file=']]
          invalids.each do |invalid|
            output, error, result = Open3.capture3(env, '/bin/zsh', fixture, *invalid)
            assert_equal 2, result.exitstatus, "#{package}: #{error}"
            refute_includes output, 'ONLY_CLEANUP=', package
          end
        end
      end
    end
  end

end
