# frozen_string_literal: true
# 在隔离 Shell 内核对真实选择器、安装映射与卸载映射，不执行构建或注册。

require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class FlutterInstallerIntegrationTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  INSTALLER = File.join(ROOT, '【MacOS】🧩安装Finder扩展.command')
  UNINSTALLER = File.join(ROOT, '【MacOS】🧩卸载Finder扩展.command')

  def test_selector_all_and_checkbox_identifiers_stay_in_the_same_order
    selector = File.read(File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift'))
    identifiers = selector.scan(/FeatureOption\(identifier: "([^"]+)"/).flatten
    all = identifiers
    independent = selector[/static let independent:.*?\n    \]/m].scan(/FeatureOption\(identifier: "([^"]+)"/).flatten
    assert_match(/static let all: \[FeatureOption\] = independent \+ terminal/, selector)
    assert_equal identifiers.uniq, identifiers
    assert_includes identifiers, 'flutter_version_manager'
    assert_includes independent, 'ios-simulator-create'
    output = run_definitions(INSTALLER, <<~'ZSH', all.join(','))
      parse_feature_selection "$1" || exit 1
      print -r -- "${(j:,:)SELECTABLE_FUNCTION_IDS}"
      print -r -- "${(j:,:)SELECTED_FUNCTION_IDS}"
      print -r -- "${(j:,:)SELECTED_KEYS}"
    ZSH
    lines = output.lines.map(&:strip)
    assert_equal all.join(','), lines[0]
    assert_equal all.join(','), lines[1]
    assert_equal independent + ['terminal_opener'], lines[2].split(',')
  end

  def test_flutter_selection_is_independent_and_terminal_actions_are_deduplicated
    output = run_definitions(INSTALLER, <<~'ZSH')
      parse_feature_selection "flutter_version_manager,flutter_pub_get,terminal_open,flutter_version_manager" || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "$TERMINAL_OPENER_ENABLED_FEATURES"
      print -r -- "${FEATURE_SCHEME[flutter_version_manager]}"
      print -r -- "${FEATURE_EXTENSION_ID[flutter_version_manager]}"
    ZSH
    assert_equal ['flutter_version_manager,terminal_opener', 'flutter-pub-get,open',
                  'JobsFlutterVersionMgr', 'com.jobs.JobsFlutterVersionMgr.FinderSyncExtension'], output.lines.map(&:strip)
  end

  def test_unknown_selection_stops_and_flutter_uninstall_has_the_same_identity
    output = run_definitions(INSTALLER, <<~'ZSH')
      log() { print -r -- "$1"; }
      if parse_feature_selection "unexpected_flutter_feature"; then
        exit 1
      fi
      print -r -- 'unknown-rejected'
    ZSH
    assert_includes output, 'unknown-rejected'
    output = run_definitions(UNINSTALLER, <<~'ZSH')
      [[ " ${(j: :)FEATURE_KEYS} " == *" flutter_version_manager "* ]] || exit 1
      print -r -- "${FEATURE_APP_NAME[flutter_version_manager]}"
      print -r -- "${FEATURE_EXTENSION_ID[flutter_version_manager]}"
      print -r -- "${FEATURE_KEY_BY_TITLE[${FEATURE_TITLE[flutter_version_manager]}]}"
    ZSH
    assert_equal ['JobsFlutterVersionMgr', 'com.jobs.JobsFlutterVersionMgr.FinderSyncExtension',
                  'flutter_version_manager'], output.lines.map(&:strip)
  end

  def test_missing_flutter_project_stops_with_complete_repository_guidance
    assert_missing_project_stops('flutter_version_manager', 'JobsFlutterVersionMgr')
  end

  def test_complete_repository_projects_pass_without_other_actions
    Dir.mktmpdir('jobs-flutter-ready-projects-') do |workspace|
      output = run_definitions(INSTALLER, <<~'ZSH', workspace)
        WORKSPACE_DIR="$1"
        for key in "${FEATURE_KEYS[@]}"; do
          /bin/mkdir -p "$(project_file_for_key "$key")"
          print -r -- '// fixture' > "$(project_file_for_key "$key")/project.pbxproj"
        done
        ensure_feature_projects_exist || exit 1
        print -r -- 'projects-ready'
      ZSH
      assert_equal "projects-ready\n", output
    end
  end

  def test_empty_project_package_stops_with_its_missing_configuration_path
    Dir.mktmpdir('jobs-flutter-empty-project-') do |workspace|
      output = run_definitions(INSTALLER, <<~'ZSH', workspace)
        WORKSPACE_DIR="$1"
        for key in "${FEATURE_KEYS[@]}"; do
          /bin/mkdir -p "$(project_file_for_key "$key")"
          [[ "$key" == flutter_version_manager ]] && continue
          print -r -- '// fixture' > "$(project_file_for_key "$key")/project.pbxproj"
        done
        log() { print -r -- "$1"; }
        if ensure_feature_projects_exist; then
          print -r -- 'unexpected-ready'
          exit 1
        fi
        print -r -- 'installation-stopped'
      ZSH
      assert_includes output, 'JobsFlutterVersionMgr.xcodeproj/project.pbxproj'
      assert_includes output, 'installation-stopped'
      refute_includes output, 'JobsGitPuller.xcodeproj'
    end
  end

  def test_all_missing_project_paths_are_reported
    Dir.mktmpdir('jobs-all-missing-projects-') do |workspace|
      output = run_definitions(INSTALLER, <<~'ZSH', workspace)
        WORKSPACE_DIR="$1"
        log() { print -r -- "$1"; }
        if ensure_feature_projects_exist; then
          exit 1
        fi
      ZSH
      expected_count = File.read(INSTALLER)[/^FEATURE_KEYS=\(([^)]+)\)/, 1].split.length
      assert_equal expected_count, output.lines.count { |line| line.start_with?('- ') && line.include?('.xcodeproj/project.pbxproj') }
      assert_includes output, '重新取得包含全部工程源码的完整 MacOS@Extension 仓库'
    end
  end

  def test_git_pull_selection_and_uninstall_identity_are_independent
    output = run_definitions(INSTALLER, <<~'ZSH')
      parse_feature_selection "git-pull,terminal_open,git-pull" || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "$TERMINAL_OPENER_ENABLED_FEATURES"
      print -r -- "${FEATURE_SCHEME[git-pull]}"
      print -r -- "${FEATURE_EXTENSION_ID[git-pull]}"
    ZSH
    assert_equal ['git-pull,terminal_opener', 'open', 'JobsGitPuller',
                  'com.jobs.JobsGitPuller.FinderSyncExtension'], output.lines.map(&:strip)
    output = run_definitions(UNINSTALLER, <<~'ZSH')
      print -r -- "${FEATURE_APP_NAME[git-pull]}"
      print -r -- "${FEATURE_EXTENSION_ID[git-pull]}"
      parse_fzf_selection "${FEATURE_TITLE[git-pull]}"
      print -r -- "${(j:,:)SELECTED_KEYS}"
    ZSH
    assert_equal ['JobsGitPuller', 'com.jobs.JobsGitPuller.FinderSyncExtension', 'git-pull'], output.lines.map(&:strip)
  end

  def test_missing_git_pull_project_stops_with_complete_repository_guidance
    assert_missing_project_stops('git-pull', 'JobsGitPuller')
  end

  def test_extraction_selection_and_uninstall_use_the_independent_project
    output = run_definitions(INSTALLER, <<~'ZSH')
      parse_feature_selection 'flutter-dependency-extract,flutter_pub_get,flutter-dependency-extract' || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "${FEATURE_SCHEME[flutter-dependency-extract]}"
      print -r -- "${FEATURE_EXTENSION_NAME[flutter-dependency-extract]}"
      print -r -- "${FEATURE_EXTENSION_ID[flutter-dependency-extract]}"
    ZSH
    assert_equal ['flutter-dependency-extract,terminal_opener', 'JobsFlutterDependencyExtractor',
                  'JobsFlutterDependencyFinderSync.appex', 'com.jobs.JobsFlutterDependencyExtractor.FinderSync'], output.lines.map(&:strip)
    output = run_definitions(UNINSTALLER, <<~'ZSH')
      print -r -- "${FEATURE_APP_NAME[flutter-dependency-extract]}"
      print -r -- "${FEATURE_EXTENSION_ID[flutter-dependency-extract]}"
    ZSH
    assert_equal ['JobsFlutterDependencyExtractor', 'com.jobs.JobsFlutterDependencyExtractor.FinderSync'], output.lines.map(&:strip)
  end

  def test_missing_extraction_project_stops_with_complete_repository_guidance
    assert_missing_project_stops('flutter-dependency-extract', 'JobsFlutterDependencyExtractor')
  end

