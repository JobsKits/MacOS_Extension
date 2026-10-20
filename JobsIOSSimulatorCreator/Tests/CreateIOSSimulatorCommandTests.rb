# frozen_string_literal: true
# 真实 zsh / 系统 JXA 隔离回归；xcrun、open、fzf 全部替换为私有夹具，不创建真实模拟器。

require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class CreateIOSSimulatorCommandTests < Minitest::Test
  SCRIPT = File.expand_path('../Scripts/CreateIOSSimulator.zsh', __dir__)
  RUNTIME_PREFIX = 'com.apple.CoreSimulator.SimRuntime.'
  DEVICE_PREFIX = 'com.apple.CoreSimulator.SimDeviceType.'
  UDID = 'A1234567-1234-1234-1234-123456789ABC'

  # 构造完整但私有的 Xcode、simctl 与 Simulator 路径。
  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-ios-simulator-test-'))
    @bin = File.join(@root, 'bin')
    @run = File.join(@root, 'run')
    @developer = File.join(@root, "Xcode 空格 ' $.app", 'Contents', 'Developer')
    @app = File.join(@developer, 'Applications', 'Simulator.app')
    FileUtils.mkdir_p([@bin, @run, File.join(@developer, 'usr', 'bin')])
    make_app(@app, 'com.apple.iphonesimulator', 'Simulator')
    File.write(File.join(@developer, 'usr', 'bin', 'simctl'), '')
    FileUtils.chmod(0o700, File.join(@developer, 'usr', 'bin', 'simctl'))
    @environment = {
      'HOME' => @root, 'TMPDIR' => @run + '/', 'PATH' => "#{@bin}:/usr/bin:/bin",
      'NO_COLOR' => '1', 'TEST_ROOT' => @root, 'TEST_DEVELOPER' => @developer,
      'TEST_TRACE' => File.join(@root, 'trace.jsonl'), 'TEST_UDID' => UDID
    }
    @runtimes = [runtime('18.0', 'iOS 18.0', ['iPhone-Old', 'iPad-Test']),
                 runtime('16.0', 'iOS 16.0')]
    @device_types = [device('iPhone Old', 'iPhone-Old', 18 * 65_536),
                     device('iPad Test', 'iPad-Test', 18 * 65_536, 'iPad'),
                     device('iPhone Future', 'iPhone-Future', 20 * 65_536),
                     device('iPhone Legacy', 'iPhone-Legacy', nil),
                     device('Apple TV', 'Apple-TV', nil, 'Apple TV')]
    save_catalog
    write_mock('xcrun', <<~'ZSH')
      printf '%s\0' xcrun "$@" >> "$TEST_TRACE"
      printf '\0' >> "$TEST_TRACE"
      if [[ "$1" == --find && "$2" == simctl ]]; then
        [[ "${TEST_FIND_FAIL:-0}" == 0 ]] || exit 13
        print -r -- "$TEST_DEVELOPER/usr/bin/simctl"
      elif [[ "$1" == simctl && "$2" == list ]]; then
        [[ "${TEST_LIST_FAIL:-}" != "$3" ]] || exit 15
        /bin/cat -- "$TEST_ROOT/$3.json"
      elif [[ "$1" == simctl && "$2" == create ]]; then
        if [[ -n "${TEST_CREATE_FAIL:-}" ]]; then
          print -ru2 -- "$TEST_CREATE_FAIL"
          exit 19
        fi
        print -r -- "${TEST_CREATE_OUTPUT:-$TEST_UDID}"
      elif [[ "$1" == simctl && "$2" == boot ]]; then
        [[ "${TEST_BOOT_FAIL:-0}" == 0 ]] || exit 21
      elif [[ "$1" == simctl && "$2" == bootstatus ]]; then
        [[ "${TEST_BOOTSTATUS_FAIL:-0}" == 0 ]] || exit 22
      else
        print -ru2 -- 'unexpected simctl fixture invocation'
        exit 64
      fi
    ZSH
    write_mock('open', <<~'ZSH')
      printf '%s\0' open "$@" >> "$TEST_TRACE"
      printf '\0' >> "$TEST_TRACE"
      [[ "${TEST_OPEN_FAIL:-0}" == 0 ]] || exit 23
    ZSH
    @source = File.read(SCRIPT).sub(/^main "\$@"\s*\z/, '')
    @source = @source.gsub('/usr/bin/xcrun', File.join(@bin, 'xcrun'))
                     .gsub('/usr/bin/open', File.join(@bin, 'open'))
    @bootstrap = <<~'ZSH'
      setopt NO_NOMATCH PIPE_FAIL
      SIM_RUN_DIR="$TEST_ROOT/run"
      SIM_APP="$TEST_DEVELOPER/Applications/Simulator.app"
      SIM_APP_KIND=com.apple.iphonesimulator
      SIM_RUNTIME_ID=com.apple.CoreSimulator.SimRuntime.iOS-18-0
      SIM_RUNTIME_NAME='iOS 18.0'
      SIM_DEVICE_ID=com.apple.CoreSimulator.SimDeviceType.iPhone-Old
      SIM_DEVICE_NAME='iPhone Old'
      SIM_NAME='iPhone Old@fixture'
    ZSH
  end

  # 只删除本测试创建的唯一私有目录。
  def teardown
    FileUtils.remove_entry(@root)
  end

  # 同一展示名、同一标识、不可用系统与其它架构均不会产生重复选择。
  def test_runtime_rows_deduplicate_and_filter_availability_platform_and_architecture
    @runtimes += [runtime('18.0.1', 'iOS 18.0', ['iPhone-Old'], identifier: 'iOS-18-0'),
                  runtime('17.0', 'iOS 17.0').merge('isAvailable' => false),
                  runtime('19.0', 'tvOS 19.0', identifier: 'tvOS-19-0'),
                  runtime('21.0', 'iOS 21.0').merge('supportedArchitectures' => ['x86_64'])]
    save_catalog
    output, status = execute('sim_data runtimes "$TEST_ROOT/runtimes.json" arm64')
    assert status.success?, output
    assert_equal ["iOS 18.0\t#{RUNTIME_PREFIX}iOS-18-0", "iOS 16.0\t#{RUNTIME_PREFIX}iOS-16-0"], output.lines.map(&:strip)
  end

  # 优先使用 Runtime 的真实支持列表，保留 iPad，拒绝该系统未列出的新型号。
  def test_supported_device_types_filter_the_selected_runtime
    output, status = execute('sim_data devices "$TEST_ROOT/runtimes.json" "$TEST_ROOT/devicetypes.json" "$SIM_RUNTIME_ID"')
    assert status.success?, output
    assert_includes output, 'iPhone Old'
    assert_includes output, 'iPad Test'
    refute_includes output, 'Future'
    refute_includes output, 'Legacy'
  end

  # 缺少兼容列表的旧 Xcode 按已知版本范围筛选，未知范围允许最终 create 校验。
  def test_legacy_device_metadata_accepts_unknown_bounds_and_rejects_known_incompatible_bounds
    output, status = execute('sim_data devices "$TEST_ROOT/runtimes.json" "$TEST_ROOT/devicetypes.json" com.apple.CoreSimulator.SimRuntime.iOS-16-0')
    assert status.success?, output
    assert_includes output, 'iPhone Legacy'
    refute_includes output, 'iPhone Old'
    refute_includes output, 'Future'
    refute_includes output, 'Apple TV'
  end

  # 显式空白名单不能回退为全部设备。
  def test_explicit_empty_supported_list_produces_no_devices
    @runtimes[0]['supportedDeviceTypes'] = []
    save_catalog
    output, status = execute('sim_data devices "$TEST_ROOT/runtimes.json" "$TEST_ROOT/devicetypes.json" "$SIM_RUNTIME_ID"')
    assert status.success?, output
    assert_empty output.strip
  end

  # 同一个 Runtime 标识的重复记录使用首条，与展示去重保持一致。
  def test_duplicate_runtime_identifier_does_not_break_selection
    @runtimes << runtime('18.0.1', 'iOS 18.0', ['iPhone-Future'], identifier: 'iOS-18-0')
    save_catalog
    output, status = execute('sim_data devices "$TEST_ROOT/runtimes.json" "$TEST_ROOT/devicetypes.json" "$SIM_RUNTIME_ID"')
    assert status.success?, output
    assert_includes output, 'iPhone Old'
    refute_includes output, 'Future'
  end

  # 错误 JSON 与带控制字符的数据均阻断进入创建。
  def test_malformed_json_and_control_characters_are_rejected
    File.write(File.join(@root, 'runtimes.json'), 'not-json')
    output, status = execute('sim_data runtimes "$TEST_ROOT/runtimes.json" arm64')
    refute status.success?, output
    @runtimes[0]['name'] = "iOS 18.0\nINJECTED"
    save_catalog
    output, status = execute('sim_data runtimes "$TEST_ROOT/runtimes.json" arm64')
    refute status.success?, output
    assert_empty trace
  end

  # 已有不可用设备的名称也参与冲突保护。
  def test_unique_name_checks_all_existing_devices
    File.write(File.join(@root, 'devices.json'), JSON.generate('devices' => {'unused-runtime' => [
      {'name' => 'iPhone@fixture', 'isAvailable' => false}, {'name' => 'iPhone@fixture (2)'}
    ]}))
    output, status = execute('sim_data unique-name "$TEST_ROOT/devices.json" iPhone@fixture')
    assert status.success?, output
    assert_equal 'iPhone@fixture (3)', output.strip
  end

  # 编号错误只会再次提示，前导零仍按十进制解释。
  def test_numbered_selection_validates_range_and_accepts_decimal_leading_zero
    output, status = execute(<<~'ZSH', input: "0\n99\nabc\n02\n")
      sim_choose_row '选择' $'One\tid-one\nTwo\tid-two' || exit $?
      print -r -- "SELECTED|$SIM_SELECTED_ROW"
    ZSH
    assert status.success?, output
    assert_includes output, "SELECTED|Two\tid-two"
    assert_equal 3, output.scan('请输入列表内的编号').length
    assert_empty trace
  end

  # 取消与输入结束不能选中第一项。
  def test_cancel_and_eof_never_select_or_create
    ["q\n", "\n", ''].each do |input|
      output, status = execute("sim_choose_row '选择' $'One\\tid-one'", input: input)
      assert_equal 130, status.exitstatus, output
    end
    assert_empty trace
  end

  # 已安装但损坏的 fzf 自动降级，健康 fzf 按 Esc 可取消。
  def test_fzf_health_fallback_and_cancellation
    make_fzf
    output, status = execute('sim_check_environment; print -r -- "FZF|$SIM_FZF"', env: {'TEST_FZF_BAD' => '1'})
    assert status.success?, output
    assert_match(/FZF\|\s*\z/, output)
    output, status = execute('SIM_FZF="$TEST_ROOT/bin/fzf"; sim_choose_row 选择 $\'One\\tid-one\'', env: {'TEST_FZF_CANCEL' => '1'})
    assert_equal 130, status.exitstatus, output
  end

  # 健康 fzf 的输出必须精确匹配原清单，再交给创建流程。
  def test_healthy_fzf_returns_a_catalog_row
    make_fzf
    output, status = execute(<<~'ZSH')
      SIM_FZF="$TEST_ROOT/bin/fzf"
      sim_choose_row '选择' $'One\tid-one\nTwo\tid-two' || exit $?
      print -r -- "SELECTED|$SIM_SELECTED_ROW"
    ZSH
    assert status.success?, output
    assert_includes output, "SELECTED|One\tid-one"
    assert_empty trace
  end

  # 真实只读入口必须只调用 --find / list；临时快照在退出时移除，不产生日志。
  def test_check_entry_reads_catalog_and_cleans_snapshots_without_mutation
    output, status = execute('main --check')
    assert status.success?, output
    assert_includes output, 'iOS 18.0：2 个兼容'
    assert_includes output, '只读体检完成'
    assert trace.all? { |entry| entry[0] == 'xcrun' && (entry[1] == '--find' || entry[2] == 'list') }, trace.inspect
    assert_empty Dir.glob(File.join(@run, 'CreateIOSSimulator.*'))
    refute_includes output, "\e["
  end

  # 系统未安装 Runtime 与清单读取失败均不得触发创建。
  def test_missing_runtime_and_list_failure_stop_before_creation
    @runtimes = []
    save_catalog
    output, status = execute('main --check')
    refute status.success?, output
    assert_includes output, '没有本机可用'
    output, status = execute('main --check', env: {'TEST_LIST_FAIL' => 'runtimes'})
    refute status.success?, output
    assert_includes output, '读取模拟器清单失败'
    refute trace.any? { |entry| entry[2] == 'create' }
  end

  # 默认入口拒绝无 TTY，确认前不探测工具链，也不写日志。
  def test_interactive_entry_rejects_non_tty_before_any_business
    output, status = execute('main')
    refute status.success?, output
    assert_includes output, '没有可交互终端'
    assert_empty trace
    assert_empty Dir.glob(File.join(@run, 'CreateIOSSimulator.*'))
  end

  # create / boot / open / bootstatus 顺序与独立参数必须保持完整。
  def test_create_and_boot_pass_arguments_without_shell_evaluation
    dangerous_name = "iPhone ' $(touch SHOULD_NOT_EXIST)"
    @environment['TEST_NAME'] = dangerous_name
    output, status = execute('SIM_NAME="$TEST_NAME"; sim_create_and_boot')
    assert status.success?, output
    assert_equal ['xcrun', 'simctl', 'create', dangerous_name, DEVICE_PREFIX + 'iPhone-Old', RUNTIME_PREFIX + 'iOS-18-0'], trace[0]
    assert_equal ['xcrun', 'simctl', 'boot', UDID], trace[1]
    assert_equal ['open', '-a', @app], trace[2]
    assert_equal ['xcrun', 'simctl', 'bootstatus', UDID], trace[3]
    refute File.exist?(File.join(@root, 'SHOULD_NOT_EXIST'))
  end

  # 仅明确的组合不兼容返回回选状态，其它失败停止。
  def test_create_failure_only_retries_explicit_incompatibility
    output, status = execute('sim_create_and_boot', env: {'TEST_CREATE_FAIL' => 'Unable to create a device for device type iPhone'})
    assert_equal 2, status.exitstatus, output
    output, status = execute('sim_create_and_boot', env: {'TEST_CREATE_FAIL' => 'CoreSimulator service unavailable'})
    assert_equal 1, status.exitstatus, output
    assert trace.all? { |entry| entry[2] == 'create' }
  end

  # 失败输出或非 UUID 成功输出不能被当作新设备继续启动。
  def test_invalid_udid_stops_before_boot
    output, status = execute('sim_create_and_boot', env: {'TEST_CREATE_OUTPUT' => 'warning text'})
    refute status.success?, output
    assert_includes output, 'UDID 无效'
    assert_equal 1, trace.length
  end

  # 新设备启动失败时保留设备，禁止删除、关闭或重新创建。
  def test_boot_failure_preserves_created_device_and_reports_udid
    output, status = execute('sim_create_and_boot', env: {'TEST_BOOT_FAIL' => '1'})
    refute status.success?, output
    assert_includes output, '新设备已保留'
    assert_includes output, UDID
    assert_equal %w[create boot], trace.map { |entry| entry[2] }
  end

  # GUI 打开失败与启动等待失败均如实失败，并保留已创建的设备。
  def test_gui_and_bootstatus_failures_do_not_claim_completed_startup
    [{'TEST_OPEN_FAIL' => '1'}, {'TEST_BOOTSTATUS_FAIL' => '1'}].each do |env|
      output, status = execute('sim_create_and_boot', env: env)
      refute status.success?, output
      refute_includes output, '新模拟器已完成启动'
    end
    refute trace.any? { |entry| %w[delete shutdown erase].include?(entry[2]) }
  end

  # 新版 Xcode Device Hub 在同一 Xcode 内查找，核验 Bundle ID 及实际可执行文件。
  def test_device_hub_new_xcode_layout_and_bundle_validation
    FileUtils.remove_entry(@app)
    hub = File.join(File.dirname(@developer), 'Applications', 'DeviceHub.app')
    make_app(hub, 'com.apple.dt.Devices', 'DevicesTrampoline')
    output, status = execute('sim_check_environment; print -r -- "APP|$SIM_APP|$SIM_APP_KIND"')
    assert status.success?, output
    assert_includes output, "APP|#{hub}|com.apple.dt.Devices"
    File.write(File.join(hub, 'Contents', 'Info.plist'), app_plist('example.wrong', 'DevicesTrampoline'))
    output, status = execute('sim_check_environment')
    refute status.success?, output
    assert_includes output, '缺少健康'
  end

  # 最终确认任意非空输入和 EOF 都取消，含空格也不能绕过。
  def test_final_confirmation_cancels_nonempty_and_eof
    ["no\n", " \n", ''].each do |input|
      output, status = execute('sim_confirm_creation', input: input)
      assert_equal 130, status.exitstatus, output
    end
    assert_empty trace
  end

  # 完整选择循环只新增一次，名称包含进程编号以避免同秒并发碰撞。
  def test_complete_selection_flow_creates_once_with_process_suffix
    output, status = execute('sim_load_catalog && sim_interactive_loop', input: "1\n1\n\n")
    assert status.success?, output
    creates = trace.select { |entry| entry[2] == 'create' }
    assert_equal 1, creates.length
    assert_match(/iPhone Old@\d{4}\.\d\d\.\d\d \d\d:\d\d:\d\d-\d+\z/, creates.first[3])
    assert_includes output, '新模拟器已完成启动'
  end

  # 在选择或最终确认取消均不创建设备。
  def test_complete_selection_flow_cancels_before_mutation
    ["q\n", "1\nq\n", "1\n1\n \n"].each do |input|
      output, status = execute('sim_load_catalog && sim_interactive_loop', input: input)
      assert status.success?, output
      assert_includes output, '已取消，未创建模拟器'
    end
    refute trace.any? { |entry| entry[2] == 'create' }
  end

  # 旧元数据导致不兼容时可回选，回选取消后不会再次创建。
  def test_incompatible_create_returns_to_selection_and_can_cancel
    output, status = execute('sim_load_catalog && sim_interactive_loop', input: "1\n1\n\nq\n",
                             env: {'TEST_CREATE_FAIL' => 'Unable to create a device for device type'})
    assert status.success?, output
    assert_includes output, '组合不受支持'
    assert_includes output, '已取消，未创建模拟器'
    assert_equal 1, trace.count { |entry| entry[2] == 'create' }
  end

  # 阻塞的外部命令被限定等待，避免损坏工具无限挂起。
  def test_command_timeout_is_bounded
    output, status = execute('sim_run_to_file "$TEST_ROOT/run/command.out" 0 /bin/sleep 10')
    assert_equal 124, status.exitstatus, output
    assert_includes output, '等待超过'
  end

  private

  # 生成 Runtime 夹具，nil 表示旧版 Xcode 缺少 supportedDeviceTypes。
  def runtime(version, name, devices = nil, identifier: nil)
    value = {'name' => name, 'version' => version, 'isAvailable' => true,
             'identifier' => RUNTIME_PREFIX + (identifier || "iOS-#{version.tr('.', '-')}"),
             'supportedArchitectures' => ['arm64', 'x86_64']}
    value['supportedDeviceTypes'] = devices.map { |d| {'identifier' => DEVICE_PREFIX + d} } unless devices.nil?
    value
  end

  # 生成设备类型夹具。
  def device(name, identifier, minimum, family = 'iPhone')
    value = {'name' => name, 'identifier' => DEVICE_PREFIX + identifier, 'productFamily' => family}
    value['minRuntimeVersion'] = minimum unless minimum.nil?
    value
  end

  # 写入 simctl 原生 JSON 格式。
  def save_catalog
    File.write(File.join(@root, 'runtimes.json'), JSON.generate('runtimes' => @runtimes))
    File.write(File.join(@root, 'devicetypes.json'), JSON.generate('devicetypes' => @device_types))
    File.write(File.join(@root, 'devices.json'), JSON.generate('devices' => {}))
  end

  # 为 NSBundle 核验准备一个最小合法应用包。
  def make_app(path, identifier, executable)
    FileUtils.mkdir_p(File.join(path, 'Contents', 'MacOS'))
    File.write(File.join(path, 'Contents', 'Info.plist'), app_plist(identifier, executable))
    File.write(File.join(path, 'Contents', 'MacOS', executable), "#!/bin/zsh\nexit 0\n")
    FileUtils.chmod(0o700, File.join(path, 'Contents', 'MacOS', executable))
  end

  # 使用明确的包字段，避免测试依赖本机已安装应用。
  def app_plist(identifier, executable)
    %(<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>#{identifier}</string><key>CFBundleExecutable</key><string>#{executable}</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>)
  end

  # 写入私有 zsh 假命令，避免 Ruby 启动体检反向调用被替换的 xcrun。
  def write_mock(name, body)
    path = File.join(@bin, name)
    File.write(path, "#!/bin/zsh\n" + body)
    FileUtils.chmod(0o700, path)
  end

  # fzf 的版本探测与 Esc 取消均在私有进程中模拟。
  def make_fzf
    write_mock('fzf', <<~'ZSH')
      if [[ "$1" == --version ]]; then
        [[ "${TEST_FZF_BAD:-0}" == 0 ]]
        exit $?
      fi
      [[ "${TEST_FZF_CANCEL:-0}" == 0 ]] || exit 130
      /usr/bin/head -n 1
    ZSH
  end

  # 执行真实函数正文，只有 xcrun 与 GUI 打开命令替换为夹具。
  def execute(code, input: '', env: {})
    FileUtils.mkdir_p(@run)
    Open3.capture2e(@environment.merge(env), '/bin/zsh', '-c', @source + "\n" + @bootstrap + "\n" + code,
                   stdin_data: input, chdir: @root)
  end

  # 读取完整 argv，以发现命令拼接或意外写操作。
  def trace
    return [] unless File.exist?(@environment['TEST_TRACE'])
    File.binread(@environment['TEST_TRACE']).force_encoding(Encoding::UTF_8).split("\0\0").map { |record| record.split("\0") }
  end
end
