# frozen_string_literal: true
# 使用临时文件验证真实 chmod / xattr；不触碰原业务脚本或业务文件。

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

require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'pty'
require 'timeout'
require 'tmpdir'

require_relative '../../../Tests/SourceLayoutHelper.rb/SourceLayoutHelper'

class RunRevocationCommandTests < Minitest::Test
  SCRIPT = File.expand_path('../Scripts/【MacOS】RevokeRun.zsh/【MacOS】RevokeRun.zsh', File.dirname(__dir__))

  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-run-authorizer-test-'))
    @logs = File.join(@root, 'logs')
    FileUtils.mkdir_p(@logs)
    @env = { 'TMPDIR' => @logs, 'NO_COLOR' => '1', 'TERM' => 'dumb' }
    @file = File.join(@root, '任意单文件.data')
    File.write(@file, "#!/bin/zsh\nprint -r -- should-not-run\n")
    File.chmod(0o755, @file)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def run_readonly(*arguments, input: '')
    out, err, result = Open3.capture3(@env, '/bin/zsh', SCRIPT, *arguments, stdin_data: input)
    [out + err, result.exitstatus]
  end

  def run_interactive(*arguments, input: "\n", mask: '022', &before_confirmation)
    output = +''.b
    result = nil
    child_pid = nil
    confirmed = false
    Timeout.timeout(10) do
      PTY.spawn(@env, '/bin/zsh', '-c', 'umask "$1"; shift; exec /bin/zsh "$@"',
                'authorization-fixture', mask, SCRIPT, *arguments, chdir: @root) do |reader, writer, child|
        child_pid = child
        begin
          loop do
            output << reader.readpartial(4096)
            next if confirmed || !output.include?('已了解用途，直接回车继续；任意字符取消：'.b)

            confirmed = true
            before_confirmation&.call
            writer.write(input)
          end
        rescue EOFError, Errno::EIO
          # macOS 的 PTY 在 slave 关闭时可能返回 EIO。
        end
        _, result = Process.waitpid2(child)
      end
    end
    [output.force_encoding('UTF-8'), result.exitstatus]
  rescue Timeout::Error
    Process.kill('TERM', child_pid) if child_pid
    Process.wait(child_pid) if child_pid
    raise "脚本等待超时：#{output.force_encoding('UTF-8').scrub}"
  end

  def mode(file = @file)
    File.stat(file).mode & 0o7777
  end

  def assert_no_logs
    assert_empty Dir.children(@logs)
  end

  def test_help_is_readonly_and_needs_no_terminal
    out, status = run_readonly('--help')
    assert_equal 0, status, out
    assert_includes out, '--check --file'
    assert_includes out, 'chmod -x'
    assert_equal 0o755, mode
    assert_no_logs
    refute_includes out, "\e["
  end

  def test_check_is_readonly_and_reports_selected_file
    out, status = run_readonly('--check', '--file', @file)
    assert_equal 0, status, out
    assert_includes out, '只读检查通过'
    assert_includes out, '755'
    assert_equal 0o755, mode
    assert_no_logs
  end

  def test_only_explicit_single_file_arguments_are_accepted
    [[], [@file], ['--file'], ['--file', @file, @file], ['--file', @file, '--file', @file],
     ['--file', 'relative.command'], ['--help', '--file', @file], ['--check'],
     ['--check', '--file', @file, @file], ['--file', @file, '--check']].each do |arguments|
      out, status = run_readonly(*arguments)
      refute_equal 0, status, "#{arguments.inspect}: #{out}"
      assert_equal 0o755, mode
      assert_no_logs
    end
  end

  def test_directories_packages_links_missing_files_and_special_files_are_rejected
    folder = File.join(@root, '目录')
    package = File.join(@root, 'Application.app')
    link = File.join(@root, '文件链接.command')
    broken_link = File.join(@root, '失效链接.command')
    missing = File.join(@root, '不存在.command')
    fifo = File.join(@root, 'pipe.command')
    FileUtils.mkdir_p([folder, package])
    File.symlink(@file, link)
    File.symlink(missing, broken_link)
    _, _, fifo_status = Open3.capture3('/usr/bin/mkfifo', fifo)
    assert fifo_status.success?
    [folder, package, link, broken_link, missing, fifo].each do |target|
      out, status = run_readonly('--check', '--file', target)
      refute_equal 0, status, out
      assert_includes out, '只支持一个普通文件'
      assert_equal 0o755, mode
      assert_no_logs
    end
  end

  def test_noninteractive_input_cannot_authorize
    out, status = run_readonly('--file', @file, input: "\n")
    refute_equal 0, status, out
    assert_includes out, '可交互终端'
    assert_equal 0o755, mode
    assert_no_logs
  end

  def test_nonempty_confirmation_and_whitespace_cancel_without_writes
    ["取消\n", " \n", "YES\n"].each do |input|
      out, status = run_interactive('--file', @file, input: input)
      assert_equal 0, status, out
      assert_includes out, '已取消移除执行权限'
      assert_equal 0o755, mode
      assert_no_logs
    end
  end

  def test_eof_stops_without_authorization_or_logs
    out, status = run_interactive('--file', @file, input: "\x04")
    refute_equal 0, status, out
    assert_includes out, '输入已结束'
    assert_equal 0o755, mode
    assert_no_logs
  end

  def test_confirmation_creates_private_distinct_logs_and_removes_execute_bits
    before = File.binread(@file)
    2.times do
      out, status = run_interactive('--file', @file)
      assert_equal 0, status, out
      assert_includes out, 'chmod -x 成功'
      assert_equal 0o644, mode
      assert_equal before, File.binread(@file)
    end
    directories = Dir.glob(File.join(@logs, 'JobsRunAuthorizationRevoker.*'))
    assert_equal 2, directories.size
    directories.each do |directory|
      assert_equal 0o700, mode(directory)
      logfile = File.join(directory, 'run.log')
      assert_equal 0o600, mode(logfile)
      assert_includes File.read(logfile), 'chmod -x 成功'
      refute_includes File.read(logfile), "\e["
    end
  end

  def test_chmod_minus_x_preserves_the_original_umask_semantics
    out, status = run_interactive('--file', @file, mask: '077')
    assert_equal 0, status, out
    assert_equal 0o655, mode
    assert_includes out, 'umask 保护的执行位仍然保留'
    File.chmod(0o755, @file)
    out, status = run_interactive('--file', @file, mask: '027')
    assert_equal 0, status, out
    assert_equal 0o645, mode
  end

  def test_read_write_bits_are_preserved_for_varied_modes_and_masks
    [[0o777, '077', 0o677], [0o751, '027', 0o641], [0o600, '777', 0o600], [0o710, '077', 0o610]].each do |initial, mask, expected|
      File.chmod(initial, @file)
      out, status = run_interactive('--file', @file, mask: mask)
      assert_equal 0, status, out
      assert_equal expected, mode
      assert_equal initial & 0o666, mode & 0o666
    end
  end

  def test_special_path_is_one_literal_argument_and_target_is_never_executed
    name = "中文 空格 ' 引号\" $ (x) $(touch SUBSTITUTED) `touch BACKTICK`\n下一行.command"
    target = File.join(@root, name)
    File.write(target, "#!/bin/zsh\ntouch EXECUTED\n")
    File.chmod(0o751, target)
    before = File.binread(target)
    out, status = run_interactive('--file', target)
    assert_equal 0, status, out
    assert_equal 0o640, mode(target)
    assert_equal before, File.binread(target)
    %w[SUBSTITUTED BACKTICK EXECUTED].each { |marker| refute File.exist?(File.join(@root, marker)) }
    assert_includes out, '\\n'
  end

  def test_quarantine_and_other_attributes_remain_unchanged
    { 'com.apple.quarantine' => '0083;12345678;Fixture;', 'com.jobs.authorization.fixture' => 'preserved' }.each do |name, value|
      out, err, status = Open3.capture3('/usr/bin/xattr', '-w', name, value, @file)
      assert status.success?, out + err
    end
    before, err, result = Open3.capture3('/usr/bin/xattr', '-l', @file)
    assert result.success?, err
    out, status = run_interactive('--file', @file)
    assert_equal 0, status, out
    after, err, result = Open3.capture3('/usr/bin/xattr', '-l', @file)
    assert result.success?, err
    assert_equal before, after
    assert_equal 0o644, mode
  end

  def test_target_replaced_while_confirming_is_not_authorized
    original = File.join(@root, '原文件.command')
    out, status = run_interactive('--file', @file) do
      File.rename(@file, original)
      File.write(@file, 'replacement')
      File.chmod(0o755, @file)
    end
    refute_equal 0, status, out
    assert_includes out, '已被替换'
    assert_equal 0o755, mode
    assert_equal 0o755, mode(original)
    assert_no_logs
  end

  def test_target_changed_to_symlink_while_confirming_is_not_authorized
    original = File.join(@root, '原文件.command')
    out, status = run_interactive('--file', @file) do
      File.rename(@file, original)
      File.symlink(original, @file)
    end
    refute_equal 0, status, out
    assert_includes out, '只支持一个普通文件'
    assert_equal 0o755, mode(original)
    assert_no_logs
  end

  def test_log_creation_failure_stops_before_chmod
    FileUtils.remove_entry(@logs)
    File.write(@logs, 'not a directory')
    out, status = run_interactive('--file', @file)
    refute_equal 0, status, out
    assert_includes out, '临时目录不存在'
    assert_equal 0o755, mode
  end

  def test_real_chmod_failure_is_reported_and_returned
    _, _, flags_status = Open3.capture3('/usr/bin/chflags', 'uchg', @file)
    skip '临时文件系统不支持用户不可变标志' unless flags_status.success?

    out, status = run_interactive('--file', @file)
    refute_equal 0, status, out
    assert_includes out, 'chmod -x 失败'
    assert_equal 0o755, mode
    logfile = Dir.glob(File.join(@logs, 'JobsRunAuthorizationRevoker.*', 'run.log')).fetch(0)
    assert_includes File.read(logfile), 'chmod -x 失败'
    refute_includes out, 'chmod -x 成功'
  ensure
    Open3.capture3('/usr/bin/chflags', 'nouchg', @file) if File.exist?(@file)
  end
end
