# frozen_string_literal: true

# FlutterRunnerJSONTests.rb · JobsFlutterRunner
# Created by Jobs on 2026年10月20日，星期二.
# 只使用临时夹具验证 JXA 协议，不创建模拟器、不注册 launchd、不启动 Flutter。

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'open3'

class FlutterRunnerJSONTests < Minitest::Test
  HELPER = File.expand_path('../Scripts/FlutterRunner.jxa', __dir__)

  def setup
    @root = Dir.mktmpdir('JobsFlutterRunnerJSON-')
    @project = File.join(@root, '项目 空格 $(touch SHOULD_NOT_EXIST)')
    FileUtils.mkdir_p(@project)
    File.write(File.join(@project, 'pubspec.yaml'), "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_flutter_devices_keep_real_supported_ids_and_two_columns
    path = write_json('devices.json', [
                        { id: 'ios-id', name: "iPhone\t17\nPro\e[0m", targetPlatform: 'ios', isSupported: true },
                        { id: 'macos', name: 'Mac', targetPlatform: 'darwin-arm64' },
                        { id: 'unsupported', name: 'Old', supported: false },
                        { id: 'unsupported2', name: 'Old', isSupported: false },
                        { id: "bad\nidentifier", name: 'invalid' },
                        { id: 'ios-id', name: 'duplicate' },
                        { name: 'missing' }
                      ])
    output = successful('devices', path)
    assert_equal 2, output.lines.length
    assert_equal ['ios-id', 'macos'], output.lines.map { |line| line.split("\t", 2)[0] }
    output.lines.each { |line| assert_equal 2, line.chomp.split("\t", -1).length }
    refute_match(/[\x00-\x08\x0b-\x1f\x7f]/, output)
    assert_includes output, 'iPhone 17 Pro [0m — ios'
  end

  def test_empty_device_array_is_distinct_from_malformed_response
    assert_empty successful('devices', write_json('empty.json', [])).strip
    [{ devices: [] }, nil, 'unexpected'].each_with_index do |data, index|
      output, status = execute('devices', write_json("bad#{index}.json", data))
      refute status.success?, output
      assert_includes output, '必须是数组'
    end
    output, status = execute('devices', write_data('broken.json', '['))
    refute status.success?, output
  end

  def test_project_platform_directories_filter_known_devices_but_preserve_custom_platforms
    values = [
      { id: 'android-phone', name: 'Phone', targetPlatform: 'android-arm64' },
      { id: 'iphone', name: 'iPhone', targetPlatform: 'ios' },
      { id: 'desktop-mac', name: 'Mac', targetPlatform: 'darwin-arm64' },
      { id: 'browser', name: 'Chrome', targetPlatform: 'web-javascript' },
      { id: 'desktop-linux', name: 'Linux', targetPlatform: 'linux-x64' },
      { id: 'desktop-windows', name: 'Windows', targetPlatform: 'windows-x64' },
      { id: 'custom-platform', name: 'Custom', targetPlatform: 'custom-extension' }
    ]
    path = write_json('platform-devices.json', values)
    assert_equal 7, successful('devices', path).lines.length
    assert_equal ['custom-platform'], successful('devices', path, @project).lines.map { |line| line.split("\t", 2)[0] }
    %w[android ios macos web linux windows].each_with_index do |directory, index|
      FileUtils.mkdir_p(File.join(@project, directory))
      output = successful('devices', path, @project)
      assert_equal index + 2, output.lines.length
      assert_equal values[0..index].map { |value| value[:id] } + ['custom-platform'], output.lines.map { |line| line.split("\t", 2)[0] }
    end
    FileUtils.remove_entry(File.join(@project, 'android'))
    File.write(File.join(@project, 'android'), 'not a directory')
    refute_includes successful('devices', path, @project), 'android-phone'
  end

  def test_emulator_array_uses_official_daemon_fields_and_only_lists_android
    path = write_json('emulators.json', [
                        { id: 'Pixel_API_35', name: "Pixel\tAPI 35\nPhone", category: 'mobile', platformType: 'android' },
                        { id: 'Pixel_API_35', name: 'duplicate', platformType: 'android' },
                        { id: 'apple_ios_simulator', name: 'iOS Simulator', category: 'mobile', platformType: 'ios' },
                        { id: "bad\nname", name: 'Bad', platformType: 'android' },
                        { id: 'unknown', name: 'Unknown', platformType: 'custom' }
                      ])
    assert_equal "Pixel_API_35\tPixel API 35 Phone — Android", successful('emulators', path).strip
    assert_empty successful('emulators', write_json('no-emulators.json', [])).strip
    output, status = execute('emulators', write_json('invalid-emulators.json', { emulators: [] }))
    refute status.success?, output
    assert_includes output, '模拟器响应必须是数组'
  end

  def test_simulators_only_use_available_ios_runtimes_and_devices
    path = write_json('simctl.json', simulator_fixture)
    output = successful('simulators', path)
    assert_equal ['booted-ios', 'shutdown-ios', 'legacy-ios'], output.lines.map { |line| line.split("\t", 2)[0] }
    assert_includes output, "booted-ios\tiPhone 17 — Booted — iOS 26.0"
    refute_includes output, 'unavailable'
    refute_includes output, 'tv-device'
    refute_includes output, 'duplicate'
    output.lines.each { |line| assert_equal 2, line.chomp.split("\t", -1).length }
  end

  def test_runtime_choices_are_available_ios_versions_newest_first
    output = successful('runtimes', write_json('simctl.json', simulator_fixture))
    assert_equal [ios_runtime('26-0'), ios_runtime('18-5')], output.lines.map { |line| line.split("\t", 2)[0] }
    assert_equal ["#{ios_runtime('26-0')}\tiOS 26.0", "#{ios_runtime('18-5')}\tiOS 18.5"], output.lines.map(&:chomp)
  end

  def test_duplicate_available_runtime_builds_only_offer_one_version_name
    fixture = simulator_fixture
    fixture[:runtimes] << { identifier: ios_runtime('26-0-duplicate'), name: 'iOS 26.0', version: '26.0', isAvailable: true }
    output = successful('runtimes', write_json('duplicate-runtimes.json', fixture))
    assert_equal 2, output.lines.length
    assert_equal 1, output.scan(/\tiOS 26\.0/).length
    assert_includes output, "#{ios_runtime('26-0')}\tiOS 26.0"
    fixture[:devices][ios_runtime('26-0-duplicate')] = [{ udid: 'second-build-device', name: 'iPhone 17', state: 'Shutdown', isAvailable: true }]
    output = successful('simulators', write_json('duplicate-runtimes.json', fixture))
    assert_includes output, 'second-build-device'
  end

  def test_device_type_choices_exclude_ipad_watch_and_tv
    output = successful('types', write_json('simctl.json', simulator_fixture))
    assert_equal "com.apple.CoreSimulator.SimDeviceType.iPhone-17\tiPhone 17", output.strip
  end

  def test_preferred_types_put_models_with_available_runtime_first
    output = successful('preferred-types', write_json('preferred.json', combination_fixture), 'arm64')
    labels = output.lines.map { |line| line.chomp.split("\t", 2)[1] }
    assert_equal ['iPhone New', 'iPhone Old', 'iPhone Unknown', 'iPhone Range（本机无可搭配系统）'], labels
    assert_equal 'com.apple.CoreSimulator.SimDeviceType.iPhone-New', output.lines.first.split("\t", 2)[0]
    output.lines.each { |line| assert_equal 2, line.chomp.split("\t", -1).length }
  end

  def test_preferred_types_rank_by_current_architecture_only
    output = successful('preferred-types', write_json('preferred.json', combination_fixture), 'x86_64')
    labels = output.lines.map { |line| line.chomp.split("\t", 2)[1] }
    # 26.0 只支持 arm64，x86_64 下 iPhone New 降到未知组，iPhone Old 升到已确认组；
    # 型号本身不因架构隐藏，只是推荐顺序变化。
    assert_equal ['iPhone Old', 'iPhone Unknown', 'iPhone New', 'iPhone Range（本机无可搭配系统）'], labels
  end

  def test_compatible_runtimes_hide_unsupported_versions_and_mark_unknown
    output = successful('compatible-runtimes', write_json('compatible.json', combination_fixture),
                        'arm64', 'com.apple.CoreSimulator.SimDeviceType.iPhone-New')
    labels = output.lines.map { |line| line.chomp.split("\t", 2)[1] }
    assert_equal ['iOS 26.0', 'iOS 17.0（未确认支持）'], labels
    refute_includes output, 'iOS 18.5'
    refute_includes output, ios_runtime('16-4')
  end

  def test_compatible_runtimes_respect_version_bounds_without_whitelist
    assert_empty successful('compatible-runtimes', write_json('compatible.json', combination_fixture),
                            'arm64', 'com.apple.CoreSimulator.SimDeviceType.iPhone-Range').strip
  end

  def test_compatible_runtimes_reject_unknown_model
    output, status = execute('compatible-runtimes', write_json('compatible.json', combination_fixture),
                             'arm64', 'com.apple.CoreSimulator.SimDeviceType.iPhone-Missing')
    refute status.success?, output
    assert_includes output, '所选型号不属于当前设备清单'
  end

  def test_combination_modes_reject_malformed_simctl_response
    output, status = execute('preferred-types', write_json('bad-preferred.json', { runtimes: [] }))
    refute status.success?, output
    assert_includes output, 'simctl 响应缺少'
    output, status = execute('compatible-runtimes', write_json('bad-compatible.json', { runtimes: [] }),
                             'arm64', 'com.apple.CoreSimulator.SimDeviceType.iPhone-New')
    refute status.success?, output
    assert_includes output, 'simctl 响应缺少'
  end

  def test_simctl_missing_structure_is_a_parse_failure
    %w[simulators runtimes types].each do |mode|
      output, status = execute(mode, write_json('simctl-bad.json', { runtimes: [] }))
      refute status.success?, output
      assert_includes output, 'simctl 响应缺少'
    end
  end

  def test_common_pubspec_block_and_flow_forms_are_accepted
    fixtures = [
      "dependencies:\n  flutter:\n    sdk: flutter # official\n",
      "'dependencies':\n  \"flutter\": {sdk: 'flutter'}\n",
      'dependencies: {flutter: {sdk: flutter}}',
      'dependencies: {http: any, flutter: {sdk: "flutter"}} # actual',
      "\uFEFFname: fixture\r\ndependencies:\r\n  flutter:\r\n    sdk: flutter\r\n",
      "description: 'dependencies: not a map'\ndependencies:\n  flutter:\n    sdk: flutter\n",
      "description: |\n  some text\ndependencies:\n  http: any\n  flutter:\n    sdk: flutter\ndev_dependencies:\n  flutter_test:\n    sdk: flutter\n"
    ]
    fixtures.each do |contents|
      File.write(File.join(@project, 'pubspec.yaml'), contents)
      assert_equal 'true', successful('validate', @project).strip, contents
    end
  end

  def test_misleading_descriptions_wrong_keys_and_ambiguous_yaml_are_rejected
    fixtures = [
      "name: dart_only\ndependencies:\n  http: any\n",
      "# dependencies:\n#   flutter:\n#     sdk: flutter\n",
      "description: |\n  dependencies:\n    flutter:\n      sdk: flutter\n",
      "description: >\n  dependencies: {flutter: {sdk: flutter}}\n",
      "dev_dependencies:\n  flutter_test:\n    sdk: flutter\n",
      "dependencies:\n  flutter_test:\n    sdk: flutter\n",
      "dependencies:\n  fluter:\n    sdk: flutter\n",
      "dependencies:\n  example:\n    flutter:\n      sdk: flutter\n",
      "dependencies:\n  flutter:\n    sdk: dart\n",
      "dependencies:\n  flutter:\n    sdk: flutter\ndependencies:\n  http: any\n",
      "dependencies:\n  flutter:\n    sdk: flutter\n  flutter:\n    sdk: flutter\n",
      "dependencies:\n  flutter:\n    sdk: flutter\n    sdk: dart\n",
      'dependencies: {flutter: {sdk: flutter, sdk: dart}}',
      'dependencies: {flutter: {sdk: flutter}, flutter: {sdk: flutter}}',
      "---\ndependencies:\n  flutter:\n    sdk: flutter\n",
      "dependencies:\n\tflutter:\n\t  sdk: flutter\n",
      "dependencies:\n  flutter:\n    sdk: flutter\u0000\n",
      "dependencies:\n  flutter: *sdk\n",
      "dependencies:\n  flutter:\n    sdk: !custom flutter\n"
    ]
    fixtures.each do |contents|
      File.write(File.join(@project, 'pubspec.yaml'), contents)
      assert_equal 'false', successful('validate', @project).strip, contents
    end
  end

  def test_validator_rejects_root_and_pubspec_symlinks_large_files_and_packages
    link = File.join(@root, 'linked-project')
    File.symlink(@project, link)
    assert_equal 'false', successful('validate', link).strip
    assert_equal 'false', successful('validate', link + '/').strip
    manifest = File.join(@project, 'pubspec.yaml')
    external = write_data('external.yaml', File.read(manifest))
    File.unlink(manifest)
    File.symlink(external, manifest)
    assert_equal 'false', successful('validate', @project).strip
    File.unlink(manifest)
    File.write(manifest, "dependencies: {flutter: {sdk: flutter}}\n" + ('#' * 1_048_576))
    assert_equal 'false', successful('validate', @project).strip
    package = File.join(@root, 'Fixture.app')
    FileUtils.mkdir_p(package)
    File.write(File.join(package, 'pubspec.yaml'), 'dependencies: {flutter: {sdk: flutter}}')
    assert_equal 'false', successful('validate', package).strip
    assert_equal 'false', successful('validate', File.join(@root, 'missing')).strip
  end

  def test_plist_preserves_argument_boundaries_and_only_selected_environment
    session = File.join(@root, "session & ' \" space")
    FileUtils.mkdir_p(session)
    worker = write_data("worker ' ; $(touch SHOULD_NOT_EXIST).zsh", '# fixture only')
    flutter = File.join(@root, 'Flutter SDK & space', 'bin', 'flutter')
    env = { 'DEVELOPER_DIR' => '/Applications/Xcode Custom.app/Contents/Developer',
            'ANDROID_SDK_ROOT' => '/example/android-sdk', 'PUB_CACHE' => '',
            'http_proxy' => 'http://127.0.0.1:7990', 'JOBS_TEST_SECRET' => 'never export' }
    output, status = execute('plist', session, 'com.jobs.flutter.fixture', worker, @project, flutter, 'device-42', env: env)
    assert status.success?, output
    path = File.join(session, 'job.plist')
    assert_equal path, output.strip
    xml = File.read(path)
    assert_includes xml, '<!DOCTYPE plist'
    result, status = Open3.capture2e('/usr/bin/plutil', '-convert', 'json', '-o', '-', path)
    assert status.success?, result
    plist = JSON.parse(result)
    assert_equal ['/bin/zsh', worker, '--worker', session, @project, flutter, 'device-42'], plist['ProgramArguments']
    assert_equal @project, plist['WorkingDirectory']
    assert_equal true, plist['RunAtLoad']
    assert_equal false, plist['KeepAlive']
    assert_equal 20, plist['ExitTimeOut']
    assert_equal 'Interactive', plist['ProcessType']
    assert_equal File.join(session, 'run.log'), plist['StandardOutPath']
    assert_equal plist['StandardOutPath'], plist['StandardErrorPath']
    %w[DEVELOPER_DIR ANDROID_SDK_ROOT PUB_CACHE http_proxy].each do |key|
      assert_equal env[key], plist['EnvironmentVariables'][key]
    end
    refute plist['EnvironmentVariables'].key?('JOBS_TEST_SECRET')
    assert_equal 0o600, File.stat(path).mode & 0o777
    refute File.exist?(File.join(@project, 'SHOULD_NOT_EXIST'))
    refute File.exist?(File.join(@root, 'SHOULD_NOT_EXIST'))
  end

  def test_plist_rejects_invalid_label_and_linked_destination_without_writes
    session = File.join(@root, 'session')
    FileUtils.mkdir_p(session)
    worker = write_data('worker.zsh', '# fixture')
    ['bad/label', "bad\nlabel", 'bad label', ''].each do |label|
      output, status = execute('plist', session, label, worker, @project, '/bin/flutter', 'macos')
      refute status.success?, output
      assert_includes output, 'label 无效'
      refute File.exist?(File.join(session, 'job.plist'))
    end
    external = write_data('outside.plist', 'keep')
    File.symlink(external, File.join(session, 'job.plist'))
    output, status = execute('plist', session, 'com.jobs.fixture', worker, @project, '/bin/flutter', 'macos')
    refute status.success?, output
    assert_equal 'keep', File.read(external)
  end

  def test_emulator_plist_owns_native_emulator_process_with_exact_avd_argument
    session = File.join(@root, 'AVD session 中文')
    FileUtils.mkdir_p(session)
    binary = write_data("SDK space & ' /emulator/emulator", "#!/bin/zsh\nexit 0\n")
    File.chmod(0o700, binary)
    avd = 'Pixel_API_35'
    output, status = execute('emulator-plist', session, 'com.jobs.flutterrunner.avd.fixture', binary, avd,
                             env: { 'ANDROID_SDK_ROOT' => File.dirname(File.dirname(binary)),
                                    'ANDROID_AVD_HOME' => '/custom/AVD home', 'ANDROID_USER_HOME' => '/custom/android-user',
                                    'ANDROID_EMULATOR_HOME' => '/custom/emulator-home', 'PUB_CACHE' => '', 'JOBS_TEST_SECRET' => 'private' })
    assert status.success?, output
    path = File.join(session, 'job.plist')
    assert_equal path, output.strip
    json, status = Open3.capture2e('/usr/bin/plutil', '-convert', 'json', '-o', '-', path)
    assert status.success?, json
    plist = JSON.parse(json)
    assert_equal [binary, '-avd', avd], plist['ProgramArguments']
    assert_equal File.dirname(binary), plist['WorkingDirectory']
    assert_equal true, plist['RunAtLoad']
    assert_equal false, plist['KeepAlive']
    assert_equal 20, plist['ExitTimeOut']
    assert_equal 'Interactive', plist['ProcessType']
    assert_equal File.join(session, 'emulator.log'), plist['StandardOutPath']
    assert_equal plist['StandardOutPath'], plist['StandardErrorPath']
    refute plist.key?('AbandonProcessGroup')
    refute plist['EnvironmentVariables'].key?('JOBS_TEST_SECRET')
    assert_equal '', plist['EnvironmentVariables']['PUB_CACHE']
    assert_equal '/custom/AVD home', plist['EnvironmentVariables']['ANDROID_AVD_HOME']
    assert_equal '/custom/android-user', plist['EnvironmentVariables']['ANDROID_USER_HOME']
    assert_equal '/custom/emulator-home', plist['EnvironmentVariables']['ANDROID_EMULATOR_HOME']
    assert_equal 0o600, File.stat(path).mode & 0o777
  end

  def test_emulator_plist_rejects_bad_binary_label_id_or_session
    session = File.join(@root, 'avd-session')
    FileUtils.mkdir_p(session)
    binary = write_data('sdk/emulator', "#!/bin/zsh\nexit 0\n")
    File.chmod(0o700, binary)
    fixtures = [
      [session, 'bad/label', binary, 'Pixel_API_35'],
      [session, 'com.jobs.avd.fixture', binary, "bad\nAVD"],
      [session, 'com.jobs.avd.fixture', File.join(@root, 'missing'), 'Pixel_API_35'],
      [session, 'com.jobs.avd.fixture', 'relative/emulator', 'Pixel_API_35']
    ]
    fixtures.each do |args|
      output, status = execute('emulator-plist', *args)
      refute status.success?, output
      refute File.exist?(File.join(session, 'job.plist'))
    end
    File.chmod(0o600, binary)
    output, status = execute('emulator-plist', session, 'com.jobs.avd.fixture', binary, 'Pixel_API_35')
    refute status.success?, output
    refute File.exist?(File.join(session, 'job.plist'))
    File.chmod(0o700, binary)
    linked = File.join(@root, 'linked-avd-session')
    File.symlink(session, linked)
    output, status = execute('emulator-plist', linked, 'com.jobs.avd.fixture', binary, 'Pixel_API_35')
    refute status.success?, output
    refute File.exist?(File.join(session, 'job.plist'))
  end

  def test_daemon_controls_use_latest_app_start_and_flutter_array_protocol
    log = write_data('run.log', <<~LOG)
      Resolving dependencies...
      [{"event":"app.start","params":{"appId":"old-id"}}]
      [broken response
      [{"event":"app.started","params":{"appId":"ignore-id"}}]
      [{"event":"app.start","params":{"appId":"latest-id"}}]
      [{"event":"app.log","params":{"log":"hello"}}]
    LOG
    %w[reload restart stop].each do |operation|
      values = JSON.parse(successful('command', log, operation))
      assert_equal 1, values.length
      value = values[0]
      assert_kind_of Integer, value['id']
      assert_equal 'latest-id', value['params']['appId']
      assert_equal(operation == 'stop' ? 'app.stop' : 'app.restart', value['method'])
      if operation == 'stop'
        assert_equal({ 'appId' => 'latest-id' }, value['params'])
      else
        assert_equal(operation == 'restart', value['params']['fullRestart'])
        assert_equal false, value['params']['pause']
      end
    end
  end

  def test_daemon_control_refuses_missing_app_id_unknown_action_and_bad_arguments
    log = write_data('no-app.log', "Flutter is compiling\n[]\n")
    output, status = execute('command', log, 'reload')
    refute status.success?, output
    assert_includes output, '尚未返回 app.start'
    output, status = execute('command', log, 'kill-all')
    refute status.success?, output
    assert_includes output, '未知 Flutter 控制操作'
    output, status = execute('devices')
    refute status.success?, output
    assert_includes output, '参数无效'
  end

  def test_fvm_version_reads_both_config_layouts
    assert_equal '3.47.7', successful('fvm-version', write_json('fvmrc.json', flutter: '3.47.7')).strip
    assert_equal 'stable', successful('fvm-version', write_json('legacy.json', flutterSdkVersion: 'stable')).strip
  end

  def test_fvm_version_rejects_missing_or_unsafe_values
    [{ flutter: '3.47.7; rm -rf /' }, { flutter: '' }, { flutter: 3 }, { other: 'x' }, nil, []].each_with_index do |data, index|
      output, status = execute('fvm-version', write_json("fvm-bad#{index}.json", data))
      refute status.success?, output
      assert_includes output, 'FVM'
    end
  end

  def test_unique_simulator_name_appends_suffix_for_existing_names
    path = write_json('devices.json', devices: {
      ios_runtime('26-0') => [
        { name: 'iPhone 18 Pro@2026.10.21 11:30:00-1234' },
        { name: 'iPhone 18 Pro@2026.10.21 11:30:00-1234 (2)' }
      ],
      ios_runtime('18-5') => [{ name: 'iPhone 16' }]
    })
    assert_equal 'iPhone 18 Pro@2026.10.21 11:30:00-1234 (3)',
                 successful('unique-name', path, 'iPhone 18 Pro@2026.10.21 11:30:00-1234').strip
    assert_equal 'iPhone 18 Pro@2026.10.21 11:30:00-9999',
                 successful('unique-name', path, 'iPhone 18 Pro@2026.10.21 11:30:00-9999').strip
  end

  def test_unique_simulator_name_rejects_empty_base_or_malformed_devices
    path = write_json('devices.json', devices: {})
    output, status = execute('unique-name', path, '   ')
    refute status.success?, output
    assert_includes output, '模拟器名称不能为空'
    [{ devices: [] }, { devices: 'x' }, nil, {}].each_with_index do |data, index|
      output, status = execute('unique-name', write_json("bad-name#{index}.json", data), 'iPhone')
      refute status.success?, output
      assert_includes output, '已有设备 JSON'
    end
    output, status = execute('unique-name', write_json('bad-list.json', devices: { 'r' => 'not-array' }), 'iPhone')
    refute status.success?, output
    assert_includes output, '格式无效'
  end

  private

  def execute(*args, env: {})
    Open3.capture2e(env, '/usr/bin/osascript', '-l', 'JavaScript', HELPER, *args)
  end

  def successful(*args)
    output, status = execute(*args)
    assert status.success?, output
    output
  end

  def write_data(name, contents)
    path = File.join(@root, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
    path
  end

  def write_json(name, value)
    write_data(name, JSON.generate(value))
  end

  def ios_runtime(version)
    'com.apple.CoreSimulator.SimRuntime.iOS-' + version
  end

  def simulator_fixture
    { runtimes: [
      { identifier: ios_runtime('18-5'), name: 'iOS 18.5', version: '18.5', availability: '(available)' },
      { identifier: ios_runtime('26-0'), name: 'iOS 26.0', version: '26.0', isAvailable: true },
      { identifier: ios_runtime('17-0'), name: 'iOS 17.0 unavailable', version: '17.0', isAvailable: false },
      { identifier: 'com.apple.CoreSimulator.SimRuntime.tvOS-26-0', name: 'tvOS 26.0', version: '26.0', isAvailable: true }
    ], devicetypes: [
      { identifier: 'com.apple.CoreSimulator.SimDeviceType.iPhone-17', name: 'iPhone 17', productFamily: 'iPhone' },
      { identifier: 'com.apple.CoreSimulator.SimDeviceType.iPhone-17', name: 'duplicate', productFamily: 'iPhone' },
      { identifier: 'com.apple.CoreSimulator.SimDeviceType.iPad', name: 'iPad', productFamily: 'iPad' },
      { identifier: 'com.apple.CoreSimulator.SimDeviceType.Apple-Watch', name: 'Apple Watch' },
      { identifier: 'com.apple.CoreSimulator.SimDeviceType.Apple-TV', name: 'Apple TV' }
    ], devices: {
      ios_runtime('26-0') => [
        { udid: 'shutdown-ios', name: 'iPhone 17 Pro', state: 'Shutdown', isAvailable: true },
        { udid: 'booted-ios', name: 'iPhone 17', state: 'Booted', isAvailable: true },
        { udid: 'bad-device', name: 'unavailable', state: 'Shutdown', isAvailable: false },
        { udid: 'booted-ios', name: 'duplicate', state: 'Shutdown', isAvailable: true }
      ],
      ios_runtime('18-5') => [{ udid: 'legacy-ios', name: 'iPhone 16', state: 'Shutdown', availability: '(available)' }],
      ios_runtime('17-0') => [{ udid: 'old-ios', name: 'unavailable', state: 'Shutdown', isAvailable: true }],
      'com.apple.CoreSimulator.SimRuntime.tvOS-26-0' => [{ udid: 'tv-device', name: 'Apple TV', state: 'Booted', isAvailable: true }]
    } }
  end

  # 型号 / 系统组合夹具：26.0 只确认支持 iPhone New 且仅 arm64，18.5 只支持 iPhone Old 且仅 x86_64，
  # 17.0 无白名单只能靠版本范围，16.4 只确认支持 iPhone Unknown 且仅 x86_64。
  def combination_fixture
    { runtimes: [
      { identifier: ios_runtime('26-0'), name: 'iOS 26.0', version: '26.0', isAvailable: true,
        supportedArchitectures: ['arm64'], supportedDeviceTypes: [{ identifier: iphone_type('New') }] },
      { identifier: ios_runtime('18-5'), name: 'iOS 18.5', version: '18.5', isAvailable: true,
        supportedArchitectures: ['x86_64'], supportedDeviceTypes: [{ identifier: iphone_type('Old') }] },
      { identifier: ios_runtime('17-0'), name: 'iOS 17.0', version: '17.0', isAvailable: true },
      { identifier: ios_runtime('16-4'), name: 'iOS 16.4', version: '16.4', isAvailable: true,
        supportedArchitectures: ['x86_64'], supportedDeviceTypes: [{ identifier: iphone_type('Unknown') }] }
    ], devicetypes: [
      { identifier: iphone_type('New'), name: 'iPhone New', productFamily: 'iPhone' },
      { identifier: iphone_type('Old'), name: 'iPhone Old', productFamily: 'iPhone' },
      { identifier: iphone_type('Unknown'), name: 'iPhone Unknown', productFamily: 'iPhone' },
      { identifier: iphone_type('Range'), name: 'iPhone Range', productFamily: 'iPhone',
        minRuntimeVersion: 18 * 65_536 },
      { identifier: 'com.apple.CoreSimulator.SimDeviceType.iPad-Pro', name: 'iPad Pro', productFamily: 'iPad' }
    ], devices: {} }
  end

  def iphone_type(name)
    'com.apple.CoreSimulator.SimDeviceType.iPhone-' + name
  end
end
