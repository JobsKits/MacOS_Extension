# frozen_string_literal: true
# 在临时 Shell 中覆盖管理入口的确认与分发；所有业务命令均替换，不安装或卸载真实扩展。
# JOBS_TERMINAL_STYLE_GUARD_V1_BEGIN
if $PROGRAM_NAME == __FILE__
  # 直接运行时由 fork 父进程保护配色；子进程继续原文件，不重放 Ruby 参数和预载模块。
  def jobs_terminal_style_bootstrap_v1
    return unless $PROGRAM_NAME == __FILE__
    plain = lambda do
      ENV.update('PLAIN_OUTPUT' => '1', 'NO_COLOR' => '1', 'FORCE_COLOR' => '0',
                 'CLICOLOR' => '0', 'ANSI_COLORS_DISABLED' => '1', 'npm_config_color' => 'false')
    end
    notify = lambda do |message|
      encoding = $stderr.external_encoding || Encoding::UTF_8
      $stderr.write((message + "\n").encode(encoding, invalid: :replace, undef: :replace))
    end
    return unless $stdin.tty? && $stdout.tty?
    return if ENV.key?('NO_COLOR') || ENV['PLAIN_OUTPUT'] == '1' ||
              ENV['IS_SOURCETREE_RUNTIME'] == '1' ||
              ENV.keys.any? { |key| key.match?(/\A(?:SOURCETREE|SOURCE_TREE)/i) }
    return if ['', 'dumb'].include?(ENV.fetch('TERM', ''))
    if File::ALT_SEPARATOR == '\\' || !Process.respond_to?(:fork) ||
       Thread.list.length > 1 || ENV['TMUX'] || ENV['STY']
      plain.call
      return
    end
    tty_name = IO.popen(['tty'], err: File::NULL, &:read).strip
    groups = IO.popen(['ps', '-o', 'pgid=', '-o', 'tpgid=', '-p', Process.pid.to_s], err: File::NULL, &:read).split
    unless tty_name.match?(%r{\A/dev/[A-Za-z0-9_./-]+\z}) && groups.length == 2 &&
           groups.all? { |group| group.match?(/\A\d+\z/) } && groups[0].to_i > 0 && groups[0] == groups[1]
      plain.call
      return
    end
    owner = ENV['JOBS_TERMINAL_STYLE_OWNER']
    if ENV['JOBS_TERMINAL_STYLE_TTY'] == tty_name && owner && owner.match?(/\A\d+\z/)
      begin
        Process.kill(0, owner.to_i)
        return
      rescue Errno::ESRCH, Errno::EPERM
      end
    end
    require 'io/console'
    require 'tmpdir'
    if Thread.list.length > 1
      plain.call
      return
    end
    tty = File.open('/dev/tty', 'r+')
    tty.binmode
    tty.sync = true
    keys = ['10', '11', '12'] + (0..15).map { |index| "4;#{index}" }
    palette = %w[000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee
                 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff]
    targets = { '10' => 'ffffff', '11' => '000000', '12' => 'ffffff' }
    palette.each_with_index { |color, index| targets["4;#{index}"] = color }
    query = lambda do |key|
      tty.write("\e]#{key};?\a")
      bytes = ''.b
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.3
      loop do
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return nil if remaining <= 0 || !IO.select([tty], nil, nil, remaining)
        piece = tty.read_nonblock(256, exception: false)
        next if piece == :wait_readable
        return nil unless piece && !piece.empty?
        bytes << piece
        return nil if bytes.bytesize > 256 || !bytes.start_with?("\e".b)
        break if bytes.end_with?("\a".b) || bytes.end_with?("\e\\".b)
      end
      match = bytes.match(/\A\e\]#{Regexp.escape(key)};rgb:([0-9a-fA-F]{1,4})\/([0-9a-fA-F]{1,4})\/([0-9a-fA-F]{1,4})(?:\a|\e\\)\z/n)
      return nil unless match
      components = match.captures.map { |hex| (hex.to_i(16) * 65535.0 / (16**hex.length - 1)).round }
      { raw: bytes, rgb: components }
    rescue IOError, SystemCallError
      nil
    end
    snapshot = lambda do
      values = {}
      tty.raw(min: 0, time: 0, intr: true) do
        keys.each do |key|
          value = query.call(key)
          return nil unless value
          values[key] = value
        end
      end
      values
    rescue IOError, SystemCallError, ArgumentError
      nil
    end
    original = snapshot.call
    unless original
      notify.call('终端不支持完整配色保存，或启动时收到其它输入；保留原配色并使用纯文本。')
      tty.close
      plain.call
      return
    end
    directory = Dir.mktmpdir('jobs-terminal-style-')
    recovery = File.join(directory, 'restore.sh')
    original_bytes = keys.map { |key| original.fetch(key).fetch(:raw) }.join
    recovery_source = "#!/bin/sh\n" \
      "[ -t 0 ] && [ \"$(tty)\" = '#{tty_name}' ] || { printf '请在原终端运行恢复入口。\\n' >&2; exit 1; }\n" \
      "printf '本操作会覆盖此终端当前配色。确认恢复脚本启动前的配色，请输入 YES：' >&2\n" \
      "IFS= read -r jobs_restore_choice\n[ \"$jobs_restore_choice\" = YES ] || exit 1\n" \
      "printf '%s\\033[0m' '#{original_bytes}' > /dev/tty\n"
    File.open(recovery, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.binmode
      file.write(recovery_source.b)
    end
    notify.call("本次终端临时使用黑底白字；强退后恢复入口：sh \"#{recovery}\"")
    changed = false
    applied = nil
    # 比较仍生效的本轮颜色，只恢复未被用户另行修改的项。
    cleanup = lambda do
      current = applied && snapshot.call
      unless current
        notify.call("终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh \"#{recovery}\"")
        return false
      end
      conflicts = []
      restore_bytes = ''.b
      keys.each do |key|
        if current.fetch(key).fetch(:rgb) == applied.fetch(key).fetch(:rgb)
          restore_bytes << original.fetch(key).fetch(:raw)
        else
          conflicts << key
        end
      end
      tty.write(restore_bytes + "\e[0m".b)
      if conflicts.empty?
        File.unlink(recovery)
        Dir.rmdir(directory)
        true
      else
        notify.call("检测到运行期间的配色变更，已保留这些项：#{conflicts.join(' ')}")
        notify.call("确认要覆盖后续改色时才使用恢复入口：sh \"#{recovery}\"")
        false
      end
    rescue IOError, SystemCallError
      notify.call("终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh \"#{recovery}\"")
      false
    end
    child_pid = nil
    guardian = false
    interrupted = nil
    previous_signals = {}
    %w[INT TERM HUP].each do |name|
      previous_signals[name] = Signal.trap(name) do
        interrupted = name
        if child_pid && name != 'INT'
          begin
            Process.kill(name, child_pid)
          rescue Errno::ESRCH
          end
        end
      end
    end
    begin
      changed = true
      tty.write(targets.map { |key, color| "\e]#{key};##{color}\a" }.join + "\e[0m")
      applied = snapshot.call
      unless applied
        notify.call('无法核实本次临时配色，已停止启动业务。')
        raise SystemExit, 1
      end
      desired = targets.all? do |key, hex|
        rgb = hex.scan(/../).map { |component| component.to_i(16) * 257 }
        applied.fetch(key).fetch(:rgb).zip(rgb).all? { |actual, expected| (actual - expected).abs <= 255 }
      end
      unless desired
        notify.call('终端未接受本次配色，恢复后使用纯文本。')
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      if interrupted
        raise SystemExit, 128 + Signal.list.fetch(interrupted)
      end
      if Thread.list.length > 1
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      $stdout.flush
      $stderr.flush
      begin
        child_pid = Process.fork
      rescue NotImplementedError, SystemCallError
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      unless child_pid
        changed = false
        ENV['JOBS_TERMINAL_STYLE_TTY'] = tty_name
        ENV['JOBS_TERMINAL_STYLE_OWNER'] = Process.ppid.to_s
        raise SystemExit, 128 + Signal.list.fetch(interrupted) if interrupted
        return
      end
      guardian = true
      result = nil
      loop do
        begin
          _, result = Process.wait2(child_pid)
          break
        rescue Interrupt, Errno::EINTR
        end
      end
      status_code = result.exitstatus || 128 + result.termsig
      %w[INT TERM HUP].each { |name| Signal.trap(name, 'IGNORE') }
      restored = cleanup.call
      changed = false
      status_code = 1 if !restored && status_code.zero?
      tty.close
      Process.exit!(status_code)
    ensure
      if changed
        %w[INT TERM HUP].each { |name| Signal.trap(name, 'IGNORE') }
        cleanup.call
      end
      previous_signals.each { |name, handler| Signal.trap(name, handler) } unless guardian
      tty.close unless tty.closed?
    end
  rescue IOError, SystemCallError, LoadError => error
    if guardian
      notify.call("终端保护监督进程异常：#{error.message}")
      Process.exit!(1)
    end
    raise SystemExit, 1 if changed
    notify.call("终端保护不可用，使用纯文本：#{error.message}")
    plain.call
  end
  jobs_terminal_style_bootstrap_v1

end
# JOBS_TERMINAL_STYLE_GUARD_V1_END

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
    assert_equal 32, MANAGERS.length
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
    if %w[JobsFileCreator JobsFileHasher].any? { |name| path.include?("/#{name}/") }
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
