# frozen_string_literal: true
# 在临时 Shell 中覆盖管理入口的确认与分发；所有业务命令均替换，不安装或卸载真实扩展。
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'pty'
require 'timeout'

class SingleFeatureManagerTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  MANAGERS = Dir.glob(File.join(ROOT, 'Jobs*', 'Scripts/ManageExtension.zsh')).sort.freeze

  def test_every_feature_has_one_parseable_manager_and_no_paired_entry
    assert_equal 31, MANAGERS.length
    assert_empty Dir.glob(File.join(ROOT, 'Jobs*', '【MacOS】安装*Finder扩展.command'))
    assert_empty Dir.glob(File.join(ROOT, 'Jobs*', '【MacOS】卸载*Finder扩展.command'))
    MANAGERS.each do |path|
      output, result = Open3.capture2e('/bin/zsh', '-n', path)
      assert result.success?, "#{path}: #{output}"
      %w[install uninstall].each do |operation|
        output, result = run_stubbed(path, '--action', operation, '--non-interactive')
        assert result.success?, "#{path}: #{output}"
        assert_equal [operation], output.scan(/BUSINESS=(install|uninstall)/).flatten, path
      end
      output, result = run_stubbed(path, '--non-interactive')
      assert_equal 2, result.exitstatus, "#{path}: #{output}"
      refute_match(/BUSINESS=(?:install|uninstall)/, output)
    end
  end

def test_non_tty_opens_gui_without_dispatching_operations
  output, result = run_stubbed(MANAGERS.first)
  assert result.success?, output
  assert_includes output, 'OPEN_GUI'
  refute_match(/BUSINESS=(?:install|uninstall)/, output)
end

def test_explicit_action_in_normal_mode_still_opens_gui
  %w[install uninstall].each do |action|
    output, result = run_stubbed(MANAGERS.first, '--action', action)
    assert result.success?, output
    assert_includes output, 'OPEN_GUI'
    refute_match(/BUSINESS=(?:install|uninstall)/, output)
  end
end

def test_worker_does_not_read_or_invoke_fzf
  %w[install uninstall].each do |action|
    output, result = Open3.capture2e('/bin/zsh', '-c', definitions(MANAGERS.first) + <<~'ZSH', MANAGERS.first, '--action', action, '--non-interactive')
      manager_open_gui() { print -r -- OPEN_GUI; }
      run_install_operation() { print -r -- BUSINESS=install; }
      run_uninstall_operation() { print -r -- BUSINESS=uninstall; }
      read() { print -u2 unexpected-read; return 99; }
      fzf() { print -u2 unexpected-fzf; return 99; }
      manager_main "$@"
    ZSH
    assert result.success?, output
    assert_includes output, "BUSINESS=#{action}"
    refute_includes output, 'unexpected-'
  end
