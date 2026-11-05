# frozen_string_literal: true
# 总管理器的双安装位置回归；仅使用临时目录和登记替身，不执行安装、注销或刷新 Finder。
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'
require_relative '../IsolatedInstallerDefinitions'

class ApplicationsLocationIntegrationTests < Minitest::Test
  include IsolatedInstallerDefinitions
  ROOT = File.expand_path('../..', __dir__)
  MANAGER = File.join(ROOT, 'Scripts/ManageFinderExtensions.zsh')

  def run_fixture(checks, *arguments)
    source = isolated_installer_source(MANAGER)
    Dir.mktmpdir('jobs-location-integration-') do |directory|
      fixture = File.join(directory, 'manager.zsh')
      File.write(fixture, source + "\nLOG_FILE=/dev/null\n" + checks)
      Open3.capture3(isolated_installer_environment(directory), '/bin/zsh', '-f', fixture, *arguments)
    end
  end

  def test_location_defaults_to_build_and_rejects_unknown_or_missing_values
    output, errors, result = run_fixture(<<~'ZSH')
      parse_management_options --action install --features file-create --non-interactive || exit $?
      print -r -- "DEFAULT=$JOBS_FINDER_INSTALL_LOCATION"
      parse_management_options --action uninstall --features file-create --non-interactive --install-location applications || exit $?
      print -r -- "APPS=$JOBS_FINDER_INSTALL_LOCATION"
    ZSH
    assert result.success?, errors
    assert_equal "DEFAULT=build\nAPPS=applications\n", output
    [%w[--install-location elsewhere], ['--install-location']].each do |options|
      _, _, failed = run_fixture('parse_management_options --action install --features file-create --non-interactive "$@"', *options)
      assert_equal 2, failed.exitstatus
    end
  end

  def test_build_output_and_selected_registration_path_remain_distinct
    Dir.mktmpdir('中文 Apps ') do |directory|
      output, errors, result = run_fixture(<<~'ZSH', directory)
        WORKSPACE_DIR="$1/source"
        export JOBS_FINDER_APPLICATIONS_DIR="$1/Applications"
        print -r -- "BUILD=$(built_app_path_for_key file-create)"
        print -r -- "DEFAULT=$(app_path_for_key file-create)"
        JOBS_FINDER_INSTALL_LOCATION=applications
        print -r -- "TARGET=$(app_path_for_key file-create)"
        print -r -- "EXT=$(extension_path_for_key file-create)"
        print -r -- "SOURCE=$(built_app_path_for_key file-create)"
      ZSH
      assert result.success?, errors
      built = File.join(directory, 'source/work/JobsFileCreatorDerivedData/Build/Products/Debug/JobsFileCreator.app')
      target = File.join(directory, 'Applications/Jobs自定义右键菜单.app/Contents/Applications/JobsFileCreator.app')
      assert_equal ["BUILD=#{built}", "DEFAULT=#{built}", "TARGET=#{target}",
                    "EXT=#{target}/Contents/PlugIns/JobsFileCreatorFinderSync.appex", "SOURCE=#{built}"], output.lines.map(&:chomp)
    end
  end

  def test_applications_deployment_commits_only_after_registration_and_rolls_back_failure
    [0, 41].each do |registration_result|
      output, errors, result = run_fixture(<<~'ZSH', registration_result.to_s)
        JOBS_FINDER_INSTALL_LOCATION=applications
        parse_feature_selection file-create || exit 1
        build_feature() { print 'BUILD'; }
        jobs_deployment_install() { print -r -- "COPY=${(j:|:)@}"; }
        jobs_deployment_commit() { print 'COMMIT'; }
        jobs_deployment_rollback() { print 'ROLLBACK'; }
        register_and_enable_feature() { print 'REGISTER'; return "$JOBS_TEST_REGISTRATION_RESULT"; }
        JOBS_TEST_REGISTRATION_RESULT="$1"
        install_feature file-create
      ZSH
      if registration_result.zero?
        assert result.success?, errors
        assert_includes output, 'COMMIT'
        refute_includes output, 'ROLLBACK'
      else
        refute result.success?, errors
        assert_includes output, 'ROLLBACK'
        refute_includes output, 'COMMIT'
      end
      assert_match(/COPY=.*JobsFileCreator\.app\|com\.jobs\.filecreator\|JobsFileCreatorFinderSync\.appex\|com\.jobs\.filecreator\.findersync/, output)
      assert_operator output.index('BUILD'), :<, output.index('COPY=')
      assert_operator output.index('COPY='), :<, output.index('REGISTER')
    end
  end

  def test_uninstall_of_missing_selected_location_preserves_shared_configuration
    Dir.mktmpdir('jobs-location-missing-') do |directory|
      config = File.join(directory, 'flutter.conf')
      File.write(config, 'run,codegen')
      %w[build applications].each do |location|
        output, errors, result = run_fixture(<<~'ZSH', directory, config, location)
          WORKSPACE_DIR="$1/source"
          JOBS_FINDER_APPLICATIONS_DIR="$1/Applications"
          FLUTTER_FEATURE_CONFIG_PATH="$2"
          JOBS_FINDER_INSTALL_LOCATION="$3"
          parse_feature_selection flutter-codegen || exit 1
          run_independent_uninstall() { print unexpected-uninstall; return 99; }
          uninstall_feature flutter-tools
        ZSH
        assert result.success?, errors
        refute_includes output, 'unexpected-uninstall'
        assert_equal 'run,codegen', File.read(config)
      end
    end
  end

  def test_foreign_app_is_rejected_before_shared_configuration_is_changed
    Dir.mktmpdir('jobs-location-identity-') do |directory|
      app = File.join(directory, 'Jobs自定义右键菜单.app/Contents/Applications/JobsFlutterTools.app')
      FileUtils.mkdir_p(File.join(app, 'Contents'))
      File.write(File.join(app, 'Contents/Info.plist'), <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.foreign.app</string></dict></plist>
      XML
      output, errors, result = run_fixture(<<~'ZSH', directory)
        load_deployment_support() { return 0; }
        jobs_deployment_app_path() { print -r -- "$JOBS_FINDER_APPLICATIONS_DIR/Jobs自定义右键菜单.app/Contents/Applications/JobsFlutterTools.app"; }
        jobs_deployment_validate_app() {
          [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist")" == "$2" ]]
        }
        JOBS_FINDER_APPLICATIONS_DIR="$1"
        JOBS_FINDER_INSTALL_LOCATION=applications
        parse_feature_selection flutter-codegen || exit 1
        write_group_configuration() { print unexpected-config-write; }
        run_independent_uninstall() { print unexpected-uninstall; }
        uninstall_feature flutter-tools
      ZSH
      assert_equal 2, result.exitstatus, errors
      refute_includes output, 'unexpected-config-write'
      refute_includes output, 'unexpected-uninstall'
      assert File.exist?(File.join(app, 'Contents/Info.plist'))
    end
  end

  def test_failed_registration_restores_original_ios_configuration_bytes
    Dir.mktmpdir('jobs-location-config-') do |directory|
      config = File.join(directory, 'ios.conf')
      original = "ios-code-snippets\n"
      File.write(config, original)
      output, errors, result = run_fixture(<<~'ZSH', config)
        IOS_FEATURE_CONFIG_PATH="$1"
        IOS_FEATURE_CONFIG_DIR="${1:h}"
        JOBS_FINDER_INSTALL_LOCATION=applications
        parse_feature_selection ios-pod-update || exit 1
        build_feature() { return 0; }
        jobs_deployment_install() { return 0; }
        jobs_deployment_rollback() { print ROLLBACK; }
        register_and_enable_feature() { return 41; }
        install_feature ios-tools
      ZSH
      refute result.success?, errors
      assert_includes output, 'ROLLBACK'
      assert_equal original, File.read(config)
    end
  end

  def test_configuration_failure_after_flutter_publication_restores_old_choices
    [false, true].each do |concurrent_change|
      Dir.mktmpdir('jobs-location-config-publication-') do |directory|
        config = File.join(directory, 'flutter.conf')
        File.write(config, "run\n")
        output, errors, result = run_fixture(<<~'ZSH', config, concurrent_change ? '1' : '0')
          FLUTTER_FEATURE_CONFIG_PATH="$1"
          FLUTTER_FEATURE_CONFIG_DIR="${1:h}"
          JOBS_FINDER_INSTALL_LOCATION=applications
          parse_feature_selection flutter-codegen || exit 1
          JOBS_TEST_CONCURRENT_CHANGE="$2"
          build_feature() { return 0; }
          jobs_deployment_install() { return 0; }
          jobs_deployment_rollback() { print ROLLBACK; }
          register_and_enable_feature() { return 0; }
          persist_terminal_feature_selection() {
            if [[ "$JOBS_TEST_CONCURRENT_CHANGE" == 1 ]]; then
              print -r -- externally-changed > "$FLUTTER_FEATURE_CONFIG_PATH"
            fi
            return 41
          }
          install_feature flutter-tools
        ZSH
        refute result.success?, errors
        assert_includes output, 'ROLLBACK'
        assert_equal concurrent_change ? "externally-changed\n" : "run\n", File.read(config)
      end
    end
  end

  def test_inactive_copy_uninstall_bypasses_active_copys_shared_configuration
    Dir.mktmpdir('jobs-location-active-') do |directory|
      config = File.join(directory, 'flutter.conf')
      File.write(config, 'run,codegen')
      output, errors, result = run_fixture(<<~'ZSH', config)
        FLUTTER_FEATURE_CONFIG_PATH="$1"
        parse_feature_selection flutter-codegen || exit 1
        selected_location_has_app() { return 0; }
        another_location_is_active() { return 0; }
        run_independent_uninstall() { print 'REMOVE_INACTIVE_COPY'; }
        uninstall_feature flutter-tools
      ZSH
      assert result.success?, errors
      assert_includes output, 'REMOVE_INACTIVE_COPY'
      assert_equal 'run,codegen', File.read(config)
    end
  end

  def test_cleanup_flag_is_only_valid_for_applications_install_before_any_work
    [%w[install applications], %w[install build], %w[uninstall applications], %w[uninstall build]].each do |action, location|
      output, errors, result = run_fixture(<<~'ZSH', action, location)
        parse_management_options --action "$1" --install-location "$2" --cleanup-build-products --features file-create --non-interactive || exit $?
        print -r -- "ACCEPTED=$JOBS_FINDER_CLEANUP_BUILD_PRODUCTS"
      ZSH
      if action == 'install' && location == 'applications'
        assert result.success?, errors
        assert_includes output, 'ACCEPTED=1'
      else
        assert_equal 2, result.exitstatus
        refute_includes output, 'ACCEPTED='
      end
    end
  end

  def test_cleanup_is_after_commit_and_never_after_registration_failure
    [0, 41].each do |registration_result|
      output, errors, result = run_fixture(<<~'ZSH', registration_result.to_s)
        JOBS_FINDER_INSTALL_LOCATION=applications
        JOBS_FINDER_CLEANUP_BUILD_PRODUCTS=1
        JOBS_TEST_REGISTRATION_RESULT="$1"
        parse_feature_selection file-create || exit 1
        build_feature() { print BUILD; }
        jobs_deployment_install() { print DEPLOY; }
        jobs_deployment_commit() { print COMMIT; }
        jobs_deployment_rollback() { print ROLLBACK; }
        register_and_enable_feature() { print REGISTER; return "$JOBS_TEST_REGISTRATION_RESULT"; }
        jobs_deployment_cleanup_build_products() { print -r -- "CLEAN=${(j:|:)@}"; return 71; }
        install_feature file-create
      ZSH
      if registration_result.zero?
        assert result.success?, errors
        assert_match(/CLEAN=.*JobsFileCreator\.app\|.*JobsFileCreatorDerivedData\|com\.jobs\.filecreator\|JobsFileCreatorFinderSync\.appex\|com\.jobs\.filecreator\.findersync/, output)
        assert_operator output.index('COMMIT'), :<, output.index('CLEAN=')
        assert_includes output, '清理失败'
        refute_includes output, 'ROLLBACK'
      else
        refute result.success?, errors
        refute_includes output, 'CLEAN='
        assert_includes output, 'ROLLBACK'
      end
    end
  end

  def test_independent_cleanup_is_apps_only_and_reuses_each_units_exact_build_root
    output, errors, result = run_fixture(<<~'ZSH', ROOT)
      WORKSPACE_DIR="$1"
      parse_management_options --action cleanup --install-location applications --features git-pull,git-rollback,file-create --non-interactive || exit $?
      parse_feature_selection "$CLI_FEATURES" || exit 1
      jobs_deployment_cleanup_existing_build_products() { print -r -- "CLEAN=${(j:|:)@}"; }
      install_feature() { print unexpected-install; return 99; }
      cleanup_selected_features
    ZSH
    assert result.success?, errors
    calls = output.lines.grep(/^CLEAN=/)
    assert_equal 2, calls.length
    assert_includes calls[0], '/JobsProjectTools/work/DerivedData/Build/Products/Debug/JobsProjectTools.app|'
    assert_includes calls[1], '/work/JobsFileCreatorDerivedData/Build/Products/Debug/JobsFileCreator.app|'
    refute_includes output, 'unexpected-install'
    _, _, rejected = run_fixture('parse_management_options --action cleanup --install-location build --features file-create --non-interactive')
    assert_equal 2, rejected.exitstatus
  end

  def test_stop_waits_until_current_install_unit_finishes_then_skips_remaining_units
    Dir.mktmpdir('jobs-cooperative-stop-') do |directory|
      output, errors, result = run_fixture(<<~'ZSH', File.join(directory, 'stop-request'))
        parse_management_options --action install --features file-create,path_copier,run-authorize --stop-request-file "$1" --non-interactive || exit $?
        parse_feature_selection "$CLI_FEATURES" || exit 1
        ensure_feature_projects_exist() { return 0; }
        install_feature() {
          print -r -- "INSTALL_START=$1"
          : > "$JOBS_FINDER_STOP_REQUEST_FILE"
          print -r -- "INSTALL_FINISHED=$1"
        }
        install_selected_features
        print -r -- "EXIT=$FINAL_EXIT_STATUS"
      ZSH
      assert result.success?, errors
      assert_equal ['INSTALL_START=file-create', 'INSTALL_FINISHED=file-create'], output.lines.map(&:chomp).grep(/^INSTALL_/)
      assert_includes output, "JOBS_MANAGER_EVENT\tfile-create\tsucceeded"
      assert_includes output, "JOBS_MANAGER_EVENT\tpath_copier\tskipped"
      assert_includes output, "JOBS_MANAGER_EVENT\trun-authorize\tskipped"
      assert_includes output, 'JOBS_MANAGER_STOPPED'
      assert_includes output, 'EXIT=0'
      refute_match(/\tfailed\t/, output)
    end
  end

  def test_app_management_block_from_child_stops_next_build_and_preserves_exit_77
    Dir.mktmpdir('jobs-auth-blocked-') do |directory|
      output, errors, result = run_fixture(<<~'ZSH', File.join(directory, 'app-management.blocked'))
        JOBS_FINDER_BLOCKED_FILE="$1"
        parse_feature_selection file-create,path_copier,run-authorize || exit 1
        ensure_feature_projects_exist() { return 0; }
        install_feature() { print -r -- "INSTALL=$1"; print app-management > "$JOBS_FINDER_BLOCKED_FILE"; return 1; }
        install_selected_features
        print -r -- "EXIT=$FINAL_EXIT_STATUS"
      ZSH
      assert result.success?, errors
      assert_equal ['INSTALL=file-create'], output.lines.map(&:chomp).grep(/^INSTALL=/)
      assert_includes output, "JOBS_MANAGER_BLOCKED\tapp-management\t77"
      assert_includes output, "JOBS_MANAGER_EVENT\tfile-create\tfailed"
      assert_includes output, "JOBS_MANAGER_EVENT\tpath_copier\tskipped"
      assert_includes output, 'EXIT=77'
      refute_includes output, 'JOBS_MANAGER_STOPPED'
    end
  end

  def test_private_block_flag_survives_real_child_process_even_if_its_status_is_wrapped
    library = File.join(ROOT, 'Scripts/【MacOS】AppDeployment.zsh/【MacOS】AppDeployment.zsh')
    output, errors, result = run_fixture(<<~'ZSH', library)
      init_runtime
      MODULE_FIXTURE="$1"
      export JOBS_FINDER_RESPONSIBLE_APP=/fixture/JobsManager.app
      parse_feature_selection file-create,path_copier || exit 1
      ensure_feature_projects_exist() { return 0; }
      install_feature() {
        print -r -- "INSTALL=$1"
        /bin/zsh -f -c 'source "$1"; jobs_deployment_error "Operation not permitted: /Applications/Jobs自定义右键菜单.app/Contents/_CodeSignature"' fixture "$MODULE_FIXTURE" || return 1
      }
      install_selected_features
      [[ -s "$JOBS_FINDER_BLOCKED_FILE" ]] || exit 91
      print -r -- "EXIT=$FINAL_EXIT_STATUS"
    ZSH
    assert result.success?, errors
    assert_equal ['INSTALL=file-create'], output.lines.map(&:chomp).grep(/^INSTALL=/)
    assert_includes output, 'EXIT=77'
    assert_includes output, "JOBS_MANAGER_EVENT\tpath_copier\tskipped"
    assert_includes errors, "JOBS_MANAGER_BLOCKED\tapp-management\t77"
  end
end
