# Created by Jobs on 2026年10月29日，星期四.
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'shellwords'

class FlutterRunnerAndroidTests < Minitest::Test
  SCRIPT = File.expand_path('../Scripts/RunFlutterProject.zsh', __dir__)

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
    File.write(picker, "#!/bin/zsh\ncat >/dev/null\nprint left\nexit 1\n")
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
