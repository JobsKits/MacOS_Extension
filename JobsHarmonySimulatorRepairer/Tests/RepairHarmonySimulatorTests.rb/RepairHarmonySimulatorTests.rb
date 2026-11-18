# frozen_string_literal: true
# 假官方 CLI 与临时实例覆盖真实诊断 / 修复链，不操作用户模拟器或系统扩展。

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
require 'json'
require 'pty'
require 'timeout'

require_relative '../../../Tests/SourceLayoutHelper.rb/SourceLayoutHelper'

class RepairHarmonySimulatorTests < Minitest::Test
  ROOT = File.expand_path('..', File.dirname(__dir__))
  SCRIPT = JobsSourceLayout.file(File.join(ROOT, 'Scripts/【MacOS】RepairHarmonySimulator.zsh/【MacOS】RepairHarmonySimulator.zsh'))

  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-harmony-repair-'))
    @instance = File.join(@root, 'instances/JobsHarmony_Test')
    @sdk = File.join(@root, 'tools/sdk')
    @emulator = File.join(@root, 'tools/emulator/Emulator')
    @calls = File.join(@root, 'calls')
    FileUtils.mkdir_p([@instance, File.dirname(@emulator), File.join(@sdk, 'default/openharmony/toolchains')])
    File.write(config, "name=JobsHarmony_Test\nsdkPath=#{@sdk}\nkeep=value\n")
    File.write(File.join(@instance, 'userdata.img'), 'existing userdata')
    write_executable(@emulator, fake_emulator)
    write_executable(File.join(@sdk, 'default/openharmony/toolchains/hdc'), "#!/bin/zsh\n[[ \"$1\" == -v ]] && { print 'HDC 3.1'; exit 0; }\nexit 44\n")
    @uname = File.join(@root, 'uname')
    write_executable(@uname, "#!/bin/zsh\n[[ \"$1\" == -s ]] && print Darwin || print arm64\n")
    @ps = File.join(@root, 'ps')
    write_executable(@ps, "#!/bin/zsh\nprint -r -- \"${JOBS_TEST_PS:-/sbin/launchd}\"\n")
    source = File.read(SCRIPT).gsub('/usr/bin/uname', shell_word(@uname)).gsub('/bin/ps', shell_word(@ps))
    source = source.gsub('/bin/sleep 2', '/usr/bin/true')
    @script = File.join(@root, 'repair.zsh')
    File.write(@script, source)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_check_is_read_only_and_accepts_official_bool_state
    before = File.binread(config)
    output, result = run_script('--check')
    assert result.success?, output
    assert_includes output, 'isRunning=false'
    assert_includes output, 'SDK / HDC 版本检测通过'
    refute_match(/-start|-stop|-delete|-config/, calls)
    assert_equal before, File.binread(config)
    assert_empty Dir.glob(File.join(@root, 'JobsHarmonySimulatorRepairer.*'))
    assert_empty backups
  end

  def test_unknown_state_rejects_all_operations
    output, result = run_script('--check', environment: { 'JOBS_TEST_UNKNOWN_STATE' => '1' })
    refute result.success?, output
    assert_includes output, '实例 JSON 结构未知'
    refute_match(/-start|-stop/, calls)
  end

  def test_duplicate_names_and_path_identity_fail_closed
    output, result = run_script('--check', environment: { 'JOBS_TEST_DUPLICATE' => '1' })
    refute result.success?, output
    File.write(config, "name=Another\nsdkPath=#{@sdk}\n")
    output, result = run_script('--check')
    refute result.success?, output
    assert_includes output, 'name 与官方清单不一致'
  end

  def test_empty_official_instance_list_is_diagnostic_failure
    output, result = run_script('--check', environment: { 'JOBS_TEST_EMPTY' => '1' })
    refute result.success?, output
    assert_includes output, '没有官方登记的本地实例'
    refute_match(/-start|-stop/, calls)
  end

  def test_noninteractive_and_unknown_flags_do_not_mutate_or_query
    output, result = run_script('--repair')
    refute result.success?, output
    assert_includes output, '可交互终端'
    assert_equal '', calls
    output, result = run_script('--check', '--yes')
    assert_equal 2, result.exitstatus
    assert_includes output, '未知参数'
    assert_equal '', calls
  end

  def test_explicit_bad_tool_never_falls_back
    output, result = run_script('--check', environment: { 'HARMONY_EMULATOR_BIN' => File.join(@root, 'missing') })
    refute result.success?, output
    assert_includes output, '不是可执行文件'
    assert_equal '', calls
  end

  def test_coldboot_stops_running_instance_then_checks_false_and_true
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n2\nYES\n", interactive: true,
                                environment: { 'JOBS_TEST_RUNNING' => 'true' })
    assert result.success?, output
    assert_includes calls, '-stop|JobsHarmony_Test'
    assert_includes calls, '-start|JobsHarmony_Test|-bootMode|coldboot'
    assert_operator calls.index('-stop|'), :<, calls.index('-start|')
    assert_includes output, '已验证所选实例 isRunning=true'
    refute_includes calls, 'reset'
    assert_equal 'existing userdata', File.read(File.join(@instance, 'userdata.img'))
  end

  def test_stopped_instance_coldboot_does_not_issue_stop
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n2\nYES\n", interactive: true)
    assert result.success?, output
    refute_includes calls, '-stop|'
    assert_includes calls, '-start|JobsHarmony_Test|-bootMode|coldboot'
  end

  def test_stop_failure_never_starts
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n2\nYES\n", interactive: true,
                                environment: { 'JOBS_TEST_RUNNING' => 'true', 'JOBS_TEST_STOP_FAIL' => '1' })
    assert_equal 7, result.exitstatus
    assert_includes output, '未继续启动'
    refute_includes calls, '-start|'
  end

  def test_stop_readback_still_running_never_starts
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n2\nYES\n", interactive: true,
                                environment: { 'JOBS_TEST_RUNNING' => 'true', 'JOBS_TEST_STOP_STUCK' => '1' })
    refute result.success?, output
    assert_includes output, 'isRunning=false'
    refute_includes calls, '-start|'
  end

  def test_unsupported_coldboot_does_not_stop_instance
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n2\nYES\n", interactive: true,
                                environment: { 'JOBS_TEST_NO_BOOT_MODE' => '1', 'JOBS_TEST_RUNNING' => 'true' })
    refute result.success?, output
    refute_includes calls, '-stop|'
    refute_includes calls, '-start|'
  end

  def test_cancel_coldboot_never_starts_or_stops
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n2\nno\n", interactive: true)
    assert result.success?, output
    assert_includes output, '已取消重启'
    refute_match(/-start|-stop/, calls)
  end

  def test_instance_recreated_during_confirmation_is_rejected
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n2\nYES\n", interactive: true,
                                environment: { 'JOBS_TEST_REPLACE_UUID' => '1', 'JOBS_TEST_RUNNING' => 'true' })
    refute result.success?, output
    assert_includes output, '实例 UUID'
    refute_match(/-start|-stop/, calls)
  end

  def test_sdk_repair_preserves_full_backup_and_unrelated_content
    original = "name=JobsHarmony_Test\nsdkPath=/missing/sdk\nkeep=value\n"
    File.write(config, original)
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n3\nYES\n", interactive: true)
    assert result.success?, output
    assert_includes File.read(config), "sdkPath=#{@sdk}"
    assert_includes File.read(config), 'keep=value'
    assert_equal 1, backups.length
    assert_equal original, File.read(File.join(backups.first, 'instance/config.ini'))
    assert_equal 'existing userdata', File.read(File.join(backups.first, 'instance/userdata.img'))
    refute_match(/-start|-stop|-delete/, calls)
  end

  def test_sdk_repair_refuses_running_instance_and_linked_content
    File.write(config, "name=JobsHarmony_Test\nsdkPath=/missing/sdk\n")
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n3\nYES\n", interactive: true,
                                environment: { 'JOBS_TEST_RUNNING' => 'true' })
    refute result.success?, output
    assert_includes output, '仍在运行'
    assert_empty backups
    File.symlink('/etc/hosts', File.join(@instance, 'linked'))
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n3\nYES\n", interactive: true)
    refute result.success?, output
    assert_includes output, '实例含符号链接'
    assert_empty backups
    assert_includes File.read(config), 'sdkPath=/missing/sdk'
  end

  def test_missing_sdk_is_reported_without_any_automatic_download
    File.write(config, "name=JobsHarmony_Test\nsdkPath=/missing/sdk\n")
    output, result = run_script('--check')
    refute result.success?, output
    assert_includes output, 'SDK 路径缺失'
    refute_match(/-start|-stop|-install/, calls)
    assert_empty backups
  end

  def test_sdk_path_with_newline_is_never_written
    File.write(config, "name=JobsHarmony_Test\nsdkPath=/missing/sdk\nkeep=value\n")
    original = File.read(config)
    alternate = File.join(@root, "tool\ninvalid")
    FileUtils.mv(File.join(@root, 'tools'), alternate)
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n3\nYES\n", interactive: true,
                                environment: { 'HARMONY_EMULATOR_BIN' => File.join(alternate, 'emulator/Emulator') })
    refute result.success?, output
    assert_equal original, File.read(config)
    assert_empty backups
  end

  def test_config_change_during_sdk_probe_is_preserved
    File.write(config, "name=JobsHarmony_Test\nsdkPath=/missing/sdk\nkeep=value\n")
    count_path = File.join(@root, 'hdc-count')
    probe = <<~RUBY_SCRIPT
      #!/usr/bin/ruby
      count_path=#{count_path.inspect}
      count=File.exist?(count_path) ? File.read(count_path).to_i : 0
      count+=1
      File.write(count_path,count.to_s)
      if count>=3
        File.open(#{config.inspect},'a') { |f| f.puts('# concurrent DevEco change') }
      end
      puts 'HDC 3.1'
    RUBY_SCRIPT
    write_executable(File.join(@sdk, 'default/openharmony/toolchains/hdc'), probe)
    output, result = run_script('--repair', '--name', 'JobsHarmony_Test', input: "\n3\nYES\n", interactive: true)
    refute result.success?, output
    assert_includes output, '发布前配置内容已改变'
    assert_includes File.read(config), '# concurrent DevEco change'
    assert_includes File.read(config), 'sdkPath=/missing/sdk'
    assert_equal 1, backups.length
  end

  private

  def config
    File.join(@instance, 'config.ini')
  end

  def backups
    Dir.glob(File.join(@root, 'instances/.JobsHarmony_Test.jobs-repair-backup.*'))
  end

  def calls
    File.exist?(@calls) ? File.read(@calls) : ''
  end

  def write_executable(path, content)
    File.write(path, content)
    File.chmod(0o700, path)
  end

  def shell_word(value)
    "'#{value.gsub("'") { "'\\''" }}'"
  end

  def run_script(*arguments, input: '', interactive: false, environment: {})
    env = { 'HOME' => File.join(@root, 'home'), 'TMPDIR' => "#{@root}/", 'NO_COLOR' => '1',
            'HARMONY_EMULATOR_BIN' => @emulator, 'JOBS_TEST_INSTANCE' => @instance,
            'JOBS_TEST_CALLS' => @calls, 'JOBS_TEST_STATE' => File.join(@root, 'running') }.merge(environment)
    return Open3.capture2e(env, '/bin/zsh', '-f', @script, *arguments, stdin_data: input) unless interactive

    output = +''
    status = nil
    Timeout.timeout(30) do
      PTY.spawn(env, '/bin/zsh', '-f', @script, *arguments) do |reader, writer, pid|
        writer.write(input)
        begin
          loop { output << reader.readpartial(4096) }
        rescue EOFError, Errno::EIO
          _, status = Process.wait2(pid)
        end
      end
    end
    [output.force_encoding(Encoding::UTF_8), status]
  end

  def fake_emulator
    <<~'CLI'
      #!/usr/bin/ruby
      require 'json'
      File.open(ENV.fetch('JOBS_TEST_CALLS'),'a') { |f| f.puts(ARGV.join('|')) }
      running = File.exist?(ENV['JOBS_TEST_STATE']) ? File.read(ENV['JOBS_TEST_STATE']) : ENV.fetch('JOBS_TEST_RUNNING','false')
      case ARGV.first
      when '-help'
        puts '-list -details -imageList -start -stop'
        puts '-bootMode coldboot snapshot reset' unless ENV['JOBS_TEST_NO_BOOT_MODE']=='1'
      when '-list'
        count_path=ENV.fetch('JOBS_TEST_STATE')+'.queries'
        count=File.exist?(count_path) ? File.read(count_path).to_i+1 : 1
        File.write(count_path,count.to_s)
        if ENV['JOBS_TEST_EMPTY']=='1'
          puts '[Empty]'
        else
          state = ENV['JOBS_TEST_UNKNOWN_STATE']=='1' ? 'unknown' : running=='true'
          uuid=ENV['JOBS_TEST_REPLACE_UUID']=='1'&&count>=3 ? 'recreated-uuid' : 'fixture-uuid'
          rows=[{name:'JobsHarmony_Test',instancePath:ENV.fetch('JOBS_TEST_INSTANCE'),deviceType:'phone',isRunning:state,uuid:uuid,'os.osVersion'=>'HarmonyOS 6.0'}]
          rows << rows.first.dup if ENV['JOBS_TEST_DUPLICATE']=='1'
          puts JSON.generate(rows)
        end
      when '-imageList'
        puts JSON.generate([{deviceType:'phone',osVersion:'HarmonyOS 6.0',releaseType:'Release',downloaded:true}])
      when '-stop'
        exit 7 if ENV['JOBS_TEST_STOP_FAIL']=='1'
        File.write(ENV.fetch('JOBS_TEST_STATE'),'false') unless ENV['JOBS_TEST_STOP_STUCK']=='1'
        puts 'Stopped'
      when '-start'
        File.write(ENV.fetch('JOBS_TEST_STATE'),'true')
        puts 'Started'
      else
        exit 99
      end
    CLI
  end
end
