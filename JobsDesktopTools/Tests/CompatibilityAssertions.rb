# frozen_string_literal: true
# 真实执行旧入口，仅由临时管理器承接参数；不会调用系统安装、注册或业务。
require 'tmpdir'
require 'fileutils'
require 'open3'

module LegacyDesktopEntryAssertions
  def test_install_entry_preserves_leaf_identity_and_options
    with_compatibility_fixture(self.class::INSTALLER) do |entry, manager|
      File.write(manager, "#!/bin/zsh\n/usr/bin/printf '%s\\0' \"$@\"\n")
      output, status = Open3.capture2e('/bin/zsh', entry, '--non-interactive', '--skip-finder-restart')
      assert status.success?, output
      assert_equal ['install', desktop_leaf, '--non-interactive', '--skip-finder-restart'], output.split("\0")
    end
  end

  def test_uninstall_entry_preserves_leaf_identity_and_options
    with_compatibility_fixture(self.class::UNINSTALLER) do |entry, manager|
      File.write(manager, "#!/bin/zsh\n/usr/bin/printf '%s\\0' \"$@\"\n")
      output, status = Open3.capture2e('/bin/zsh', entry, '--non-interactive', '--skip-finder-restart')
      assert status.success?, output
      assert_equal ['uninstall', desktop_leaf, '--non-interactive', '--skip-finder-restart'], output.split("\0")
    end
  end

  def test_compatibility_entry_propagates_manager_failure
    with_compatibility_fixture(self.class::INSTALLER) do |entry, manager|
      File.write(manager, "#!/bin/zsh\nexit 7\n")
      _output, status = Open3.capture2e('/bin/zsh', entry, '--non-interactive')
      assert_equal 7, status.exitstatus
    end
  end

  def test_missing_aggregate_source_stops_before_any_business
    with_compatibility_fixture(self.class::INSTALLER) do |entry, _manager|
      output, status = Open3.capture2e('/bin/zsh', entry, '--non-interactive')
      refute status.success?, output
      assert_includes output, '包含 JobsDesktopTools 的完整'
    end
  end

  private

  def with_compatibility_fixture(source)
    Dir.mktmpdir('jobs-desktop-compatibility-') do |directory|
      legacy = File.join(directory, File.basename(self.class::ROOT))
      manager = File.join(directory, 'JobsDesktopTools/Scripts/ManageDesktopTools.zsh')
      FileUtils.mkdir_p([legacy, File.dirname(manager)])
      entry = File.join(legacy, File.basename(source))
      FileUtils.cp(source, entry)
      yield entry, manager
    end
  end
end
