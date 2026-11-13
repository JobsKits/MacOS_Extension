# Created by Jobs on 2026年10月29日，星期四.
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
require 'open3'
require 'shellwords'

class FlutterRunnerAndroidTests < Minitest::Test
  SCRIPT = ENV.fetch('JOBS_TEST_RUNNER_SCRIPT') { File.expand_path('../Scripts/RunFlutterProject.zsh', __dir__) }

  def setup
    @tmp = Dir.mktmpdir('jobs-android-runner-')
    @sdk = File.join(@tmp, "Android SDK 中文 ' $(touch NEVER)")
    @library = File.join(@tmp, 'runtime.zsh')
    @trace = File.join(@tmp, 'trace')
    File.write(@library, File.read(SCRIPT).sub(/\nmain "\$@"\s*\z/, "\n"))
    @abi = `uname -m`.strip == 'arm64' ? 'arm64-v8a' : 'x86_64'
    @image = "system-images;android-36;google_apis;#{@abi}"
    FileUtils.mkdir_p(File.join(@sdk, "system-images/android-36/google_apis/#{@abi}"))
    %w[system.img source.properties].each { |name| File.write(File.join(@sdk, "system-images/android-36/google_apis/#{@abi}", name), '') }
    fake('emulator/emulator', <<~'ZSH')
      case "$1" in
        -list-avds) [[ ! -f "$TEST_SDK/avds" ]] || cat "$TEST_SDK/avds" ;;
        -version) print 'Android emulator fixture' ;;
        *) exit 92 ;;
      esac
    ZSH
    fake('cmdline-tools/latest/bin/avdmanager', <<~'ZSH')
      if [[ "$1" == list ]]; then
        print 'id: 0 or "pixel_9"'
        print '    Name: Pixel 9'
      elif [[ "$1" == create ]]; then
        read -r answer
        [[ "$answer" == no ]] || exit 93
        printf '%s\n' "$@" >> "$TRACE"
        while (( $# )); do
          [[ "$1" != -n ]] || { print -r -- "$2" >> "$TEST_SDK/avds"; break; }
          shift
        done
      else
        exit 94
      fi
    ZSH
    fake('cmdline-tools/latest/bin/sdkmanager', <<~'ZSH')
      if [[ "$2" == --list ]]; then
        print -r -- "$IMAGE | fixture"
      else
        print -r -- "INSTALL:$*" >> "$TRACE"
        exit 9
      fi
    ZSH
    fake('platform-tools/adb', <<~'ZSH')
      case "$1" in
        version) print fixture ;;
        devices) printf 'List of devices attached\nphone-1\tdevice\nemulator-5554\tdevice\nemulator-5556\tdevice\n' ;;
        -s)
          if [[ "$3" == emu ]]; then
            [[ "$2" == emulator-5556 ]] && print TARGET || print OTHER
            print OK
          else
            print 1
          fi ;;
        *) exit 95 ;;
      esac
    ZSH
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def fake(relative, body)
    path = File.join(@sdk, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/bin/zsh\n#{body}\n")
    FileUtils.chmod(0o700, path)
  end

  def shell(body, input: '')
    env = { 'HOME' => @tmp, 'ANDROID_HOME' => @sdk, 'ANDROID_SDK_ROOT' => '', 'ANDROID_AVD_HOME' => File.join(@tmp, 'avds'),
            'JOBS_FLUTTER_RUNNER_FZF' => '0', 'TEST_SDK' => @sdk, 'TRACE' => @trace, 'IMAGE' => @image, 'NO_COLOR' => '1' }
    Open3.capture3(env, '/bin/zsh', '-f', '-c', <<~ZSH, stdin_data: input, chdir: @tmp)
      source #{@library.shellescape}
      setopt NO_NOMATCH PIPE_FAIL
      LOG_FILE=#{File.join(@tmp, 'run.log').shellescape}
      resolve_android_tools || exit 1
      #{body}
    ZSH
  end

  def test_empty_avd_inventory_enters_creation_and_confirms_exact_model_and_image
    out, err, result = shell('create_android_emulator && print "AVD=$REPLY"', input: "1\n1\n\n")
    assert result.success?, out + err
    assert_match(/AVD=Jobs_pixel_9_/, out)
    args = File.readlines(@trace, chomp: true)
    assert_includes args, @image
    assert_includes args, 'pixel_9'
    refute_includes args, '--force'
    refute_includes args, '-f'
    refute File.exist?(File.join(@tmp, 'NEVER'))
  end

  def test_model_cancel_writes_no_avd
    out, err, result = shell('create_android_emulator || print CANCELLED', input: "\n")
    assert result.success?, err
    assert_includes out, 'CANCELLED'
    refute File.exist?(@trace)
  end

  def test_image_back_returns_to_model_without_writing
    out, err, result = shell('create_android_emulator || print CANCELLED', input: "1\n3\n\n")
    assert result.success?, err
    assert_equal 2, out.scan('选择 Android 模拟器型号').length
    refute File.exist?(@trace)
  end

  def test_final_cancel_does_not_create_or_install
    out, err, result = shell('create_android_emulator || print CANCELLED', input: "1\n1\nno\n")
    assert result.success?, err
    assert_includes out, 'CANCELLED'
    refute File.exist?(@trace)
  end

  def test_install_failure_stops_before_creation
    FileUtils.rm(File.join(@sdk, "system-images/android-36/google_apis/#{@abi}/system.img"))
    out, err, result = shell('create_android_emulator || print STOPPED', input: "1\n1\n1\n\n")
    assert result.success?, err
    assert_includes out, '安装失败'
    assert_includes File.read(@trace), 'INSTALL:'
    refute File.exist?(File.join(@sdk, 'avds'))
  end

  def test_collision_created_after_confirmation_is_preserved
    out, err, result = shell(<<~'ZSH', input: "1\n1\n\n")
      install_android_packages() { mkdir -p "$ANDROID_AVD_HOME/$avd.avd"; }
      create_android_emulator || print STOPPED
    ZSH
    assert result.success?, err
    assert_includes out, '已有遗留目录'
    refute File.exist?(@trace)
  end

  def test_adb_matching_ignores_physical_phone_and_other_avd
    out, err, result = shell('android_serial_for_avd TARGET && print "SERIAL=$REPLY"')
    assert result.success?, out + err
    assert_includes out, 'SERIAL=emulator-5556'
  end

  def test_no_avds_enters_initialization_without_launch_on_cancel
    out, err, result = shell(<<~'ZSH')
      create_android_emulator() { print INITIALIZATION; return 1; }
      start_android_emulator || print CANCELLED
    ZSH
    assert result.success?, err
    assert_includes out, 'INITIALIZATION'
    assert_includes out, 'CANCELLED'
    refute File.exist?(@trace)
    refute Dir.exist?(File.join(@tmp, 'Library'))
  end

  def test_existing_running_avd_is_reused_without_creation
    File.write(File.join(@sdk, 'avds'), "TARGET\n")
    out, err, result = shell(<<~'ZSH', input: "1\n")
      create_android_emulator() { print UNEXPECTED_CREATE; return 1; }
      refresh_devices() { ROWS=($'emulator-5556\tTarget'); }
      start_android_emulator && print "DEVICE=$DEVICE_ID"
    ZSH
    assert result.success?, out + err
    assert_includes out, 'DEVICE=emulator-5556'
    refute_includes out, 'UNEXPECTED_CREATE'
    refute File.exist?(@trace)
    refute Dir.exist?(File.join(@tmp, 'Library'))
  end

  def test_running_target_waits_for_exact_flutter_id
    out, err, result = shell(<<~'ZSH')
      refresh_devices() { ROWS=($'phone-1\tPhysical' $'emulator-5556\tTarget'); }
      wait_for_android_avd TARGET && print "DEVICE=$DEVICE_ID"
    ZSH
    assert result.success?, out + err
    assert_includes out, 'DEVICE=emulator-5556'
  end

  def test_flutter_wait_revalidates_original_avd_identity_and_serial_before_handoff
    cases={
      unchanged: ['',0,'emulator-5556'],
      replaced: ['CURRENT_IDENTITY=replacement',1,''],
      swapped: ['CURRENT_SERIAL=emulator-5558',1,''],
      disconnected: ['CURRENT_SERIAL=""',1,''],
      wrong_id: ['DEVICE_ID=phone-1',1,''],
      back: ['return 10',10,''],
      cancelled: ['return 130',130,'']
    }
    cases.each do |name,(during_wait,expected_code,expected_id)|
      out,err,result=shell(<<~ZSH)
        ANDROID_RUN_AVD_IDENTITY=original
        CURRENT_IDENTITY=original
        CURRENT_SERIAL=emulator-5556
        DEVICE_ID=stale
        jobs_sim_android_avd_identity() { print -r -- "$CURRENT_IDENTITY"; }
        android_serial_for_avd() { REPLY="$CURRENT_SERIAL"; [[ -n "$REPLY" ]]; }
        wait_for_simulator_recognition() {
          DEVICE_ID="$1"
          #{during_wait}
          return 0
        }
        wait_for_android_avd TARGET
        print "RESULT=$? DEVICE=$DEVICE_ID"
      ZSH
      assert result.success?,"#{name}: #{out}#{err}"
      assert_includes out,"RESULT=#{expected_code} DEVICE=#{expected_id}\n",name.to_s
    end
  end

  def test_creation_timeout_prevents_late_avd_writes
    fake('cmdline-tools/latest/bin/avdmanager', <<~'ZSH')
      read -r answer
      [[ "$answer" == no ]] || exit 93
      /bin/sleep 4
      print LATE_AVD_WRITE > "$TRACE"
    ZSH
    out, err, result = shell(<<~'ZSH')
      run_bounded 1 "$LOG_FILE.create-timeout" create_android_avd_command Jobs_timeout "$IMAGE" pixel_9
      create_status=$?
      /bin/sleep 4
      print "CREATE_STATUS=$create_status"
      [[ ! -e "$TRACE" ]]
    ZSH
    assert result.success?, out + err
    assert_includes out, 'CREATE_STATUS=124'
    refute File.exist?(@trace), '创建器超时后仍继续写入 AVD'
  end

  def test_fzf_left_with_no_matching_rows_returns_parent
    picker = File.join(@tmp, 'fzf')
    File.write(picker, "#!/bin/zsh\n[[ \"$1\" != --version ]] || { print 0.68.0; exit 0; }\n[[ \"$*\" != *--filter=* ]] || { print probe; exit 0; }\ncat >/dev/null\nprint left\nexit 1\n")
    FileUtils.chmod(0o700, picker)
    out, err, result = shell(<<~ZSH)
      JOBS_FLUTTER_RUNNER_FZF=always
      FZF_BIN=#{picker.shellescape}
      ROWS=($'id\tModel')
      select_row Model 1 && print "ACTION=$REPLY"
    ZSH
    assert result.success?, err
    assert_includes out, 'ACTION=__back__'
  end
end
