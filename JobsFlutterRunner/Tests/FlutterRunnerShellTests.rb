# Created by Jobs on 2026年10月20日，星期二.
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
require 'timeout'
require 'pty'
require 'io/console'

class FlutterRunnerShellTests < Minitest::Test
  SCRIPT = ENV.fetch('JOBS_TEST_RUNNER_SCRIPT') { File.expand_path('../Scripts/RunFlutterProject.zsh', __dir__) }

  def setup
    @tmp = Dir.mktmpdir('jobs-flutter-runner-shell-')
    @library = File.join(@tmp, 'Runtime.zsh')
    FileUtils.mkdir_p([File.join(@tmp, 'android'), File.join(@tmp, 'ios')])
    File.write(@library, File.read(SCRIPT).sub(/\nmain "\$@"\s*\z/, "\n"))
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def shell(body, input: '', env: {})
    Open3.capture3({ 'HOME' => @tmp, 'NO_COLOR' => '1' }.merge(env), '/bin/zsh', '-f', '-c',
      "source #{@library.shellescape}\nPROJECT_PATH=#{@tmp.shellescape}\nLOG_FILE=#{File.join(@tmp, 'test.log').shellescape}\n: > \"$LOG_FILE\"\n" \
      "jobs_flutter_route_prepare() { return 0; }\n" \
      "jobs_flutter_fvm_runtime() { return 0; }\n" \
      "jobs_flutter_fvm_install() { install_project_fvm_sdk_once; }\n#{body}", stdin_data: input, chdir: @tmp)
  end

  def test_eof_at_first_confirmation_does_not_create_state
    out, err, result = Open3.capture3({ 'HOME' => @tmp, 'NO_COLOR' => '1' }, '/bin/zsh', SCRIPT,
      '--project', @tmp, stdin_data: '')
    assert result.success?, err
    assert_includes out, 'launchd'
    refute Dir.exist?(File.join(@tmp, 'Library'))
  end

  def test_simulator_failure_stops_without_selecting_another_phone
    out, err, result = shell(<<~'ZSH', input: "3\n1\n")
      refresh_devices() { print UNEXPECTED_PHONE_QUERY; ROWS=($'android-42\tPhone'); }
      load_simulator_start_environment() { return 0; }
      jobs_flutter_prepare_simulator_environment() { return 0; }
      select_ios_simulator() { return 7; }
      choose_device
      print -r -- "RESULT=$? DEVICE=$DEVICE_ID"
    ZSH
    assert result.success?, err
    assert_includes out, 'RESULT=7 DEVICE='
    refute_includes out, 'UNEXPECTED_PHONE_QUERY'
  end

  def test_device_refresh_option_and_selection
    out, err, result = shell(<<~'ZSH', input: "4\n2\n1\n")
      refresh_devices() { ROWS=($'android-42\tPhone — android'); }
      choose_device
      print -r -- "CHOSEN=$DEVICE_ID"
    ZSH
    assert result.success?, err
    assert_includes out, 'CHOSEN=android-42'
    assert_equal 2, out.scan('目前已有的设备：').length
  end

  def test_new_device_continues_directly_without_a_second_device_selection
    out, err, result = shell(<<~'ZSH', input: "2\n2\n")
      refresh_devices() { print UNEXPECTED_REFRESH; ROWS=($'phone-42\tPhone'); }
      run_simulator_creator() { print -r -- "CREATE=$1"; DEVICE_ID=emulator-5556; return 0; }
      choose_device
      print -r -- "CHOSEN=$DEVICE_ID"
    ZSH
    assert result.success?, err
    assert_includes out, 'CREATE=android'
    assert_includes out, 'CHOSEN=emulator-5556'
    refute_includes out, 'UNEXPECTED_REFRESH'
    refute_includes out, '目前已有的设备：'
    assert_equal 1, out.scan('CHOSEN=').length
  end

  def creator_fixture(contents)
    creator = File.join(@tmp, "Creator 中文 ' $(touch NEVER).zsh")
    File.write(creator, "#!/bin/zsh\n#{contents}\n")
    "simulator_creator_path() { REPLY=#{creator.shellescape}; }\n"
  end

  def test_creation_receipt_waits_for_exact_avd_before_running_once
    setup = creator_fixture("print -r -- $'android\\tTarget_AVD' > \"$JOBS_FLUTTER_CREATED_DEVICE_FILE\"")
    out, err, result = shell(setup + <<~'ZSH', input: "2\n2\n")
      resolve_android_tools() { print SDK_RESOLVED; }
      wait_for_android_avd() { print -r -- "WAIT=$1"; DEVICE_ID=emulator-5556; }
      choose_existing_device() { print UNEXPECTED_MENU; return 130; }
      choose_device
      print -r -- "RUN=$DEVICE_ID"
    ZSH
    assert result.success?, out + err
    assert_includes out, 'WAIT=Target_AVD'
    assert_includes out, 'RUN=emulator-5556'
    assert_equal 1, out.scan('RUN=').length
    refute_includes out, 'UNEXPECTED_MENU'
    refute File.exist?(File.join(@tmp, 'NEVER'))
    assert_empty Dir.glob(File.join(@tmp, 'test.log.created.*'))
  end

  def test_cancelled_creator_without_receipt_never_runs_an_existing_phone
    out, err, result = shell(creator_fixture('exit 0') + <<~'ZSH', input: "2\n2\n5\n")
      choose_existing_device() { print UNEXPECTED_MENU; DEVICE_ID=phone-42; }
      choose_device
      print UNEXPECTED_RUN
    ZSH
    assert result.success?, out + err
    assert_includes out, '未回传'
    refute_includes out, 'UNEXPECTED_MENU'
    refute_includes out, 'UNEXPECTED_RUN'
    assert_empty Dir.glob(File.join(@tmp, 'test.log.created.*'))
  end

  def test_malformed_creation_receipt_does_not_wait_or_run
    ["ios\\tOTHER", "android\\tTarget\\tOTHER", "android\\tTarget\\nandroid\\tOTHER"].each do |receipt|
      out, err, result = shell(creator_fixture("print -r -- $'#{receipt}' > \"$JOBS_FLUTTER_CREATED_DEVICE_FILE\"") + <<~'ZSH')
        wait_for_android_avd() { print UNEXPECTED_WAIT; }
        run_simulator_creator android || print STOPPED
      ZSH
      assert result.success?, out + err
      assert_includes out, '回执无效'
      assert_includes out, 'STOPPED'
      refute_includes out, 'UNEXPECTED_WAIT'
    end
  end

  def test_creation_for_an_unsupported_project_platform_preserves_device_without_running
    setup = creator_fixture("print -r -- $'harmony\\t127.0.0.1:12345' > \"$JOBS_FLUTTER_CREATED_DEVICE_FILE\"")
    out, err, result = shell(setup + <<~'ZSH', input: "2\n3\n5\n")
      wait_for_simulator_recognition() { print UNEXPECTED_WAIT; }
      choose_device
      print UNEXPECTED_RUN
    ZSH
    assert result.success?, out + err
    assert_includes out, '没有 ohos 平台'
    refute_includes out, 'UNEXPECTED_WAIT'
    refute_includes out, 'UNEXPECTED_RUN'
  end

  def test_wait_failure_never_enters_flutter_run
    setup = creator_fixture("print -r -- $'android\\tTarget_AVD' > \"$JOBS_FLUTTER_CREATED_DEVICE_FILE\"")
    out, err, result = shell(setup + <<~'ZSH', input: "2\n2\n5\n")
      resolve_android_tools() { return 0; }
      wait_for_android_avd() { print BOOT_FAILED; return 1; }
      choose_device
      print UNEXPECTED_RUN
    ZSH
    assert result.success?, out + err
    assert_includes out, 'BOOT_FAILED'
    refute_includes out, 'UNEXPECTED_RUN'
  end

  def test_return_from_new_group_then_existing_does_not_create
    out, err, result = shell(<<~'ZSH', input: "2\n4\n1\n1\n")
      refresh_devices() { ROWS=($'phone-42\tPhone'); }
      run_simulator_creator() { print UNEXPECTED_CREATE; }
      choose_device
      print -r -- "CHOSEN=$DEVICE_ID"
    ZSH
    assert result.success?, err
    assert_includes out, 'CHOSEN=phone-42'
    refute_includes out, 'UNEXPECTED_CREATE'
  end

  def test_creator_failure_returns_to_groups_without_running_or_refreshing
    out, err, result = shell(<<~'ZSH', input: "2\n3\n5\n")
      refresh_devices() { print UNEXPECTED_REFRESH; ROWS=($'phone-42\tPhone'); }
      run_simulator_creator() { print CREATE_FAILED; return 7; }
      choose_device
      print UNEXPECTED_RUN
    ZSH
    assert result.success?, err
    assert_includes out, 'CREATE_FAILED'
    refute_includes out, 'UNEXPECTED_REFRESH'
    refute_includes out, 'UNEXPECTED_RUN'
  end

  def test_group_cancel_does_not_query_or_create_devices
    ["5\n", "1\n\n", "2\n5\n", "3\n5\n"].each do |input|
      out, err, result = shell(<<~'ZSH', input: input)
        refresh_devices() { ROWS=(); }
        run_simulator_creator() { print UNEXPECTED_CREATE; }
        choose_device
        print UNEXPECTED_RUN
      ZSH
      assert result.success?, err
      refute_includes out, 'UNEXPECTED_CREATE'
      refute_includes out, 'UNEXPECTED_RUN'
    end
  end

  def test_existing_ios_empty_inventory_does_not_create
    out, err, result = shell(<<~'ZSH')
      read_simulator_inventory() { return 0; }
      json_helper() { return 0; }
      create_simulator() { print UNEXPECTED_CREATE; }
      select_ios_simulator existing || print EMPTY
    ZSH
    assert result.success?, err
    assert_includes out, 'EMPTY'
    refute_includes out, 'UNEXPECTED_CREATE'
  end

  def test_existing_android_empty_inventory_does_not_create
    out, err, result = shell(<<~'ZSH')
      resolve_android_tools() { return 0; }
      read_android_avds() { ROWS=(); }
      create_android_emulator() { print UNEXPECTED_CREATE; }
      start_android_emulator existing || print EMPTY
    ZSH
    assert result.success?, err
    assert_includes out, 'EMPTY'
    refute_includes out, 'UNEXPECTED_CREATE'
  end

  def test_packaged_creator_runs_literal_path_and_preserves_failure
    assets = File.join(@tmp, "Tools 中文 ' $(touch NEVER)")
    %w[ios android harmony].each do |platform|
      standalone_name = { 'ios' => 'CreateIOSSimulator.zsh', 'android' => 'CreateAndroidSimulator.zsh', 'harmony' => 'CreateHarmonySimulator.zsh' }.fetch(platform)
      relative = if SCRIPT.include?('Scripts/Tools/')
                   platform == 'harmony' ? 'SetupCreateHarmonySimulator.zsh/SetupCreateHarmonySimulator.zsh' : "Setup#{standalone_name}"
                 else
                   "SimulatorCreators/#{standalone_name}/#{standalone_name}"
                 end
      creator = File.join(assets, relative)
      FileUtils.mkdir_p(File.dirname(creator))
      File.write(creator, "#!/bin/zsh\nprint -r -- \"ARGS=$*\"\nexit 7\n")
      out, err, result = shell(<<~ZSH)
        SCRIPT_DIR=#{assets.shellescape}
        result=0
        run_simulator_creator #{platform} || result=$?
        print -r -- "RESULT=$result"
      ZSH
      assert result.success?, err
      assert_includes out, "ARGS=#{platform == 'ios' ? '' : '--create'}"
      assert_includes out, 'RESULT=7'
      refute File.exist?(File.join(@tmp, 'NEVER'))
    end
  end

  def test_invalid_number_can_retry_and_cancel
    out, err, result = shell(<<~'ZSH', input: "999\ntext\n\n")
      ROWS=($'unique-id\tDevice')
      select_row '设备' && print 'BAD'
      print 'CANCELLED'
    ZSH
    assert result.success?, err
    assert_includes out, 'CANCELLED'
    refute_includes out, 'BAD'
    assert_equal 2, out.scan('编号无效').length
  end

  def test_fzf_selection_returns_hidden_identifier
    fake = File.join(@tmp, 'fakefzf')
    File.write(fake, <<~'ZSH')
      #!/bin/zsh
      [[ "$1" != --version ]] || { print 0.68.0; exit 0; }
      [[ "$*" != *--filter=* ]] || { print probe; exit 0; }
      [[ "$1" != --help ]] || { print -- '--bind --expect --with-nth --no-height'; exit 0; }
      lines=()
      while IFS= read -r line; do
        [[ -n "$FZF_CAPTURE" ]] && print -r -- "$line" >> "$FZF_CAPTURE"
        lines+=("$line")
      done
      print -r -- "${lines[2]}"
    ZSH
    FileUtils.chmod(0o700, fake)
    capture = File.join(@tmp, 'fzf-input')
    out, err, result = shell(<<~ZSH, env: { 'JOBS_FLUTTER_RUNNER_FZF' => 'always', 'FZF_CAPTURE' => capture })
      FZF_BIN=#{fake.shellescape}
      ROWS=($'ios-sim\tiOS 模拟器' $'mac-1\tmacOS — darwin')
      select_row '选择 Flutter 运行设备：' && print -r -- "PICK=$REPLY"
    ZSH
    assert result.success?, err
    assert_includes out, 'PICK=mac-1'
    # 整行传给 fzf，界面靠 --with-nth 隐藏标识列，回取值仍是原始 id。
    assert_includes File.read(capture), "mac-1\tmacOS — darwin"
  end

  def test_fzf_user_defaults_cannot_change_selection_or_parent_environment
    fake = File.join(@tmp, 'strictfzf')
    File.write(fake, <<~'ZSH')
      #!/bin/zsh
      [[ "$1" != --version ]] || { print 0.68.0; exit 0; }
      [[ "$*" != *--filter=* ]] || { print probe; exit 0; }
      [[ "$1" != --help ]] || { print -- '--bind --expect --with-nth --no-height'; exit 0; }
      if [[ -n "${FZF_DEFAULT_OPTS+x}" || -n "${FZF_DEFAULT_OPTS_FILE+x}" ]]; then
        print -ru2 -- 'unexpected inherited fzf default options'
        exit 41
      fi
      lines=()
      while IFS= read -r line; do lines+=("$line"); done
      print -r -- "${lines[1]}"
    ZSH
    FileUtils.chmod(0o700, fake)
    options_file = File.join(@tmp, '个人 fzf 选项.conf')
    File.write(options_file, "--tac\n--multi\n")
    out, err, result = shell(<<~ZSH, env: { 'JOBS_FLUTTER_RUNNER_FZF' => 'always', 'FZF_DEFAULT_OPTS' => '--tac --multi', 'FZF_DEFAULT_OPTS_FILE' => options_file })
      FZF_BIN=#{fake.shellescape}
      ROWS=($'ios-sim\tiOS 模拟器' $'mac-1\tmacOS — darwin')
      select_row '选择 Flutter 运行设备：' && print -r -- "PICK=$REPLY"
      print -r -- "PARENT|${FZF_DEFAULT_OPTS}"
    ZSH
    assert result.success?, err
    assert_includes out, 'PICK=ios-sim'
    assert_includes out, 'PARENT|--tac --multi'
  end

  def test_fzf_cancel_is_treated_as_cancellation
    fake = File.join(@tmp, 'fakefzf-cancel')
    File.write(fake, "#!/bin/zsh\n[[ \"$1\" != --version ]] || { print 0.68.0; exit 0; }\n[[ \"$*\" != *--filter=* ]] || { print probe; exit 0; }\n[[ \"$1\" != --help ]] || { print -- '--bind --expect --with-nth --no-height'; exit 0; }\ncat >/dev/null\nexit 130\n")
    FileUtils.chmod(0o700, fake)
    out, err, result = shell(<<~ZSH, env: { 'JOBS_FLUTTER_RUNNER_FZF' => 'always' })
      FZF_BIN=#{fake.shellescape}
      ROWS=($'ios-sim\tiOS 模拟器' $'mac-1\tmacOS — darwin')
      select_row '选择 Flutter 运行设备：' || print 'CANCELLED'
    ZSH
    assert result.success?, err
    assert_includes out, 'CANCELLED'
    refute_includes out, '编号无效'
  end

  # 真实 fzf 的备用屏幕与清理协议不能由假 fzf 的参数断言代替。
  def real_fzf_terminal(setup: '', invocation: "select_row 'Choose device: '", ready: ['Alpha device', 'Beta device'])
    fzf = ['/opt/homebrew/bin/fzf', '/usr/local/bin/fzf'].find { |path| File.executable?(path) }
    skip '需要已安装的 fzf 执行真实 PTY 回归' unless fzf
    carrier = File.join(@tmp, 'menu-tty.zsh')
    File.write(carrier, <<~ZSH)
      source #{@library.shellescape}
      LOG_FILE=#{File.join(@tmp, 'tty.log').shellescape}
      FZF_BIN=#{fzf.shellescape}
      ROWS=($'alpha\\tAlpha device' $'beta\\tBeta device')
      #{setup}
      if #{invocation}; then
        print -r -- "PICK=$REPLY"
      else
        print 'CANCELLED'
      fi
    ZSH
    transcript = ''.b
    PTY.spawn({ 'TERM' => 'xterm-256color', 'NO_COLOR' => '1' }, '/bin/zsh', '-f', carrier) do |reader, writer, pid|
      writer.winsize = [68, 234]
      read_until = lambda do |&condition|
        until condition.call(transcript)
          chunk = reader.readpartial(65_536)
          transcript << chunk
          # PTY 没有终端模拟器，按 fzf 请求回复光标位置。
          queries = chunk.scan("\e[6n").length
          writer.write("\e[1;1R" * queries) if queries.positive?
        end
      end
      begin
        Timeout.timeout(8) do
          read_until.call { |text| ready.all? { |label| text.include?(label.b) } }
          yield writer, read_until, transcript
          loop { transcript << reader.readpartial(65_536) }
        end
      rescue EOFError, Errno::EIO
        # macOS PTY 在子进程关闭后返回 EIO。
      ensure
        begin
          # PTY 子进程是独立进程组长，只清理本次 Shell 和同组 fzf。
          if Process.getpgid(pid) == pid
            Process.kill('TERM', -pid)
            begin
              Timeout.timeout(1) do
                loop do
                  begin
                    Process.waitpid(pid, Process::WNOHANG)
                  rescue Errno::ECHILD
                    nil
                  end
                  Process.kill(0, -pid)
                  sleep 0.02
                end
              end
            rescue Timeout::Error
              Process.kill('KILL', -pid)
            end
          end
        rescue Errno::ESRCH
          nil
        end
        begin
          Timeout.timeout(1) { Process.waitpid(pid) }
        rescue Errno::ECHILD
          nil
        end
      end
    end
    transcript
  end

  def test_real_fzf_resize_and_filter_restores_original_terminal_screen
    transcript = real_fzf_terminal do |writer, read_until, _text|
      writer.winsize = [24, 80]
      writer.write('Beta')
      read_until.call { |text| text.include?('1/2') }
      writer.write("\r")
    end
    assert_includes transcript, "\e[?1049h", '菜单必须在备用屏幕绘制，避免原日志屏留下旧菜单'
    assert_includes transcript, "\e[?1049l", '选择后必须恢复原日志屏幕'
    assert_includes transcript, 'PICK=beta'
    refute_includes transcript, 'PICK=alpha'
  end

  def test_real_fzf_cancel_restores_original_terminal_screen
    transcript = real_fzf_terminal { |writer, _read_until, _text| writer.write("\e") }
    assert_includes transcript, "\e[?1049h"
    assert_includes transcript, "\e[?1049l"
    assert_includes transcript, 'CANCELLED'
    refute_includes transcript, 'PICK='
  end

  def test_real_fzf_group_navigation_with_left_and_enter
    setup = <<~ZSH
      PROJECT_PATH=#{@tmp.shellescape}
      refresh_devices() { ROWS=($'phone-fixture\\tPhone fixture'); }
      run_simulator_creator() { print UNEXPECTED_CREATE; return 7; }
    ZSH
    transcript = real_fzf_terminal(setup: setup, invocation: 'choose_device', ready: ['目前已有的设备', '新建设备']) do |writer, read_until, text|
      writer.write("\e[B\r")
      read_until.call { |text| text.include?('新建 Harmony'.b) }
      previous = text.scan('目前已有的设备（'.b).length
      writer.write("\e[D")
      read_until.call { |text| text.scan('目前已有的设备（'.b).length > previous }
      writer.write("\r")
      read_until.call { |text| text.include?('Phone fixture'.b) }
      writer.write("\r")
    end
    assert transcript.include?('PICK=phone-fixture'), '真实 fzf 分组往返后应选中原始设备 ID'
    refute_includes transcript, 'UNEXPECTED_CREATE'
  end

  def test_cancel_existing_simulator_picker_cancels_run
    out, err, result = shell(<<~'ZSH', input: "3\n1\n")
      refresh_devices() { ROWS=($'phone-42\tPhone'); }
      load_simulator_start_environment() { return 0; }
      jobs_flutter_prepare_simulator_environment() { return 0; }
      select_ios_simulator() { return 130; }
      choose_device
      print UNEXPECTED_RUN
    ZSH
    assert result.success?, err
    refute_includes out, 'UNEXPECTED_RUN'
  end

  def test_fvm_project_never_falls_back_to_global_flutter
    File.write(File.join(@tmp, '.fvmrc'), '{"flutter":"3.24.0"}')
    out, _err, result = shell("PROJECT_PATH=#{@tmp.shellescape}\nfind_flutter")
    refute result.success?
    assert_includes out, '项目 FVM SDK 未就绪'
  end

  def test_untrusted_project_is_rechecked_before_worker
    session = File.join(@tmp, 'session')
    FileUtils.mkdir_p(session)
    system('/usr/bin/mkfifo', File.join(session, 'control.fifo'), exception: true)
    out, err, result = shell(<<~ZSH)
      json_helper() { print false; }
      run_worker #{session.shellescape} #{@tmp.shellescape} /usr/bin/true device-1
    ZSH
    assert_equal 65, result.exitstatus, err
    assert_includes out, '项目身份已变化'
    assert_equal "65\n", File.read(File.join(session, 'exitcode'))
  end

  def test_worker_holds_stdin_open_without_terminal_and_records_result
    session = File.join(@tmp, 'worker session 中文')
    FileUtils.mkdir_p(session)
    system('/usr/bin/mkfifo', File.join(session, 'control.fifo'), exception: true)
    mock = File.join(@tmp, 'mock flutter')
    File.write(mock, <<~'ZSH')
      #!/bin/zsh
      [[ "$*" == 'run --machine -d device-1' ]] || exit 71
      [[ ! -t 0 ]] || exit 72
      /usr/bin/ruby -rfcntl -e 'exit((STDIN.fcntl(Fcntl::F_GETFL) & Fcntl::O_ACCMODE) == Fcntl::O_RDONLY ? 0 : 75)' || exit 75
      IFS= read -r request || exit 73
      [[ "$request" == '[{"method":"test"}]' ]] || exit 74
      print 'MOCK_RUNNING'
      exit 7
    ZSH
    FileUtils.chmod(0o700, mock)
    out, err, result = shell(<<~ZSH)
      json_helper() { print true; }
      ( /bin/sleep 0.2; print -r -- '[{"method":"test"}]' > #{File.join(session, 'control.fifo').shellescape} ) &
      run_worker #{session.shellescape} #{@tmp.shellescape} #{mock.shellescape} device-1
    ZSH
    assert_equal 7, result.exitstatus, err
    assert_includes out, 'MOCK_RUNNING'
    assert_equal "7\n", File.read(File.join(session, 'exitcode'))
  end

  def test_lock_releases_when_owner_exits
    lock = File.join(@tmp, 'start.lock')
    File.write(lock, '')
    2.times do
      _out, err, result = shell("zmodload zsh/system\nzsystem flock -t 0 -f runner_fd #{lock.shellescape}")
      assert result.success?, err
    end
  end

  def test_control_uses_data_and_does_not_block_without_worker_reader
    session = File.join(@tmp, 'session')
    FileUtils.mkdir_p(session)
    system('/usr/bin/mkfifo', File.join(session, 'control.fifo'), exception: true)
    out, err, result = shell(<<~ZSH)
      SESSION_DIR=#{session.shellescape}
      session_live() { return 0; }
      json_helper() { print -r -- '[{"id":1,"method":"app.stop"}]'; }
      send_control stop
      print 'SENT'
    ZSH
    assert result.success?, err
    assert_includes out, 'SENT'
  end

  def test_bounded_command_failure_returns_actual_status
    out, err, result = shell(<<~ZSH)
      run_bounded 3 #{File.join(@tmp, 'bounded.log').shellescape} /bin/zsh -c 'print diagnostic; exit 9'
      print -r -- "RESULT=$?"
    ZSH
    assert result.success?, err
    assert_includes out, 'RESULT=9'
    refute_includes out, 'diagnostic'
    assert_equal "diagnostic\n", File.read(File.join(@tmp, 'bounded.log'))
  end

  def test_bounded_stream_preserves_progress_bytes_and_command_failure
    output = File.join(@tmp, 'download 中文.log')
    out, err, result = shell(<<~ZSH)
      RUN_BOUNDED_STREAM=1 run_bounded 5 #{output.shellescape} /bin/zsh -c 'printf "10%%\\r20%%\\r"; printf "下载失败" >&2; exit 9'
      print -r -- "RESULT=$? FD=$QUERY_PROGRESS_FD"
    ZSH
    assert result.success?, err
    expected = "10%\r20%\r下载失败"
    assert_includes out, expected
    assert_includes out, "RESULT=9 FD=\n"
    assert_equal expected.b, File.binread(output)
  end

  def test_bounded_stream_is_visible_before_command_finishes
    output = File.join(@tmp, 'live.log')
    release = File.join(@tmp, 'release')
    command = <<~ZSH
      source #{@library.shellescape}
      LOG_FILE=#{File.join(@tmp, 'test.log').shellescape}
      RUN_BOUNDED_STREAM=1 run_bounded 8 #{output.shellescape} /bin/zsh -c 'printf "15%%\\r"; while [[ ! -f "$1" ]]; do /bin/sleep 0.1; done; printf "100%%\\n"' fixture #{release.shellescape}
    ZSH
    Open3.popen3({ 'HOME' => @tmp, 'NO_COLOR' => '1' }, '/bin/zsh', '-f', '-c', command) do |input, stdout, stderr, process|
      input.close
      progress = Timeout.timeout(5) { stdout.readpartial(1024) }
      assert_includes progress, "15%\r"
      assert process.alive?, '下载结束前必须已显示首批进度'
      File.write(release, '')
      remaining = stdout.read
      assert_includes remaining, "100%\n"
      assert process.value.success?, stderr.read
    end
    assert_equal "15%\r100%\n", File.read(output)
  end

  def test_bounded_stream_timeout_keeps_progress_and_closes_reader
    output = File.join(@tmp, 'timeout.log')
    out, err, result = shell(<<~ZSH)
      RUN_BOUNDED_STREAM=1 run_bounded 1 #{output.shellescape} /bin/zsh -c 'printf "30%%\\r"; exec /bin/sleep 10'
      print -r -- "RESULT=$? FD=$QUERY_PROGRESS_FD PID=$QUERY_PID"
    ZSH
    assert result.success?, err
    assert_includes out, "30%\r"
    assert_includes out, "RESULT=124 FD= PID=\n"
    assert_includes out, "详情：#{output}"
    assert_equal "30%\r", File.read(output)
  end

  def test_prepare_project_fvm_sdk_streams_install_and_use_output
    version = '3.99.0'
    project = File.join(@tmp, 'project 中文')
    fake = File.join(@tmp, 'fake fvm')
    FileUtils.mkdir_p(File.join(project, '.fvm'))
    File.write(File.join(project, '.fvmrc'), %({"flutter":"#{version}"}))
    File.write(fake, <<~'ZSH')
      #!/bin/zsh
      [[ "$1" != --version ]] || { print 0.68.0; exit 0; }
      [[ "$*" != *--filter=* ]] || { print probe; exit 0; }
      [[ "$1" != --help ]] || { print -- '--bind --expect --with-nth --no-height'; exit 0; }
      case "$1" in
        install)
          printf 'DOWNLOAD 25%%\rDOWNLOAD 100%%\n'
          mkdir -p "$HOME/fvm/versions/$2/bin"
          print '#!/bin/zsh' > "$HOME/fvm/versions/$2/bin/flutter"
          chmod +x "$HOME/fvm/versions/$2/bin/flutter"
          ;;
        use)
          printf 'LINK READY\n' >&2
          ln -s "$HOME/fvm/versions/$2" .fvm/flutter_sdk
          ;;
        *) exit 71 ;;
      esac
    ZSH
    File.chmod(0o700, fake)
    out, err, result = shell(<<~ZSH, input: "\n")
      PROJECT_PATH=#{project.shellescape}
      cd "$PROJECT_PATH"
      JOBS_FVM_BIN=#{fake.shellescape}
      json_helper() { [[ "$1" != fvm-version ]] || print -r -- '#{version}'; }
      prepare_project_fvm_sdk || exit 1
      print -r -- "READY=$REPLY"
    ZSH
    assert result.success?, err
    assert_includes out, "DOWNLOAD 25%\rDOWNLOAD 100%\n"
    assert_includes out, "LINK READY\n"
    assert_includes out, '✔ FVM SDK 已就绪'
    assert_equal "DOWNLOAD 25%\rDOWNLOAD 100%\n", File.read(File.join(@tmp, 'test.log.fvminstall'))
    assert_equal "LINK READY\n", File.read(File.join(@tmp, 'test.log.fvmuse'))
  end

  def test_find_flutter_streams_bootstrap_download_from_existing_sdk
    sdk = File.join(@tmp, 'sdk')
    FileUtils.mkdir_p([File.join(sdk, 'bin'), File.join(@tmp, '.fvm')])
    File.write(File.join(@tmp, '.fvmrc'), '{"flutter":"fixture"}')
    FileUtils.ln_s(sdk, File.join(@tmp, '.fvm/flutter_sdk'))
    flutter = File.join(sdk, 'bin/flutter')
    File.write(flutter, <<~'ZSH')
      #!/bin/zsh
      case "$*" in
        --version)
          printf 'Downloading Dart SDK 20%%\rDownloading Dart SDK 100%%\n' >&2
          print 'Flutter fixture' ;;
        'precache --universal') print 'Downloading common SDK 100%' ;;
        *) exit 71 ;;
      esac
    ZSH
    File.chmod(0o700, flutter)
    out, err, result = shell('find_flutter')
    assert result.success?, err
    assert_includes out, "Downloading Dart SDK 20%\rDownloading Dart SDK 100%\n"
    assert_includes out, 'Flutter fixture'
    assert_includes out, '首次执行可能下载组件'
    assert_equal "Downloading Dart SDK 20%\rDownloading Dart SDK 100%\nFlutter fixture\n", File.read(File.join(@tmp, 'test.log.version'))
    assert_includes out, 'Downloading common SDK 100%'
    assert_equal "Downloading common SDK 100%\n", File.read(File.join(@tmp, 'test.log.discovery-sdk'))
  end

  def test_discovery_sdk_uses_routed_visible_long_acquisition_before_devices
    out, err, result = shell(<<~'ZSH')
      FLUTTER_BIN=/fixture/sdk/bin/flutter
      json_helper() { [[ "$1" == universal-ready ]] && print false; }
      jobs_flutter_sdk_retry() {
        [[ "$JOBS_FLUTTER_ROUTE_MODE" == platform && "$RUN_BOUNDED_STREAM" == 1 && "$JOBS_SDK_LOG_REPLACED" == 1 ]] || return 72
        shift 4
        "$@"
      }
      run_bounded() {
        [[ "$1" == 1800 && "$3" == "$FLUTTER_BIN" && "$4" == precache && "$5" == --universal && $# == 5 ]] || return 73
        print 'PUBLIC_CACHE_READY'
      }
      prepare_device_discovery_sdk || exit $?
      print 'DEVICE_DISCOVERY_ALLOWED'
    ZSH
    assert result.success?, err
    assert_match(/PUBLIC_CACHE_READY.*DEVICE_DISCOVERY_ALLOWED/m, out)
  end

  def test_warm_discovery_sdk_needs_no_network_or_sdk_process
    out, err, result = shell(<<~'ZSH')
      FLUTTER_BIN=/fixture/sdk/bin/flutter
      json_helper() { [[ "$1" == universal-ready ]] && print true; }
      jobs_flutter_sdk_retry() { print 'UNEXPECTED_NETWORK'; return 74; }
      run_bounded() { print 'UNEXPECTED_SDK'; return 75; }
      prepare_device_discovery_sdk || exit $?
    ZSH
    assert result.success?, err
    assert_includes out, '复用本地组件'
    refute_includes out, 'UNEXPECTED'
  end

  def test_failed_discovery_sdk_preparation_blocks_device_discovery
    out, err, result = shell(<<~'ZSH')
      FLUTTER_BIN=/fixture/sdk/bin/flutter
      json_helper() { print false; }
      jobs_flutter_sdk_retry() { return 130; }
      prepare_device_discovery_sdk || exit $?
      print 'UNEXPECTED_DEVICES'
    ZSH
    assert_equal 130, result.exitstatus, err
    refute_includes out, 'UNEXPECTED_DEVICES'
  end

  def test_discovery_sdk_retry_keeps_each_completed_attempt
    out, err, result = shell(<<~'ZSH')
      FLUTTER_BIN=/fixture/sdk/bin/flutter
      json_helper() { print false; }
      integer downloads=0
      run_bounded() {
        (( downloads += 1 ))
        print -r -- "DOWNLOAD_ATTEMPT=$downloads" > "$2"
        (( downloads > 1 ))
      }
      prepare_device_discovery_sdk || exit $?
      print 'DEVICE_DISCOVERY_ALLOWED'
    ZSH
    assert result.success?, err
    assert_includes out, 'DEVICE_DISCOVERY_ALLOWED'
    history = File.read(File.join(@tmp, 'test.log.discovery-sdk.attempts.log'))
    assert_includes history, 'DOWNLOAD_ATTEMPT=1'
    assert_includes history, 'DOWNLOAD_ATTEMPT=2'
    assert_includes history, '退出码 1'
    assert_includes history, '退出码 0'
  end

  def test_missing_ios_simulator_creates_selected_type_and_runtime
    out, err, result = shell(<<~'ZSH', input: "1\n1\n\n")
      json_helper() {
        case "$1" in
          preferred-types) print -r -- $'com.apple.CoreSimulator.SimDeviceType.iPhone-16\tiPhone 16' ;;
          compatible-runtimes) print -r -- $'com.apple.CoreSimulator.SimRuntime.iOS-18-0\tiOS 18.0' ;;
          runtimes) print -r -- $'com.apple.CoreSimulator.SimRuntime.iOS-18-0\tiOS 18.0' ;;
          unique-name) print -r -- "$3" ;;
        esac
      }
      run_bounded() {
        [[ "$4" == simctl && "$5" == create ]] || return 0
        [[ "$3" == /usr/bin/xcrun && "$7" == com.apple.CoreSimulator.SimDeviceType.iPhone-16 && "$8" == com.apple.CoreSimulator.SimRuntime.iOS-18-0 ]] || return 74
        print -r -- "NAME=$6"
        print '01234567-89AB-CDEF-0123-456789ABCDEF' > "$2"
      }
      create_simulator || exit 1
      print -r -- "CREATED=$REPLY"
    ZSH
    assert result.success?, err
    assert_includes out, 'CREATED=01234567-89AB-CDEF-0123-456789ABCDEF'
    assert_equal 1, out.scan('选择模拟器设备型号').length
    # 与独立初始化脚本同款：型号名@年.月.日 时:分:秒-进程号
    assert_match(/\ANAME=iPhone 16@\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2}-\d+\z/, out.lines.grep(/\ANAME=/).first.to_s.chomp)
  end

  def test_created_simulator_name_uses_model_time_and_pid
    out, err, result = shell(<<~'ZSH', input: "1\n1\n\n")
      json_helper() {
        case "$1" in
          preferred-types) print -r -- $'type-a\tiPhone 18 Pro' ;;
          compatible-runtimes) print -r -- $'runtime-a\tiOS 27.0' ;;
          runtimes) print -r -- $'runtime-a\tiOS 27.0' ;;
          unique-name) print -r -- "$3" ;;
        esac
      }
      run_bounded() {
        [[ "$4" == simctl && "$5" == create ]] || return 0
        print -r -- "BASE=$6"
        print '01234567-89AB-CDEF-0123-456789ABCDEF' > "$2"
      }
      create_simulator || exit 1
    ZSH
    assert result.success?, err
    base = out.lines.grep(/\ABASE=/).first.to_s.chomp.sub('BASE=', '')
    assert_match(/\AiPhone 18 Pro@\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2}-\d+\z/, base)
    refute_includes base, 'Jobs Flutter'
  end

  def test_simulator_name_failure_stops_before_create
    out, _err, result = shell(<<~'ZSH', input: "1\n1\n\n")
      json_helper() {
        case "$1" in
          preferred-types) print -r -- $'type-a\tiPhone' ;;
          compatible-runtimes) print -r -- $'runtime-a\tiOS' ;;
          runtimes) print -r -- $'runtime-a\tiOS' ;;
          unique-name) return 1 ;;
        esac
      }
      run_bounded() { [[ "$4" == simctl && "$5" == create ]] || return 0; print 'UNEXPECTED_CREATE'; return 1; }
      create_simulator
    ZSH
    refute result.success?
    assert_includes out, '无法确认唯一的模拟器名称'
    refute_includes out, 'UNEXPECTED_CREATE'
  end

  def test_missing_ios_runtime_stops_before_any_create
    out, _err, result = shell(<<~'ZSH', input: "1\n")
      json_helper() { [[ "$1" != preferred-types ]] || print -r -- $'type-1\tiPhone'; [[ "$1" != unique-name ]] || print -r -- "$3"; }
      run_bounded() { print 'UNEXPECTED_CREATE'; return 1; }
      create_simulator
    ZSH
    refute result.success?
    assert_includes out, '没有可用的 iOS Runtime'
    refute_includes out, 'UNEXPECTED_CREATE'
  end

  def test_model_without_matching_runtime_stops_on_enter
    out, err, result = shell(<<~'ZSH', input: "1\n\n")
      json_helper() {
        case "$1" in
          preferred-types) print -r -- $'type-1\tiPhone'; ;;
          runtimes) print -r -- $'runtime-1\tiOS'; ;;
          unique-name) print -r -- "$3" ;;
          compatible-runtimes) ;;
        esac
      }
      run_bounded() { print 'UNEXPECTED_CREATE'; return 1; }
      create_simulator
      print -r -- "RESULT=$?"
    ZSH
    assert result.success?, err
    assert_includes out, '没有可搭配的已安装 iOS 系统'
    assert_includes out, 'RESULT=1'
    refute_includes out, 'UNEXPECTED_CREATE'
    assert_equal 1, out.scan('选择模拟器设备型号').length
  end

  def test_ios_incompatible_combination_only_reselects_with_explicit_r
    out, err, result = shell(<<~'ZSH', input: "1\n1\n\nr\n1\n1\n\n")
      json_helper() { [[ "$1" != unique-name ]] || print -r -- "$3"; [[ "$1" == unique-name ]] || print -r -- $'fixture-id\tfixture'; }
      integer attempts=0
      run_bounded() {
        [[ "$4" == simctl && "$5" == create ]] || return 0
        (( attempts += 1 ))
        if (( attempts == 1 )); then
          print -r -- 'Incompatible device' > "$2"
          return 7
        fi
        print -r -- '01234567-89AB-CDEF-0123-456789ABCDEF' > "$2"
      }
      create_simulator || exit 1
      print -r -- "CREATED=$REPLY ATTEMPTS=$attempts"
    ZSH
    assert result.success?, err
    assert_includes out, 'CREATED=01234567-89AB-CDEF-0123-456789ABCDEF ATTEMPTS=2'
    assert_equal 2, out.scan('选择模拟器设备型号').length
  end

  def test_ios_enter_after_incompatible_does_not_reselect
    out, err, result = shell(<<~'ZSH', input: "1\n1\n\n\n")
      json_helper() { [[ "$1" != unique-name ]] || print -r -- "$3"; [[ "$1" == unique-name ]] || print -r -- $'fixture-id\tfixture'; }
      run_bounded() { [[ "$4" == simctl && "$5" == create ]] || return 0; print -r -- 'Incompatible device' > "$2"; return 7; }
      create_simulator
      print -r -- "RESULT=$?"
    ZSH
    assert result.success?, err
    assert_includes out, '组合不受支持'
    assert_includes out, 'RESULT=1'
    assert_equal 1, out.scan('选择模拟器设备型号').length
  end

  def test_ios_generic_create_failure_is_not_treated_as_incompatible
    out, err, result = shell(<<~'ZSH', input: "1\n1\n\n")
      json_helper() { [[ "$1" != unique-name ]] || print -r -- "$3"; [[ "$1" == unique-name ]] || print -r -- $'fixture-id\tfixture'; }
      run_bounded() { [[ "$4" == simctl && "$5" == create ]] || return 0; print -r -- 'Unable to create a device for device type' > "$2"; return 7; }
      create_simulator
      print -r -- "RESULT=$?"
    ZSH
    assert result.success?, err
    assert_includes out, '创建失败'
    assert_includes out, 'RESULT=1'
    refute_includes out, '组合不受支持'
    assert_equal 1, out.scan('选择模拟器设备型号').length
  end

  def test_simulator_interface_path_prefers_xcode_27_device_hub_layout
    out, err, result = shell(<<~ZSH)
      local root=#{File.join(@tmp, 'Xcode27.app').shellescape}
      mkdir -p "$root/Contents/Applications/DeviceHub.app" "$root/Contents/Developer/usr/bin"
      simulator_interface_path "$root/Contents/Developer" || print 'NOT_FOUND'
      print -r -- "APP=$REPLY"
    ZSH
    assert result.success?, err
    assert_includes out, "APP=#{File.join(@tmp, 'Xcode27.app/Contents/Applications/DeviceHub.app')}"
  end

  def test_simulator_interface_path_falls_back_to_legacy_simulator_app
    out, err, result = shell(<<~ZSH)
      local root=#{File.join(@tmp, 'Xcode15.app').shellescape}
      mkdir -p "$root/Contents/Developer/Applications/Simulator.app" "$root/Contents/Developer/usr/bin"
      simulator_interface_path "$root/Contents/Developer" || print 'NOT_FOUND'
      print -r -- "APP=$REPLY"
    ZSH
    assert result.success?, err
    assert_includes out, "APP=#{File.join(@tmp, 'Xcode15.app/Contents/Developer/Applications/Simulator.app')}"
  end

  def test_simulator_interface_path_rejects_xcode_without_any_interface
    out, err, result = shell(<<~ZSH)
      local root=#{File.join(@tmp, 'Bare.app').shellescape}
      mkdir -p "$root/Contents/Developer/usr/bin"
      simulator_interface_path "$root/Contents/Developer"
      print -r -- "RESULT=$?"
    ZSH
    assert result.success?, err
    assert_includes out, 'RESULT=1'
  end

  def test_prepare_project_fvm_sdk_uses_ready_link_without_touching
    sdk = File.join(@tmp, 'sdk')
    project = File.join(@tmp, 'project')
    FileUtils.mkdir_p(File.join(sdk, 'bin'))
    File.write(File.join(sdk, 'bin', 'flutter'), "#!/bin/zsh\nexit 0\n")
    File.chmod(0o755, File.join(sdk, 'bin', 'flutter'))
    FileUtils.mkdir_p(File.join(project, '.fvm'))
    FileUtils.ln_s(sdk, File.join(project, '.fvm', 'flutter_sdk'))
    out, err, result = shell(<<~ZSH)
      PROJECT_PATH=#{project.shellescape}
      run_bounded() { print 'UNEXPECTED_FVM'; return 1; }
      prepare_project_fvm_sdk || exit 1
      print -r -- "REPLY=$REPLY"
    ZSH
    assert result.success?, err
    assert_includes out, "REPLY=#{File.realpath(sdk)}/bin/flutter"
    refute_includes out, 'UNEXPECTED_FVM'
  end

  def test_prepare_project_fvm_sdk_relinks_when_cache_already_exists
    version = '3.47.7'
    project = File.join(@tmp, 'project')
    FileUtils.mkdir_p(File.join(@tmp, 'fvm/versions', version, 'bin'))
    File.write(File.join(@tmp, 'fvm/versions', version, 'bin', 'flutter'), "#!/bin/zsh\nexit 0\n")
    File.chmod(0o755, File.join(@tmp, 'fvm/versions', version, 'bin', 'flutter'))
    FileUtils.mkdir_p(File.join(project, '.fvm'))
    FileUtils.ln_s(File.join(@tmp, 'missing-old-machine', version), File.join(project, '.fvm', 'flutter_sdk'))
    File.write(File.join(project, '.fvmrc'), "{ \"flutter\": \"#{version}\" }\n")
    out, err, result = shell(<<~ZSH, input: "\n")
      PROJECT_PATH=#{project.shellescape}
      JOBS_FVM_BIN=/usr/bin/true
      json_helper() { [[ "$1" != fvm-version ]] || print -r -- '#{version}'; }
      run_bounded() {
        [[ "$4" == use ]] || return 0
        /bin/ln -s "$HOME/fvm/versions/$5" "$PROJECT_PATH/.fvm/flutter_sdk"
      }
      prepare_project_fvm_sdk || exit 1
      print -r -- "REPLY=$REPLY"
    ZSH
    assert result.success?, err
    assert_includes out, '本机 FVM 缓存已有该版本'
    assert_includes out, "REPLY=#{File.realpath(File.join(@tmp, 'fvm/versions', version))}/bin/flutter"
    refute File.exist?(File.join(project, '.fvm', 'flutter_sdk')) && File.readlink(File.join(project, '.fvm', 'flutter_sdk')).include?('/Users/jobs')
  end

  def test_prepare_project_fvm_sdk_downloads_when_cache_missing
    version = '3.99.0'
    project = File.join(@tmp, 'project')
    FileUtils.mkdir_p(File.join(project, '.fvm'))
    File.write(File.join(project, '.fvm/fvm_config.json'), "{ \"flutterSdkVersion\": \"#{version}\" }\n")
    out, err, result = shell(<<~ZSH, input: "\n")
      PROJECT_PATH=#{project.shellescape}
      JOBS_FVM_BIN=/usr/bin/true
      json_helper() { [[ "$1" != fvm-version ]] || print -r -- '#{version}'; }
      run_bounded() {
        print -r -- "STEP=$4"
        if [[ "$4" == install ]]; then
          mkdir -p "$HOME/fvm/versions/$5/bin"
          print '#!/bin/zsh' > "$HOME/fvm/versions/$5/bin/flutter"
          chmod +x "$HOME/fvm/versions/$5/bin/flutter"
          return 0
        fi
        /bin/ln -s "$HOME/fvm/versions/$5" "$PROJECT_PATH/.fvm/flutter_sdk"
      }
      prepare_project_fvm_sdk || exit 1
      print -r -- "REPLY=$REPLY"
    ZSH
    assert result.success?, err
    assert_includes out, '本机 FVM 缓存没有该版本'
    assert_equal %w[install use], out.scan(/STEP=(\w+)/).flatten
    assert_includes out, "REPLY=#{File.realpath(File.join(@tmp, 'fvm/versions', version))}/bin/flutter"
  end

  def test_prepare_project_fvm_sdk_relinks_when_fvm_only_writes_config
    version = '3.47.7'
    project = File.join(@tmp, 'project')
    FileUtils.mkdir_p(File.join(@tmp, 'fvm/versions', version, 'bin'))
    File.write(File.join(@tmp, 'fvm/versions', version, 'bin', 'flutter'), "#!/bin/zsh\nexit 0\n")
    File.chmod(0o755, File.join(@tmp, 'fvm/versions', version, 'bin', 'flutter'))
    FileUtils.mkdir_p(File.join(project, '.fvm'))
    FileUtils.ln_s(File.join(@tmp, 'missing-old-machine', version), File.join(project, '.fvm', 'flutter_sdk'))
    File.write(File.join(project, '.fvmrc'), "{ \"flutter\": \"#{version}\" }\n")
    out, err, result = shell(<<~ZSH, input: "\n")
      PROJECT_PATH=#{project.shellescape}
      JOBS_FVM_BIN=/usr/bin/true
      json_helper() { [[ "$1" != fvm-version ]] || print -r -- '#{version}'; }
      run_bounded() { return 0; }
      prepare_project_fvm_sdk || exit 1
      print -r -- "REPLY=$REPLY"
    ZSH
    assert result.success?, err
    assert_includes out, '已按本机 FVM 缓存重建'
    assert_includes out, "REPLY=#{File.realpath(File.join(@tmp, 'fvm/versions', version))}/bin/flutter"
  end

  def test_prepare_project_fvm_sdk_respects_tool_cancellation_without_download_confirmation
    project = File.join(@tmp, 'project')
    FileUtils.mkdir_p(File.join(project, '.fvm'))
    File.write(File.join(project, '.fvmrc'), '{ "flutter": "3.47.7" }' + "\n")
    out, err, result = shell(<<~ZSH, input: "n\n")
      PROJECT_PATH=#{project.shellescape}
      JOBS_FVM_BIN=/usr/bin/true
      json_helper() { [[ "$1" != fvm-version ]] || print -r -- '3.47.7'; }
      run_bounded() { return 130; }
      prepare_project_fvm_sdk
      print -r -- "RESULT=$?"
      IFS= read -r untouched
      print -r -- "INPUT=$untouched"
    ZSH
    assert result.success?, err
    assert_includes out, 'RESULT=130'
    assert_includes out, 'INPUT=n'
    assert_includes out, '已取消'
  end

  def test_prepare_project_fvm_sdk_rejects_unreadable_version
    project = File.join(@tmp, 'project')
    FileUtils.mkdir_p(File.join(project, '.fvm'))
    File.write(File.join(project, '.fvmrc'), '{ "nope": true }' + "\n")
    out, err, result = shell(<<~ZSH)
      PROJECT_PATH=#{project.shellescape}
      JOBS_FVM_BIN=/usr/bin/true
      json_helper() { [[ "$1" != fvm-version ]] || return 1; }
      run_bounded() { print 'UNEXPECTED_FVM'; return 1; }
      prepare_project_fvm_sdk
      print -r -- "RESULT=$?"
    ZSH
    assert result.success?, err
    assert_includes out, '无法解析 FVM 版本声明'
    assert_includes out, 'RESULT=1'
    refute_includes out, 'UNEXPECTED_FVM'
  end

  def test_resolve_fvm_cli_prefers_explicit_override
    out, err, result = shell(<<~'ZSH')
      JOBS_FVM_BIN=/usr/bin/true
      resolve_fvm_cli || exit 1
      print -r -- "REPLY=$REPLY"
    ZSH
    assert result.success?, err
    assert_includes out, 'REPLY=/usr/bin/true'
  end

  def test_refresh_devices_defaults_to_30_seconds_and_honours_override
    out, err, result = shell(<<~'ZSH')
      FLUTTER_BIN=/bin/true
      json_helper() { print -r -- '[]'; }
      integer attempt=0
      run_bounded() {
        (( attempt += 1 ))
        print -r -- "SECONDS=$1"
        [[ "$3" == /bin/true && "$4" == devices ]] || return 73
        print -r -- '[]' > "$2"
      }
      refresh_devices || print 'FAIL1'
      refresh_devices 120 || print 'FAIL2'
      print -r -- "ATTEMPTS=$attempt"
    ZSH
    assert result.success?, err
    assert_includes out, 'SECONDS=30'
    assert_includes out, 'SECONDS=120'
    assert_includes out, 'ATTEMPTS=2'
  end

  def test_refresh_devices_failure_prints_recent_output
    out, err, result = shell(<<~'ZSH')
      FLUTTER_BIN=/bin/false
      run_bounded() { [[ "$3" == /bin/false && "$4" == devices ]] || return 0; print 'flutter tool rebuilt' > "$2"; print 'Something went wrong' >> "$2"; return 1; }
      refresh_devices || print 'FAIL'
    ZSH
    assert result.success?, err
    assert_includes out, '最近输出'
    assert_includes out, 'Something went wrong'
    assert_includes out, 'FAIL'
  end

  def test_simulator_recognition_first_refresh_gets_120_seconds
    out, err, result = shell(<<~'ZSH')
      refresh_devices() {
        print -r -- "TIMEOUT=$1"
        ROWS=($'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\tiPhone')
        return 0
      }
      wait_for_simulator_recognition 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE' || exit 1
      print -r -- "DEVICE=$DEVICE_ID"
    ZSH
    assert result.success?, err
    assert_includes out, 'TIMEOUT=120'
    assert_includes out, 'DEVICE=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
  end

  def test_simulator_recognition_retries_after_initial_failure
    out, err, result = shell(<<~'ZSH')
      integer reads=0
      refresh_devices() {
        (( reads += 1 ))
        print -r -- "TIMEOUT=$1"
        (( reads == 1 )) && return 1
        ROWS=($'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\tiPhone')
        return 0
      }
      wait_for_simulator_recognition 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE' || exit 1
      print -r -- "DEVICE=$DEVICE_ID READS=$reads"
    ZSH
    assert result.success?, err
    assert_includes out, 'TIMEOUT=120'
    assert_includes out, 'TIMEOUT=60'
    assert_includes out, 'DEVICE=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee READS=2'
  end

  def test_simulator_recognition_gives_up_after_four_attempts
    out, _err, result = shell(<<~'ZSH')
      integer reads=0
      refresh_devices() { (( reads += 1 )); print -r -- "TIMEOUT=$1"; return 1; }
      wait_for_simulator_recognition 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'
      print -r -- "REACHED=$reads"
    ZSH
    refute result.success?
    assert_equal %w[120 60 30 30], out.scan(/TIMEOUT=(\d+)/).flatten
    assert_includes out, '尚未识别'
  end

  def test_missing_simulator_interface_warns_without_aborting
    out, err, result = shell(<<~'ZSH')
      simulator_interface_app() { return 1; }
      reveal_simulator_interface 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'
      print -r -- "RESULT=$?"
    ZSH
    assert result.success?, err
    assert_includes out, '没有 Simulator / Device Hub'
    assert_includes out, 'RESULT=1'
  end

  def test_unopenable_simulator_interface_only_warns
    out, err, result = shell(<<~ZSH)
      local stub=#{File.join(@tmp, 'Stub.app').shellescape}
      mkdir -p "$stub"
      simulator_interface_app() { REPLY="$stub"; }
      reveal_simulator_interface 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'
      print -r -- "RESULT=$?"
    ZSH
    assert result.success?, err
    assert_includes out, '无法打开模拟器界面'
    assert_includes out, 'RESULT=1'
  end

  def test_connected_harmony_diagnostic_prepares_and_returns_only_the_original_real_target
    out, err, result = shell(<<~'ZSH')
      local picks=0 prepared=0
      refresh_devices() { ROWS=($'ios-phone\tiPhone — ios'); }
      jobs_flutter_harmony_discovery_rows() { print -r -- $'__harmony_usb__:fixture\t鸿蒙 USB 设备 — 已连接，环境未就绪'; }
      select_row() {
        (( picks++ ))
        print -rl -- "${ROWS[@]}"
        REPLY=__harmony_usb__:fixture
      }
      prepare_harmony_run_target() { [[ -z "$DEVICE_ID" && "$1" == __harmony_usb__:fixture ]] || return 71; (( prepared++ )); DEVICE_ID=original-harmony-phone; return 0; }
      choose_existing_device || exit $?
      print -r -- "CHOSEN=$DEVICE_ID PREPARED=$prepared PICKS=$picks"
    ZSH
    assert result.success?, err
    assert_includes out, '鸿蒙 USB 设备 — 已连接'
    assert_includes out, 'CHOSEN=original-harmony-phone PREPARED=1 PICKS=1'
    refute_includes out, 'CHOSEN=__harmony'
  end

  def test_harmony_usb_diagnostic_survives_flutter_device_query_failure
    out, err, result = shell(<<~'ZSH')
      refresh_devices() { ROWS=(); return 1; }
      jobs_flutter_harmony_discovery_rows() { print -r -- $'__harmony_usb__:fixture\t鸿蒙 USB 设备 — 已连接，环境未就绪'; }
      select_row() { print -rl -- "${ROWS[@]}"; REPLY=__cancel__; }
      choose_existing_device
    ZSH
    assert_equal 130, result.exitstatus, err
    assert_includes out, '__harmony_usb__:fixture'
  end

  def test_cancel_from_harmony_diagnostic_does_not_start_background
    out, _err, result = preflight_main(<<~'ZSH')
      refresh_devices() { ROWS=(); }
      jobs_flutter_harmony_discovery_rows() { print -r -- $'__harmony_hdc__:fixture\t鸿蒙 HDC 设备 — 已连接，环境未就绪'; }
      select_row() { REPLY=__harmony_hdc__:fixture; }
      prepare_harmony_run_target() { HARMONY_PREPARATION_FAILED=1; return 130; }
      choose_device() { choose_existing_device; }
    ZSH
    assert_equal 130, result.exitstatus
    refute_includes out, 'TARGET_READY'
    refute_includes out, 'START_BACKGROUND'
  end

  def test_failed_native_harmony_query_does_not_inject_output_into_device_rows
    out, err, result = shell(<<~'ZSH')
      refresh_devices() { ROWS=($'ios-phone\tiPhone — ios'); }
      jobs_flutter_harmony_discovery_rows() { print INVALID_DEVICE_ROW; return 1; }
      select_row() { print -rl -- "${ROWS[@]}"; REPLY=ios-phone; }
      choose_existing_device || exit $?
      print -r -- "CHOSEN=$DEVICE_ID"
    ZSH
    assert result.success?, err
    assert_includes out, 'CHOSEN=ios-phone'
    refute_includes out, 'INVALID_DEVICE_ROW'
    assert_includes out, '鸿蒙连接状态读取失败'
  end

  def preflight_main(body)
    shell(<<~ZSH)
      functions[choose_device_before_stub]="$functions[choose_device]"
      functions[require_environment_before_stub]="$functions[require_selected_device_environment]"
      show_script_intro_and_wait() { return 0; }
      initialize_runtime() { return 0; }
      leave_terminal() { return 0; }
      read_project() { return 0; }
      find_flutter() { print SDK_READY; }
      load_run_preflight() { return 0; }
      jobs_flutter_preflight_overview() { print HEALTH_REPORT; }
      choose_device() { print SELECT_DEVICE; DEVICE_ID=phone; }
      require_selected_device_environment() { print TARGET_READY; }
      prepare_target_sdk_resources() { print TARGET_RESOURCES; }
      prepare_session() { print START_BACKGROUND; }
      watch_session() { print WATCH_LOG; }
      #{body}
      main --project "$PROJECT_PATH"
    ZSH
  end

  def harmony_preparation_fixture
    directory = File.join(@tmp, 'runner-assets')
    preflight = File.join(directory, '【MacOS】Flutter运行前体检.zsh')
    preparation = File.join(preflight, '【MacOS】鸿蒙运行环境准备.zsh')
    FileUtils.mkdir_p(preparation)
    FileUtils.cp(File.join(File.dirname(SCRIPT), '【MacOS】Flutter运行前体检.zsh/Flutter运行前体检.jxa'), preflight)
    File.write(File.join(preparation, '【MacOS】鸿蒙运行环境准备.zsh'), <<~'ZSH')
      jobs_flutter_prepare_harmony_for_run() {
        (( PREP_CALLS++ ))
        FLUTTER_BIN=/fixture/new-harmony-sdk/bin/flutter
        HARMONY_PARENT_ENV=prepared
        export HARMONY_PARENT_ENV
        REPLY="$1"
        print PREPARED_ORIGINAL_TARGET
        return "${PREP_RESULT:-0}"
      }
    ZSH
    <<~ZSH
      SCRIPT_DIR=#{directory.shellescape}
      HELPER=#{File.join(File.dirname(SCRIPT), 'FlutterRunner.jxa').shellescape}
      typeset -gA JOBS_PREFLIGHT_STATE JOBS_PREFLIGHT_DETAIL
      JOBS_PREFLIGHT_STATE[ohos]=failed
      PREP_CALLS=0
      refresh_devices() {
        if (( PREP_CALLS == 0 )); then
          ROWS=()
          print '[]' > "$LOG_FILE.devices.json"
        else
          ROWS=($'ORIGINAL123\tHarmony — ohos-arm64')
          print '[{"id":"ORIGINAL123","isSupported":true,"targetPlatform":"ohos-arm64"},{"id":"OTHER456","isSupported":true,"targetPlatform":"ohos-arm64"}]' > "$LOG_FILE.devices.json"
        fi
      }
      jobs_flutter_harmony_discovery_rows() { (( PREP_CALLS != 0 )) || print -r -- $'__harmony_hdc__:ORIGINAL123\t鸿蒙HDC设备'; }
      jobs_flutter_preflight_overview() { if (( PREP_CALLS > 0 )); then JOBS_PREFLIGHT_STATE[ohos]=passed; fi; print HEALTH_REPORT; }
      find_flutter() { print SDK_READY; }
    ZSH
  end

  def test_harmony_preparation_success_continues_same_main_and_runs_once
    out, err, result = preflight_main(harmony_preparation_fixture + <<~'ZSH')
      choose_device() { choose_device_before_stub; }
      require_selected_device_environment() { require_environment_before_stub; }
      select_row() { if [[ "${ROWS[1]%%$'\t'*}" == __existing__ ]]; then REPLY=__existing__; else REPLY=__harmony_hdc__:ORIGINAL123; fi; }
      jobs_flutter_preflight_require() { [[ "$1" == ohos && "$2" == ORIGINAL123 && "$HARMONY_PARENT_ENV" == prepared && "$FLUTTER_BIN" == /fixture/new-harmony-sdk/bin/flutter ]] || return 74; print TARGET_READY; }
      prepare_session() { [[ "$DEVICE_ID" == ORIGINAL123 && "$PREP_CALLS" == 1 ]] || return 75; print START_BACKGROUND; }
    ZSH
    assert result.success?, err
    assert_equal 1, out.scan('PREPARED_ORIGINAL_TARGET').length, out
    assert_equal 2, out.scan('SDK_READY').length, out
    assert_equal 2, out.scan('HEALTH_REPORT').length, out
    assert_equal 1, out.scan('START_BACKGROUND').length, out
    refute_includes out, 'OTHER456'
  end

  def test_harmony_preparation_failure_and_cancel_stop_main_without_reselecting
    [7, 130].each do |code|
      out, err, result = preflight_main(harmony_preparation_fixture + <<~ZSH)
        PREP_RESULT=#{code}
        choose_device() { choose_device_before_stub; }
        select_row() { if [[ "${ROWS[1]%%$'\t'*}" == __existing__ ]]; then REPLY=__existing__; else REPLY=__harmony_hdc__:ORIGINAL123; fi; }
      ZSH
      assert_equal code, result.exitstatus, err
      assert_equal 1, out.scan('PREPARED_ORIGINAL_TARGET').length, out
      refute_includes out, 'TARGET_RESOURCES'
      refute_includes out, 'START_BACKGROUND'
    end
  end

  def test_original_harmony_target_wait_is_bounded_without_repeating_preparation
    out, err, result = preflight_main(harmony_preparation_fixture + <<~'ZSH')
      JOBS_HARMONY_DEVICE_WAIT_ATTEMPTS=2
      QUERY_CALLS=0
      choose_device() { choose_device_before_stub; }
      select_row() { if [[ "${ROWS[1]%%$'\t'*}" == __existing__ ]]; then REPLY=__existing__; else REPLY=__harmony_hdc__:ORIGINAL123; fi; }
      refresh_devices() { (( QUERY_CALLS++ )); ROWS=(); print '[]' > "$LOG_FILE.devices.json"; print QUERY_CALL; }
    ZSH
    assert_equal 1, result.exitstatus, err
    assert_equal 1, out.scan('PREPARED_ORIGINAL_TARGET').length, out
    assert_equal 3, out.scan('QUERY_CALL').length, out
    refute_includes out, 'START_BACKGROUND'
  end

  def test_supported_harmony_device_with_unhealthy_environment_is_prepared_in_same_main
    out, err, result = preflight_main(harmony_preparation_fixture + <<~'ZSH')
      require_selected_device_environment() { require_environment_before_stub; }
      choose_device() { DEVICE_ID=ORIGINAL123; print '[{"id":"ORIGINAL123","isSupported":true,"targetPlatform":"ohos-arm64"}]' > "$LOG_FILE.devices.json"; }
      jobs_flutter_preflight_require() { [[ "$1" == ohos && "$2" == ORIGINAL123 && "$PREP_CALLS" == 1 ]] || return 73; print TARGET_READY; }
    ZSH
    assert result.success?, err
    assert_equal 1, out.scan('PREPARED_ORIGINAL_TARGET').length, out
    assert_equal 1, out.scan('START_BACKGROUND').length, out
    assert_includes out, 'TARGET_READY'
  end

  def test_main_reports_health_before_device_selection_and_gates_background_run
    out, err, result = preflight_main('')
    assert result.success?, err
    assert_equal %w[SDK_READY HEALTH_REPORT SELECT_DEVICE TARGET_READY TARGET_RESOURCES START_BACKGROUND WATCH_LOG], out.lines.map(&:strip)
    assert_equal 1, out.scan('START_BACKGROUND').length
  end

  def test_main_stops_before_devices_if_preflight_report_fails
    out, _err, result = preflight_main('jobs_flutter_preflight_overview() { print HEALTH_FAILED; return 124; }')
    assert_equal 124, result.exitstatus
    refute_includes out, 'SELECT_DEVICE'
    refute_includes out, 'START_BACKGROUND'
  end

  def test_main_stops_before_precache_and_background_if_selected_platform_fails
    out, _err, result = preflight_main('require_selected_device_environment() { print TARGET_FAILED; return 1; }')
    refute result.success?
    assert_includes out, 'HEALTH_REPORT'
    refute_includes out, 'TARGET_RESOURCES'
    refute_includes out, 'START_BACKGROUND'
  end

  def test_main_device_cancellation_never_checks_target_or_starts_background
    out, _err, result = preflight_main('choose_device() { return 130; }')
    assert_equal 130, result.exitstatus
    refute_includes out, 'TARGET_READY'
    refute_includes out, 'START_BACKGROUND'
  end

  def test_missing_preflight_resource_blocks_run
    out, err, result = shell(<<~'ZSH')
      SCRIPT_DIR="$PROJECT_PATH/missing-resources"
      load_run_preflight
    ZSH
    refute result.success?, err
    assert_includes out, '缺少运行前环境体检模块'
  end

  def test_selected_device_platform_is_resolved_each_time
    out, err, result = shell(<<~'ZSH')
      DEVICE_ID=phone
      typeset -gA JOBS_PREFLIGHT_STATE
      JOBS_PREFLIGHT_STATE[ohos]=passed
      local calls=0
      json_helper() { [[ "$1" == precache-platform && "$3" == phone ]] || return 1; print -r -- "$PLATFORM"; }
      jobs_flutter_preflight_require() { print -r -- "CHECK=$1:$2"; [[ "$1" == ios ]]; }
      PLATFORM=ios
      require_selected_device_environment || exit 71
      PLATFORM=ohos
      require_selected_device_environment
    ZSH
    refute result.success?, err
    assert_equal %w[CHECK=ios:phone CHECK=ohos:phone], out.lines.map(&:strip)
  end

  def test_unparseable_selected_device_does_not_reuse_old_health
    out, err, result = shell(<<~'ZSH')
      DEVICE_ID=phone
      json_helper() { return 1; }
      jobs_flutter_preflight_require() { print UNEXPECTED_PASS; }
      require_selected_device_environment
    ZSH
    refute result.success?, err
    refute_includes out, 'UNEXPECTED_PASS'
    assert_includes out, '无法确认所选设备的平台'
  end

  def test_ios_incompatible_combination_does_not_claim_success
    out, err, result = shell(<<~'ZSH', input: "1\n1\n\n")
      json_helper() { [[ "$1" != unique-name ]] || print -r -- "$3"; [[ "$1" == unique-name ]] || print -r -- $'fixture-id\tfixture'; }
      run_bounded() { [[ "$4" == simctl && "$5" == create ]] || return 0; return 7; }
      create_simulator
      print -r -- "RESULT=$?"
    ZSH
    assert result.success?, err
    assert_includes out, '创建失败'
    assert_includes out, 'RESULT=1'
  end
  def test_virtual_group_prepares_selected_platform_before_inventory_and_runs_only_original_target
    out, err, result = shell(<<~'ZSH', input: "3\n2\n")
      refresh_devices() { print UNEXPECTED_PHONE_QUERY; }
      run_simulator_creator() { print UNEXPECTED_CREATE; }
      load_simulator_start_environment() { print LOAD; }
      jobs_flutter_prepare_simulator_environment() { print -r -- "PREPARE=$1"; }
      jobs_flutter_preflight_overview() { print REFRESH_HEALTH; }
      start_android_emulator() { print -r -- "LIST_AND_START=$1"; DEVICE_ID=emulator-original; }
      choose_device
      print -r -- "RUN=$DEVICE_ID"
    ZSH
    assert result.success?, out + err
    assert_includes out, 'PREPARE=android'
    assert_includes out, 'LIST_AND_START=existing'
    assert_operator out.index('PREPARE=android'), :<, out.index('REFRESH_HEALTH')
    assert_operator out.index('REFRESH_HEALTH'), :<, out.index('LIST_AND_START=existing')
    assert_includes out, 'RUN=emulator-original'
    refute_includes out, 'UNEXPECTED_PHONE_QUERY'
    refute_includes out, 'UNEXPECTED_CREATE'
  end

  def test_virtual_group_back_and_cancel_do_not_prepare_or_launch
    ["3\nb\n5\n", "3\n5\n"].each do |input|
      out, err, result = shell(<<~'ZSH', input: input)
        load_simulator_start_environment() { print UNEXPECTED_LOAD; }
        jobs_flutter_prepare_simulator_environment() { print UNEXPECTED_PREPARE; }
        choose_device
        print UNEXPECTED_RUN
      ZSH
      assert result.success?, out + err
      refute_includes out, 'UNEXPECTED_LOAD'
      refute_includes out, 'UNEXPECTED_PREPARE'
      refute_includes out, 'UNEXPECTED_RUN'
    end
  end

  def test_real_fzf_virtual_platform_navigation_returns_to_exact_parent
    setup = <<~'ZSH'
      load_simulator_start_environment() { print UNEXPECTED_LOAD; }
      refresh_devices() { ROWS=($'phone-fixture\tPhone fixture'); }
    ZSH
    transcript = real_fzf_terminal(setup: setup, invocation: 'choose_device', ready: ['启动虚拟设备']) do |writer, read_until, text|
      writer.write("\e[B\e[B\r")
      read_until.call { |text| text.include?('启动鸿蒙模拟器'.b) }
      previous = text.scan('目前已有的设备（'.b).length
      writer.write("zz-no-matches")
      read_until.call { |text| text.include?('0/5'.b) }
      writer.write("\e[D")
      read_until.call { |text| text.scan('目前已有的设备（'.b).length > previous }
      writer.write("\r")
      read_until.call { |text| text.include?('Phone fixture'.b) }
      writer.write("\r")
    end
    assert_includes transcript, 'PICK=phone-fixture'
    refute_includes transcript, 'UNEXPECTED_LOAD'
  end

  def test_fzf_runtime_error_is_not_reported_as_cancel_or_text_fallback
    fake = File.join(@tmp, 'brokenfzf')
    File.write(fake, "#!/bin/zsh\nexit 2\n")
    FileUtils.chmod(0o700, fake)
    out, err, result = shell(<<~ZSH, env: { 'JOBS_FLUTTER_RUNNER_FZF'=>'always' })
      FZF_BIN=#{fake.shellescape}
      FZF_VALIDATED_BIN="$FZF_BIN"
      ROWS=($'id\\tDevice')
      select_row 'Child' 1
      print -r -- "RESULT=$?"
    ZSH
    assert result.success?, out + err
    assert_includes out, 'RESULT=2'
    assert_includes out, 'fzf选择器运行失败'
    refute_includes out, '输入编号'
  end

  def test_return_from_instance_list_reuses_prepared_environment_without_replaying_acquisition
    out,err,status=shell(<<~'ZSH',input:"3\n2\n2\n")
      integer lists=0
      load_simulator_start_environment() { print LOAD; }
      jobs_flutter_prepare_simulator_environment() { print PREPARE; }
      start_android_emulator() { (( lists++ )); (( lists > 1 )) || return 10; DEVICE_ID=original; }
      choose_device
      print DEVICE=$DEVICE_ID
    ZSH
    assert status.success?,out+err
    assert_equal 1,out.lines.count { |line| line.strip=='PREPARE' }
    assert_equal 1,out.lines.count { |line| line.strip=='LOAD' }
    assert_includes out,'DEVICE=original'
  end
  def test_replaced_avd_after_selection_stops_before_version_start_or_wait
    out,err,status=shell(<<~'ZSH')
      integer checks=0
      resolve_android_tools() { return 0; }
      read_android_avds() { ROWS=($'TARGET\tOriginal AVD'); }
      jobs_sim_android_avd_identity() { print -r -- "$IDENTITY"; }
      IDENTITY=original
      select_row() { REPLY=TARGET; IDENTITY=replaced; }
      run_bounded() { print UNEXPECTED_HOST; }
      wait_for_android_avd() { print UNEXPECTED_WAIT; }
      start_android_emulator existing
      print RESULT=$?
    ZSH
    assert status.success?,out+err
    assert_includes out,'RESULT=1'
    assert_includes out,'原 AVD 已被替换'
    refute_includes out,'UNEXPECTED_HOST'
    refute_includes out,'UNEXPECTED_WAIT'
  end

end
