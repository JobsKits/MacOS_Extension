# frozen_string_literal: true

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
require 'tmpdir'
require 'fileutils'
require 'json'
require 'open3'
require 'timeout'
require 'pty'

require_relative '../../../Tests/SourceLayoutHelper.rb/SourceLayoutHelper'

class FlutterRunnerLogTests < Minitest::Test
  HELPER = ENV.fetch('JOBS_TEST_RUNNER_HELPER') { File.expand_path('../Scripts/FlutterRunner.jxa/FlutterRunner.jxa', File.dirname(__dir__)) }

  def setup
    @tmp = Dir.mktmpdir('jobs-flutter-log-')
    @log = File.join(@tmp, 'run.log')
    @exit = File.join(@tmp, 'exitcode')
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def format(text)
    File.write(@log, text)
    out, err, result = Open3.capture3('/usr/bin/osascript', '-l', 'JavaScript', HELPER, 'format-log', @log)
    assert result.success?, err
    out
  end

  def terminal_format(text, env: {})
    File.write(@log, text)
    captured = String.new
    process_status = nil
    PTY.spawn({ 'TERM' => 'xterm-256color', 'NO_COLOR' => nil, 'PLAIN_OUTPUT' => nil,
                'IS_SOURCETREE_RUNTIME' => nil }.merge(env),
              '/usr/bin/osascript', '-l', 'JavaScript', HELPER, 'format-log', @log) do |reader, input, pid|
      input.close
      begin
        Timeout.timeout(10) { loop { captured << reader.readpartial(8192) } }
      rescue EOFError, Errno::EIO
      end
      _, process_status = Process.wait2(pid)
    end
    captured.force_encoding(Encoding::UTF_8)
    assert process_status.success?, captured
    captured
  end

  def test_log_labels_have_icons_and_preserve_source_urls
    raw = "Flutter 后台运行：fixture\nResolving dependencies...\nwarning: check https://example.com/help?q=1\n"
    out = format(raw)
    assert_includes out, '💬 [会话]'
    assert_includes out, '📦 [依赖]'
    assert_includes out, '⚠️ [警告]'
    assert_includes out, 'https://example.com/help?q=1'
    refute_includes out, "\e"
    assert_equal raw, File.read(@log)
  end

  def test_terminal_errors_are_red_and_urls_restore_the_error_color
    raw = "Error: download https://example.com/a(b)?q=1 failed; see https://second.example/help).\n"
    out = terminal_format(raw)
    assert_includes out, "\e[0;31m❌ [错误] Error: download "
    assert_includes out, "\e[32;4mhttps://example.com/a(b)?q=1\e[0m\e[0;31m failed"
    assert_includes out, "\e[32;4mhttps://second.example/help\e[0m\e[0;31m)."
    assert_equal raw, File.read(@log)
  end

  def test_terminal_plain_modes_keep_urls_and_error_body_without_ansi
    raw = "Error: download https://example.com/a(b)?q=1 failed\n"
    [{ 'NO_COLOR' => '' }, { 'PLAIN_OUTPUT' => '1' }, { 'TERM' => 'dumb' },
     { 'IS_SOURCETREE_RUNTIME' => '1' }].each do |env|
      out = terminal_format(raw, env: env)
      assert_includes out, '❌ [错误] Error: download https://example.com/a(b)?q=1 failed'
      refute_includes out, "\e"
    end
  end

  def test_success_and_warnings_are_distinct_from_machine_noise
    out = format(<<~LOG)
      Resolving dependencies...
      Downloading packages...
        analyzer 10.0.1 (14.6.0 available)
      Got dependencies!
      1 package is discontinued.
      1 package has newer versions incompatible with dependency constraints.
      [{"event":"daemon.connected","params":{"pid":12}}]
      [{"event":"device.removed","params":{"name":"unrelated phone"}}]
      [{"event":"app.start","params":{"deviceId":"sim","mode":"debug"}}]
      [{"event":"app.progress","params":{"appId":"a","id":"1","message":"Running Xcode build...","finished":false}}]
      [{"event":"app.progress","params":{"appId":"a","id":"1","finished":true}}]
      Xcode build done. 12.0s
      [{"event":"app.started","params":{"appId":"a"}}]
      Errored: 0
    LOG
    assert_includes out, '[依赖] 解析依赖'
    assert_includes out, '已折叠 1 条版本明细'
    assert_includes out, '[警告]'
    assert_includes out, '[进行] Xcode 编译'
    assert_includes out, '[进行] 正在确认构建结果'
    assert_includes out, '[成功] 应用已启动'
    refute_includes out, '[错误]'
    refute_includes out, '"event"'
    refute_includes out, 'unrelated phone'
  end

  def test_build_start_does_not_claim_success_and_errors_survive
    out = format(<<~'LOG')
      [{"event":"app.start","params":{"deviceId":"sim"}}]
      [{"event":"app.progress","params":{"appId":"a","id":"1","message":"Running Xcode build...","finished":false}}]
      [{"event":"app.progress","params":{"appId":"a","id":"1","finished":true}}]
      Xcode build done. 12.0s
      [{"event":"app.log","params":{"error":true,"log":"Compiler failed\n  at main.dart:12"}}]
      [{"id":1,"error":{"message":"reload denied"}}]
      [{"event":"new.protocol.event","params":{"detail":"keep me"}}]
      [{"event":"broken json"
      Error (Xcode): missing symbol
      #0 main (main.dart:12)
    LOG
    refute_includes out, '[成功]'
    refute_includes out, '[完成]'
    assert_includes out, '[错误] Compiler failed'
    assert_includes out, '[错误]   at main.dart:12'
    assert_includes out, 'reload denied'
    assert_includes out, 'keep me'
    assert_includes out, 'broken json'
    assert_includes out, 'missing symbol'
    assert_includes out, '#0 main'
  end

  def test_spm_warning_preserves_plugin_names_and_explanation
    out = format(<<~LOG)
      The following plugins do not support Swift Package Manager for ios:
        - plugin_a
        - plugin_b
      This will become an error in a future version of Flutter.
    LOG
    assert_includes out, 'CocoaPods'
    assert_includes out, 'plugin_a'
    assert_includes out, 'plugin_b'
    assert_includes out, '未来 Flutter'
    refute_includes out, '[错误]'
  end

  def test_known_macos_shortcuts_index_diagnostics_are_folded_once
    # 夹具取自现场日志，去掉旧格式化器添加的 [错误] / [日志] 标签。
    raw = <<~LOG
      Failed to index parameter type: <WFMailSenderPickerParameter: 0x10a7efd80> in is.workflow.actions.sendemail: (extension in ActionKit):__C.WFParameter.ToolKitConversionError.missingIntentDescription for locale: en
      Failed to index parameter type: <WFMailSenderPickerParameter: 0x10a7efd80> in is.workflow.actions.sendemail: (extension in ActionKit):__C.WFParameter.ToolKitConversionError.missingIntentDescription for locale: zh_CN
      Failed to index action parameter: <WFConfiguredSystemActionParameter: 0x10b1d4c00> due to (extension in ActionKit):__C.WFParameter.ToolKitConversionError.incompatibleParameterType(WFConfiguredSystemActionParameter)
      Failed to check availability in Spotlight for action is.workflow.actions.sendemail: Error Domain=NSOSStatusErrorDomain Code=-10814 "(null)" UserInfo={NSDebugDescription=Unable to find this application extension record in the Launch Services database.}
      Skipping: <WFUnionParameter: 0x109cc7900> in com.apple.MobileSMS.DraftMessageIntent because union values themselves are not treated as a type
      is.workflow.actions.conditional WFConditionalAction: Skipped because: [control flow]
      is.workflow.actions.sirikit.donation.handle WFHandleDonatedIntentAction: Skipped because: [donation-based action]
      Skipped: [donation-based action: 2, control flow: 4]
         donation-based action: 2
         control flow: 4
      Indexed: 100
      Errored: 0
      Bundle cache: 2 hits
      Finished in 1.2s
    LOG
    out = format(raw)
    assert_equal 1, out.scan('[提示] macOS 快捷指令 / Spotlight 系统索引诊断已折叠').length
    refute_includes out, '[错误]'
    refute_includes out, 'Failed to index'
    refute_includes out, 'NSOSStatusErrorDomain'
    refute_includes out, 'Skipping:'
    refute_includes out, 'Skipped:'
    refute_includes out, 'donation-based action:'
    refute_includes out, 'Indexed:'
    refute_includes out, 'Errored:'
    refute_includes out, 'Bundle cache:'
    refute_includes out, 'Finished in'
    assert_equal raw, File.read(@log), '折叠显示不得改写原始 run.log'
  end

  def test_unknown_and_real_build_errors_survive_system_index_filter
    lines = [
      '[WFCompiler] error: missing symbol in user source',
      'Failed to index parameter type: <WFUserParameter: 0x123> in user.compiler: unexpected conversion failure',
      'Failed to index parameter type: <WFUserParameter: 0x123> in user.compiler: ToolKitConversionError.userFailure',
      'Failed to index parameter type: <UserParameter: 0x123> in user.compiler: ToolKitConversionError.userFailure',
      'Failed to check availability in Spotlight for action is.workflow.actions.sendemail: Error Domain=NSOSStatusErrorDomain Code=-10815',
      'Failed to check availability in Spotlight for action user.action: Error Domain=NSOSStatusErrorDomain Code=-10814',
      'Error (Xcode): missing symbol',
      "lib/main.dart:12: Error: Type 'MissingType' not found.",
      'Errored: 2'
    ]
    out = format(lines.join("\n") + "\n")
    lines.each { |line| assert_includes out, "[错误] #{line}" }
    refute_includes out, '系统索引诊断已折叠'
  end

  def test_machine_app_errors_with_system_index_text_are_never_folded
    lines = [
      'Failed to index action parameter: <WFConfiguredSystemActionParameter: 0x10b1d4c00> due to (extension in ActionKit):__C.WFParameter.ToolKitConversionError.incompatibleParameterType(WFConfiguredSystemActionParameter)',
      'Failed to check availability in Spotlight for action is.workflow.actions.sendemail: Error Domain=NSOSStatusErrorDomain Code=-10814 "(null)"',
      '[WFCompiler] error: failed to compile application'
    ]
    events = lines.map { |line| [{ event: 'app.log', params: { error: true, log: line } }].to_json }
    out = format(events.join("\n") + "\n")
    lines.each { |line| assert_includes out, "[错误] #{line}" }
    refute_includes out, '系统索引诊断已折叠'
  end

  def test_stream_preserves_split_utf8_partial_lines_and_failure_exit
    File.write(@log, '')
    Open3.popen3('/usr/bin/osascript', '-l', 'JavaScript', HELPER, 'watch-log', @log, @exit) do |input, output, errors, process|
      input.close
      captured = String.new
      reader = Thread.new { captured << output.read }
      begin
        # 留出启动时间，再模拟 worker 将 UTF-8 中文字符分两次写入。
        sleep 0.5
        bytes = "错误：中文完整\n最后一行".b
        File.open(@log, 'ab') { |f| f.write(bytes.byteslice(0, 2)) }
        sleep 0.3
        File.open(@log, 'ab') { |f| f.write(bytes.byteslice(2..-1)) }
        sleep 0.3
        File.write(@exit, '7')
        Timeout.timeout(10) { process.value; reader.join }
        assert process.value.success?, errors.read
        assert_includes captured, '错误：中文完整'
        assert_includes captured, '最后一行'
        assert_includes captured, '[错误] Flutter 退出，退出码：7'
        assert_equal 1, captured.scan('最后一行').length
      ensure
        Process.kill('TERM', process.pid) if process.alive?
        reader.join(2)
      end
    end
  end

  def test_sdk_download_carriage_returns_are_visible_before_worker_exit
    File.write(@log, '')
    Open3.popen3('/usr/bin/osascript', '-l', 'JavaScript', HELPER, 'watch-log', @log, @exit) do |input, output, errors, process|
      input.close
      begin
        File.open(@log, 'ab') { |file| file.write("Downloading SDK 25%\r") }
        progress = Timeout.timeout(10) { output.gets }
        assert_includes progress, 'Downloading SDK 25%'
        assert process.alive?, 'SDK下载进度不能等到worker退出才显示'
        File.open(@log, 'ab') { |file| file.write("Downloading SDK 100%\r\n") }
        File.write(@exit, '0')
        remaining = Timeout.timeout(10) { output.read }
        assert_includes remaining, 'Downloading SDK 100%'
        assert_includes remaining, '[结束] Flutter 正常退出'
        assert process.value.success?, errors.read
        assert_equal "Downloading SDK 25%\rDownloading SDK 100%\r\n", File.read(@log)
      ensure
        Process.kill('TERM', process.pid) if process.alive?
      end
    end
  end

  def test_replay_and_machine_logs_keep_all_sdk_progress_frames
    event = [{ event: 'app.log', params: { log: "engine 10%\rengine 100%" } }].to_json
    out = format("Dart 10%\rDart 100%\r\n#{event}\n")
    %w[Dart engine].each do |name|
      assert_includes out, "#{name} 10%"
      assert_includes out, "#{name} 100%"
    end
    assert_equal 1, out.scan('Dart 100%').length
    assert_equal 1, out.scan('engine 100%').length
  end
end
