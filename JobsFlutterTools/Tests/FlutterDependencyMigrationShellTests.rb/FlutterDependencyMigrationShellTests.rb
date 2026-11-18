# Created by Jobs on 2026年11月4日，星期三。
# 隔离覆盖迁移范围、拖入路径、ZIP保留/删除、预检失败与写入确认，不读取真实缓存。
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
require 'json'
require 'minitest/autorun'
require 'open3'
require 'shellwords'
require 'tmpdir'
require 'timeout'
require 'uri'
require 'pty'
require 'io/console'

require_relative '../../../Tests/SourceLayoutHelper.rb/SourceLayoutHelper'

class FlutterDependencyMigrationShellTests < Minitest::Test
  TOOLS = ENV.fetch('JOBS_TEST_TOOLS_DIR') { File.expand_path('../../Scripts/Tools', __dir__) }
  SCRIPT = JobsSourceLayout.file(File.join(TOOLS, '【MacOS】一键迁移Flutter依赖.zsh/【MacOS】一键迁移Flutter依赖.zsh'))

  def setup
    @base = File.realpath(Dir.mktmpdir('jobs-migration-shell-'))
    @bundle = File.join(@base, '迁移 包 $(touch NEVER)')
    FileUtils.mkdir_p(@bundle)
    File.write(File.join(@bundle, 'migration.json'), '{"status":"complete"}')
    File.write(File.join(@bundle, '.hidden'), 'hidden data')
  end

  def teardown
    FileUtils.remove_entry(@base)
  end

  def run_functions(body, *arguments, input: '', env: {})
    fixture = File.join(@base, 'fixture.zsh')
    File.write(fixture, <<~ZSH + body)
      source #{Shellwords.escape(SCRIPT)}
      setopt NO_NOMATCH PIPE_FAIL
      FM_LOG=/dev/null
    ZSH
    Open3.capture2e({ 'NO_COLOR' => '1' }.merge(env), '/bin/zsh', '-f', fixture, *arguments, stdin_data: input)
  end

  def test_scope_empty_private_nonempty_all_and_eof_cancels
    [["\n", '1'], [" \n", '0'], ["全部\n", '0']].each do |input, value|
      output, status = run_functions('fm_choose_scope; print -r -- "PRIVATE=$FM_PRIVATE"', input: input)
      assert status.success?, output
      assert_includes output, "PRIVATE=#{value}"
      assert_includes output, '私库'
    end
    output, status = run_functions('fm_choose_scope', input: '')
    assert_equal 130, status.exitstatus, output
  end

  def test_wait_feedback_preserves_failure_output_and_machine_receipt
    receipt = File.join(@base, 'timer-receipt')
    log = File.join(@base, 'timer-log')
    output, status = run_functions('FM_LOG="$1"; fm_run_timed "扫描测试" "$2" /bin/zsh -f -c \'print JOBS_MIGRATION_PLAN=fixture; print -u2 failure-detail; exit 23\'', log, receipt)
    assert_equal 23, status.exitstatus, output
    assert_includes output, '扫描测试｜已耗时 00:00:00'
    assert_includes output, '扫描测试 失败（退出码 23）｜总用时'
    assert_equal "JOBS_MIGRATION_PLAN=fixture\nfailure-detail\n", File.read(receipt)
    assert_includes File.read(log), 'failure-detail'
    refute_match(/\e\[|\r/, output + File.read(log))
    formatted, result = run_functions('fm_duration 90061')
    assert result.success?, formatted
    assert_equal '25:01:01', formatted
  end

  def test_silent_wait_refreshes_in_a_real_terminal_and_stops_before_input
    log = File.join(@base, 'tty-timer-log')
    code = "source #{Shellwords.escape(SCRIPT)}; setopt PIPE_FAIL; FM_LOG=#{Shellwords.escape(log)}; fm_run_timed '扫描测试' '' /bin/sleep 2.2; print TIMER_STOPPED; sleep 1.2; print PROMPT_READY"
    output = +''
    child_status = nil
    PTY.spawn({ 'TERM' => 'xterm-256color', 'NO_COLOR' => nil, 'PLAIN_OUTPUT' => nil }, '/bin/zsh', '-f', '-c', code) do |reader, _writer, pid|
      Timeout.timeout(10) do
        begin
          loop { output << reader.readpartial(4096) }
        rescue EOFError, Errno::EIO
        end
        _, child_status = Process.wait2(pid)
      end
    end
    output.force_encoding('UTF-8')
    assert child_status.success?, output
    assert_includes output, '已耗时 00:00:01'
    assert_includes output, '已耗时 00:00:02'
    assert_match(/扫描测试 完成｜总用时 00:00:0[23]/, output)
    refute_includes output.split('TIMER_STOPPED', 2).last, '已耗时'
    refute_match(/\e\[|\r/, File.read(log))
  end

  def test_wait_feedback_term_and_hup_stop_only_the_owned_child_tree
    { 'TERM' => 143, 'HUP' => 129, 'INT' => 130 }.each do |signal, expected|
      worker = File.join(@base, "timer-worker-#{signal}")
      fixture = File.join(@base, "timer-#{signal}.zsh")
      File.write(fixture, <<~ZSH)
        source #{Shellwords.escape(SCRIPT)}
        setopt PIPE_FAIL
        FM_LOG=/dev/null
        fm_run_timed '取消测试' '' /bin/zsh -f -c 'print -r -- $$ > "$1"; /bin/sleep 30' -- #{Shellwords.escape(worker)}
        result=$?
        print -r -- "STOPPED=$result"
        exit "$result"
      ZSH
      Open3.popen2e({ 'NO_COLOR' => '1' }, '/bin/zsh', '-f', fixture) do |stdin, stdout, waiter|
        stdin.close
        output = +''
        Timeout.timeout(8) do
          sleep 0.02 until File.file?(worker)
          Process.kill(signal, waiter.pid)
          output = stdout.read
          assert_equal expected, waiter.value.exitstatus, output
        end
        assert_includes output, "STOPPED=#{expected}"
        assert_includes output, '取消测试 已中断｜总用时'
        child_pid = Integer(File.read(worker).strip)
        assert_raises(Errno::ESRCH) { Process.kill(0, child_pid) }
      end
    end
  end

  def test_wait_feedback_plain_heartbeat_and_standard_input
    log = File.join(@base, 'plain-timer-log')
    output, status = run_functions('FM_LOG="$1"; fm_run_timed "静默测试" "" /bin/zsh -f -c \'IFS= read -r value; print -r -- "INPUT=$value"; sleep 10.2\'', log, input: "literal $(never run)\n")
    assert status.success?, output
    assert_includes output, 'INPUT=literal $(never run)'
    assert_includes output, '静默测试｜已耗时 00:00:10'
    assert_includes output, '静默测试 完成｜总用时'
    assert_includes File.read(log), '静默测试｜已耗时 00:00:10'
    refute_match(/\e\[|\r/, output + File.read(log))
  end

  def test_dragged_renamed_cache_path_is_data
    source = File.join(@base, '改名 缓存 ; $(touch NEVER)')
    Dir.mkdir(source)
    [source, Shellwords.escape(source), "'#{source}'\u00a0"].each do |raw|
      output, status = run_functions('fm_normalize "$1"; print -r -- "$REPLY"', raw)
      assert status.success?, output
      assert_equal source, output.strip
    end
    refute File.exist?(File.join(@base, 'NEVER'))
  end

  def test_import_empty_input_retries_and_eof_stops
    output, status = run_functions('FM_MODE=import; fm_read_directory; print -r -- "$FM_DIRECTORY"', input: "\n#{Shellwords.escape(@bundle)}\n")
    assert status.success?, output
    assert_includes output, '尚未输入依赖目录'
    assert_includes output, File.realpath(@bundle)
    output, status = run_functions('FM_MODE=import; fm_read_directory', input: '')
    assert_equal 130, status.exitstatus, output
  end

  def zip(input)
    run_functions('FM_DIRECTORY="$1"; FM_OUTPUT="$2"; fm_zip_offer', @base, @bundle, input: input)
  end

  def test_zip_default_keeps_directory_and_includes_hidden_files
    output, status = zip("\n\n")
    assert status.success?, output
    assert Dir.exist?(@bundle)
    assert File.file?(@bundle + '.zip')
    listing, result = Open3.capture2e('/usr/bin/unzip', '-Z1', @bundle + '.zip')
    assert result.success?, listing
    assert_includes listing, '/.hidden'
    assert_includes output, 'ZIP 已完成并校验'
  end

  def test_zip_nonempty_delete_removes_only_new_bundle
    unrelated = File.join(@base, '保留我')
    File.write(unrelated, 'existing')
    output, status = zip("\n \n")
    assert status.success?, output
    refute File.exist?(@bundle)
    assert File.file?(@bundle + '.zip')
    assert_equal 'existing', File.read(unrelated)
  end

  def test_no_zip_and_zip_conflict_both_preserve_original
    output, status = zip(" \n")
    assert status.success?, output
    assert Dir.exist?(@bundle)
    refute File.exist?(@bundle + '.zip')
    File.write(@bundle + '.zip', 'preexisting')
    output, status = zip("\n")
    refute status.success?, output
    assert_equal 'preexisting', File.read(@bundle + '.zip')
    assert Dir.exist?(@bundle)
  end

  def fake_dart(preview_status: 0)
    fake = File.join(@base, 'fake-dart')
    File.write(fake, <<~ZSH)
      #!/bin/zsh
      print -r -- "$*" >> "$TEST_CALLS"
      print -r -- 'preview plan'
      print -r -- 'JOBS_MIGRATION_CONFLICTS=0'
      print -r -- 'JOBS_MIGRATION_PLAN=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      if [[ " $* " != *' --apply '* ]]; then exit #{preview_status}; fi
    ZSH
    File.chmod(0o755, fake)
    fake
  end

  def test_import_preflight_failure_cannot_apply_even_with_yes
    fake = fake_dart(preview_status: 23)
    trace = File.join(@base, 'calls')
    output, status = run_functions('FM_DART="$1"; FM_DIRECTORY="$2"; fm_import', fake, @bundle, input: "YES\n", env: { 'TEST_CALLS' => trace })
    assert_equal 23, status.exitstatus, output
    assert_equal 1, File.readlines(trace).length
    refute_includes File.read(trace), '--apply'
  end

  def test_import_requires_exact_yes
    fake = fake_dart
    ["yes\n", " YES\n", " \n", "YES\n"].each_with_index do |input, index|
      trace = File.join(@base, "calls#{index}")
      output, status = run_functions('FM_DART="$1"; FM_DIRECTORY="$2"; fm_import', fake, @bundle, input: input, env: { 'TEST_CALLS' => trace })
      assert status.success?, output
      assert_equal(input == "YES\n" ? 2 : 1, File.readlines(trace).length)
      assert_includes File.read(trace), '--expected-plan ' + 'a' * 64 if input == "YES\n"
    end
  end

  def test_empty_final_confirmation_repeats_without_repreview_or_apply_until_yes
    trace = File.join(@base, 'empty-confirm-calls')
    output, status = run_functions('FM_DART="$1"; FM_DIRECTORY="$2"; fm_import', fake_dart, @bundle,
      input: "\n\n\nYES\n", env: { 'TEST_CALLS' => trace })
    assert status.success?, output
    assert_equal 3, output.scan('尚未输入确认内容').length
    assert_equal 2, File.readlines(trace).length
    assert_equal 1, File.readlines(trace).count { |line| line.include?('--apply') }
    refute_includes output, '已取消'
  end

  def test_empty_final_confirmation_can_then_cancel_or_end_input_without_writing
    [["\nNO\n", 0], ["\n", 130], ['', 130]].each_with_index do |(input, expected), index|
      trace = File.join(@base, "empty-cancel-calls-#{index}")
      output, status = run_functions('FM_DART="$1"; FM_DIRECTORY="$2"; fm_import', fake_dart, @bundle,
        input: input, env: { 'TEST_CALLS' => trace })
      assert_equal expected, status.exitstatus, output
      assert_equal 1, File.readlines(trace).length
      refute_includes File.read(trace), '--apply'
    end
  end

  def conflict_dart
    fake = File.join(@base, 'conflict-dart')
    File.write(fake, <<~'ZSH')
      #!/bin/zsh
      print -r -- "$*" >> "$TEST_CALLS"
      print -r -- '冲突：pub-cache/git/pkg/.git/index'
      print -r -- 'JOBS_MIGRATION_CONFLICTS=3'
      if [[ " $* " == *' --conflict-policy '* ]]; then
        print -r -- 'JOBS_MIGRATION_PLAN=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
      else
        print -r -- 'JOBS_MIGRATION_PLAN=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      fi
    ZSH
    File.chmod(0o755, fake)
    fake
  end

  def conflict_import(input)
    trace = File.join(@base, 'conflict-calls')
    output, status = run_functions('FM_DART="$1"; FM_DIRECTORY="$2"; fm_import', conflict_dart, @bundle,
      input: input, env: { 'TEST_CALLS' => trace, 'JOBS_FLUTTER_MIGRATION_FZF' => '0' })
    [output, status, File.readlines(trace, chomp: true)]
  end

  def test_source_conflict_default_backup_accepts_literal_dragged_parent
    parent = File.join(@base, "备份 ' $(touch NEVER)")
    Dir.mkdir(parent)
    output, status, calls = conflict_import("\n\n#{Shellwords.escape(parent)}\nYES\n")
    assert status.success?, output
    assert_equal 3, calls.length
    assert_includes calls.last, '--conflict-policy source'
    assert_includes calls.last, "--backup-directory #{parent}"
    assert_includes calls.last, '--expected-plan ' + 'b' * 64
    refute_includes calls.last, '--no-backup'
    refute File.exist?(File.join(@base, 'NEVER'))
  end

  def test_source_conflict_default_backup_parent_is_system_desktop
    output, status, calls = conflict_import("\n\n\nYES\n")
    assert status.success?, output
    desktop, desktop_status = Open3.capture2e('/usr/bin/osascript', '-e', 'POSIX path of (path to desktop folder)')
    desktop = JobsSourceLayout.file(File.join(Dir.home, 'Desktop')) unless desktop_status.success? && !desktop.strip.empty?
    assert_includes calls.last, "--backup-directory #{desktop.strip}"
    assert_includes calls.last, '--apply'
  end

  def test_source_conflict_nonempty_including_space_disables_persistent_backup
    ["x", " "].each do |answer|
      output, status, calls = conflict_import("1\n#{answer}\nYES\n")
      assert status.success?, output
      assert_includes calls.last, '--conflict-policy source --no-backup'
      refute_includes calls.last, '--backup-directory'
      assert_includes calls.last, '--apply'
    end
  end

  def render_backup_prompt_pty(env = {})
    log = File.join(@base, 'prompt.log')
    File.write(log, '')
    output = +''.b
    child_status = nil
    code = "source #{SCRIPT.shellescape}\nFM_LOG=#{log.shellescape}\nfm_show_backup_prompt\n"
    PTY.spawn({ 'TERM' => 'xterm-256color', 'NO_COLOR' => nil, 'PLAIN_OUTPUT' => nil, 'IS_SOURCETREE_RUNTIME' => nil }.merge(env), '/bin/zsh', '-f', '-c', code) do |reader, _writer, pid|
      Timeout.timeout(10) do
        begin
          loop { output << reader.readpartial(4096).b }
        rescue EOFError, Errno::EIO
        end
        _, child_status = Process.wait2(pid)
      end
    end
    [output.force_encoding('UTF-8'), File.read(log), child_status]
  end

  def test_backup_prompt_colors_only_choices_and_keeps_log_plain
    output, log, status = render_backup_prompt_pty
    assert status.success?, output
    assert_includes output, "是否备份将被覆盖的当前文件？ \e[1;32m回车 = 备份\e[0m"
    assert_includes output, "\e[1;31m任意字符再回车 = 不备份直接覆盖：\e[0m"
    assert output.end_with?("\e[0m"), '读取输入前应恢复终端默认颜色'
    assert_equal "是否备份将被覆盖的当前文件？ 回车 = 备份；任意字符再回车 = 不备份直接覆盖：\n", log
    refute_includes log, "\e"
  end

  def test_backup_prompt_plain_modes_and_redirected_output_have_no_ansi
    [{ 'NO_COLOR' => '1' }, { 'TERM' => 'dumb' }, { 'PLAIN_OUTPUT' => '1' }, { 'IS_SOURCETREE_RUNTIME' => '1' }].each do |env|
      output, log, status = render_backup_prompt_pty(env)
      assert status.success?, output
      refute_includes output, "\e"
      refute_includes log, "\e"
      assert_includes output, '回车 = 备份；任意字符再回车 = 不备份直接覆盖：'
    end
    output, status = run_functions('fm_show_backup_prompt', env: { 'NO_COLOR' => nil, 'TERM' => 'xterm-256color' })
    assert status.success?, output
    refute_includes output, "\e"
  end

  def test_existing_conflict_skips_backup_prompt_and_retains_final_yes
    output, status, calls = conflict_import("2\nYES\n")
    assert status.success?, output
    assert_equal 3, calls.length
    assert_includes calls.last, '--conflict-policy existing'
    assert_includes calls.last, '--apply'
    refute_includes calls.last, '--backup-directory'
    refute_includes calls.last, '--no-backup'
    refute_includes output, '备份父目录：'
  end

  def test_conflict_selection_backup_or_final_confirmation_cancellation_never_applies
    ["q\n", '', "1\n", "1\n\n", "1\nx\nNO\n", "2\nNO\n"].each do |input|
      output, status, calls = conflict_import(input)
      assert [0, 130].include?(status.exitstatus), output
      refute calls.any? { |call| call.include?('--apply') }, output
    end
  end

  def test_fzf_uses_hidden_policy_and_escape_is_cancellation
    fake = File.join(@base, 'fake-fzf')
    File.write(fake, "#!/bin/zsh\ncat > \"$TEST_FZF_ROWS\"\n[[ \"$TEST_FZF_CANCEL\" != 1 ]] || exit 130\nprint -r -- $'existing\\t保留本机'\n")
    File.chmod(0o755, fake)
    rows = File.join(@base, 'fzf-rows')
    ['0', '1'].each do |cancel|
      output, status = run_functions('FM_FZF_BIN="$1"; fm_choose_conflict_policy || exit $?; print -r -- "PICK=$FM_CONFLICT_POLICY"', fake,
        env: { 'JOBS_FLUTTER_MIGRATION_FZF' => 'always', 'TEST_FZF_ROWS' => rows, 'TEST_FZF_CANCEL' => cancel })
      if cancel == '1'
        assert_equal 130, status.exitstatus, output
        refute_includes output, 'PICK='
      else
        assert status.success?, output
        assert_includes output, 'PICK=existing'
      end
      assert File.read(rows).start_with?("source\t")
    end
  end

  def test_real_fzf_default_direction_and_escape_in_pty
    fzf = %w[/opt/homebrew/bin/fzf /usr/local/bin/fzf].find { |p| File.executable?(p) }
    skip '需要已有 fzf；本测试不会安装' unless fzf
    fixture = File.join(@base, 'fzf-pty.zsh')
    File.write(fixture, <<~ZSH)
      source #{SCRIPT.shellescape}
      FM_LOG=/dev/null
      FM_FZF_BIN=#{fzf.shellescape}
      fm_choose_conflict_policy
      result=$?
      print -r -- "PICK=$FM_CONFLICT_POLICY"
      exit $result
    ZSH
    [["\r", 'source'], ["\e[B\r", 'existing'], ["\e", '']].each do |keys, expected|
      output = +''.b
      child_status = nil
      PTY.spawn({ 'TERM' => 'xterm-256color', 'NO_COLOR' => '1' }, '/bin/zsh', '-f', fixture) do |reader, writer, pid|
        reader.winsize = [24, 100]
        Timeout.timeout(10) do
          until output.include?('2/2'.b) && output.include?('使用导入源'.b)
            output << reader.readpartial(4096).b
          end
          writer.write(keys)
          writer.flush
          begin
            loop { output << reader.readpartial(4096).b }
          rescue EOFError, Errno::EIO
          end
          _, child_status = Process.wait2(pid)
        end
      end
      assert_equal(expected.empty? ? 130 : 0, child_status.exitstatus, output.force_encoding('UTF-8'))
      assert_includes output, "PICK=#{expected}"
    end
  end

  def test_export_engine_failure_propagates_without_zip
    fake = fake_dart(preview_status: 29)
    trace = File.join(@base, 'calls')
    output, status = run_functions('FM_DART="$1"; FM_DIRECTORY="$2"; fm_export', fake, @base, input: "\n \n", env: { 'TEST_CALLS' => trace })
    assert_equal 29, status.exitstatus, output
    refute File.exist?(@bundle + '.zip')
    assert Dir.exist?(@bundle)
  end
  def real_dart
    candidate = ENV['JOBS_TEST_DART'] || ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).map { |entry| File.join(entry, 'dart') }.find { |path| File.file?(path) && File.executable?(path) }
    skip '需要已有原生 Dart；本测试不会安装 SDK' unless candidate && File.executable?(candidate)
    resolved = File.realpath(candidate)
    sdk_binary = JobsSourceLayout.file(File.join(File.dirname(resolved), 'cache/dart-sdk/bin/dart'))
    File.file?(sdk_binary) ? File.realpath(sdk_binary) : resolved
  end

  def prepare_real_pipeline
    dart = real_dart
    copied = File.join(@base, '打包资源/Tools')
    FileUtils.mkdir_p(File.dirname(copied))
    FileUtils.cp_r(TOOLS, copied)
    @project = File.join(@base, '原工程 不应写入')
    @target = File.join(@base, '目标 无 lib')
    manifest = "name: fixture\nenvironment:\n  sdk: '>=3.0.0 <4.0.0'\ndependencies:\n  flutter:\n    sdk: flutter\n  private_pkg:\n    git: https://private.invalid/pkg.git\n  public_pkg: ^1.0.0\n"
    [@project, @target].each do |project|
      FileUtils.mkdir_p(project)
      File.write(File.join(project, 'pubspec.yaml'), manifest)
      path = File.join(project, '.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart')
      FileUtils.mkdir_p(File.dirname(path))
      File.symlink(dart, path)
    end
    FileUtils.mkdir_p(File.join(@project, '.dart_tool'))
    lock = "packages:\n"
    packages = [{ 'name' => 'fixture', 'rootUri' => URI::DEFAULT_PARSER.escape("file://#{@project}/") }]
    %w[private_pkg public_pkg flutter].each do |name|
      package = File.join(@base, 'resolved', name)
      FileUtils.mkdir_p(File.join(package, 'lib'))
      File.write(File.join(package, 'pubspec.yaml'), "name: #{name}\nversion: 1.0.0\n")
      File.write(File.join(package, 'lib', name + '.dart'), "// #{name}\n")
      File.write(File.join(package, 'LICENSE'), 'original license')
      source = { 'private_pkg' => 'git', 'public_pkg' => 'hosted', 'flutter' => 'sdk' }.fetch(name)
      lock += "  #{name}:\n    source: #{source}\n    version: \"1.0.0\"\n"
      lock += "    description:\n      name: #{name}\n      url: https://pub.dev\n" if name == 'public_pkg'
      packages << { 'name' => name, 'rootUri' => URI::DEFAULT_PARSER.escape("file://#{package}/") }
    end
    File.write(File.join(@project, 'pubspec.lock'), lock)
    File.write(File.join(@project, '.dart_tool/package_config.json'), JSON.generate('configVersion' => 2, 'packages' => packages))
    @pubcache = File.join(@base, 'environment/pub')
    @gradle = File.join(@base, 'environment/gradle')
    @output = File.join(@base, 'output')
    @testhome = File.join(@base, 'environment/home')
    [@pubcache, @gradle, @output, @testhome].each { |dir| FileUtils.mkdir_p(dir) }
    @real_environment = {
      'HOME' => @testhome, 'PUB_CACHE' => @pubcache, 'GRADLE_USER_HOME' => @gradle,
      'MAVEN_REPO_LOCAL' => File.join(@base, 'environment/maven'),
      'NO_COLOR' => '1', 'TERM' => 'dumb', 'CI' => 'true', 'DART_SUPPRESS_ANALYTICS' => 'true',
      'TMPDIR' => @base + '/'
    }
    @dispatcher = File.join(copied, 'DispatchFlutterTools.zsh')
  end

  def actual_dispatch(action, project, input)
    Timeout.timeout(90) do
      Open3.capture2e(@real_environment, '/bin/zsh', '-f', @dispatcher, action, project, stdin_data: input, chdir: '/')
    end
  end

  def test_real_copied_dispatcher_export_zip_and_bundle_yes_import
    prepare_real_pipeline
    source_before = File.binread(File.join(@project, 'pubspec.yaml'))
    output, status = actual_dispatch('export-all-dependencies', @project, "\n\n#{@output}\n\n\n")
    assert status.success?, output
    bundles = Dir.children(@output).map { |name| File.join(@output, name) }.select { |path| File.directory?(path) }
    assert_equal 1, bundles.length, output
    bundle = bundles.first
    assert File.file?(bundle + '.zip'), output
    metadata = JSON.parse(File.read(File.join(bundle, 'migration.json')))
    assert_equal 'private-candidates', metadata.fetch('scope')
    pub_manifest = JSON.parse(File.read(File.join(bundle, metadata.fetch('pubSnapshot'), 'manifest.json')))
    assert_equal ['private_pkg'], pub_manifest.fetch('packages').map { |item| item.fetch('name') }
    output, status = actual_dispatch('import-all-dependencies', @target, "\n#{Shellwords.escape(bundle)}\nYES\n")
    assert status.success?, output
    assert_includes File.read(File.join(@target, 'pubspec_overrides.yaml')), 'private_pkg:'
    refute_includes File.read(File.join(@target, 'pubspec_overrides.yaml')), 'public_pkg:'
    assert_equal source_before, File.binread(File.join(@project, 'pubspec.yaml'))
    assert File.directory?(bundle), 'ZIP 默认必须保留原始导出目录'
    refute File.exist?(File.join(@target, 'lib')), '迁移目标允许无 lib'
  end

  def test_real_copied_dispatcher_imports_renamed_raw_caches_without_overwriting_existing_files
    prepare_real_pipeline
    donor = File.join(@base, '来件 父目录')
    pub_file = 'hosted/pub.dev/public_pkg-1.0.0/pubspec.yaml'
    jar = 'caches/modules-2/files-2.1/com.private/sdk/1.0/hash/sdk.jar'
    source_pub = File.join(donor, '改名A', pub_file)
    source_jar = File.join(donor, '改名B', jar)
    [source_pub, source_jar].each { |path| FileUtils.mkdir_p(File.dirname(path)) }
    File.write(source_pub, "name: public_pkg\nversion: 1.0.0\n")
    File.binwrite(source_jar, "jar\x00bytes")
    File.write(File.join(donor, '改名B', 'gradle.properties'), 'secret=DO_NOT_COPY')
    existing = File.join(@gradle, 'keep.txt')
    File.write(existing, 'retain')
    output, status = actual_dispatch('import-all-dependencies', @target, "\n#{Shellwords.escape(donor)}\nNO\n")
    assert status.success?, output
    refute File.exist?(File.join(@pubcache, pub_file))
    refute File.exist?(File.join(@gradle, jar))
    output, status = actual_dispatch('import-all-dependencies', @target, "\n\n#{Shellwords.escape(donor)}\nYES\n")
    assert status.success?, output
    assert_equal File.binread(source_pub), File.binread(File.join(@pubcache, pub_file))
    assert_equal File.binread(source_jar), File.binread(File.join(@gradle, jar))
    assert_equal 'retain', File.read(existing)
    refute File.exist?(File.join(@gradle, 'gradle.properties'))
    assert_includes output, '尚未输入依赖目录'
  end

  def raw_git_conflict
    prepare_real_pipeline
    donor = File.join(@base, '同名Git缓存来件')
    relative = "git/private-#{'a' * 40}/.git/index"
    source = File.join(donor, relative)
    target = File.join(@pubcache, relative)
    [source, target].each { |file| FileUtils.mkdir_p(File.dirname(file)) }
    File.binwrite(source, "incoming-index\x00\xff")
    File.binwrite(target, "local-index\x00\xfe")
    missing = File.join(donor, 'hosted/pub.dev/new_pkg-1.0.0/pubspec.yaml')
    FileUtils.mkdir_p(File.dirname(missing))
    File.write(missing, "name: new_pkg\nversion: 1.0.0\n")
    [donor, source, target]
  end

  def test_real_git_index_conflict_source_with_backup_restores_exact_previous_bytes
    donor, source, target = raw_git_conflict
    previous = File.binread(target)
    backups = File.join(@base, "备份位置 中文 ' $(touch NEVER)")
    output, status = actual_dispatch('import-all-dependencies', @target,
      "\n#{Shellwords.escape(donor)}\n1\n\n#{Shellwords.escape(backups)}\nYES\n")
    assert status.success?, output
    assert_equal File.binread(source), File.binread(target)
    saved = Dir.glob(File.join(backups, '**/*'), File::FNM_DOTMATCH).select { |p| File.file?(p) && File.basename(p) == 'index' }
    assert_equal 1, saved.length, output
    assert_equal previous, File.binread(saved.first)
    assert File.file?(File.join(@pubcache, 'hosted/pub.dev/new_pkg-1.0.0/pubspec.yaml'))
    refute File.exist?(File.join(@base, 'NEVER'))
  end

  def test_real_git_index_conflict_source_without_backup
    donor, source, target = raw_git_conflict
    output, status = actual_dispatch('import-all-dependencies', @target,
      "\n#{Shellwords.escape(donor)}\n1\n \nYES\n")
    assert status.success?, output
    assert_equal File.binread(source), File.binread(target)
    assert File.file?(File.join(@pubcache, 'hosted/pub.dev/new_pkg-1.0.0/pubspec.yaml'))
    refute Dir.exist?(File.join(@testhome, 'Desktop'))
  end

  def test_real_git_index_conflict_existing_keeps_current_and_imports_missing
    donor, _source, target = raw_git_conflict
    previous = File.binread(target)
    output, status = actual_dispatch('import-all-dependencies', @target,
      "\n#{Shellwords.escape(donor)}\n2\n\n\nYES\n")
    assert status.success?, output
    assert_equal previous, File.binread(target)
    assert File.file?(File.join(@pubcache, 'hosted/pub.dev/new_pkg-1.0.0/pubspec.yaml'))
    refute_includes output, '备份父目录：'
    assert_equal 2, output.scan('尚未输入确认内容').length
  end

  def test_real_conflict_final_cancel_does_not_create_backup_or_write_anything
    donor, _source, target = raw_git_conflict
    previous = File.binread(target)
    backups = File.join(@base, 'cancelled-backups')
    output, status = actual_dispatch('import-all-dependencies', @target,
      "\n#{Shellwords.escape(donor)}\n1\n\n#{backups}\nNO\n")
    assert status.success?, output
    assert_equal previous, File.binread(target)
    refute Dir.exist?(backups)
    refute File.exist?(File.join(@pubcache, 'hosted/pub.dev/new_pkg-1.0.0/pubspec.yaml'))
  end

  def test_missing_plan_fingerprint_stops_before_yes
    fake = File.join(@base, 'old-dart')
    File.write(fake, "#!/bin/zsh\nprint -r -- legacy-preview\n")
    File.chmod(0o755, fake)
    output, status = run_functions('FM_DART="$1"; FM_DIRECTORY="$2"; fm_import', fake, @bundle, input: "YES\n")
    refute status.success?, output
    assert_includes output, '预检指纹'
  end

  def test_missing_duplicate_or_invalid_conflict_marker_stops_before_apply
    ['', "JOBS_MIGRATION_CONFLICTS=0\nJOBS_MIGRATION_CONFLICTS=0", 'JOBS_MIGRATION_CONFLICTS=invalid'].each do |marker|
      fake = File.join(@base, 'invalid-protocol-dart')
      trace = File.join(@base, 'invalid-protocol-calls')
      File.write(fake, "#!/bin/zsh\nprint -r -- \"$*\" >> \"$TEST_CALLS\"\nprint -r -- 'JOBS_MIGRATION_PLAN=#{'a' * 64}'\nprint -r -- '#{marker}'\n")
      File.chmod(0o755, fake)
      output, status = run_functions('FM_DART="$1"; FM_DIRECTORY="$2"; fm_import', fake, @bundle, input: "YES\n", env: { 'TEST_CALLS' => trace })
      refute status.success?, output
      assert_includes output, '冲突数量响应'
      refute_includes File.read(trace), '--apply'
    end
  end

  def test_real_source_change_during_confirmation_stops_all_writes
    prepare_real_pipeline
    donor = File.join(@base, '变化的原始缓存')
    first = File.join(donor, 'hosted/pub.dev/pkg-1.0.0/pubspec.yaml')
    FileUtils.mkdir_p(File.dirname(first))
    File.write(first, "name: pkg\nversion: 1.0.0\n")
    output = +''.b
    status = nil
    Timeout.timeout(90) do
      Open3.popen2e(@real_environment, '/bin/zsh', '-f', @dispatcher, 'import-all-dependencies', @target, chdir: '/') do |input, stream, waiter|
        input.write("\n#{Shellwords.escape(donor)}\n")
        input.flush
        until output.include?('JOBS_MIGRATION_PLAN=')
          output << stream.readpartial(4096).b
        end
        File.write(JobsSourceLayout.file(File.join(File.dirname(first), 'added_after_preview.dart')), '// changed')
        input.write("YES\n")
        input.close
        output << stream.read.b
        status = waiter.value
      end
    end
    output.force_encoding('UTF-8')
    refute status.success?, output
    assert_match(/变化|指纹|不一致/, output)
    assert_empty Dir.children(@pubcache), '预检后来源变化必须保持缓存零写入'
  end

  def test_native_full_archive_zip_uses_native_manifest_identity
    prepare_real_pipeline
    native = File.join(@base, 'native-module-source')
    FileUtils.mkdir_p(native)
    File.binwrite(File.join(native, 'sdk.jar'), "archive\x00")
    code = <<~'ZSH'
      source "$1/ArchiveProjectDependencies.zsh"
      ar_initialize() { return 0; }
      ar_choose_platform() { return 0; }
      ar_resolve_dart() { return 0; }
      ar_resolve_root() { return 0; }
      pe_log() { print -r -- "$*"; }
      pe_run_logged() { "$@"; }
      AR_PRIVATE=0 AR_CHECK=0 AR_MODE=export AR_KIND=gradle AR_PLATFORM=android
      AR_PROJECT="$2" SF_PROJECT="$2" AR_ROOT="$3" AR_DIRECTORY="$4" AR_DART="$5"
      PE_TOOLS_DIR="$1" PE_LOG_FILE=/dev/null AR_VERSION='Gradle 8.10.2 modules'
      ar_run
    ZSH
    output, status = run_functions(code, TOOLS, @project, native, @output, real_dart, input: "\n\n")
    assert status.success?, output
    bundles = Dir.children(@output).map { |name| File.join(@output, name) }.select { |path| File.directory?(path) }
    assert_equal 1, bundles.length, output
    assert File.file?(File.join(bundles.first, 'manifest.json'))
    assert File.file?(bundles.first + '.zip'), output
    refute File.exist?(File.join(bundles.first, 'migration.json'))
  end

  def test_zip_never_deletes_payload_changed_after_archive_verification
    code = <<~'ZSH'
      read() {
        if [[ "$*" == *'是否删除原始提取目录'* ]]; then
          print -r -- 'user changes after archive' > "$FM_OUTPUT/.hidden"
          print -r -- 'new user file' > "$FM_OUTPUT/new-after-zip.txt"
        fi
        builtin read "$@"
      }
      FM_DIRECTORY="$1" FM_OUTPUT="$2"
      fm_zip_offer
    ZSH
    original_manifest = File.binread(File.join(@bundle, 'migration.json'))
    output, status = run_functions(code, @base, @bundle, input: "\nDELETE\n")
    refute status.success?, output
    assert Dir.exist?(@bundle), output
    assert File.file?(@bundle + '.zip'), output
    assert_equal original_manifest, File.binread(File.join(@bundle, 'migration.json'))
    assert_equal "user changes after archive\n", File.read(File.join(@bundle, '.hidden'))
    assert File.file?(File.join(@bundle, 'new-after-zip.txt'))
    assert_includes output, '发生变化，未删除'
  end

end