end

  def test_flutter_unknown_action_is_rejected_before_confirmation_and_build
    manager = MANAGERS.find { |p| p.include?('/JobsFlutterTools/') }
    output, result = run_stubbed(manager, '--action', 'install', '--features', 'unexpected', '--non-interactive')
    assert_equal 2, result.exitstatus
    refute_match(/BUSINESS=(?:install|uninstall)/, output)
  end

  def test_flutter_partial_removal_preserves_unselected_actions_and_valid_empty_config
    manager = MANAGERS.find { |p| p.include?('/JobsFlutterTools/') }
    Dir.mktmpdir('jobs-manager-shared-') do |dir|
      configuration = File.join(dir, 'Library/Application Support/JobsFinderExtensions/flutter-tools-features.conf')
      FileUtils.mkdir_p(File.dirname(configuration))
      File.write(configuration, 'run,package-ios,sdk-manage')
      output, result = Open3.capture2e({ 'HOME' => dir }, '/bin/zsh', '-c', definitions(manager) + <<~'ZSH')
        MANAGER_REQUESTED_FEATURES=package-ios
        MANAGER_SKIP_RESTART=1
        manager_plan_shared_removal || exit $?
        print -r -- "partial=$MANAGER_PARTIAL_REMOVAL"
      ZSH
      assert result.success?, output
      assert_equal 'run,sdk-manage', File.read(configuration)
      assert_includes output, 'partial=1'
      File.write(configuration, '')
      output, result = Open3.capture2e({ 'HOME' => dir }, '/bin/zsh', '-c', definitions(manager) + <<~'ZSH')
        MANAGER_REQUESTED_FEATURES=run
        MANAGER_SKIP_RESTART=1
        manager_plan_shared_removal || exit $?
        print -r -- "partial=$MANAGER_PARTIAL_REMOVAL"
      ZSH
      assert result.success?, output
      assert_includes output, 'partial=0'
    end
  end

  def test_flutter_subset_install_creates_a_valid_list_without_enabling_unselected_actions
    manager = MANAGERS.find { |p| p.include?('/JobsFlutterTools/') }
    Dir.mktmpdir('jobs-manager-install-selection-') do |dir|
      configuration = File.join(dir, 'Library/Application Support/JobsFinderExtensions/flutter-tools-features.conf')
      output, result = Open3.capture2e({ 'HOME' => dir }, '/bin/zsh', '-c', definitions(manager) + <<~'ZSH')
        MANAGER_REQUESTED_FEATURES=package-android
        log() { print -r -- "$*"; }
        manager_persist_flutter_selection || exit $?
      ZSH
      assert result.success?, output
      assert_equal 'package-android', File.read(configuration)
    end
  end

  def test_bad_shared_configuration_stops_without_changing_the_file
    manager = MANAGERS.find { |p| p.include?('/JobsFlutterTools/') }
    Dir.mktmpdir('jobs-manager-bad-config-') do |dir|
      configuration = File.join(dir, 'Library/Application Support/JobsFinderExtensions/flutter-tools-features.conf')
      FileUtils.mkdir_p(File.dirname(configuration))
      ['run,,sdk-manage', 'unexpected', ',run', 'run,'].each do |content|
        File.write(configuration, content)
        output, result = Open3.capture2e({ 'HOME' => dir }, '/bin/zsh', '-c', definitions(manager) + "\nmanager_validate_existing_configuration\n")
        refute result.success?, output
        assert_equal content, File.read(configuration)
      end
    end
  end

  def test_dependency_import_can_be_installed_and_removed_independently_of_extraction
    manager = MANAGERS.find { |p| p.include?('/JobsFlutterTools/') }
    Dir.mktmpdir('jobs-manager-import-selection-') do |dir|
      configuration = File.join(dir, 'Library/Application Support/JobsFinderExtensions/flutter-tools-features.conf')
      FileUtils.mkdir_p(File.dirname(configuration))
      File.write(configuration, 'extract')
      output, result = Open3.capture2e({ 'HOME' => dir }, '/bin/zsh', '-c', definitions(manager) + <<~'ZSH')
        MANAGER_REQUESTED_FEATURES=import-dependencies
        MANAGER_SKIP_RESTART=1
        log() { print -r -- "$*"; }
        manager_persist_flutter_selection || exit $?
      ZSH
      assert result.success?, output
      assert_equal 'extract,import-dependencies', File.read(configuration)
      output, result = Open3.capture2e({ 'HOME' => dir }, '/bin/zsh', '-c', definitions(manager) + <<~'ZSH')
        MANAGER_REQUESTED_FEATURES=import-dependencies
        MANAGER_SKIP_RESTART=1
        manager_plan_shared_removal || exit $?
        print -r -- "partial=$MANAGER_PARTIAL_REMOVAL"
      ZSH
      assert result.success?, output
      assert_equal 'extract', File.read(configuration)
      assert_includes output, 'partial=1'
    end
  end

  def test_bad_ios_configuration_stops_before_uninstall_and_accepts_legacy_alias
    manager = MANAGERS.find { |p| p.include?('/JobsIOSTools/') }
    Dir.mktmpdir('jobs-manager-ios-config-') do |dir|
      configuration = File.join(dir, 'Library/Application Support/JobsIOSTools/EnabledFeatures.txt')
      FileUtils.mkdir_p(File.dirname(configuration))
      ['unexpected', 'ios-pod-install,,ios-pod-update'].each do |content|
        File.write(configuration, content)
        output, result = Open3.capture2e({ 'HOME' => dir }, '/bin/zsh', '-c', definitions(manager) + "\nmanager_validate_existing_configuration\n")
        refute result.success?, output
        assert_equal content, File.read(configuration)
      end
      File.write(configuration, 'ios-clean-cache')
      output, result = Open3.capture2e({ 'HOME' => dir }, '/bin/zsh', '-c', definitions(manager) + "\nmanager_validate_existing_configuration\n")
      assert result.success?, output
    end
  end

  private

  def definitions(path)
    text = File.read(path)
    raise '管理入口缺失' unless text.sub!(/^(?:manager_)?main "\$@"\s*\z/, '')
    text
  end

  def stubbed(path)
    if path.include?('/JobsFileCreator/')
      return definitions(path) + <<~'ZSH'
        open_management_panel() { print -r -- OPEN_GUI; }
        run_worker() { print -r -- "BUSINESS=$MANAGER_ACTION"; }
        main "$@"
      ZSH
    end
    definitions(path) + <<~'ZSH'
      manager_open_gui() { print -r -- OPEN_GUI; }
      run_install_operation() { print -r -- BUSINESS=install; }
      run_uninstall_operation() { print -r -- BUSINESS=uninstall; }
      manager_validate_existing_configuration() { return 0; }
      manager_main "$@"
    ZSH
  end

  def run_stubbed(path, *args)
    Open3.capture2e('/bin/zsh', '-c', stubbed(path), path, *args)
  end

  def run_tty(operation, input, picker_exit: nil)
    Dir.mktmpdir('jobs-manager-tty-') do |directory|
      source = definitions(MANAGERS.first)
      source += <<~'ZSH'
        run_install_operation() { print -r -- BUSINESS=install; }
        run_uninstall_operation() { print -r -- BUSINESS=uninstall; }
      ZSH
      unless picker_exit.nil?
        source += "fzf() { [[ \"$1\" == --version ]] && { print 0.60.0; return 0; }; return #{picker_exit}; }\n"
      end
      source += "manager_main \"$@\"\n"
      fixture = File.join(directory, 'manager.zsh')
      File.write(fixture, source)
      args = operation ? ['--action', operation] : []
      transcript = +''
      pid = nil
      result = nil
      PTY.spawn({ 'TERM' => 'dumb', 'NO_COLOR' => '1' }, '/bin/zsh', fixture, *args) do |reader, writer, child_pid|
        pid = child_pid
        writer.write(input)
        writer.flush
        Timeout.timeout(8) do
          begin
            loop { transcript << reader.readpartial(4096) }
          rescue EOFError, Errno::EIO
            # 正常 PTY 收尾。
          end
        end
        _, result = Process.wait2(pid)
      end
      [transcript.delete("\r"), result]
    end
  end
end
