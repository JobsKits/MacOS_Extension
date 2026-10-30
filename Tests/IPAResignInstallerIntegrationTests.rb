# frozen_string_literal: true
# 只读取真实安装器定义并在临时 Shell 内核对映射，不注册扩展或执行 IPA 重签。

require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require_relative 'IsolatedInstallerDefinitions'

class IPAResignInstallerIntegrationTests < Minitest::Test
  include IsolatedInstallerDefinitions
  ROOT = File.expand_path('..', __dir__)
  INSTALLER = File.join(ROOT, 'Scripts/ManageFinderExtensions.zsh')
  UNINSTALLER = File.join(ROOT, 'Scripts/ManageFinderExtensions.zsh')
  PROJECT = File.join(ROOT, 'JobsIPAResigner')
  KEY = 'ipa-resign'
  APP = 'JobsIPAResigner'
  APP_ID = 'com.jobs.JobsIPAResigner'
  TITLE = 'IPA 免编译重签'

  def test_selector_contains_ipa_resign_once
    selector = File.read(File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift'))
    options = selector.scan(/FeatureOption\(identifier: "([^"]+)", title: "([^"]+)"\)/)
    assert_equal [[KEY, TITLE]], options.select { |identifier, _| identifier == KEY }
  end

  def test_ipa_resign_is_available_once_in_install_and_uninstall_feature_lists
    [INSTALLER, UNINSTALLER].each do |entry|
      output = run_definitions(entry, 'print -rl -- "${FEATURE_KEYS[@]}"')
      assert_equal 1, output.lines.map(&:strip).count(KEY), entry
    end
  end

  def test_install_mapping_keeps_an_independent_project_and_explicit_bundle_ids
    output = run_definitions(INSTALLER, <<~'ZSH', ROOT)
      WORKSPACE_DIR="$1"
      parse_feature_selection 'ipa-resign,ipa-resign' || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "${(j:,:)SELECTED_FUNCTION_IDS}"
      print -r -- "${FEATURE_TITLE[ipa-resign]}"
      print -r -- "${FEATURE_PROJECT_DIR[ipa-resign]}"
      print -r -- "${FEATURE_SCHEME[ipa-resign]}"
      print -r -- "${FEATURE_APP_NAME[ipa-resign]}"
      print -r -- "${FEATURE_EXTENSION_NAME[ipa-resign]}"
      app_bundle_id_for_key ipa-resign
      print -r -- "${FEATURE_EXTENSION_ID[ipa-resign]}"
      print -r -- "terminal:${TERMINAL_OPENER_ENABLED_FEATURES}"
      project_file_for_key ipa-resign
      derived_data_dir_for_key ipa-resign
    ZSH
    assert_equal [KEY, KEY, TITLE, APP, APP, APP, 'JobsIPAResignerFinderSync.appex',
                  APP_ID, "#{APP_ID}.FinderSyncExtension", 'terminal:', File.join(PROJECT, "#{APP}.xcodeproj"),
                  File.join(ROOT, "work/#{APP}DerivedData")], output.lines.map(&:strip)
  end

  def test_install_selection_deduplicates_ipa_resign_when_combined_with_terminal
    output = run_definitions(INSTALLER, <<~'ZSH')
      parse_feature_selection 'ipa-resign,terminal_open,ipa-resign,terminal_open' || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "${(j:,:)SELECTED_FUNCTION_IDS}"
      print -r -- "$TERMINAL_OPENER_ENABLED_FEATURES"
    ZSH
    assert_equal ['ipa-resign,terminal_opener', 'ipa-resign,terminal_open', 'open'],
                 output.lines.map(&:strip)
  end

  def test_unknown_feature_selection_is_rejected
    output = run_definitions(INSTALLER, <<~'ZSH')
      if parse_feature_selection 'unexpected-ipa-resign-feature,ipa-resign'; then
        exit 1
      fi
      [[ "${#SELECTED_KEYS[@]}" == 0 ]] || exit 1
      print -r -- 'unknown-rejected'
    ZSH
    assert_includes output, '未知标识：unexpected-ipa-resign-feature'
    assert_includes output, 'unknown-rejected'
  end

  def test_registration_initializes_host_without_resigning_ipa
    output = run_definitions(INSTALLER, <<~'ZSH', replacements: {'/usr/bin/open' => 'jobs_record_open'})
      jobs_record_open() {
        print -r -- "${(j:|:)@}"
      }
      open_host_for_extension_registration ipa-resign '/fixture/中文 space/JobsIPAResigner.app'
    ZSH
    assert_equal ['-gj|/fixture/中文 space/JobsIPAResigner.app|--args|--initialize-finder-extension'],
                 output.lines.map(&:strip)
  end

  def test_uninstall_mapping_and_title_selection_keep_the_same_identity
    output = run_definitions(UNINSTALLER, <<~'ZSH', ROOT)
      WORKSPACE_DIR="$1"
      parse_feature_selection 'ipa-resign,ipa-resign' || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "${FEATURE_TITLE[ipa-resign]}"
      print -r -- "${FEATURE_PROJECT_DIR[ipa-resign]}"
      print -r -- "${FEATURE_APP_NAME[ipa-resign]}"
      print -r -- "${FEATURE_EXTENSION_NAME[ipa-resign]}"
      print -r -- "${FEATURE_EXTENSION_ID[ipa-resign]}"
      derived_data_dir_for_key ipa-resign
    ZSH
    assert_equal [KEY, TITLE, APP, APP, 'JobsIPAResignerFinderSync.appex', "#{APP_ID}.FinderSyncExtension",

                  File.join(ROOT, "work/#{APP}DerivedData")], output.lines.map(&:strip)
  end

  def test_missing_ipa_resign_project_is_reported_before_building
    Dir.mktmpdir('jobs-ipa-resign-missing-project-') do |workspace|
      output = run_definitions(INSTALLER, <<~'ZSH', workspace)
        WORKSPACE_DIR="$1"
        for key in "${FEATURE_KEYS[@]}"; do
          [[ "$key" == ipa-resign ]] && continue
          /bin/mkdir -p "$(project_file_for_key "$key")"
          print -r -- '// fixture' > "$(project_file_for_key "$key")/project.pbxproj"
        done
        if ensure_feature_projects_exist; then
          exit 1
        fi
        print -r -- 'installation-stopped'
      ZSH
      assert_includes output, 'JobsIPAResigner.xcodeproj/project.pbxproj'
      assert_includes output, 'installation-stopped'
      assert_includes output, '重新取得包含全部工程源码的完整 MacOS@Extension 仓库'
      refute_includes output, 'JobsIOSSimulatorCreator.xcodeproj/project.pbxproj'
    end
  end

  private

  def run_definitions(path, checks, *arguments, replacements: {})
    source = isolated_installer_source(path, replacements: replacements)

    Dir.mktmpdir('jobs-ipa-resign-install-mapping-') do |directory|
      fixture = File.join(directory, 'mapping.zsh')
      File.write(fixture, source + "\nLOG_FILE=\"${0:h}/mapping.log\"\n" + checks)
      output, status = Open3.capture2e(isolated_installer_environment(directory), '/bin/zsh', '-f', fixture, *arguments)
      assert status.success?, output
      output
    end
  end
end
