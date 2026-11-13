# Created by Jobs on 2026年11月10日，星期二.
# 隔离真实文件与子进程验证运行门禁；不会运行本机 Flutter 或安装 SDK。
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'open3'

class FlutterRunPreflightTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  HELPER = ENV.fetch('JOBS_PREFLIGHT_TEST_HELPER', File.join(ROOT, 'Scripts/【MacOS】Flutter运行前体检.zsh/【MacOS】Flutter运行前体检.zsh'))
  HEALTHY = <<~DOCTOR
    [✓] Flutter (Channel stable, 3.47.8)
        • Flutter version 3.47.8
    [✓] Android toolchain - develop for Android devices
        • Java version 17
        • All Android licenses accepted.
    [✓] Xcode - develop for iOS and macOS
        • CocoaPods version 1.16.2
    [✓] Chrome - develop for the web
  DOCTOR
  BUILD = "    ios       Build an iOS application.\n    apk       Build an APK.\n    hap       Build a Harmony application.\n    macos     Build macOS.\n    web       Build web.\n"

  def setup
    @temporary = Dir.mktmpdir('flutter-preflight-')
    @project = File.join(@temporary, 'project with spaces')
    @sdk = File.join(@temporary, 'sdk with spaces')
    @harmony = File.join(@temporary, 'harmony tools')
    %w[ios android ohos/AppScope macos web .dart_tool lib].each { |d| FileUtils.mkdir_p(File.join(@project, d)) }
    %w[build-profile.json5 oh-package.json5 AppScope/app.json5 hvigorfile.ts].each { |f| File.write(File.join(@project, 'ohos', f), '{}') }
    File.write(File.join(@project, 'pubspec.yaml'), "name: sample\ndependencies:\n  flutter:\n    sdk: flutter\n")
    FileUtils.mkdir_p(File.join(@sdk, 'packages/flutter'))
    FileUtils.mkdir_p(File.join(@sdk, 'packages/flutter_tools/.dart_tool'))
    FileUtils.mkdir_p(File.join(@sdk, 'bin/cache/dart-sdk/bin'))
    File.write(File.join(@sdk, 'packages/flutter_tools/.dart_tool/package_config.json'), '{}')
    File.write(File.join(@sdk, 'bin/cache/flutter_tools.snapshot'), 'isolated snapshot fixture')
    File.write(File.join(@sdk, 'bin/cache/flutter.version.json'), JSON.generate(frameworkVersion: '3.47.8', channel: 'stable'))
    write_executable(File.join(@sdk, 'bin/flutter'), "#!/bin/sh\necho shim-invoked >> \"$MOCK_TRACE\"\nexit 97\n")
    write_executable(File.join(@sdk, 'bin/cache/dart-sdk/bin/dart'), <<~'SH')
      #!/bin/sh
      printf '%s\n' "$*" >> "$MOCK_TRACE"
      case "$*" in
        *DoctorScope.dart*) cat "$MOCK_DOCTOR"; exit "${MOCK_DOCTOR_EXIT:-0}" ;;
        *' build -h') cat "$MOCK_BUILD"; exit "${MOCK_BUILD_EXIT:-0}" ;;
        *) echo forbidden-command; exit 98 ;;
      esac
    SH
    %w[ets native toolchains].each { |d| FileUtils.mkdir_p(File.join(@harmony, 'sdk/default/openharmony', d)) }
    %w[node ohpm hvigorw hdc java].each do |name|
      write_executable(File.join(@harmony, 'bin', name), <<~'SH')
        #!/bin/sh
        name=${0##*/}
        printf 'tool:%s:%s\n' "$name" "$*" >> "$MOCK_TRACE"
        [ "$MOCK_TOOL_FAIL" != "$name" ] || exit 7
        case "$name" in
          java) echo 'openjdk version "17.0.13"' ;;
          hdc) if [ "$1 $2" = 'list targets' ]; then echo fixture-device; else echo 'hdc 1.0.0'; fi ;;
          *) echo "$name 1.0.0" ;;
        esac
      SH
    end
    @doctor = File.join(@temporary, 'doctor.txt')
    @build = File.join(@temporary, 'build.txt')
    write_doctor(HEALTHY)
    File.write(@build, BUILD)
    @trace = File.join(@temporary, 'trace.txt')
    @env = {
      'MOCK_DOCTOR' => @doctor, 'MOCK_BUILD' => @build, 'MOCK_TRACE' => @trace,
      'DEVECO_STUDIO_HOME' => @harmony, 'JAVA_HOME' => '', 'TOOL_HOME' => '',
      'DEVECO_SDK_HOME' => '', 'OHOS_SDK_HOME' => '', 'MOCK_TOOL_FAIL' => '',
      'MOCK_DOCTOR_EXIT' => '0', 'MOCK_BUILD_EXIT' => '0', 'MOCK_TIMEOUT' => '',
      'JOBS_TEST_HELPER' => HELPER, 'JOBS_TEST_PROJECT' => @project, 'JOBS_TEST_SDK' => @sdk,
      'JOBS_TEST_LOG' => File.join(@temporary, 'operation.log')
    }
    @packages = [{ name: 'flutter', rootUri: File.join(@sdk, 'packages/flutter') }]
    write_config
  end

  def teardown
    FileUtils.remove_entry(@temporary)
  end

  def write_executable(path, text)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    File.chmod(0o755, path)
  end

  def write_config
    File.write(File.join(@project, '.dart_tool/package_config.json'), JSON.generate(configVersion: 2, packages: @packages))
  end

  def write_doctor(text)
    validators = []
    text.lines.each do |line|
      match = line.match(/^\[([✓!])\] (.+)$/)
      if match
        next if match[2].start_with?('Flutter')
        validators << { title: match[2].strip, type: match[1] == '✓' ? 'success' : 'partial', statusInfo: nil, messages: [] }
      elsif !validators.empty? && !line.strip.empty?
        validators.last[:messages] << { type: 'information', message: line.strip }
      end
    end
    File.write(@doctor, JSON.generate(schemaVersion: 1, complete: true, base: { frameworkVersion: '3.47.8', dartSdkVersion: '3.13.7' }, validators: validators))
  end

  def package(name, yaml)
    directory = File.join(@temporary, 'packages', name)
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, 'pubspec.yaml'), "name: #{name}\n#{yaml}")
    @packages << { name: name, rootUri: directory }
    write_config
  end

  def root_dependency(name)
    File.open(File.join(@project, 'pubspec.yaml'), 'a') { |f| f.write("  #{name}: any\n") }
  end

  def execute(platform = 'ios', overview: true)
    script = <<~'ZSH'
      setopt NO_NOMATCH PIPE_FAIL
      PROJECT_PATH="$JOBS_TEST_PROJECT"
      FLUTTER_BIN="$JOBS_TEST_SDK/bin/flutter"
      LOG_FILE="$JOBS_TEST_LOG"
      log() { print -r -- "$*"; }
      run_bounded() {
        local limit="$1" output="$2"
        shift 2
        if [[ -n "$MOCK_TIMEOUT" && "$output" == *".$MOCK_TIMEOUT" ]]; then
          : > "$output"
          return 124
        fi
        "$@" > "$output" 2>&1
      }
      load_run_preflight() { source "$JOBS_TEST_HELPER"; }
      load_run_preflight
      [[ "$JOBS_TEST_OVERVIEW" != 1 ]] || jobs_flutter_preflight_overview
      [[ -z "$JOBS_TEST_AFTER_OVERVIEW" ]] || eval "$JOBS_TEST_AFTER_OVERVIEW"
      jobs_flutter_preflight_require "$JOBS_TEST_PLATFORM" fixture-device
    ZSH
    output, status = Open3.capture2e(@env.merge('JOBS_TEST_PLATFORM' => platform, 'JOBS_TEST_OVERVIEW' => overview ? '1' : '0'), '/bin/zsh', '-c', script)
    [output, status.exitstatus]
  end

  def test_healthy_mobile_platforms_and_direct_snapshot_without_shim
    %w[ios android ohos].each do |platform|
      output, status = execute(platform)
      assert_equal 0, status, output
      %w[ios android ohos].each { |shown| assert_includes output, "✓ #{shown}：环境检查通过" }
    end
    trace = File.read(@trace)
    refute_includes trace, 'shim-invoked'
    assert_includes trace, 'DoctorScope.dart all'
    refute_match(/(?:precache|pub get|--android-licenses| run )/, trace)
  end

  def test_android_license_warning_does_not_block_healthy_ios
    write_doctor(HEALTHY.sub('[✓] Android toolchain', '[!] Android toolchain').sub('All Android licenses accepted.', 'Some Android licenses not accepted.'))
    @env['MOCK_DOCTOR_EXIT'] = '1'
    output, status = execute('ios')
    assert_equal 0, status, output
    assert_includes output, '✖ android：未就绪'
    assert_includes output, 'Flutter 本地官方验证器退出码：1'
    output, status = execute('android')
    assert_equal 1, status, output
    assert_includes output, 'Some Android licenses not accepted.'
  end

  def test_unknown_or_interrupted_doctor_never_passes
    [2, 124, 130].each do |code|
      @env['MOCK_DOCTOR_EXIT'] = code.to_s
      output, status = execute
      assert_equal 1, status, output
    end
    @env['MOCK_DOCTOR_EXIT'] = '0'
    File.write(@doctor, 'unrecognized output')
    output, status = execute
    assert_equal 1, status, output
  end

  def test_missing_ohos_structure_remains_visible_while_ios_can_run
    FileUtils.remove_entry(File.join(@project, 'ohos'))
    output, status = execute('ios')
    assert_equal 0, status, output
    assert_includes output, '✖ ohos：未就绪'
    output, status = execute('ohos')
    assert_equal 1, status, output
    assert_includes output, '缺少 ohos/build-profile.json5'
  end

  def test_missing_snapshot_does_not_bootstrap_sdk
    File.delete(File.join(@sdk, 'bin/cache/flutter_tools.snapshot'))
    output, status = execute
    assert_equal 1, status, output
    refute File.exist?(@trace)
  end

  def test_tool_exit_and_missing_hap_block_only_harmony
    @env['MOCK_TOOL_FAIL'] = 'hdc'
    output, status = execute('ohos')
    assert_equal 1, status, output
    assert_includes output, 'hdc 版本检查失败（退出码 7）'
    output, status = execute('ios')
    assert_equal 0, status, output
    @env['MOCK_TOOL_FAIL'] = ''
    File.write(@build, BUILD.lines.reject { |line| line.include?('hap ') }.join)
    output, status = execute('ohos')
    assert_equal 1, status, output
    assert_includes output, '没有 flutter build hap 能力'
  end

  def test_stale_package_sdk_and_timeout_cannot_run
    @packages[0][:rootUri] = @project
    write_config
    output, status = execute
    assert_equal 1, status, output
    assert_includes output, '依赖索引未指向当前工程 SDK'
    @env['MOCK_TIMEOUT'] = 'doctor'
    output, status = execute
    assert_equal 1, status, output
    assert_includes output, 'doctor=124'
  end

  def test_native_plugin_without_harmony_support_blocks_harmony
    package('private_plugin', "flutter:\n  plugin:\n    platforms:\n      android:\n        pluginClass: Example\n")
    root_dependency('private_plugin')
    output, status = execute('ohos')
    assert_equal 1, status, output
    assert_includes output, 'private_plugin'
  end

  def test_federated_android_implementation_is_not_required_on_harmony
    package('parent_plugin', "dependencies:\n  android_impl: any\n  ohos_impl: any\nflutter:\n  plugin:\n    platforms:\n      android:\n        default_package: android_impl\n      ohos:\n        default_package: ohos_impl\n")
    package('android_impl', "dependencies:\n  android_only_native: any\nflutter:\n  plugin:\n    implements: parent_plugin\n    platforms:\n      android:\n        pluginClass: AndroidPlugin\n")
    package('android_only_native', "flutter:\n  plugin:\n    platforms:\n      android:\n        pluginClass: Native\n")
    package('ohos_impl', "flutter:\n  plugin:\n    implements: parent_plugin\n    platforms:\n      ohos:\n        pluginClass: HarmonyPlugin\n")
    root_dependency('parent_plugin')
    output, status = execute('ohos')
    assert_equal 0, status, output
    root_dependency('android_impl')
    output, status = execute('ohos')
    assert_equal 1, status, output
    assert_includes output, 'android_impl'
  end

  def test_no_overview_and_unknown_platform_fail_closed
    output, status = execute('ios', overview: false)
    assert_equal 1, status, output
    assert_includes output, '体检未完成'
    output, status = execute('custom-device')
    assert_equal 1, status, output
    assert_includes output, '未识别或未完成此平台'
  end

  def test_declared_fvm_version_cannot_use_other_sdk
    FileUtils.mkdir_p(File.join(@project, '.fvm'))
    File.symlink(@sdk, File.join(@project, '.fvm/flutter_sdk'))
    File.write(File.join(@project, '.fvmrc'), JSON.generate(flutter: '3.47.7'))
    output, status = execute('ios')
    assert_equal 1, status, output
    assert_includes output, '实际 SDK 3.47.8'
    File.write(File.join(@project, '.fvmrc'), JSON.generate(flutter: '3.47.8'))
    output, status = execute('ios')
    assert_equal 0, status, output
  end

  def test_menu_time_changes_and_revoked_hdc_authorization_block_run
    @env['JOBS_TEST_AFTER_OVERVIEW'] = 'print "# changed" >> "$PROJECT_PATH/pubspec.yaml"'
    output, status = execute('ios')
    assert_equal 1, status, output
    assert_includes output, '体检后 SDK、工程声明、依赖索引或工具链环境已变化'
    @env['JOBS_TEST_AFTER_OVERVIEW'] = 'MOCK_TOOL_FAIL=hdc; export MOCK_TOOL_FAIL'
    output, status = execute('ohos')
    assert_equal 1, status, output
    assert_includes output, 'hdc 版本检查失败'
  end

  def test_target_doctor_is_rechecked_after_device_selection
    @env['JOBS_TEST_AFTER_OVERVIEW'] = 'print "[✓] Flutter SDK\\n[!] Xcode - missing" > "$MOCK_DOCTOR"; export MOCK_DOCTOR_EXIT=1'
    output, status = execute('ios')
    assert_equal 1, status, output
    assert_includes output, '工具链复核失败'
  end

  def test_incomplete_json_or_legacy_prefixed_output_cannot_pass
    data = JSON.parse(File.read(@doctor))
    data['complete'] = false
    File.write(@doctor, JSON.generate(data))
    output, status = execute('ios')
    assert_equal 1, status, output
    File.write(@doctor, "[   +2 ms] [✓] Flutter SDK\n[        ] [✓] Xcode - healthy\n")
    output, status = execute('ios')
    assert_equal 1, status, output
  end

  def usb_node(serial: 'TEST12345678', location: 1, product: 'HDC Device', vendor: 4817)
    { 'IORegistryEntryName' => product, 'USB Product Name' => product, 'idVendor' => vendor,
      'idProduct' => 4353, 'locationID' => location, 'USB Serial Number' => serial }
  end

  def usb_rows(tree, visible: '', targets: nil)
    json = File.join(@temporary, 'usb.json')
    plist = File.join(@temporary, 'usb.plist')
    File.write(json, JSON.generate(tree))
    _, converted = Open3.capture2e('/usr/bin/plutil', '-convert', 'xml1', '-o', plist, json)
    assert converted.success?
    visible_file = File.join(@temporary, 'visible.txt')
    File.write(visible_file, visible)
    arguments = ['usb-harmony', plist, visible_file]
    if targets
      target_file = File.join(@temporary, 'hdc.txt')
      File.write(target_file, targets)
      arguments << target_file
    end
    Open3.capture2e('/usr/bin/osascript', '-l', 'JavaScript', File.join(File.dirname(HELPER), 'Flutter运行前体检.jxa'), *arguments)
  end

  def test_usb_hdc_detected_without_flutter_and_vendor_alone_is_not_harmony
    tree = { 'IORegistryEntryName' => 'Root', 'IORegistryEntryChildren' => [usb_node, usb_node(product: 'HUAWEI phone', location: 2), usb_node(product: 'iPhone', vendor: 1452, location: 3)] }
    output, status = usb_rows(tree)
    assert status.success?, output
    assert_equal 1, output.lines.length
    assert_match(/^__harmony_usb__:[^\t]+\t鸿蒙 USB 设备（HDC Device）— 已连接，环境未就绪$/, output.strip)
    refute_includes output.split("\t", 2).last, 'TEST12345678'
  end

  def test_usb_duplicates_keep_distinct_physical_locations_and_visible_ids_are_precise
    first = usb_node
    output, status = usb_rows([first, first, usb_node(serial: 'SECOND123', location: 2)], visible: "TEST12345678\n")
    assert status.success?, output
    assert_equal 1, output.lines.length
    assert_includes output, 'SECOND123'
    output, status = usb_rows([first, usb_node(location: 2)], visible: "TEST12345678\n")
    assert status.success?, output
    assert_equal 2, output.lines.length
    assert_equal 2, output.lines.map { |line| line.split("\t").first }.uniq.length
  end

  def test_hdc_rows_merge_usb_serial_and_ignore_status_or_already_visible_ids
    output, status = usb_rows([usb_node], visible: "VISIBLE123\n", targets: "TEST12345678\nREMOTE12345\nREMOTE12345\n[Empty]\nUnauthorized\nOffline\nID123 Unauthorized\nVISIBLE123\n")
    assert status.success?, output
    assert_equal 2, output.lines.length
    assert_includes output, '__harmony_usb__:'
    assert_includes output, '__harmony_hdc__:REMOTE12345'
    refute_includes output, 'Unauthorized'
    refute_includes output, 'VISIBLE123'
  end

  def discovery(usb_exit: 0, usb_text: nil, targets: nil, environment: {})
    usb_rows([]) if usb_text.nil?
    fixture = File.join(@temporary, 'usb.plist')
    File.write(fixture, usb_text) unless usb_text.nil?
    if targets
      write_executable(File.join(@harmony, 'bin/hdc'), "#!/bin/sh\ncat <<'TARGETS'\n#{targets}\nTARGETS\n")
    end
    script = <<~'ZSH'
      setopt NO_NOMATCH PIPE_FAIL
      PROJECT_PATH="$JOBS_TEST_PROJECT"
      FLUTTER_BIN="$JOBS_TEST_SDK/bin/flutter"
      LOG_FILE="$JOBS_TEST_LOG"
      log() { print -r -- "$*"; print -r -- "$*" >> "$LOG_FILE"; }
      run_bounded() {
        local limit="$1" output="$2"
        shift 2
        if [[ "$1" == /usr/sbin/ioreg ]]; then
          /bin/cat "$MOCK_USB" > "$output"
          return "$MOCK_USB_EXIT"
        fi
        "$@" > "$output" 2>&1
      }
      source "$JOBS_TEST_HELPER"
      jobs_flutter_harmony_discovery_rows $'visible-id\t已列出的设备'
    ZSH
    Open3.capture3(@env.merge('MOCK_USB' => fixture, 'MOCK_USB_EXIT' => usb_exit.to_s).merge(environment), '/bin/zsh', '-c', script)
  end

  def test_discovery_finds_explicit_sdk_hdc_without_complete_build_toolchain
    sdk = File.join(@temporary, 'incomplete isolated sdk')
    FileUtils.mkdir_p(File.join(sdk, 'toolchains'))
    FileUtils.cp(File.join(@harmony, 'bin/hdc'), File.join(sdk, 'toolchains/hdc'))
    output, warning, status = discovery(environment: { 'OHOS_SDK_HOME' => sdk })
    assert status.success?, warning
    assert_includes output, '__harmony_hdc__:fixture-device'
    evidence = File.read(@env['JOBS_TEST_LOG'] + '.harmony-discovery')
    assert_includes evidence, "HDC 路径：#{File.realpath(sdk)}/toolchains/hdc"
    assert_includes evidence, 'HDC list targets 退出码：0'
    assert_includes evidence, '诊断行数：1'
    refute Dir.exist?(File.join(sdk, 'ets'))
  end

  def test_discovery_resolves_hdc_on_current_process_path_without_a_build_root
    output, warning, status = discovery(environment: { 'DEVECO_STUDIO_HOME' => '', 'PATH' => "#{@harmony}/bin:/usr/bin:/bin" })
    assert status.success?, warning
    assert_includes output, '__harmony_hdc__:fixture-device'
    assert_includes File.read(@env['JOBS_TEST_LOG'] + '.harmony-discovery'), "HDC 路径：#{File.realpath(@harmony)}/bin/hdc"
  end

  def test_discovery_preserves_hdc_when_usb_query_times_out_or_plist_is_invalid
    [[124, nil], [0, 'not a plist']].each do |code, text|
      output, warning, status = discovery(usb_exit: code, usb_text: text)
      assert status.success?, warning
      assert_equal 1, output.lines.length
      assert_includes output, '__harmony_hdc__:fixture-device'
      assert_includes warning, code == 124 ? 'USB 调试节点读取失败（退出码 124）' : 'USB/设备清单解析失败'
      evidence = File.read(@env['JOBS_TEST_LOG'] + '.harmony-discovery')
      assert_includes evidence, "USB ioreg 退出码：#{code}"
    end
  end

  def test_discovery_retains_failed_hdc_output_but_never_creates_a_device_from_it
    write_executable(File.join(@harmony, 'bin/hdc'), "#!/bin/sh\necho misleading-device\nexit 7\n")
    output, warning, status = discovery
    assert status.success?, warning
    assert_equal '', output
    assert_includes warning, 'HDC 目标查询失败（退出码 7）'
    assert_equal "misleading-device\n", File.read(@env['JOBS_TEST_LOG'] + '.harmony-hdc.targets')
    assert_includes File.read(@env['JOBS_TEST_LOG'] + '.harmony-discovery'), 'HDC list targets 退出码：7'
  end

  def test_hdc_unauthorized_and_offline_are_visible_evidence_without_synthetic_ids
    output, warning, status = discovery(targets: "authorized-id\nID123 Unauthorized\nOFF123 Offline\n[Empty]\n[Fail] could not connect\n")
    assert status.success?, warning
    assert_equal 1, output.lines.length
    assert_includes output, '__harmony_hdc__:authorized-id'
    refute_includes output, 'ID123'
    refute_includes output, 'OFF123'
    assert_includes warning, '未授权 1，离线 1，非目标消息 1'
    assert_includes warning, '开发者模式本身不代表已授权'
  end

  def test_discovery_reports_absent_and_ambiguous_explicit_hdc_without_fallback
    sdk = File.join(@temporary, 'selected sdk')
    output, warning, status = discovery(environment: { 'OHOS_SDK_HOME' => sdk })
    assert status.success?, warning
    assert_equal '', output
    assert_includes warning, '未找到可执行 HDC'
    %w[20 21].each do |version|
      FileUtils.mkdir_p(File.join(sdk, version, 'toolchains'))
      FileUtils.cp(File.join(@harmony, 'bin/hdc'), File.join(sdk, version, 'toolchains/hdc'))
    end
    output, warning, status = discovery(environment: { 'OHOS_SDK_HOME' => sdk })
    assert status.success?, warning
    assert_equal '', output
    assert_includes warning, '发现多个 HDC'
    refute File.exist?(@trace)
  end

  def test_discovery_propagates_cancellation_instead_of_continuing_to_menu
    output, warning, status = discovery(usb_exit: 130)
    assert_equal 130, status.exitstatus, warning
    assert_equal '', output
    write_executable(File.join(@harmony, 'bin/hdc'), "#!/bin/sh\nexit 130\n")
    output, warning, status = discovery
    assert_equal 130, status.exitstatus, warning
    assert_equal '', output
  end

  def test_usb_invalid_tree_fails_and_product_fields_cannot_inject_rows
    output, status = usb_rows({ 'IORegistryEntryChildren' => 'broken' })
    refute status.success?, output
    output, status = usb_rows([usb_node(product: "HDC Device\nInjected\tRow", serial: "BAD\tSERIAL")])
    assert status.success?, output
    assert_equal 1, output.lines.length
    assert_equal 2, output.strip.split("\t").length
    assert_includes output, 'HDC Device Injected Row'
    output, status = usb_rows([usb_node(vendor: '4817')])
    assert status.success?, output
    assert_equal '', output.strip
  end

  def match_harmony_target(key, devices, usb = nil)
    file = File.join(@temporary, 'target-devices.json')
    File.write(file, JSON.generate(devices))
    args = ['harmony-run-target', key, file]
    args << usb if usb
    Open3.capture2e('/usr/bin/osascript', '-l', 'JavaScript', File.join(File.dirname(HELPER), 'Flutter运行前体检.jxa'), *args)
  end

  def test_harmony_target_is_exact_supported_and_unique
    target = { id: 'ORIGINAL123', isSupported: true, targetPlatform: 'ohos-arm64' }
    output, status = match_harmony_target('__harmony_hdc__:ORIGINAL123', [target, target.merge(id: 'OTHER123')])
    assert status.success?, output
    assert_equal 'ORIGINAL123', output.strip
    output, status = match_harmony_target('__harmony_hdc__:ORIGINAL123', [target.merge(isSupported: false)])
    assert status.success?, output
    assert_equal '', output.strip
    output, status = match_harmony_target('__harmony_hdc__:ORIGINAL123', [target, target])
    refute status.success?, output
    output, status = match_harmony_target('__harmony_hdc__:ORIGINAL123', [target.merge(targetPlatform: 'android-arm64')])
    assert status.success?, output
    assert_equal '', output.strip
    output, status = match_harmony_target('__harmony_hdc__:192.168.1.5%3A8888', [target.merge(id: '192.168.1.5:8888')])
    assert status.success?, output
    assert_equal '192.168.1.5:8888', output.strip
  end

  def test_usb_target_requires_current_physical_identity_and_nonempty_unique_serial
    output, status = usb_rows([usb_node])
    assert status.success?, output
    key = output.strip.split("\t").first
    target = [{ id: 'TEST12345678', isSupported: true, targetPlatform: 'openharmony-arm64' }]
    output, status = match_harmony_target(key, target, File.join(@temporary, 'usb.plist'))
    assert status.success?, output
    assert_equal 'TEST12345678', output.strip
    usb_rows([usb_node(location: 2)])
    output, status = match_harmony_target(key, target, File.join(@temporary, 'usb.plist'))
    refute status.success?, output
    assert_includes output, '物理身份发生变化'
    usb_rows([usb_node, usb_node(location: 2)])
    output, status = match_harmony_target(key, target, File.join(@temporary, 'usb.plist'))
    refute status.success?, output
    assert_includes output, '相同序列号'
    output, status = usb_rows([usb_node(serial: '')])
    assert status.success?, output
    key = output.strip.split("\t").first
    output, status = match_harmony_target(key, target, File.join(@temporary, 'usb.plist'))
    refute status.success?, output
    assert_includes output, '没有可核验序列号'
  end

  def test_project_hvigor_wrapper_does_not_require_executable_bit_or_global_hvigor
    File.delete(File.join(@harmony, 'bin/hvigorw'))
    File.write(File.join(@project, 'ohos/hvigorw'), "#!/bin/sh\n[ \"$PWD\" = \"$JOBS_TEST_PROJECT/ohos\" ] || exit 72\necho 'project hvigor 1.0.0'\n")
    File.chmod(0o644, File.join(@project, 'ohos/hvigorw'))
    output, status = execute('ohos')
    assert_equal 0, status, output
  end
end