def test_flutter_run_is_independent_and_uninstall_has_matching_identity
  output = run_definitions(INSTALLER, <<~'ZSH')
    parse_feature_selection 'flutter-run,flutter_pub_get,flutter-run' || exit 1
    print -r -- "${(j:,:)SELECTED_KEYS}"
    print -r -- "${FEATURE_SCHEME[flutter-run]}"
    print -r -- "${FEATURE_EXTENSION_NAME[flutter-run]}"
    print -r -- "${FEATURE_EXTENSION_ID[flutter-run]}"
  ZSH
  assert_equal ['flutter-run,terminal_opener', 'JobsFlutterRunner',
                'JobsFlutterRunFinderSync.appex', 'com.jobs.JobsFlutterRunner.FinderSyncExtension'], output.lines.map(&:strip)
  output = run_definitions(UNINSTALLER, <<~'ZSH')
    print -r -- "${FEATURE_APP_NAME[flutter-run]}"
    print -r -- "${FEATURE_EXTENSION_ID[flutter-run]}"
    parse_fzf_selection "${FEATURE_TITLE[flutter-run]}"
    print -r -- "${(j:,:)SELECTED_KEYS}"
  ZSH
  assert_equal ['JobsFlutterRunner', 'com.jobs.JobsFlutterRunner.FinderSyncExtension', 'flutter-run'], output.lines.map(&:strip)
