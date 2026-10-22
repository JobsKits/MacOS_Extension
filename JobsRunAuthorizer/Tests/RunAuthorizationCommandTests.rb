# frozen_string_literal: true
# 使用临时文件验证真实 chmod / xattr；不触碰原业务脚本或业务文件。

require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'pty'
require 'timeout'
require 'tmpdir'

class RunAuthorizationCommandTests < Minitest::Test
  SCRIPT = File.expand_path('../Scripts/AuthorizeRun.zsh', __dir__)

  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-run-authorizer-test-'))
    @logs = File.join(@root, 'logs')
    FileUtils.mkdir_p(@logs)
    @env = { 'TMPDIR' => @logs, 'NO_COLOR' => '1', 'TERM' => 'dumb' }
    @file = File.join(@root, '待授权.command')
    File.write(@file, "#!/bin/zsh\nprint -r -- should-not-run\n")
    File.chmod(0o644, @file)
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
    assert_includes out, 'chmod +x'
    assert_equal 0o644, mode
    assert_no_logs
    refute_includes out, "\e["
  end

  def test_check_is_readonly_and_reports_selected_file
    out, status = run_readonly('--check', '--file', @file)
    assert_equal 0, status, out
    assert_includes out, '只读检查通过'
    assert_includes out, '644'
    assert_equal 0o644, mode
    assert_no_logs
  end

  def test_only_explicit_single_file_arguments_are_accepted
    [[], [@file], ['--file'], ['--file', @file, @file], ['--file', @file, '--file', @file],
     ['--file', 'relative.command'], ['--help', '--file', @file], ['--check'],
     ['--check', '--file', @file, @file], ['--file', @file, '--check']].each do |arguments|
      out, status = run_readonly(*arguments)
      refute_equal 0, status, "#{arguments.inspect}: #{out}"
      assert_equal 0o644, mode
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
      assert_equal 0o644, mode
      assert_no_logs
    end
  end

  def test_noninteractive_input_cannot_authorize
    out, status = run_readonly('--file', @file, input: "\n")
    refute_equal 0, status, out
    assert_includes out, '可交互终端'
    assert_equal 0o644, mode
    assert_no_logs
  end

  def test_nonempty_confirmation_and_whitespace_cancel_without_writes
    ["取消\n", " \n", "YES\n"].each do |input|
      out, status = run_interactive('--file', @file, input: input)
      assert_equal 0, status, out
      assert_includes out, '已取消授权'
      assert_equal 0o644, mode
      assert_no_logs
    end
  end

  def test_eof_stops_without_authorization_or_logs
    out, status = run_interactive('--file', @file, input: "\x04")
    refute_equal 0, status, out
    assert_includes out, '输入已结束'
    assert_equal 0o644, mode
    assert_no_logs
  end

  def test_confirmation_creates_private_distinct_logs_and_adds_execute_bits
    before = File.binread(@file)
    2.times do
      out, status = run_interactive('--file', @file)
      assert_equal 0, status, out
      assert_includes out, 'chmod +x 成功'
      assert_equal 0o755, mode
      assert_equal before, File.binread(@file)
    end
    directories = Dir.glob(File.join(@logs, 'JobsRunAuthorizer.*'))
    assert_equal 2, directories.size
    directories.each do |directory|
      assert_equal 0o700, mode(directory)
      logfile = File.join(directory, 'run.log')
      assert_equal 0o600, mode(logfile)
      assert_includes File.read(logfile), 'chmod +x 成功'
      refute_includes File.read(logfile), "\e["
    end
  end

  def test_original_chmod_plus_x_umask_semantics_are_preserved
    out, status = run_interactive('--file', @file, mask: '077')
    assert_equal 0, status, out
    assert_equal 0o744, mode
    File.chmod(0o644, @file)
    out, status = run_interactive('--file', @file, mask: '027')
    assert_equal 0, status, out
    assert_equal 0o754, mode
  end

  def test_special_path_is_one_literal_argument_and_target_is_never_executed
    name = "中文 空格 ' 引号\" $ (x) $(touch SUBSTITUTED) `touch BACKTICK`\n下一行.command"
    target = File.join(@root, name)
    File.write(target, "#!/bin/zsh\ntouch EXECUTED\n")
    File.chmod(0o640, target)
    before = File.binread(target)
    out, status = run_interactive('--file', target)
    assert_equal 0, status, out
    assert_equal 0o751, mode(target)
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
    assert_equal 0o755, mode
  end

  def test_target_replaced_while_confirming_is_not_authorized
    original = File.join(@root, '原文件.command')
    out, status = run_interactive('--file', @file) do
      File.rename(@file, original)
      File.write(@file, 'replacement')
      File.chmod(0o644, @file)
    end
    refute_equal 0, status, out
    assert_includes out, '已被替换'
    assert_equal 0o644, mode
    assert_equal 0o644, mode(original)
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
    assert_equal 0o644, mode(original)
    assert_no_logs
  end

  def test_log_creation_failure_stops_before_chmod
    FileUtils.remove_entry(@logs)
    File.write(@logs, 'not a directory')
    out, status = run_interactive('--file', @file)
    refute_equal 0, status, out
    assert_includes out, '临时目录不存在'
    assert_equal 0o644, mode
  end

  def test_real_chmod_failure_is_reported_and_returned
    _, _, flags_status = Open3.capture3('/usr/bin/chflags', 'uchg', @file)
    skip '临时文件系统不支持用户不可变标志' unless flags_status.success?

    out, status = run_interactive('--file', @file)
    refute_equal 0, status, out
    assert_includes out, 'chmod +x 失败'
    assert_equal 0o644, mode
    logfile = Dir.glob(File.join(@logs, 'JobsRunAuthorizer.*', 'run.log')).fetch(0)
    assert_includes File.read(logfile), 'chmod +x 失败'
    refute_includes out, 'chmod +x 成功'
  ensure
    Open3.capture3('/usr/bin/chflags', 'nouchg', @file) if File.exist?(@file)
  end
end
