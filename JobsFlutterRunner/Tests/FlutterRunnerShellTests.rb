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
      "source #{@library.shellescape}\nPROJECT_PATH=#{@tmp.shellescape}\nLOG_FILE=#{File.join(@tmp, 'test.log').shellescape}\n: > \"$LOG_FILE\"\n#{body}", stdin_data: input)
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

  def test_fvm_project_never_falls_back_to_global_flutter
    File.write(File.join(@tmp, '.fvmrc'), '{"flutter":"3.24.0"}')
    out, _err, result = shell("PROJECT_PATH=#{@tmp.shellescape}\nfind_flutter")
    refute result.success?
    assert_includes out, '本地 .fvm/flutter_sdk 尚未就绪'
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
          types) print -r -- $'com.apple.CoreSimulator.SimDeviceType.iPhone-16\tiPhone 16' ;;
          runtimes) print -r -- $'com.apple.CoreSimulator.SimRuntime.iOS-18-0\tiOS 18.0' ;;
        esac
      }
      run_bounded() {
        [[ "$3" == /usr/bin/xcrun && "$4" == simctl && "$5" == create ]] || return 73
        [[ "$7" == com.apple.CoreSimulator.SimDeviceType.iPhone-16 && "$8" == com.apple.CoreSimulator.SimRuntime.iOS-18-0 ]] || return 74
        print '01234567-89AB-CDEF-0123-456789ABCDEF' > "$2"
      }
      create_simulator || exit 1
      print -r -- "CREATED=$REPLY"
    ZSH
    assert result.success?, err
    assert_includes out, 'CREATED=01234567-89AB-CDEF-0123-456789ABCDEF'
  end

  def test_missing_ios_runtime_stops_before_any_create
    out, _err, result = shell(<<~'ZSH', input: "1\n")
      json_helper() { [[ "$1" != types ]] || print -r -- $'type-1\tiPhone'; }
      run_bounded() { print 'UNEXPECTED_CREATE'; return 1; }
      create_simulator
    ZSH
    refute result.success?
    assert_includes out, '没有可用的 iOS Runtime'
    refute_includes out, 'UNEXPECTED_CREATE'
  end

  def test_ios_incompatible_combination_does_not_claim_success
    out, err, result = shell(<<~'ZSH', input: "1\n1\n\n")
      json_helper() { print -r -- $'fixture-id\tfixture'; }
      run_bounded() { return 7; }
      create_simulator
      print -r -- "RESULT=$?"
    ZSH
    assert result.success?, err
    assert_includes out, '创建失败'
    assert_includes out, 'RESULT=1'
  end
end