end

def test_missing_flutter_run_project_stops_with_complete_repository_guidance
  assert_missing_project_stops('flutter-run', 'JobsFlutterRunner')
end

  def test_simulator_selection_uses_its_own_project_and_explicit_bundle_identifiers
    output = run_definitions(INSTALLER, <<~'ZSH')
      parse_feature_selection 'ios-simulator-create,ios-simulator-create' || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "${FEATURE_TITLE[ios-simulator-create]}"
      print -r -- "${FEATURE_SCHEME[ios-simulator-create]}"
      print -r -- "${FEATURE_APP_NAME[ios-simulator-create]}"
      print -r -- "${FEATURE_EXTENSION_NAME[ios-simulator-create]}"
      app_bundle_id_for_key ios-simulator-create
      print -r -- "${FEATURE_EXTENSION_ID[ios-simulator-create]}"
      print -r -- "terminal:${TERMINAL_OPENER_ENABLED_FEATURES}"
      app_bundle_id_for_key flutter_version_manager
      app_bundle_id_for_key flutter-run
    ZSH
    assert_equal ['ios-simulator-create', '新建 iOS 模拟器', 'JobsIOSSimulatorCreator',
                  'JobsIOSSimulatorCreator', 'JobsIOSSimulatorFinderSync.appex',
                  'com.jobs.iossimulatorcreator', 'com.jobs.iossimulatorcreator.findersync',
                  'terminal:', 'com.jobs.JobsFlutterVersionMgr', 'com.jobs.JobsFlutterRunner'], output.lines.map(&:strip)
  end

  def test_simulator_uninstall_selection_uses_the_matching_process_and_paths
    output = run_definitions(UNINSTALLER, <<~'ZSH', ROOT)
      WORKSPACE_DIR="$1"
      [[ " ${(j: :)FEATURE_KEYS} " == *" ios-simulator-create "* ]] || exit 1
      parse_fzf_selection "${FEATURE_TITLE[ios-simulator-create]}"
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "${FEATURE_APP_NAME[ios-simulator-create]}"
      print -r -- "${FEATURE_EXTENSION_PROCESS_NAME[ios-simulator-create]}"
      print -r -- "${FEATURE_EXTENSION_ID[ios-simulator-create]}"
      print -r -- "${FEATURE_REFRESH_MARKER[ios-simulator-create]}"
      print -r -- "${FEATURE_RUNTIME_LOG[ios-simulator-create]}"
      local_derived_data_dir_for_key ios-simulator-create
    ZSH
    assert_equal ['ios-simulator-create', 'JobsIOSSimulatorCreator', 'JobsIOSSimulatorFinderSync',
                  'com.jobs.iossimulatorcreator.findersync', '/tmp/JobsIOSSimulatorCreatorNeedsFinderRestart',
                  '/tmp/JobsIOSSimulatorCreator.log', File.join(ROOT, 'work/JobsIOSSimulatorCreatorDerivedData')], output.lines.map(&:strip)
  end

  def test_simulator_fallback_host_launch_requires_explicit_initialization
    output = run_definitions(INSTALLER, <<~'ZSH', replacements: { '/usr/bin/open' => 'jobs_record_open' })
      jobs_record_open() {
        print -r -- "${(j:|:)@}"
      }
      open_host_for_extension_registration ios-simulator-create '/fixture/中文 space/JobsIOSSimulatorCreator.app'
      open_host_for_extension_registration flutter_version_manager '/fixture/JobsFlutterVersionMgr.app'
    ZSH
    assert_equal ['-gj|/fixture/中文 space/JobsIOSSimulatorCreator.app|--args|--initialize-finder-extension',
                  '-gj|/fixture/JobsFlutterVersionMgr.app'], output.lines.map(&:strip)
  end

  def test_registration_cleanup_finds_explicit_and_legacy_host_identifiers
    Dir.mktmpdir('jobs-finder-registration-records-') do |directory|
      lsregister = File.join(directory, 'lsregister')
      File.write(lsregister, <<~'ZSH')
        #!/bin/zsh
        /bin/cat <<'RECORDS'
        --------------------------------------------------------------------------------
        path: /fixture/new simulator.app
        identifier: com.jobs.iossimulatorcreator
        --------------------------------------------------------------------------------
        path: /fixture/legacy flutter.app
        identifier: com.jobs.JobsFlutterVersionMgr
        --------------------------------------------------------------------------------
        path: /fixture/unrelated.app
        identifier: com.jobs.unrelated
        RECORDS
      ZSH
      File.chmod(0o700, lsregister)
      replacements = { '/usr/bin/pluginkit' => 'jobs_no_registration', '/usr/bin/find' => 'jobs_no_registration' }
      output = run_definitions(INSTALLER, <<~'ZSH', lsregister, replacements: replacements)
        JOBS_TEST_LSREGISTER="$1"
        lsregister_path() {
          print -r -- "$JOBS_TEST_LSREGISTER"
        }
        jobs_no_registration() {
          return 0
        }
        collect_registered_paths_for_feature ios-simulator-create
        print -r -- "${REGISTERED_PATHS[1]}"
        collect_registered_paths_for_feature flutter_version_manager
        print -r -- "${REGISTERED_PATHS[1]}"
      ZSH
      assert_equal ['/fixture/new simulator.app', '/fixture/legacy flutter.app'], output.lines.map(&:strip)
    end
  end

  def test_missing_simulator_project_stops_with_complete_repository_guidance
    assert_missing_project_stops('ios-simulator-create', 'JobsIOSSimulatorCreator')
  end

  def test_registration_activation_requires_the_exact_current_extension_path
    replacements = { '/usr/bin/pluginkit' => 'jobs_fake_pluginkit', '/bin/sleep' => 'jobs_no_wait',
                     'for attempt in {1..90}' => 'for attempt in {1..2}' }
    output = run_definitions(INSTALLER, <<~'ZSH', replacements: replacements)
      jobs_fake_pluginkit() {
        if [[ "$1" == -m ]]; then
          print -r -- "$JOBS_TEST_PLUGIN_RECORDS"
        fi
        return 0
      }
      jobs_no_wait() {
        return 0
      }
      gray_echo() {
        return 0
      }
      LOG_FILE=/dev/null
      extension_id='com.jobs.iossimulatorcreator.findersync'
      extension_path='/fixture/新 path/JobsIOSSimulatorFinderSync.appex'
      old_record="+ ${extension_id}(1.0) /fixture/old/JobsIOSSimulatorFinderSync.appex"
      JOBS_TEST_PLUGIN_RECORDS="$old_record"
      if wait_until_extension_enabled "$extension_id" "$extension_path"; then
        exit 1
      fi
      print -r -- 'old-enabled-new-missing:rejected'
      JOBS_TEST_PLUGIN_RECORDS="${old_record}"$'\n'"- ${extension_id}(1.0) ${extension_path}"
      if wait_until_extension_enabled "$extension_id" "$extension_path"; then
        exit 1
      fi
      print -r -- 'old-enabled-new-disabled:rejected'
      JOBS_TEST_PLUGIN_RECORDS="+ ${extension_id}(1.0) ${extension_path}.backup"
      if wait_until_extension_enabled "$extension_id" "$extension_path"; then
        exit 1
      fi
      print -r -- 'similar-path:rejected'
      JOBS_TEST_PLUGIN_RECORDS="${old_record}"$'\n'"+ ${extension_id}(1.0) ${extension_path}"
      wait_until_extension_enabled "$extension_id" "$extension_path" || exit 1
      print -r -- 'new-enabled:accepted'
    ZSH
    assert_equal ['old-enabled-new-missing:rejected', 'old-enabled-new-disabled:rejected',
                  'similar-path:rejected', 'new-enabled:accepted'], output.lines.map(&:strip)
  end

  private

  def assert_missing_project_stops(missing_key, project_name)
    Dir.mktmpdir('jobs-missing-repository-project-') do |workspace|
      output = run_definitions(INSTALLER, <<~'ZSH', workspace, missing_key)
        WORKSPACE_DIR="$1"
        for key in "${FEATURE_KEYS[@]}"; do
          [[ "$key" == "$2" ]] && continue
          /bin/mkdir -p "$(project_file_for_key "$key")"
          print -r -- '// fixture' > "$(project_file_for_key "$key")/project.pbxproj"
        done
        log() { print -r -- "$1"; }
        if ensure_feature_projects_exist; then
          print -r -- 'unexpected-ready'
          exit 1
        fi
        print -r -- 'installation-stopped'
      ZSH
      assert_includes output, "#{project_name}.xcodeproj/project.pbxproj"
      expected_count = File.read(INSTALLER)[/^FEATURE_KEYS=\(([^)]+)\)/, 1].split.length
      assert_includes output, "#{expected_count} 个工程均随当前仓库统一管理"
      assert_includes output, '重新取得包含全部工程源码的完整 MacOS@Extension 仓库'
      assert_includes output, 'installation-stopped'
      refute_includes output, '子模块'
    end
  end

  def run_definitions(path, checks, *arguments, replacements: {})
    source = File.read(path)
    raise '入口未找到' unless source.sub!(/^main "\$@"\s*\z/, '')
    replacements.each { |from, to| source = source.gsub(from, to) }

    Dir.mktmpdir('jobs-flutter-install-mapping-') do |directory|
      fixture = File.join(directory, 'mapping.zsh')
      File.write(fixture, source + "\n" + checks)
      output, result = Open3.capture2e({ 'NO_COLOR' => '1' }, '/bin/zsh', '-f', fixture, *arguments)
      assert result.success?, output
      output
    end
  end
end
