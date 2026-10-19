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
    assert_match(/static let all: \[FeatureOption\] = independent \+ terminal/, selector)
    assert_equal 14, identifiers.length
    assert_equal identifiers.uniq, identifiers
    assert_includes identifiers, 'flutter_version_manager'
    output = run_definitions(INSTALLER, <<~'ZSH', all.join(','))
      parse_feature_selection "$1" || exit 1
      print -r -- "${(j:,:)SELECTABLE_FUNCTION_IDS}"
      print -r -- "${(j:,:)SELECTED_FUNCTION_IDS}"
      print -r -- "${(j:,:)SELECTED_KEYS}"
    ZSH
    lines = output.lines.map(&:strip)
    assert_equal all.join(','), lines[0]
    assert_equal all.join(','), lines[1]
    assert_equal 10, lines[2].split(',').length
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

  def test_missing_flutter_submodule_uses_the_shared_bootstrap_flow
    Dir.mktmpdir('jobs-flutter-missing-submodule-') do |workspace|
      output = run_definitions(INSTALLER, <<~'ZSH', workspace)
        WORKSPACE_DIR="$1"
        for key in "${FEATURE_KEYS[@]}"; do
          [[ "$key" == flutter_version_manager ]] && continue
          /bin/mkdir -p "$(project_file_for_key "$key")"
        done
        log() { print -r -- "$1"; }
        run_submodule_setup_script() { print -r -- 'shared-bootstrap'; }
        restart_current_script_after_submodule_setup() { print -r -- "restart:$1"; }
        ensure_feature_projects_or_bootstrap_submodules preserved-argument
      ZSH
      assert_includes output, 'JobsFlutterVersionMgr.xcodeproj'
      assert_includes output, '十个工程均由 Git 子模块提供'
      assert_includes output, "shared-bootstrap\nrestart:preserved-argument"
      refute_includes output, '恢复完整父仓'
    end
  end

  def test_ready_submodules_do_not_start_bootstrap
    Dir.mktmpdir('jobs-flutter-ready-submodules-') do |workspace|
      output = run_definitions(INSTALLER, <<~'ZSH', workspace)
        WORKSPACE_DIR="$1"
        for key in "${FEATURE_KEYS[@]}"; do
          /bin/mkdir -p "$(project_file_for_key "$key")"
        done
        run_submodule_setup_script() { print -r -- 'unexpected-bootstrap'; exit 1; }
        restart_current_script_after_submodule_setup() { print -r -- 'unexpected-restart'; exit 1; }
        ensure_feature_projects_or_bootstrap_submodules || exit 1
        print -r -- 'projects-ready'
      ZSH
      assert_equal "projects-ready\n", output
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

  def test_missing_git_pull_submodule_uses_the_shared_bootstrap_flow
    Dir.mktmpdir('jobs-git-pull-missing-project-') do |workspace|
      output = run_definitions(INSTALLER, <<~'ZSH', workspace)
        WORKSPACE_DIR="$1"
        for key in "${FEATURE_KEYS[@]}"; do
          [[ "$key" == git-pull ]] && continue
          /bin/mkdir -p "$(project_file_for_key "$key")"
        done
        log() { print -r -- "$1"; }
        run_submodule_setup_script() { print -r -- 'shared-bootstrap'; }
        restart_current_script_after_submodule_setup() { print -r -- "restart:$1"; }
        ensure_feature_projects_or_bootstrap_submodules preserved-argument
      ZSH
      assert_includes output, 'JobsGitPuller.xcodeproj'
      assert_includes output, '十个工程均由 Git 子模块提供'
      assert_includes output, "shared-bootstrap\nrestart:preserved-argument"
    end
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

  def test_missing_extraction_submodule_uses_the_shared_bootstrap_flow
    Dir.mktmpdir('jobs-extract-missing-project-') do |workspace|
      output = run_definitions(INSTALLER, <<~'ZSH', workspace)
        WORKSPACE_DIR="$1"
        for key in "${FEATURE_KEYS[@]}"; do
          [[ "$key" == flutter-dependency-extract ]] && continue
          /bin/mkdir -p "$(project_file_for_key "$key")"
        done
        log() { print -r -- "$1"; }
        run_submodule_setup_script() { print -r -- 'shared-bootstrap'; }
        restart_current_script_after_submodule_setup() { print -r -- "restart:$1"; }
        ensure_feature_projects_or_bootstrap_submodules preserved-argument
      ZSH
      assert_includes output, 'JobsFlutterDependencyExtractor.xcodeproj'
      assert_includes output, '十个工程均由 Git 子模块提供'
      assert_includes output, "shared-bootstrap\nrestart:preserved-argument"
    end
  end

  private

  def run_definitions(path, checks, *arguments)
    source = File.read(path)
    raise '入口未找到' unless source.sub!(/^main "\$@"\s*\z/, '')

    Dir.mktmpdir('jobs-flutter-install-mapping-') do |directory|
      fixture = File.join(directory, 'mapping.zsh')
      File.write(fixture, source + "\n" + checks)
      output, result = Open3.capture2e({ 'NO_COLOR' => '1' }, '/bin/zsh', '-f', fixture, *arguments)
      assert result.success?, output
      output
    end
  end
end
