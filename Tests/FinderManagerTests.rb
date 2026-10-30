# frozen_string_literal: true
# 在临时配置和命令替身下验证统一管理计划，不构建、登记扩展或刷新 Finder。
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'

class FinderManagerTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  MANAGER = File.join(ROOT, 'Scripts/ManageFinderExtensions.zsh')

  def run_definitions(checks, *arguments, stdin: '', replacements: {})
    source = File.read(MANAGER).sub(/^main "\$@"\s*\z/, '')
    replacements.each { |from, to| source = source.gsub(from, to) }
    Dir.mktmpdir('jobs-finder-manager-') do |directory|
      fixture = File.join(directory, '管理 定义.zsh')
      File.write(fixture, source + "\nLOG_FILE=/dev/null\n" + checks)
      Open3.capture3('/bin/zsh', fixture, *arguments, stdin_data: stdin)
    end
  end

  def test_explicit_scope_and_action_form_one_deduplicated_plan
    output, errors, status = run_definitions(<<~'ZSH')
      parse_management_options --scope git-pull,git-rollback --features git-pull,git-pull,git-rollback --action uninstall --non-interactive || exit $?
      select_management_features || exit $?
      print -r -- "$MANAGEMENT_ACTION|${(j:,:)SELECTED_KEYS}|${(j:,:)SELECTED_FUNCTION_IDS}"
    ZSH
    assert status.success?, errors
    assert_equal "uninstall|project-tools|git-pull,git-rollback\n", output
  end

  def test_invalid_unknown_empty_or_out_of_scope_parameters_stop
    [
      %w[--non-interactive],
      %w[--action uninstall --non-interactive],
      %w[--action erase],
      ['--scope', ''],
      %w[--scope unknown],
      %w[--scope git-pull --action uninstall --features git-rollback --non-interactive],
      %w[--action uninstall --features git-pull, --non-interactive],
      %w[--action uninstall --features git-pull,,git-rollback --non-interactive],
      %w[--features git-pull]
    ].each do |arguments|
      _, _, status = run_definitions('parse_management_options "$@"', *arguments)
      refute status.success?, arguments.inspect
    end
  end

  def test_panel_install_and_uninstall_execute_without_another_terminal_read
    %w[install uninstall].each do |action|
      output, errors, status = run_definitions(<<~'ZSH', action)
        MANAGEMENT_ACTION="$1"
        MANAGER_NON_INTERACTIVE=1
        CLI_FEATURES=path_copier
        show_script_intro_and_wait() { return 0; }
        init_runtime() { return 0; }
        select_management_features() { parse_feature_selection path_copier; }
        read() { print -u2 'unexpected terminal confirmation'; return 99; }
        check_environment() { return 0; }
        install_selected_features() { print 'BUSINESS=install'; }
        uninstall_selected_features() { print 'BUSINESS=uninstall'; }
        restart_finder_after_install() { return 0; }
        print_done_tips() { return 0; }
        main
      ZSH
      assert status.success?, errors
      assert_includes output, "BUSINESS=#{action}"
      refute_includes errors, 'unexpected terminal confirmation'
    end
  end

  def test_partial_flutter_uninstall_keeps_sibling_and_never_unloads_package
    Dir.mktmpdir('jobs-flutter-partial-') do |directory|
      config = File.join(directory, '配置 带空格', 'flutter.conf')
      FileUtils.mkdir_p(File.dirname(config))
      File.write(config, 'run,package-android,codegen')
      output, errors, status = run_definitions(<<~'ZSH', config)
        FLUTTER_FEATURE_CONFIG_PATH="$1"
        MANAGEMENT_ACTION=uninstall
        parse_feature_selection flutter-package-android || exit 1
        run_independent_uninstall() { print 'unexpected-full-uninstall'; return 99; }
        uninstall_feature flutter-tools || exit 1
      ZSH
      assert status.success?, errors
      refute_includes output, 'unexpected-full-uninstall'
      assert_equal 'run,codegen', File.read(config)
    end
  end

  def test_last_flutter_action_unloads_only_its_package
    Dir.mktmpdir('jobs-flutter-last-') do |directory|
      config = File.join(directory, 'flutter.conf')
      File.write(config, 'package-android')
      output, errors, status = run_definitions(<<~'ZSH', config)
        FLUTTER_FEATURE_CONFIG_PATH="$1"
        MANAGEMENT_ACTION=uninstall
        parse_feature_selection flutter-package-android || exit 1
        run_independent_uninstall() { print -r -- "unload:$1"; }
        uninstall_feature flutter-tools
      ZSH
      assert status.success?, errors
      assert_includes output, 'unload:flutter-tools'
      refute_includes output, 'unload:terminal_opener'
    end
  end

  def test_terminal_uninstall_preserves_current_and_legacy_siblings
    Dir.mktmpdir('jobs-terminal-partial-') do |directory|
      config = File.join(directory, 'terminal.conf')
      File.write(config, 'open,pod-install,codegraph-bootstrap')
      _, errors, status = run_definitions(<<~'ZSH', config)
        TERMINAL_FEATURE_CONFIG_PATH="$1"
        MANAGEMENT_ACTION=uninstall
        parse_feature_selection terminal_open || exit 1
        run_independent_uninstall() { return 99; }
        uninstall_feature terminal_opener
      ZSH
      assert status.success?, errors
      assert_equal 'pod-install,codegraph-bootstrap', File.read(config)
    end
  end

  def test_file_viewer_maps_to_terminal_and_uninstalls_only_its_action
    Dir.mktmpdir('jobs-file-viewer-selection-') do |directory|
      config = File.join(directory, 'terminal.conf')
      File.write(config, 'open,file-content,pod-install,codegraph-bootstrap')
      output, errors, status = run_definitions(<<~'ZSH', config)
        TERMINAL_FEATURE_CONFIG_PATH="$1"
        parse_feature_selection file_content,file_content || exit 1
        print -r -- "${(j:,:)SELECTED_KEYS}|$TERMINAL_OPENER_ENABLED_FEATURES"
        validate_group_configuration terminal_opener 'file-content' || exit 1
        run_independent_uninstall() { print 'unexpected-full-uninstall'; return 99; }
        uninstall_feature terminal_opener || exit 1
      ZSH
      assert status.success?, errors
      assert_includes output, 'terminal_opener|file-content'
      refute_includes output, 'unexpected-full-uninstall'
      assert_equal 'open,pod-install,codegraph-bootstrap', File.read(config)
    end
  end

  def test_installing_file_viewer_preserves_existing_terminal_choices
    Dir.mktmpdir('jobs-file-viewer-add-') do |directory|
      config = File.join(directory, 'terminal.conf')
      File.write(config, 'open,codegraph-bootstrap')
      _, errors, status = run_definitions(<<~'ZSH', config)
        TERMINAL_FEATURE_CONFIG_PATH="$1"
        TERMINAL_FEATURE_CONFIG_DIR="${1:h}"
        parse_feature_selection file_content || exit 1
        build_feature() { return 0; }
        register_and_enable_feature() { return 0; }
        install_feature terminal_opener || exit 1
      ZSH
      assert status.success?, errors
      assert_equal %w[open codegraph-bootstrap file-content].sort, File.read(config).split(',').sort
    end
  end

  def test_terminal_missing_user_config_reads_enabled_app_default
    Dir.mktmpdir('jobs-terminal-fallback-') do |directory|
      app = File.join(directory, '中文 目录', 'JobsTerminalOpener.app')
      info = File.join(app, 'Contents', 'Info.plist')
      FileUtils.mkdir_p(File.dirname(info))
      File.write(info, '<?xml version="1.0"?><plist version="1.0"><dict><key>JobsTerminalEnabledFeatures</key><string>open,codegraph-bootstrap</string></dict></plist>')
      extension = File.join(app, 'Contents', 'PlugIns', 'JobsTerminalFinderSync.appex')
      output, errors, status = run_definitions(<<~'ZSH', File.join(directory, 'missing'), extension, replacements: {'/usr/bin/pluginkit' => 'fake_pluginkit'})
        TERMINAL_FEATURE_CONFIG_PATH="$1"
        MANAGEMENT_ACTION=uninstall
        records="$2"
        fake_pluginkit() { print -r -- '+ com.jobs.JobsTerminalOpener.FinderSyncExtension'; print -r -- "    Path = $records"; }
        parse_feature_selection terminal_open || exit 1
        plan_group_feature_removal terminal_opener || exit 1
        print -r -- "remaining:$REMAINING_CONFIG_FEATURES"
      ZSH
      assert status.success?, errors
      assert_includes output, 'remaining:codegraph-bootstrap'
      refute_includes output, 'pod-install'
    end
  end

  def test_symlink_configuration_is_rejected_before_unload_or_write
    Dir.mktmpdir('jobs-config-link-') do |directory|
      original = File.join(directory, 'original')
      config = File.join(directory, 'linked')
      File.write(original, 'run,codegen')
      File.symlink(original, config)
      _, _, status = run_definitions(<<~'ZSH', config)
        FLUTTER_FEATURE_CONFIG_PATH="$1"
        parse_feature_selection flutter-codegen || exit 1
        MANAGEMENT_ACTION=uninstall
        run_independent_uninstall() { return 0; }
        uninstall_feature flutter-tools
      ZSH
      refute status.success?
      assert_equal 'run,codegen', File.read(original)
    end
  end

  def test_malformed_group_configuration_stops_before_overwrite
    Dir.mktmpdir('jobs-invalid-config-') do |directory|
      config = File.join(directory, 'flutter.conf')
      ['run,unknown', 'run,,codegen', 'run,run', ',run', 'run,'].each do |value|
        File.write(config, value)
        _, _, status = run_definitions(<<~'ZSH', config)
          FLUTTER_FEATURE_CONFIG_PATH="$1"
          parse_feature_selection flutter-codegen || exit 1
          run_independent_uninstall() { return 0; }
          uninstall_feature flutter-tools
        ZSH
        refute status.success?, value
        assert_equal value, File.read(config)
      end
    end
  end

  def test_missing_or_disabled_flutter_registration_does_not_enable_old_defaults
    ['  (no matches)', '- com.jobs.JobsFlutterTools.FinderSyncExtension'].each do |records|
      output, errors, status = run_definitions(<<~'ZSH', records, replacements: {'/usr/bin/pluginkit' => 'fake_pluginkit'})
        FLUTTER_FEATURE_CONFIG_PATH="${0:h}/missing"
        records="$1"
        fake_pluginkit() { print -r -- "$records"; }
        read_group_configuration flutter-tools
      ZSH
      assert status.success?, errors
      assert_empty output
    end
  end

  def test_bad_ios_configuration_stops_before_build_and_keeps_file
    Dir.mktmpdir('jobs-ios-invalid-') do |directory|
      config = File.join(directory, 'ios.conf')
      File.write(config, 'ios-pod-install,unknown')
      output, _, status = run_definitions(<<~'ZSH', config)
        IOS_FEATURE_CONFIG_PATH="$1"
        parse_feature_selection ios-code-snippets || exit 1
        build_feature() { print 'unexpected-build'; return 0; }
        install_feature ios-tools
      ZSH
      refute status.success?
      refute_includes output, 'unexpected-build'
      assert_equal 'ios-pod-install,unknown', File.read(config)
    end
  end

  def test_project_and_desktop_delegates_receive_only_selected_leaf_ids
    output, errors, status = run_definitions(<<~'ZSH', replacements: {'/bin/zsh "$WORKSPACE_DIR/JobsProjectTools/Scripts/ManageProjectTools.zsh"' => 'record_project', '/bin/zsh "$WORKSPACE_DIR/JobsDesktopTools/Scripts/ManageDesktopTools.zsh"' => 'record_desktop'})
      record_project() { print -r -- "project:${(j:|:)@}"; }
      record_desktop() { print -r -- "desktop:${(j:|:)@}"; }
      parse_feature_selection git-rollback,android-simulator-repair || exit 1
      uninstall_selected_features || exit 1
    ZSH
    assert status.success?, errors
    assert_includes output, 'project:uninstall|git-rollback'
    assert_includes output, 'desktop:uninstall|android-simulator-repair|--non-interactive|--skip-finder-restart'
    refute_includes output, 'git-pull'
  end

  def test_installing_one_flutter_action_keeps_existing_choices
    Dir.mktmpdir('jobs-flutter-add-') do |directory|
      config = File.join(directory, 'flutter.conf')
      File.write(config, 'run')
      _, errors, status = run_definitions(<<~'ZSH', config)
        FLUTTER_FEATURE_CONFIG_PATH="$1"
        FLUTTER_FEATURE_CONFIG_DIR="${1:h}"
        parse_feature_selection flutter-codegen || exit 1
        build_feature() { return 0; }
        register_and_enable_feature() { return 0; }
        install_feature flutter-tools
      ZSH
      assert status.success?, errors
      assert_equal 'run,codegen', File.read(config)
    end
  end

  def test_failure_reports_selected_leaf_and_keeps_failure_status
    output, errors, status = run_definitions(<<~'ZSH')
      parse_feature_selection git-pull,run-authorize || exit 1
      uninstall_feature() { [[ "$1" == project-tools ]]; }
      uninstall_selected_features
      print -r -- "result:$FINAL_EXIT_STATUS|${(j:,:)SUCCEEDED_FEATURES}|${(j:,:)FAILED_FEATURES}"
    ZSH
    assert status.success?, errors
    assert_includes output, 'result:1|拉取 Git 到最新|运行授权'
  end
end
