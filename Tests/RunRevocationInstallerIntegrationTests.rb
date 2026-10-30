# frozen_string_literal: true
# 只读取真实安装器定义并在临时 Shell 内核对映射，不构建、注册扩展或操作模拟器。

require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require_relative 'IsolatedInstallerDefinitions'

class RunRevocationInstallerIntegrationTests < Minitest::Test
  include IsolatedInstallerDefinitions
  ROOT = File.expand_path('..', __dir__)
  INSTALLER = File.join(ROOT, 'Scripts/ManageFinderExtensions.zsh')
  UNINSTALLER = File.join(ROOT, 'Scripts/ManageFinderExtensions.zsh')
  PROJECT = File.join(ROOT, 'JobsRunAuthorizationRevoker')
  KEY = 'run-revoke'
  APP = 'JobsRunAuthorizationRevoker'
  APP_ID = 'com.jobs.JobsRunAuthorizationRevoker'

  def test_selector_contains_revocation_once_next_to_ios
    selector = File.read(File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift'))
    options = selector.scan(/FeatureOption\(identifier: "([^"]+)", title: "([^"]+)"\)/)
    assert_equal [[KEY, '解除运行授权']], options.select { |identifier, _| identifier == KEY }
    identifiers = options.map(&:first)
    assert_operator identifiers.index(KEY), :>, identifiers.index('run-authorize')
    assert_operator identifiers.index(KEY), :<, identifiers.index('terminal_open')
  end

  def test_install_mapping_is_independent_and_keeps_explicit_revocation_identity
    output = run_definitions(INSTALLER, <<~'ZSH', ROOT)
      WORKSPACE_DIR="$1"
      parse_feature_selection 'run-revoke,run-revoke' || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "${FEATURE_TITLE[run-revoke]}"
      print -r -- "${FEATURE_SCHEME[run-revoke]}"
      print -r -- "${FEATURE_APP_NAME[run-revoke]}"
      print -r -- "${FEATURE_EXTENSION_NAME[run-revoke]}"
      app_bundle_id_for_key run-revoke
      print -r -- "${FEATURE_EXTENSION_ID[run-revoke]}"
      print -r -- "terminal:${TERMINAL_OPENER_ENABLED_FEATURES}"
      project_file_for_key run-revoke
      derived_data_dir_for_key run-revoke
    ZSH
    assert_equal [KEY, '解除运行授权', APP, APP, 'JobsRunAuthorizationRevokerFinderSync.appex',
                  APP_ID, "#{APP_ID}.FinderSyncExtension", 'terminal:', File.join(PROJECT, "#{APP}.xcodeproj"),
                  File.join(ROOT, "work/#{APP}DerivedData")], output.lines.map(&:strip)
  end

  def test_install_selection_can_combine_both_mobile_platforms_and_terminal
    output = run_definitions(INSTALLER, <<~'ZSH')
      parse_feature_selection 'run-revoke,run-authorize,terminal_open,run-revoke' || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "$TERMINAL_OPENER_ENABLED_FEATURES"
    ZSH
    assert_equal ['run-revoke,run-authorize,terminal_opener', 'open'], output.lines.map(&:strip)
  end

  def test_uninstall_mapping_keeps_revocation_process_marker_log_and_derived_data
    output = run_definitions(UNINSTALLER, <<~'ZSH', ROOT)
      WORKSPACE_DIR="$1"
      parse_feature_selection 'run-revoke' || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "${FEATURE_PROJECT_DIR[run-revoke]}"
      print -r -- "${FEATURE_APP_NAME[run-revoke]}"
      print -r -- "${FEATURE_EXTENSION_NAME[run-revoke]}"
      print -r -- "${FEATURE_EXTENSION_ID[run-revoke]}"
      derived_data_dir_for_key run-revoke
    ZSH
    assert_equal [KEY, APP, APP, 'JobsRunAuthorizationRevokerFinderSync.appex', "#{APP_ID}.FinderSyncExtension",

                  File.join(ROOT, "work/#{APP}DerivedData")], output.lines.map(&:strip)
  end

  def test_registration_initializes_revocation_host_without_creating_a_simulator
    output = run_definitions(INSTALLER, <<~'ZSH', replacements: {'/usr/bin/open' => 'jobs_record_open'})
      jobs_record_open() {
        print -r -- "${(j:|:)@}"
      }
      open_host_for_extension_registration run-revoke '/fixture/中文 space/JobsRunAuthorizationRevoker.app'
    ZSH
    assert_equal ['-gj|/fixture/中文 space/JobsRunAuthorizationRevoker.app|--args|--initialize-finder-extension'], output.lines.map(&:strip)
  end

  def test_missing_revocation_project_is_reported_before_building
    Dir.mktmpdir('jobs-revocation-missing-project-') do |workspace|
      output = run_definitions(INSTALLER, <<~'ZSH', workspace)
        WORKSPACE_DIR="$1"
        for key in "${FEATURE_KEYS[@]}"; do
          [[ "$key" == run-revoke ]] && continue
          /bin/mkdir -p "$(project_file_for_key "$key")"
          print -r -- '// fixture' > "$(project_file_for_key "$key")/project.pbxproj"
        done
        log() { print -r -- "$1"; }
        if ensure_feature_projects_exist; then
          exit 1
        fi
        print -r -- 'installation-stopped'
      ZSH
      assert_includes output, 'JobsRunAuthorizationRevoker.xcodeproj/project.pbxproj'
      assert_includes output, 'installation-stopped'
      assert_includes output, '重新取得包含全部工程源码的完整 MacOS@Extension 仓库'
      refute_includes output, 'JobsIOSSimulatorCreator.xcodeproj/project.pbxproj'
    end
  end

  def test_standalone_project_declares_both_targets_and_bundled_business_script
    project = File.read(File.join(PROJECT, "#{APP}.xcodeproj/project.pbxproj"))
    assert_includes project, 'PRODUCT_BUNDLE_IDENTIFIER = com.jobs.JobsRunAuthorizationRevoker;'
    assert_includes project, 'PRODUCT_BUNDLE_IDENTIFIER = com.jobs.JobsRunAuthorizationRevoker.FinderSyncExtension;'
    assert_includes project, 'RevokeRun.zsh in Resources'
    assert_includes project, 'JobsRunAuthorizationRevokerFinderSync.appex in Embed App Extensions'
    assert File.file?(File.join(PROJECT, 'Scripts/ManageExtension.zsh'))
    assert_empty Dir.glob(File.join(PROJECT, '【MacOS】安装*Finder扩展.command'))
    assert_empty Dir.glob(File.join(PROJECT, '【MacOS】卸载*Finder扩展.command'))
    refute_includes project, 'IOSSimulator'
    refute_includes project, 'iossimulator'
  end

  private

  def run_definitions(path, checks, *arguments, replacements: {})
    source = isolated_installer_source(path, replacements: replacements)

    Dir.mktmpdir('jobs-revocation-install-mapping-') do |directory|
      fixture = File.join(directory, 'mapping.zsh')
      File.write(fixture, source + "\nLOG_FILE=\"${0:h}/mapping.log\"\n" + checks)
      output, status = Open3.capture2e(isolated_installer_environment(directory), '/bin/zsh', '-f', fixture, *arguments)
      assert status.success?, output
      output
    end
  end
end
