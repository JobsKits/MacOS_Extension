# frozen_string_literal: true
# 在私有临时目录使用假 adb / emulator 验证真实函数；不连接设备、不改本机 AVD 或扩展注册。

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

require_relative '../../../Tests/SourceLayoutHelper.rb/SourceLayoutHelper'

class RepairAndroidSimulatorTests < Minitest::Test
  ROOT = File.expand_path('..', File.dirname(__dir__))
  SCRIPT = JobsSourceLayout.file(File.join(ROOT, 'Scripts/【MacOS】RepairAndroidSimulator.zsh/【MacOS】RepairAndroidSimulator.zsh'))

  def setup
    @root = Dir.mktmpdir('jobs-android-repair-')
    @home = File.join(@root, 'home')
    @avd_home = File.join(@home, '.android/avd')
    @avd = File.join(@avd_home, 'Pixel_Repair.avd')
    @calls = File.join(@root, 'calls')
    FileUtils.mkdir_p(@avd)
    File.write(File.join(@avd_home, 'Pixel_Repair.ini'), "path=#{@avd}\n")
    File.write(File.join(@avd, 'config.ini'), "AvdId=Pixel_Repair\ndisk.dataPartition.size=1024M\nkeep=value\n")
    File.write(File.join(@avd, 'userdata-qemu.img'), 'existing user data')
    @adb = File.join(@root, 'adb')
    File.write(@adb, fake_adb)
    File.chmod(0o700, @adb)
    @emulator = File.join(@root, 'emulator')
    File.write(@emulator, "#!/bin/zsh\n[[ \"$1\" == -version ]] && exit 0\nexit 55\n")
    File.chmod(0o700, @emulator)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_check_queries_only_emulators_and_creates_no_tool_log
    output, result = run_script('--check')
    assert result.success?, output
    assert_includes output, '/data 可用：2048 MB'
    refute_includes calls, 'physical-123'
    refute_match(/set-install-location|uninstall|compile|emu\|kill/, calls)
    assert_empty Dir.glob(File.join(@root, 'JobsAndroidSimulatorRepairer-*.log'))
    assert_equal "AvdId=Pixel_Repair\ndisk.dataPartition.size=1024M\nkeep=value\n", File.read(config)
  end

  def test_check_low_space_and_wrong_location_report_nonzero
    output, result = run_script('--check', environment: {'JOBS_TEST_FREE_KB' => '100', 'JOBS_TEST_LOCATION' => '2[external]'})
    refute result.success?, output
    assert_includes output, '空间偏低'
    assert_includes output, '不是 0'
    refute_match(/set-install-location|uninstall|compile|emu\|kill/, calls)
  end

  def test_bad_df_is_diagnostic_failure
    output, result = run_script('--check', environment: {'JOBS_TEST_DF_BAD' => '1'})
    refute result.success?, output
    assert_includes output, '无法解析'
    refute_includes output, '可用：0 MB'
  end

  def test_physical_serial_unknown_flags_and_auto_yes_are_rejected_before_adb
    [%w[--check --serial physical-123], %w[--check --yes], %w[--check --app-id com.jobs.demo]].each do |arguments|
      output, result = run_script(*arguments)
      refute result.success?, output
      assert_equal '', calls
    end
  end

  def test_missing_explicit_adb_does_not_install_or_fallback
    output, result = run_script('--check', environment: {'ANDROID_ADB_BIN' => File.join(@root, 'missing')})
    refute result.success?, output
    assert_includes output, 'ANDROID_ADB_BIN 不可执行'
    assert_equal '', calls
  end

  def test_noninteractive_repair_stops_before_initializing_log
    output, result = run_script('--repair')
    refute result.success?, output
    assert_includes output, '修复需要可交互终端'
    assert_equal '', calls
    assert_empty Dir.glob(File.join(@root, 'JobsAndroidSimulatorRepairer-*.log'))
  end

  def test_install_location_requires_nonempty_confirmation_and_readback
    output, result = run_functions('fix_install_location', input: "\n")
    assert result.success?, output
    refute_includes calls, 'set-install-location'
    output, result = run_functions('fix_install_location', input: "run\n", environment: {'JOBS_TEST_LOCATION' => '1[internal]'})
    refute result.success?, output
    assert_includes calls, 'set-install-location|0'
    assert_includes output, '未确认恢复'
  end

  def test_shell_error_with_zero_exit_cannot_report_install_success
    output, result = run_functions('fix_install_location', input: "run\n", environment: {'JOBS_TEST_SET_ERROR' => '1'})
    refute result.success?, output
    assert_includes output, '设备拒绝'
    refute_includes output, '✔ 已回读'
  end

  def test_compile_reset_requires_yes_and_refuses_error_text
    output, result = run_functions('reset_compile_cache', input: "yes\n")
    assert result.success?, output
    refute_includes calls, 'compile'
    output, result = run_functions('reset_compile_cache', input: "YES\n", environment: {'JOBS_TEST_COMPILE_ERROR' => '1'})
    refute result.success?, output
    assert_includes calls, 'compile|--reset|-a'
    assert_includes output, '设备拒绝'
  end

  def test_uninstall_rejects_injection_prefix_and_builtin_packages
    ["com.jobs.demo;touch /tmp/no", 'com.jobs', 'com.android.chrome'].each do |package|
      output, result = run_functions('uninstall_exact_package', input: "#{package}\nYES\n")
      refute result.success?, output
      refute_match(/\|uninstall\|/, calls)
    end
  end

  def test_uninstall_exact_third_party_package_requires_yes_and_success
    output, result = run_functions('uninstall_exact_package', input: "com.jobs.demo\nno\n")
    assert result.success?, output
    refute_match(/\|uninstall\|/, calls)
    output, result = run_functions('uninstall_exact_package', input: "com.jobs.demo\nYES\n", environment: {'JOBS_TEST_UNINSTALL_FAIL' => '1'})
    refute result.success?, output
    assert_includes calls, 'uninstall|com.jobs.demo'
    refute_includes output, '✔ 设备报告已卸载'
  end

  def test_size_parser_supports_byte_k_m_g_and_rejects_unknown_values
    output, result = run_functions("size_in_mb 1073741824; size_in_mb 2048K; size_in_mb 12G; size_in_mb 900M; ! size_in_mb 0; ! size_in_mb 2T; ! size_in_mb '1G;id'")
    assert result.success?, output
    assert_equal %w[1024 2 12288 900], output.lines.map(&:strip)
  end

  def test_avd_root_environment_and_descriptor_paths_are_used
    relative = File.join(@avd_home, 'Pixel_Repair.ini')
    File.write(relative, "path.rel=avd/Pixel_Repair.avd\n")
    output, result = run_functions('resolve_avd_paths; print -r -- "$CONFIG_PATH"')
    assert result.success?, output
    assert_equal File.realpath(config), output.strip
  end

  def test_avd_outside_root_symlink_and_wrong_identity_are_rejected
    outside = File.join(@root, 'external.avd')
    FileUtils.mkdir_p(outside)
    File.write(File.join(@avd_home, 'Pixel_Repair.ini'), "path=#{outside}\n")
    output, result = run_functions('resolve_avd_paths')
    refute result.success?, output
    assert_includes output, '根之外'
    File.write(File.join(@avd_home, 'Pixel_Repair.ini'), "path=#{@avd}\n")
    File.symlink(File.join(@root, 'absent'), File.join(@avd, 'unsafe-link'))
    output, result = run_functions('resolve_avd_paths')
    refute result.success?, output
    assert_includes output, '符号链接'
    File.unlink(File.join(@avd, 'unsafe-link'))
    File.write(config, "AvdId=Other\ndisk.dataPartition.size=1024M\n")
    output, result = run_functions('resolve_avd_paths')
    refute result.success?, output
    assert_includes output, 'AvdId'
  end

  def test_capacity_refuses_custom_userdata_unknown_process_shrink_and_duplicate_key
    File.open(config, 'a') { |file| file.puts('disk.dataPartition.path=/external/userdata.img') }
    output, result = run_functions('increase_avd_capacity', input: "8G\nYES\n")
    refute result.success?, output
    assert_includes output, '显式 disk.dataPartition.path'
    refute_includes calls, 'emu|kill'
    File.write(config, "AvdId=Pixel_Repair\ndisk.dataPartition.size=1024M\n")
    ['-data /external/userdata.img', '-datadir /external', '-read-only', ''].each do |flags|
      process = flags.empty? ? '' : "/sdk/emulator/qemu-system-aarch64 -avd Pixel_Repair #{flags}"
      output, result = run_functions('increase_avd_capacity', input: "8G\nYES\n", environment: {'JOBS_TEST_PROCESS' => process})
      refute result.success?, output
      refute_includes calls, 'emu|kill'
    end
    output, result = run_functions('increase_avd_capacity', input: "1G\nYES\n")
    refute result.success?, output
    assert_includes output, '不会缩容'
    File.open(config, 'a') { |file| file.puts('disk.dataPartition.size=2G') }
    output, result = run_functions('increase_avd_capacity', input: "8G\nYES\n")
    refute result.success?, output
    assert_includes output, '缺失或重复'
  end

  def test_target_must_exceed_filesystem_and_image_logical_size
    output, result = run_functions('increase_avd_capacity', input: "2G\nYES\n")
    refute result.success?, output
    assert_includes output, '文件系统总量'
    File.open(File.join(@avd, 'userdata-qemu.img'), 'w') { |file| file.truncate(10 * 1024**3) }
    output, result = run_functions('increase_avd_capacity', input: "8G\nYES\n")
    refute result.success?, output
    assert_includes output, '镜像逻辑大小'
    refute_includes calls, 'emu|kill'
  end

  def test_duplicate_descriptor_and_avd_identity_are_rejected
    File.open(File.join(@avd_home, 'Pixel_Repair.ini'), 'a') { |file| file.puts("path=#{@avd}") }
    output, result = run_functions('resolve_avd_paths')
    refute result.success?, output
    assert_includes output, '重复 path'
    File.write(File.join(@avd_home, 'Pixel_Repair.ini'), "path=#{@avd}\n")
    File.open(config, 'a') { |file| file.puts('AvdId=Other') }
    output, result = run_functions('resolve_avd_paths')
    refute result.success?, output
    assert_includes output, 'AvdId 缺失或重复'
  end

  def test_cold_boot_does_not_pass_without_actual_capacity_growth
    extra = <<~'ZSH'
      ask_run() { return 0; }
      avd_is_stopped() { return 0; }
      jobs_fake_nohup() { return 0; }
    ZSH
    output, result = run_functions('cold_boot_and_recheck 4096', extra: extra)
    refute result.success?, output
    assert_includes output, '总量没有增加'
    refute_includes output, '✔ 已复核 /data 总量增加'
    output, result = run_functions('cold_boot_and_recheck 4096', extra: extra,
                                   environment: {'JOBS_TEST_TOTAL_KB' => '8388608'})
    assert result.success?, output
    assert_includes output, '4096 → 8192 MB'
    output, result = run_functions('cold_boot_and_recheck 4096', extra: extra,
                                   environment: {'JOBS_TEST_TOTAL_KB' => '8388608', 'JOBS_TEST_FREE_KB' => '100'})
    refute result.success?, output
    assert_includes output, '空间偏低'
    refute_includes output, '✔ 已复核 /data 总量增加'
  end

  def test_backup_space_failure_preserves_config
    original = File.read(config)
    extra = <<~'ZSH'
      jobs_fake_df() { print -r -- $'Filesystem 1024-blocks Used Available Capacity Mounted\n/dev/fake 10485760 10000000 485760 95% /'; }
    ZSH
    output, result = run_functions('increase_avd_capacity', input: "8G\nYES\n", extra: extra)
    refute result.success?, output
    assert_includes output, '可用空间不足'
    assert_equal original, File.read(config)
    assert_empty backups
  end

  def test_stop_failure_or_residual_lock_preserves_config_without_backup
    original = File.read(config)
    File.write(File.join(@avd, 'hardware-qemu.ini.lock'), 'still locked')
    output, result = run_functions('increase_avd_capacity', input: "8G\nYES\n")
    refute result.success?, output
    assert_includes output, '无法确认完全停机'
    assert_equal original, File.read(config)
    assert_empty backups
  end

  def test_successful_config_change_has_full_backup_and_remains_pending_without_cold_boot
    original = File.read(config)
    output, result = run_functions('increase_avd_capacity', input: "8G\nYES\n\n")
    refute result.success?, output
    assert_includes output, '待验证'
    assert_includes File.read(config), 'disk.dataPartition.size=8192M'
    assert_equal 1, backups.length
    assert_equal original, File.read(File.join(backups.first, 'avd/config.ini'))
    assert_equal 'existing user data', File.read(File.join(backups.first, 'avd/userdata-qemu.img'))
    assert File.file?(File.join(backups.first, 'Pixel_Repair.ini'))
    assert_includes calls, 'emu|kill'
    refute_match(/wipe-data|\|uninstall\|/, calls)
  end

  def test_backup_failure_prevents_config_write
    original = File.read(config)
    output, result = run_functions('increase_avd_capacity', input: "8G\nYES\n", extra: "backup_stopped_avd() { log 'backup rejected'; return 1; }")
    refute result.success?, output
    assert_includes output, 'backup rejected'
    assert_equal original, File.read(config)
  end

  def test_config_change_during_stop_is_not_overwritten
    output, result = run_functions('increase_avd_capacity', input: "8G\nYES\n", environment: {'JOBS_TEST_MODIFY_ON_STOP' => '1'})
    refute result.success?, output
    assert_includes output, '等待期间 config.ini 发生变化'
    assert_includes File.read(config), 'keep=changed-after-stop'
    assert_empty backups
  end

  def test_menu_preserves_failed_action_exit_status
    output, result = run_functions('run_repair_menu', input: "2\nrun\n0\n", environment: {'JOBS_TEST_SET_ERROR' => '1'})
    refute result.success?, output
    assert_includes output, '本项修复未完成'
  end

  def test_log_control_sequences_are_removed
    output, result = run_functions("log $'hello\\e[31mred\\e[0m\\x01done'")
    assert result.success?, output
    assert_equal "helloreddone\n", output
    refute_includes File.read(File.join(@root, 'run.log')), "\e"
  end

  private

  def config
    File.join(@avd, 'config.ini')
  end

  def backups
    Dir.glob(File.join(@avd_home, '.Pixel_Repair.repair-backup.*'))
  end

  def calls
    File.exist?(@calls) ? File.read(@calls) : ''
  end

  def base_environment
    {'HOME' => @home, 'TMPDIR' => "#{@root}/", 'NO_COLOR' => '1', 'ANDROID_ADB_BIN' => @adb,
     'ANDROID_EMULATOR_BIN' => @emulator, 'JOBS_TEST_CALLS' => @calls, 'JOBS_TEST_ROOT' => @root,
     'JOBS_TEST_CONFIG' => config, 'JOBS_TEST_PROCESS' => '/sdk/emulator/qemu-system-aarch64 -avd Pixel_Repair -no-snapshot-load'}
  end

  def run_script(*arguments, environment: {})
    Open3.capture2e(base_environment.merge(environment), '/bin/zsh', '-f', SCRIPT, *arguments)
  end

  def run_functions(checks, input: '', environment: {}, extra: '')
    source = File.read(SCRIPT)
    raise 'missing real main' unless source.sub!(/^main "\$@"\s*\z/, '')
    source = source.gsub('/bin/ps', 'jobs_fake_ps').gsub('/bin/sleep', 'jobs_fake_sleep').gsub('/usr/bin/nohup', 'jobs_fake_nohup')
    source = source.gsub('/bin/df', 'jobs_fake_df') if extra.include?('jobs_fake_df()')
    fixture = File.join(@root, 'fixture.zsh')
    File.write(fixture, source + <<~ZSH)
      jobs_fake_ps() {
        [[ ! -e "$JOBS_TEST_ROOT/offline" ]] && print -r -- "$JOBS_TEST_PROCESS"
        return 0
      }
      jobs_fake_sleep() { return 0; }
      setopt NO_NOMATCH PIPE_FAIL
      ADB_BIN="$ANDROID_ADB_BIN"
      EMULATOR_BIN="$ANDROID_EMULATOR_BIN"
      DEVICE_ID=emulator-5554
      AVD_NAME=Pixel_Repair
      LOG_FILE="$JOBS_TEST_ROOT/run.log"
      : > "$LOG_FILE"
      #{extra}
      #{checks}
    ZSH
    Open3.capture2e(base_environment.merge(environment), '/bin/zsh', '-f', fixture, stdin_data: input)
  end

  def fake_adb
    <<~'ZSH'
      #!/bin/zsh
      print -r -- "${(j:|:)@}" >> "$JOBS_TEST_CALLS"
      if [[ "$1" == version ]]; then print -r -- 'Android Debug Bridge version fake'; exit 0; fi
      if [[ "$1" == devices ]]; then
        print -r -- 'List of devices attached'
        [[ -e "$JOBS_TEST_ROOT/offline" ]] || print -r -- $'emulator-5554\tdevice'
        print -r -- $'physical-123\tdevice'
        exit 0
      fi
      [[ "$1" == -s && "$2" == emulator-5554 ]] || exit 71
      shift 2
      case "$*" in
        'emu avd name') print -r -- $'Pixel_Repair\r\nOK'; exit 0 ;;
        'shell getprop ro.kernel.qemu') print -r -- 1; exit 0 ;;
        'shell getprop sys.boot_completed') print -r -- 1; exit 0 ;;
        'shell pm get-install-location') print -r -- "${JOBS_TEST_LOCATION:-0[auto]}"; exit 0 ;;
        'shell pm set-install-location 0') [[ "${JOBS_TEST_SET_ERROR:-0}" == 1 ]] && print -r -- 'Error: denied'; exit 0 ;;
        'shell cmd package compile --reset -a') [[ "${JOBS_TEST_COMPILE_ERROR:-0}" == 1 ]] && print -r -- 'Error: unsupported'; exit 0 ;;
        'shell pm list packages -3') print -r -- $'package:com.jobs.demo\npackage:com.jobs.demo.extra'; exit 0 ;;
        'uninstall com.jobs.demo')
          [[ "${JOBS_TEST_UNINSTALL_FAIL:-0}" == 1 ]] && print -r -- 'Failure [DELETE_FAILED]' || print -r -- Success
          exit 0 ;;
        'shell df -k /data')
          if [[ "${JOBS_TEST_DF_BAD:-0}" == 1 ]]; then print -r -- 'unknown df'; exit 0; fi
          print -r -- 'Filesystem 1K-blocks Used Available Use% Mounted on'
          print -r -- "/dev/fake ${JOBS_TEST_TOTAL_KB:-4194304} 2097152 ${JOBS_TEST_FREE_KB:-2097152} 50% /data"
          exit 0 ;;
        'emu kill')
          /usr/bin/touch "$JOBS_TEST_ROOT/offline"
          [[ "${JOBS_TEST_MODIFY_ON_STOP:-0}" == 1 ]] && print -r -- 'keep=changed-after-stop' >> "$JOBS_TEST_CONFIG"
          print -r -- OK
          exit 0 ;;
      esac
      exit 79
    ZSH
  end
end
