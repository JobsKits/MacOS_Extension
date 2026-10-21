# Created by Jobs on 2026年10月20日，星期二.
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'shellwords'

class FlutterRunnerShellTests < Minitest::Test
  SCRIPT = File.expand_path('../Scripts/RunFlutterProject.zsh', __dir__)

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
      "source #{@library.shellescape}\nPROJECT_PATH=#{@tmp.shellescape}\nLOG_FILE=#{File.join(@tmp, 'test.log').shellescape}\n: > \"$LOG_FILE\"\n#{body}", stdin_data: input, chdir: @tmp)
  end

  def test_eof_at_first_confirmation_does_not_create_state
    out, err, result = Open3.capture3({ 'HOME' => @tmp, 'NO_COLOR' => '1' }, '/bin/zsh', SCRIPT,
      '--project', @tmp, stdin_data: '')
    assert result.success?, err
    assert_includes out, 'launchd'
    refute Dir.exist?(File.join(@tmp, 'Library'))
  end

  def test_simulator_cancel_returns_to_device_selection
    out, err, result = shell(<<~'ZSH', input: "2\n1\n")
      setopt NO_NOMATCH
      refresh_devices() { ROWS=($'android-42\tPhone — android'); }
      select_ios_simulator() { return 1; }
      choose_device
      print -r -- "CHOSEN=$DEVICE_ID"
    ZSH
    assert result.success?, err
    assert_includes out, 'CHOSEN=android-42'
  end

  def test_device_refresh_option_and_selection
    out, err, result = shell(<<~'ZSH', input: "4\n1\n")
      refresh_devices() { ROWS=($'android-42\tPhone — android'); }
      choose_device
      print -r -- "CHOSEN=$DEVICE_ID"
    ZSH
    assert result.success?, err
    assert_includes out, 'CHOSEN=android-42'
    assert_equal 2, out.scan('选择 Flutter 运行设备').length
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
    File.write(fake, "#!/bin/zsh\ncat >/dev/null\nexit 130\n")
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
    assert_equal "diagnostic\n", File.read(File.join(@tmp, 'bounded.log'))
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
    FileUtils.ln_s('/Users/jobs/fvm/versions/3.47.7', File.join(project, '.fvm', 'flutter_sdk'))
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
    FileUtils.ln_s('/Users/jobs/fvm/versions/3.47.7', File.join(project, '.fvm', 'flutter_sdk'))
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

  def test_prepare_project_fvm_sdk_respects_cancellation
    project = File.join(@tmp, 'project')
    FileUtils.mkdir_p(File.join(project, '.fvm'))
    File.write(File.join(project, '.fvmrc'), '{ "flutter": "3.47.7" }' + "\n")
    out, err, result = shell(<<~ZSH, input: "n\n")
      PROJECT_PATH=#{project.shellescape}
      JOBS_FVM_BIN=/usr/bin/true
      json_helper() { [[ "$1" != fvm-version ]] || print -r -- '3.47.7'; }
      run_bounded() { print 'UNEXPECTED_FVM'; return 1; }
      prepare_project_fvm_sdk
      print -r -- "RESULT=$?"
    ZSH
    assert result.success?, err
    assert_includes out, 'RESULT=1'
    assert_includes out, '已取消'
    refute_includes out, 'UNEXPECTED_FVM'
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
end
