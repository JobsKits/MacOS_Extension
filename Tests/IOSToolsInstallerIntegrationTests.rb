# frozen_string_literal: true
# 读取真实安装定义，在隔离目录核对 iOS 子功能映射、配置合并与派发；不构建或注册扩展。

require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class IOSToolsInstallerIntegrationTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  INSTALLER = File.join(ROOT, '【MacOS】🧩安装Finder扩展.command')
  UNINSTALLER = File.join(ROOT, '【MacOS】🧩卸载Finder扩展.command')
  IDS = %w[ios-disable-sandbox ios-install-cocoapods ios-pods-source-github
           ios-extract-pods ios-pod-update ios-xcode-dependencies ios-pod-repo-update ios-pod-build-check ios-code-snippets ios-clean-build-artifacts].freeze
  ACTION_IDS = (IDS.take(4) + ['ios-pod-install'] + IDS.drop(4)).freeze

  def test_ios_options_are_unique_and_map_to_one_project
    selector = File.read(File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift'))
    ios = selector[/static let ios:.*?\n    \]/m]
    refute_nil ios
    assert_equal IDS, ios.scan(/FeatureOption\(identifier: "([^"]+)"/).flatten
    output = run_definitions(INSTALLER, <<~'ZSH', IDS.join(','))
      parse_feature_selection "$1,$1" || exit 1
      print -r -- "${(j:,:)SELECTED_FUNCTION_IDS}"
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "$IOS_TOOLS_ENABLED_FEATURES"
      print -r -- "terminal:$TERMINAL_OPENER_ENABLED_FEATURES"
      print -r -- "${#SELECTABLE_FUNCTION_IDS[@]}:${#FEATURE_KEYS[@]}"
    ZSH
    lines = output.lines.map(&:strip)
    assert_equal [IDS.join(','), 'ios-tools', IDS.join(','), 'terminal:'], lines.first(4)
    option_count, project_count = lines.last.split(':').map(&:to_i)
    assert_equal selector.scan(/FeatureOption\(identifier: "([^"]+)"/).length, option_count
    assert_operator option_count, :>=, 29
    assert_operator project_count, :>=, 12
  end

  def test_codesnippets_can_be_installed_alone_without_disabling_existing_ios_tools
    Dir.mktmpdir('jobs-snippets-feature-config-') do |directory|
      config = File.join(directory, 'EnabledFeatures.txt')
      File.write(config, 'ios-pod-update')
      run_definitions(INSTALLER, <<~'ZSH', config)
        IOS_FEATURE_CONFIG_PATH="$1"
        IOS_FEATURE_CONFIG_DIR="${1:h}"
        parse_feature_selection 'ios-code-snippets' || exit 1
        [[ "${(j:,:)SELECTED_KEYS}" == ios-tools ]] || exit 1
        persist_ios_feature_selection ios-tools || exit 1
      ZSH
      assert_equal 'ios-pod-update,ios-code-snippets', File.read(config)
    end
  end

  def test_pod_install_and_ios_build_cleanup_are_independent_ios_actions
    output = run_definitions(INSTALLER, <<~'ZSH')
      parse_feature_selection 'pod_install,ios-clean-build-artifacts,pod_install' || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "$IOS_TOOLS_ENABLED_FEATURES"
      print -r -- "terminal:$TERMINAL_OPENER_ENABLED_FEATURES"
    ZSH
    assert_equal ['ios-tools', 'ios-pod-install,ios-clean-build-artifacts', 'terminal:'], output.lines.map(&:strip)
  end

  def test_all_five_git_actions_share_one_project_without_terminal_dependencies
    ids = %w[git-pull git_remote git_remote_copier git-proxy-configure git_empty_commit_push]
    output = run_definitions(INSTALLER, <<~'ZSH', ids.join(','))
      parse_feature_selection "$1" || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "terminal:$TERMINAL_OPENER_ENABLED_FEATURES"
      print -r -- "ios:$IOS_TOOLS_ENABLED_FEATURES"
    ZSH
    assert_equal ['project-tools', 'terminal:', 'ios:'], output.lines.map(&:strip)
    output = run_definitions(UNINSTALLER, <<~'ZSH', ROOT, *ids, replacements: {'/bin/zsh "$WORKSPACE_DIR/JobsProjectTools/Scripts/ManageProjectTools.zsh"' => 'jobs_record_git_uninstall'})
      WORKSPACE_DIR="$1"
      shift
      jobs_record_git_uninstall() { print -r -- "delegate:${(j:|:)@}"; }
      for key in "$@"; do
        uninstall_feature "$key" || exit 1
      done
    ZSH
    assert_equal ids.map { |id| "delegate:uninstall|#{id}" }, output.lines.map(&:strip)
  end

  def test_independent_install_and_uninstall_share_the_complete_fixed_action_list
    %w[安装 卸载].each do |operation|
      path = File.join(ROOT, "JobsIOSTools/【MacOS】#{operation}iOS辅助工具Finder扩展.command")
      output = run_definitions(path, <<~'ZSH')
        parse_feature_options --features ios-code-snippets || exit 1
        print -r -- "${(j:,:)ALL_FEATURES}"
        print -r -- "${(j:,:)REQUESTED_FEATURES}"
      ZSH
      assert_equal [ACTION_IDS.join(','), 'ios-code-snippets'], output.lines.map(&:strip)
    end
  end

  def test_ios_project_identity_matches_install_and_uninstall
    output = run_definitions(INSTALLER, <<~'ZSH', ROOT)
      WORKSPACE_DIR="$1"
      print -r -- "${FEATURE_PROJECT_DIR[ios-tools]}"
      print -r -- "${FEATURE_SCHEME[ios-tools]}"
      print -r -- "${FEATURE_APP_NAME[ios-tools]}"
      print -r -- "${FEATURE_EXTENSION_NAME[ios-tools]}"
      app_bundle_id_for_key ios-tools
      print -r -- "${FEATURE_EXTENSION_ID[ios-tools]}"
      derived_data_dir_for_key ios-tools
    ZSH
    assert_equal ['JobsIOSTools', 'JobsIOSTools', 'JobsIOSTools', 'JobsIOSToolsFinderSync.appex',
                  'com.jobs.JobsIOSTools', 'com.jobs.JobsIOSTools.FinderSyncExtension',
                  File.join(ROOT, 'work/JobsIOSToolsDerivedData')], output.lines.map(&:strip)
    output = run_definitions(UNINSTALLER, <<~'ZSH')
      parse_fzf_selection "${FEATURE_TITLE[ios-tools]}" || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "${FEATURE_PROJECT_DIR[ios-tools]}"
      print -r -- "${FEATURE_EXTENSION_PROCESS_NAME[ios-tools]}"
      print -r -- "${FEATURE_EXTENSION_ID[ios-tools]}"
    ZSH
    assert_equal ['ios-tools', 'JobsIOSTools', 'JobsIOSToolsFinderSync', 'com.jobs.JobsIOSTools.FinderSyncExtension'], output.lines.map(&:strip)
  end

  def test_installation_preserves_existing_ios_selection_and_ignores_invalid_ids
    Dir.mktmpdir('jobs-ios-feature-config-') do |directory|
      config = File.join(directory, '配置 space', 'EnabledFeatures.txt')
      output = run_definitions(INSTALLER, <<~'ZSH', config)
        IOS_FEATURE_CONFIG_PATH="$1"
        IOS_FEATURE_CONFIG_DIR="${1:h}"
        /bin/mkdir -p "$IOS_FEATURE_CONFIG_DIR"
        print -nr -- 'ios-pod-build-check,unknown,ios-clean-cache' > "$IOS_FEATURE_CONFIG_PATH"
        parse_feature_selection 'ios-pod-update,ios-clean-cache' || exit 1
        persist_ios_feature_selection ios-tools || exit 1
        print -r -- "configured:$(<"$IOS_FEATURE_CONFIG_PATH")"
      ZSH
      assert_includes output.lines.map(&:strip), 'configured:ios-pod-update,ios-pod-build-check,ios-clean-build-artifacts'
      assert_equal 'ios-pod-update,ios-pod-build-check,ios-clean-build-artifacts', File.read(config)
      assert_empty Dir.glob(File.join(File.dirname(config), '.features.*'))
    end
  end

  def test_legacy_cache_selection_maps_to_the_single_build_cleanup_action
    output = run_definitions(INSTALLER, <<~'ZSH')
      parse_feature_selection 'ios-clean-cache,ios-clean-build-artifacts' || exit 1
      print -r -- "${(j:,:)SELECTED_FUNCTION_IDS}"
      print -r -- "$IOS_TOOLS_ENABLED_FEATURES"
    ZSH
    assert_equal ['ios-clean-build-artifacts', 'ios-clean-build-artifacts'], output.lines.map(&:strip)
  end

  def test_first_install_or_empty_configuration_only_enables_selected_tools
    [false, true].each do |empty_existing|
      Dir.mktmpdir('jobs-ios-subset-config-') do |directory|
        config = File.join(directory, 'EnabledFeatures.txt')
        File.write(config, '') if empty_existing
        run_definitions(INSTALLER, <<~'ZSH', config)
          IOS_FEATURE_CONFIG_PATH="$1"
          IOS_FEATURE_CONFIG_DIR="${1:h}"
          parse_feature_selection 'ios-pod-build-check' || exit 1
          persist_ios_feature_selection ios-tools || exit 1
        ZSH
        assert_equal 'ios-pod-build-check', File.read(config)
      end
    end
  end

  def test_other_features_do_not_write_ios_configuration
    Dir.mktmpdir('jobs-ios-no-config-') do |directory|
      config = File.join(directory, 'not-created', 'EnabledFeatures.txt')
      run_definitions(INSTALLER, <<~'ZSH', config)
        IOS_FEATURE_CONFIG_PATH="$1"
        IOS_FEATURE_CONFIG_DIR="${1:h}"
        parse_feature_selection 'terminal_open' || exit 1
        persist_ios_feature_selection terminal_opener || exit 1
      ZSH
      refute File.exist?(File.dirname(config))
    end
  end

  def test_build_failure_does_not_persist_configuration_and_registration_reads_saved_selection
    output = run_definitions(INSTALLER, <<~'ZSH')
      build_feature() { print -r -- 'build'; return 1; }
      persist_ios_feature_selection() { print -r -- 'persist'; }
      register_and_enable_feature() { print -r -- 'register'; }
      if install_feature ios-tools; then exit 1; fi
      build_feature() { print -r -- 'build'; }
      persist_terminal_feature_selection() { print -r -- 'terminal'; }
      install_feature ios-tools || exit 1
    ZSH
    phases = output.lines.map(&:strip).select { |line| %w[build persist register terminal].include?(line) }
    assert_equal %w[build build persist register terminal], phases
  end

  def test_ios_host_initialization_never_dispatches_a_tool
    output = run_definitions(INSTALLER, <<~'ZSH', replacements: {'/usr/bin/open' => 'jobs_record_open'})
      jobs_record_open() { print -r -- "${(j:|:)@}"; }
      open_host_for_extension_registration ios-tools '/fixture/中文 space/JobsIOSTools.app'
    ZSH
    assert_equal ['-gj|/fixture/中文 space/JobsIOSTools.app|--args|--initialize-finder-extension'], output.lines.map(&:strip)
  end

  def test_bulk_uninstall_delegates_configuration_cleanup_and_retains_root_artifact_cleanup
    output = run_definitions(UNINSTALLER, <<~'ZSH', ROOT, replacements: {'/bin/zsh "$WORKSPACE_DIR/JobsIOSTools/【MacOS】卸载iOS辅助工具Finder扩展.command"' => 'jobs_record_uninstall'})
      WORKSPACE_DIR="$1"
      jobs_record_uninstall() { print -r -- "delegate:${(j:|:)@}"; }
      for phase in print_current_extension_status disable_extension stop_host_application stop_extension_processes reset_election_and_unregister_extension clear_runtime_markers remove_xcode_deriveddata_app_bundles remove_local_deriveddata_dir remove_legacy_automator_service; do
        functions[$phase]='print -r -- "phase:${funcstack[1]}:$1"'
      done
      uninstall_feature ios-tools || exit 1
    ZSH
    assert_includes output, "delegate:--features|#{ACTION_IDS.join(',')}|--non-interactive"
    assert_includes output, 'phase:remove_local_deriveddata_dir:ios-tools'
    assert_includes output, 'phase:reset_election_and_unregister_extension:ios-tools'
  end

  private

  def run_definitions(path, checks, *arguments, replacements: {})
    source = File.read(path)
    raise '真实主入口未找到' unless source.sub!(/^main "\$@"\s*\z/, '')
    replacements.each { |from, to| source = source.gsub(from, to) }
    Dir.mktmpdir('jobs-ios-install-mapping-') do |directory|
      fixture = File.join(directory, 'mapping.zsh')
      File.write(fixture, source + "\nLOG_FILE=\"${0:h}/mapping.log\"\n" + checks)
      output, status = Open3.capture2e({'NO_COLOR' => '1'}, '/bin/zsh', '-f', fixture, *arguments)
      assert status.success?, output
      output
    end
  end
end
