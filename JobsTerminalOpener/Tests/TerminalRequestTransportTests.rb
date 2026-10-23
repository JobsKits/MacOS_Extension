# frozen_string_literal: true
# 编译真实 Swift 传输层，用注入请求和独立 PTY 验证，不控制真实 Terminal.app。

require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'pty'
require 'rbconfig'
require 'timeout'
require 'tmpdir'

class TerminalRequestTransportTests < Minitest::Test
  def self.fixture_executable
    return @fixture_executable if @fixture_executable

    @fixture_build = Dir.mktmpdir('jobs-terminal-transport-build-')
    @fixture_executable = File.join(@fixture_build, 'transport-fixture')
    project = File.expand_path('..', __dir__)
    output, status = Open3.capture2e(
      '/usr/bin/swiftc', '-module-cache-path', File.join(@fixture_build, 'ModuleCache'),
      File.join(project, 'JobsTerminalShared/DependencyProjectValidator.swift'),
      File.join(project, 'JobsTerminalFinderSync/TerminalOpener.swift'),
      File.join(__dir__, 'TerminalRequestTransportFixture.swift'), '-o', @fixture_executable
    )
    raise "Swift 传输夹具编译失败：#{output}" unless status.success?

    FileUtils.cp(File.join(project, 'Scripts/CleanBuildArtifacts.zsh'), @fixture_build)
    Minitest.after_run { FileUtils.remove_entry(@fixture_build) if File.directory?(@fixture_build) }
    @fixture_executable
  end

  def setup
    @executable = self.class.fixture_executable
    @root = File.realpath(Dir.mktmpdir('jobs-terminal-transport-'))
    @owned_scripts = []
    @project = File.join(@root, "工程 空格 ' \" $(touch SHOULD_NOT_EXIST)\n第二行")
    @bin = File.join(@root, 'bin')
    @trace = File.join(@root, 'tool-trace')
    FileUtils.mkdir_p([File.join(@project, 'Demo.xcodeproj'), File.join(@project, 'lib'), @bin])
    File.write(File.join(@project, 'Podfile'), "platform :ios, '12.0'\n")
    File.write(File.join(@project, 'pubspec.yaml'), "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n")
    @environment = {
      'HOME' => @root, 'TMPDIR' => "#{@root}/", 'PATH' => @bin, 'NO_COLOR' => '1',
      'LANG' => 'zh_CN.UTF-8', 'LC_CTYPE' => 'UTF-8', 'TERM' => 'xterm',
      'PS1' => 'TRANSPORT_PROMPT> ', 'PS2' => 'quote> ',
      'POD_TEST_TRACE' => @trace
    }
    %w[ruby bundle codegraph git touch].each do |name|
      write_tool(name, "printf 'UNEXPECTED_#{name}\\n' >> \"$POD_TEST_TRACE\"\nexit 95")
    end
    write_tool('pod', <<~'SH')
      printf 'MOCK_POD_EXECUTED\n'
      printf 'pod-arguments|%s\n' "$*" >> "$POD_TEST_TRACE"
      printf 'pod-directory|%s\n' "$PWD" >> "$POD_TEST_TRACE"
      exit "${TRANSPORT_POD_EXIT:-0}"
    SH
  end

  def teardown
    @owned_scripts&.uniq&.each do |path|
      File.unlink(path) if File.file?(path) && !File.symlink?(path)
      begin
        Dir.rmdir(File.dirname(path))
      rescue Errno::ENOENT, Errno::ENOTEMPTY
        # 只删除本请求的空目录；其它条目保留给所属实例。
      end
    end
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def test_every_action_produces_one_terminal_line_even_with_quotes_and_newlines_in_target
    %w[open pod-install flutter-pub-get clean-build-artifacts codegraph-bootstrap git-empty-commit-push].each do |action|
      request = fixture('prepare', action: action)
      refute_match(/[\r\n]/, request.fetch('commandLine'), action)
      assert_operator request.fetch('commandLine').bytesize, :<, 2048, action
      refute_includes request.fetch('commandLine'), 'show_script_intro_and_wait'
      refute_includes request.fetch('commandLine'), 'codegraph_ensure_cli'
      refute File.exist?(File.join(@project, 'SHOULD_NOT_EXIST'))
    end
  end

  def test_pod_is_a_direct_install_command_without_a_private_payload_or_workspace
    request = fixture('prepare')
    assert_nil request.fetch('scriptPath')
    assert_nil request.fetch('runtimeDirectory')
    assert_match(/\Acd -- .+ && pod install\z/, request.fetch('commandLine'))
    refute Dir.glob(File.join(@root, 'JobsTerminalOpener-*', 'action.zsh')).any?
    refute File.exist?(File.join(@project, 'Demo.xcworkspace'))
    result = fixture('dispatch-success')
    refute result.fetch('didThrow')
    assert_empty result.fetch('scriptsDuringDispatch')
    assert_empty result.fetch('scriptsAfterDispatch')
    assert_equal request.fetch('commandLine'), result.fetch('commandLine')
  end

  def test_build_clean_payload_identifies_target_and_cleans_its_own_carrier
    FileUtils.mkdir_p(File.join(@project, 'build'))
    File.write(File.join(@project, 'build/artifact'), 'generated')
    request = fixture('prepare', action: 'clean-build-artifacts')
    output, status = Open3.capture2e(@environment, '/bin/zsh', request.fetch('scriptPath'), stdin_data: "CLEAN\n")
    assert status.success?, output
    assert_includes output, '工程类型：Flutter'
    refute File.exist?(File.join(@project, 'build'))
    assert File.file?(File.join(@project, 'pubspec.yaml'))
    refute File.exist?(request.fetch('scriptPath'))
    refute File.exist?(request.fetch('runtimeDirectory'))
    refute File.exist?(File.join(@project, 'SHOULD_NOT_EXIST'))
  end

  def test_complex_actions_keep_private_unique_payloads_and_target_out_of_terminal_input
    %w[clean-build-artifacts codegraph-bootstrap git-empty-commit-push].each do |action|
      first = fixture('prepare', action: action)
      second = fixture('prepare', action: action)
      refute_equal first.fetch('runtimeDirectory'), second.fetch('runtimeDirectory')
      [first, second].each do |request|
        assert_equal 0o700, File.stat(request.fetch('runtimeDirectory')).mode & 0o777
        assert_equal 0o600, File.stat(request.fetch('scriptPath')).mode & 0o777
        refute File.symlink?(request.fetch('runtimeDirectory'))
        refute File.symlink?(request.fetch('scriptPath'))
        assert_includes request.fetch('commandLine'), '/bin/zsh '
        refute_includes request.fetch('commandLine'), @project
        assert_includes File.read(request.fetch('scriptPath')), 'jobs_terminal_cleanup_runtime'
      end
    end
  end

  def test_applescript_keeps_complex_payload_after_dispatch_success
    result = fixture('dispatch-success', action: 'codegraph-bootstrap')
    refute result.fetch('didThrow')
    refute_match(/[\r\n]/, result.fetch('commandLine'))
    assert_includes result.fetch('appleScript'), 'do script '
    assert_includes result.fetch('appleScript'), 'item 1 of argv'
    refute_match(/item\s+[2-9]\s+of argv/, result.fetch('appleScript'))
    refute_includes result.fetch('appleScript'), 'codeGraphDependencyCommand'
    refute_includes result.fetch('appleScript'), 'set targetPath'
    assert_equal 1, result.fetch('scriptsDuringDispatch').length
    assert_equal result.fetch('scriptsDuringDispatch'), result.fetch('scriptsAfterDispatch')
    result.fetch('scriptsAfterDispatch').each { |path| assert File.file?(path) }
  end

  def test_failed_applescript_request_cleans_its_complex_payload_immediately
    result = fixture('dispatch-failure', action: 'codegraph-bootstrap')
    assert result.fetch('didThrow')
    assert_equal 1, result.fetch('scriptsDuringDispatch').length
    assert_empty result.fetch('scriptsAfterDispatch')
    result.fetch('scriptsDuringDispatch').each do |path|
      refute File.exist?(path)
      refute File.exist?(File.dirname(path))
    end
  end

  def test_complex_request_cleanup_is_idempotent_and_cannot_delete_another_request
    result = fixture('concurrency', action: 'codegraph-bootstrap')
    assert result.fetch('differentDirectories')
    assert result.fetch('firstRemoved')
    assert result.fetch('secondSurvivesFirstCleanup')
    assert result.fetch('secondRemoved')
  end

  def test_missing_podfile_or_xcodeproj_dispatches_no_terminal_request
    %w[Podfile Demo.xcodeproj].each do |name|
      path = File.join(@project, name)
      File.directory?(path) ? FileUtils.remove_entry(path) : File.delete(path)
      result = fixture('invalid-pod')
      assert result.fetch('didThrow'), name
      assert_equal 0, result.fetch('dispatchCount'), name
      assert_empty result.fetch('preparedScripts')
      if name == 'Podfile'
        File.write(path, "platform :ios, '12.0'\n")
      else
        FileUtils.mkdir_p(path)
      end
    end
  end

  def test_pod_command_runs_install_once_in_the_literal_directory_without_confirmation
    File.write(File.join(@project, 'Gemfile'), "raise 'must not be loaded'\n")
    request = fixture('prepare')
    output, shell_status = execute_in_pty(request)
    assert_equal 0, shell_status, output
    assert_includes output, 'MOCK_POD_EXECUTED'
    assert_equal ["pod-arguments|install\n"], File.read(@trace).lines.grep(/^pod-arguments\|/)
    assert_includes File.read(@trace), "pod-directory|#{@project}"
    refute_includes File.read(@trace), 'UNEXPECTED_'
    refute_includes output, 'quote>'
    refute_includes output, 'show_script_intro_and_wait'
    refute File.exist?(File.join(@project, 'SHOULD_NOT_EXIST'))
    refute Dir.glob(File.join(@root, 'JobsTerminalOpener-Pod.*')).any?
    refute File.exist?(File.join(@project, 'Gemfile.lock'))
  end

  def test_direct_pod_command_preserves_its_exit_status
    @environment['TRANSPORT_POD_EXIT'] = '37'
    output, shell_status = execute_in_pty(fixture('prepare'))
    assert_equal 37, shell_status, output
    assert_equal ["pod-arguments|install\n"], File.read(@trace).lines.grep(/^pod-arguments\|/)
  end

  def test_failed_cd_never_executes_pod
    request = fixture('prepare')
    FileUtils.remove_entry(@project)
    output, shell_status = execute_in_pty(request)
    refute_equal 0, shell_status, output
    refute File.exist?(@trace)
  end

  def test_native_ruby_pod_prompt_is_visible_before_input_and_keeps_all_three_ttys
    write_interactive_ruby_pod
    @environment['TRANSPORT_POD_EXIT'] = '47'
    prompt_visible = false
    output, shell_status = execute_in_pty(fixture('prepare')) do |reader, writer, captured|
      prompt_visible = read_until(reader, captured, 'RUBY_POD_ANSWER> ')
      writer.write(prompt_visible ? "answer after prompt\n" : "\u0003")
    end
    assert prompt_visible, "Ruby 提示没有在等待输入前显示：#{output}"
    assert_equal 47, shell_status, output
    assert_includes File.read(@trace), 'ruby-pod-tty|true,true,true'
    assert_includes File.read(@trace), 'ruby-pod-arguments|install'
    assert_includes File.read(@trace), "ruby-pod-directory|#{@project}"
    assert_includes File.read(@trace), 'ruby-pod-answer|"answer after prompt\\n"'
    assert_ruby_pod_has_exited
  end

  def test_real_control_c_during_native_pod_input_leaves_no_pod_process
    write_interactive_ruby_pod
    prompt_visible = false
    output, shell_status = execute_in_pty(fixture('prepare')) do |reader, writer, captured|
      prompt_visible = read_until(reader, captured, 'RUBY_POD_ANSWER> ')
      writer.write("\u0003")
    end
    assert prompt_visible, "没有进入 Pod 的真实输入等待：#{output}"
    assert_includes File.read(@trace), 'ruby-pod-tty|true,true,true'
    refute_includes File.read(@trace), 'ruby-pod-answer|'
    assert_ruby_pod_has_exited
    assert_equal 130, shell_status, output
  end

  def test_complex_payload_eof_cleans_request_without_running_tools
    request = fixture('prepare', action: 'codegraph-bootstrap')
    output, shell_status = execute_in_pty(request, waiting_for: '已了解用途与影响，按回车继续', input: "\u0004")
    assert_equal 1, shell_status, output
    refute File.exist?(request.fetch('scriptPath'))
    refute File.exist?(request.fetch('runtimeDirectory'))
    refute File.exist?(@trace)
  end

  def test_interrupt_cleans_only_its_complex_payload
    first = fixture('prepare', action: 'codegraph-bootstrap')
    second = fixture('prepare', action: 'codegraph-bootstrap')
    output, shell_status = execute_in_pty(first, waiting_for: '已了解用途与影响，按回车继续', signal: 'INT')
    assert_equal 130, shell_status, output
    refute File.exist?(first.fetch('scriptPath'))
    refute File.exist?(first.fetch('runtimeDirectory'))
    assert File.file?(second.fetch('scriptPath'))
    assert File.directory?(second.fetch('runtimeDirectory'))
    refute File.exist?(@trace)
  end

  def test_hangup_cleans_complex_payload_without_running_tools
    request = fixture('prepare', action: 'codegraph-bootstrap')
    output, shell_status = execute_in_pty(request, waiting_for: '已了解用途与影响，按回车继续', signal: 'HUP')
    assert_equal 129, shell_status, output
    refute File.exist?(request.fetch('scriptPath'))
    refute File.exist?(request.fetch('runtimeDirectory'))
    refute File.exist?(@trace)
  end

  def test_termination_keeps_its_signal_status_and_cleans_complex_payload
    request = fixture('prepare', action: 'codegraph-bootstrap')
    output, shell_status = execute_in_pty(request, waiting_for: '已了解用途与影响，按回车继续', signal: 'TERM')
    assert_equal 143, shell_status, output
    refute File.exist?(request.fetch('scriptPath'))
    refute File.exist?(request.fetch('runtimeDirectory'))
    refute File.exist?(@trace)
  end

  private

  def fixture(mode, action: 'pod-install')
    output, status = Open3.capture2e(@environment, @executable, mode, @project, action, unsetenv_others: true)
    assert status.success?, output
    result = JSON.parse(output)
    @owned_scripts << result['scriptPath'] if result['scriptPath']
    @owned_scripts.concat(result.fetch('scriptsDuringDispatch', []))
    @owned_scripts.concat(result.fetch('scriptsAfterDispatch', []))
    result
  end

  def write_tool(name, body)
    path = File.join(@bin, name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o700, path)
  end

  def write_interactive_ruby_pod
    File.write(File.join(@bin, 'pod'), "#!#{RbConfig.ruby} --disable-gems\n" + <<~'RUBY_POD')
      File.open(ENV.fetch('POD_TEST_TRACE'), 'a') do |file|
        file.puts "ruby-pod-pid|#{Process.pid}"
        file.puts "ruby-pod-tty|#{[STDIN, STDOUT, STDERR].map(&:tty?).join(',')}"
        file.puts "ruby-pod-arguments|#{ARGV.join(' ')}"
        file.puts "ruby-pod-directory|#{Dir.pwd}"
      end
      print 'RUBY_POD_ANSWER> '
      answer = STDIN.gets
      File.open(ENV.fetch('POD_TEST_TRACE'), 'a') { |file| file.puts "ruby-pod-answer|#{answer.inspect}" }
      puts "RUBY_POD_RECEIVED=#{answer.inspect}"
      exit Integer(ENV.fetch('TRANSPORT_POD_EXIT', '0'))
    RUBY_POD
  end

  def assert_ruby_pod_has_exited
    pid = File.read(@trace)[/ruby-pod-pid\|(\d+)/, 1]
    assert pid, '没有记录实际 Ruby Pod 进程'
    assert_raises(Errno::ESRCH) { Process.kill(0, Integer(pid)) }
  end

  def read_until(reader, output, marker, after: 0)
    Timeout.timeout(3) do
      output << reader.readpartial(4096) until output.index(marker.b, after)
    end
    true
  rescue Timeout::Error, EOFError, Errno::EIO
    false
  end

  def execute_in_pty(request, waiting_for: nil, input: nil, signal: nil)
    output = +''.b
    Timeout.timeout(12) do
      PTY.spawn(@environment, '/bin/zsh', '-f', '-i', unsetenv_others: true) do |reader, writer, process_id|
        assert read_until(reader, output, 'TRANSPORT_PROMPT>'), '隔离 Shell 没有显示提示符'
        prompt_offset = output.bytesize
        writer.write("#{request.fetch('commandLine')}\n")
        if waiting_for
          assert read_until(reader, output, waiting_for), '复杂载体没有进入确认阶段'
          if signal
            signal_payload(process_id, request, signal)
          else
            writer.write(input)
          end
        end
        yield reader, writer, output if block_given?
        assert read_until(reader, output, 'TRANSPORT_PROMPT>', after: prompt_offset),
               "命令未返回交互 Shell：#{output.dup.force_encoding(Encoding::UTF_8)}"
        writer.write("print -r -- \"__TRANSPORT_STATUS__=$?\"\nexit\n")
        begin
          loop { output << reader.readpartial(4096) }
        rescue EOFError, Errno::EIO
          Process.wait(process_id)
        end
      end
    end
    output.force_encoding(Encoding::UTF_8)
    match = output.match(/__TRANSPORT_STATUS__=(\d+)/)
    assert match, "没有取得命令退出状态：#{output}"
    [output.gsub("\r\n", "\n"), match[1].to_i]
  end

  def signal_payload(shell_pid, request, signal)
    children, children_status = Open3.capture2('/usr/bin/pgrep', '-P', shell_pid.to_s)
    assert children_status.success?, '没有找到测试 Shell 的载体子进程'
    child = children.lines.map(&:to_i).find do |pid|
      command, = Open3.capture2('/bin/ps', '-p', pid.to_s, '-o', 'command=')
      command.include?("#{File.basename(request.fetch('runtimeDirectory'))}/action.zsh")
    end
    assert child, '拒绝向不属于本次载体的进程发送信号'
    Process.kill(signal, child)
  end
end
