# frozen_string_literal: true
# 读取真实总入口，在隔离 Shell 中验证面板叶映射和安装/卸载转发。
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require_relative '../../Tests/IsolatedInstallerDefinitions'

module DesktopRootIntegrationAssertions
  include IsolatedInstallerDefinitions
  def test_leaf_remains_an_independent_selector_option
    selector = File.read(File.join(desktop_workspace, 'Scripts/SelectFinderExtensionFeatures.swift'))
    ids = selector.scan(/FeatureOption\(identifier: "([^"]+)"/).flatten
    assert_equal 1, ids.count(desktop_leaf)
  end

  def test_selected_leaf_uses_one_aggregate_installation_unit
    output = run_root_source('Scripts/ManageFinderExtensions.zsh', <<~'ZSH')
      parse_feature_selection "$2,$2" || exit 1
      print -r -- "${(j:,:)SELECTED_KEYS}"
      print -r -- "${(j:,:)SELECTED_FUNCTION_IDS}"
      print -r -- "${FEATURE_PROJECT_DIR[desktop-tools]}"
      print -r -- "${FEATURE_EXTENSION_ID[desktop-tools]}"
    ZSH
    assert_equal ['desktop-tools', desktop_leaf, 'JobsDesktopTools', 'com.jobs.desktoptools.findersync'], output.lines.map(&:strip)
  end

  def test_install_dispatches_only_requested_leaf_to_transaction_manager
    output = run_root_source('Scripts/ManageFinderExtensions.zsh', <<~'ZSH', replace_zsh: true)
      jobs_fake_zsh() { print -r -- "${(j:|:)@}"; }
      parse_feature_selection "$2" || exit 1
      install_feature desktop-tools
    ZSH
    assert_equal [File.join(desktop_workspace, 'JobsDesktopTools/Scripts/ManageDesktopTools.zsh'), 'install', desktop_leaf, '--non-interactive', '--skip-finder-restart'].join('|'), output.strip
  end

  def test_uninstall_dispatches_only_requested_leaf_without_removing_shared_app
    output = run_root_source('Scripts/ManageFinderExtensions.zsh', <<~'ZSH', replace_zsh: true)
      jobs_fake_zsh() { print -r -- "${(j:|:)@}"; }
      disable_extension() { print -u2 'unexpected legacy package uninstall'; return 9; }
      remove_local_deriveddata_dir() { return 9; }
      parse_feature_selection "$2" || exit 1
      uninstall_feature desktop-tools
    ZSH
    assert_equal [File.join(desktop_workspace, 'JobsDesktopTools/Scripts/ManageDesktopTools.zsh'), 'uninstall', desktop_leaf, '--non-interactive', '--skip-finder-restart'].join('|'), output.strip
  end

  private

  def desktop_workspace
    File.expand_path('../..', __dir__)
  end

  def run_root_source(filename, checks, replace_zsh: false)
    replacements = replace_zsh ? {'/bin/zsh' => 'jobs_fake_zsh'} : {}
    source = isolated_installer_source(File.join(desktop_workspace, filename), replacements: replacements)
    Dir.mktmpdir('jobs-desktop-root-integration-') do |directory|
      fixture = File.join(directory, 'fixture.zsh')
      File.write(fixture, source + "\nWORKSPACE_DIR=\"$1\"\nLOG_FILE=\"${0:h}/fixture.log\"\n" + checks)
      output, status = Open3.capture2e(isolated_installer_environment(directory), '/bin/zsh', '-f', fixture, desktop_workspace, desktop_leaf)
      assert status.success?, output
      output
    end
  end
end
