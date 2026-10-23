# frozen_string_literal: true
# 只读取真实安装器定义并在临时 Shell 内核对映射，不注册扩展或改写 Finder 偏好。

require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class HiddenFilesInstallerIntegrationTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  INSTALLER = File.join(ROOT, '【MacOS】🧩安装Finder扩展.command')
  UNINSTALLER = File.join(ROOT, '【MacOS】🧩卸载Finder扩展.command')
  PROJECT = File.join(ROOT, 'JobsHiddenFilesToggler')
  KEY = 'hidden-files-toggle'
  APP = 'JobsHiddenFilesToggler'
  APP_ID = 'com.jobs.hiddenfilestoggler'
  TITLE = '显示 / 隐藏文件'

  def test_selector_contains_hidden_files_once
    selector = File.read(File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift'))
    options = selector.scan(/FeatureOption\(identifier: "([^"]+)", title: "([^"]+)"\)/)
    assert_equal [[KEY, TITLE]], options.select { |identifier, _| identifier == KEY }
  end

  def test_hidden_files_is_available_once_in_install_and_uninstall_feature_lists
    [INSTALLER, UNINSTALLER].each do |entry|
      output = run_definitions(entry, 'print -rl -- "${FEATURE_KEYS[@]}"')
      assert_equal 1, output.lines.map(&:strip).count(KEY), entry
    end
  end

  def test_install_mapping_keeps_an_independent_project_and_explicit_bundle_ids
    output = run_definitions(INSTALLER, <<~'ZSH', ROOT)
      WORKSPACE_DIR="$1"
      parse_feature_selection 'hidden-files-toggle,hidden-files-toggle' || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "${(j:,:)SELECTED_FUNCTION_IDS}"
      print -r -- "${FEATURE_TITLE[hidden-files-toggle]}"
      print -r -- "${FEATURE_PROJECT_DIR[hidden-files-toggle]}"
      print -r -- "${FEATURE_SCHEME[hidden-files-toggle]}"
      print -r -- "${FEATURE_APP_NAME[hidden-files-toggle]}"
      print -r -- "${FEATURE_EXTENSION_NAME[hidden-files-toggle]}"
      app_bundle_id_for_key hidden-files-toggle
      print -r -- "${FEATURE_EXTENSION_ID[hidden-files-toggle]}"
      print -r -- "terminal:${TERMINAL_OPENER_ENABLED_FEATURES}"
      project_file_for_key hidden-files-toggle
      derived_data_dir_for_key hidden-files-toggle
    ZSH
    assert_equal [KEY, KEY, TITLE, APP, APP, APP, 'JobsHiddenFilesFinderSync.appex',
                  APP_ID, "#{APP_ID}.findersync", 'terminal:', File.join(PROJECT, "#{APP}.xcodeproj"),
                  File.join(ROOT, "work/#{APP}DerivedData")], output.lines.map(&:strip)
  end

  def test_install_selection_deduplicates_hidden_files_when_combined_with_terminal
    output = run_definitions(INSTALLER, <<~'ZSH')
      parse_feature_selection 'hidden-files-toggle,terminal_open,hidden-files-toggle,terminal_open' || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "${(j:,:)SELECTED_FUNCTION_IDS}"
      print -r -- "$TERMINAL_OPENER_ENABLED_FEATURES"
    ZSH
    assert_equal ['hidden-files-toggle,terminal_opener', 'hidden-files-toggle,terminal_open', 'open'],
                 output.lines.map(&:strip)
  end

  def test_unknown_feature_selection_is_rejected
    output = run_definitions(INSTALLER, <<~'ZSH')
      if parse_feature_selection 'unexpected-hidden-files-feature,hidden-files-toggle'; then
        exit 1
      fi
      [[ "${#SELECTED_KEYS[@]}" == 0 ]] || exit 1
      print -r -- 'unknown-rejected'
    ZSH
    assert_includes output, '未知标识：unexpected-hidden-files-feature'
    assert_includes output, 'unknown-rejected'
  end

  def test_registration_initializes_host_without_toggling_hidden_files
    output = run_definitions(INSTALLER, <<~'ZSH', replacements: {'/usr/bin/open' => 'jobs_record_open'})
      jobs_record_open() {
        print -r -- "${(j:|:)@}"
      }
      open_host_for_extension_registration hidden-files-toggle '/fixture/中文 space/JobsHiddenFilesToggler.app'
    ZSH
    assert_equal ['-gj|/fixture/中文 space/JobsHiddenFilesToggler.app|--args|--initialize-finder-extension'],
                 output.lines.map(&:strip)
  end

  def test_uninstall_mapping_and_title_selection_keep_the_same_identity
    output = run_definitions(UNINSTALLER, <<~'ZSH', ROOT)
      WORKSPACE_DIR="$1"
      parse_fzf_selection "${FEATURE_TITLE[hidden-files-toggle]}"$'\n'"${FEATURE_TITLE[hidden-files-toggle]}" || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "${FEATURE_TITLE[hidden-files-toggle]}"
      print -r -- "${FEATURE_PROJECT_DIR[hidden-files-toggle]}"
      print -r -- "${FEATURE_APP_NAME[hidden-files-toggle]}"
      print -r -- "${FEATURE_EXTENSION_PROCESS_NAME[hidden-files-toggle]}"
      print -r -- "${FEATURE_EXTENSION_ID[hidden-files-toggle]}"
      print -r -- "${FEATURE_REFRESH_MARKER[hidden-files-toggle]}"
      print -r -- "${FEATURE_RUNTIME_LOG[hidden-files-toggle]}"
      local_derived_data_dir_for_key hidden-files-toggle
    ZSH
    assert_equal [KEY, TITLE, APP, APP, 'JobsHiddenFilesFinderSync', "#{APP_ID}.findersync",
                  "/tmp/#{APP}NeedsFinderRestart", "/tmp/#{APP}.log",
                  File.join(ROOT, "work/#{APP}DerivedData")], output.lines.map(&:strip)
  end

  def test_missing_hidden_files_project_is_reported_before_building
    Dir.mktmpdir('jobs-hidden-files-missing-project-') do |workspace|
      output = run_definitions(INSTALLER, <<~'ZSH', workspace)
        WORKSPACE_DIR="$1"
        for key in "${FEATURE_KEYS[@]}"; do
          [[ "$key" == hidden-files-toggle ]] && continue
          /bin/mkdir -p "$(project_file_for_key "$key")"
          print -r -- '// fixture' > "$(project_file_for_key "$key")/project.pbxproj"
        done
        if ensure_feature_projects_exist; then
          exit 1
        fi
        print -r -- 'installation-stopped'
      ZSH
      assert_includes output, 'JobsHiddenFilesToggler.xcodeproj/project.pbxproj'
      assert_includes output, 'installation-stopped'
      assert_includes output, '重新取得包含全部工程源码的完整 MacOS@Extension 仓库'
      refute_includes output, 'JobsIOSSimulatorCreator.xcodeproj/project.pbxproj'
    end
  end

  private

  def run_definitions(path, checks, *arguments, replacements: {})
    source = File.read(path)
    raise '真实主入口未找到' unless source.sub!(/^main "\$@"\s*\z/, '')
    replacements.each { |from, to| source = source.gsub(from, to) }
    Dir.mktmpdir('jobs-hidden-files-install-mapping-') do |directory|
      fixture = File.join(directory, 'mapping.zsh')
      File.write(fixture, source + "\nLOG_FILE=\"${0:h}/mapping.log\"\n" + checks)
      output, status = Open3.capture2e({'NO_COLOR' => '1'}, '/bin/zsh', '-f', fixture, *arguments)
      assert status.success?, output
      output
    end
  end
end
