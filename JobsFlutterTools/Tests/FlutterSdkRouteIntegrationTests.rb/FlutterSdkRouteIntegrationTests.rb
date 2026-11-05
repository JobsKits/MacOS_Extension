# Created by Jobs. Entry-point fixtures never invoke the network, SDK, build, launchd or device tools.
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'shellwords'
require 'timeout'
require 'json'

class FlutterSdkRouteIntegrationTests < Minitest::Test
  ROOT = File.expand_path('../../..', __dir__)
  RUNNERS = %w[JobsFlutterRunner/Scripts/RunFlutterProject.zsh JobsFlutterTools/Scripts/Tools/RunFlutterProject.zsh].freeze
  TOOLS = File.join(ROOT, 'JobsFlutterTools/Scripts/Tools')
  def setup
    @tmp = Dir.mktmpdir('jobs-route-entry-中文')
    @sdk = File.join(@tmp, 'SDK 空格')
    @project = File.join(@tmp, '工程')
    @calls = File.join(@tmp, 'calls')
    FileUtils.mkdir_p([File.join(@sdk, 'bin'), @project])
    File.write(File.join(@sdk, 'bin/flutter'), "#!/bin/zsh\nexit 88\n")
    File.chmod(0o700, File.join(@sdk, 'bin/flutter'))
    FileUtils.mkdir_p(File.join(@project, '.fvm'))
    File.symlink(@sdk, File.join(@project, '.fvm/flutter_sdk'))
    File.write(File.join(@project, '.fvmrc'), '{"flutter":"3.38.4"}')
  end
  def teardown
    FileUtils.remove_entry(@tmp)
  end
  def library(path)
    File.read(path).sub(/\nmain "\$@"\s*\z/, "\n")
  end
  def invoke(path, body)
    Timeout.timeout(5) { Open3.capture3({ 'NO_COLOR' => '1', 'FIXTURE_CALLS' => @calls }, '/bin/zsh', '-f', '-c', library(path) + "\n" + body) }
  end
  def runner_setup
    <<~SH
      PROJECT_PATH=#{@project.shellescape}
      LOG_FILE=#{File.join(@tmp, 'log').shellescape}
      commands[flutter]=#{File.join(@sdk, 'bin/flutter').shellescape}
      show_sdk_download_context() { print context >> "$FIXTURE_CALLS"; SDK_VERSION_LABEL=3.38.4; }
      wait_for_sdk_download_writers() { print writers >> "$FIXTURE_CALLS"; }
      jobs_flutter_sdk_retry() { print -r -- "route|$3|$4|$*" >> "$FIXTURE_CALLS"; return ${FIXTURE_CANCEL:-0}; }
    SH
  end
  def test_runner_bootstrap_uses_resolved_sdk_and_logs_context_before_route
    RUNNERS.each do |relative|
      FileUtils.rm_f(@calls)
      out, err, status = invoke(File.join(ROOT, relative), runner_setup + "find_flutter\n")
      assert status.success?, err+out
      calls = File.readlines(@calls).map(&:strip)
      assert_equal 'context', calls[0]
      assert_equal 'writers', calls[1]
      assert_includes calls[2], "route|#{File.realpath(@sdk)}||"
      assert_includes calls[2], '1800'
      assert_includes calls[2], '--version'
    end
  end
  def test_runner_bootstrap_cancel_does_not_enter_device_selector
    RUNNERS.each do |relative|
      FileUtils.rm_f(@calls)
      body = runner_setup + <<~SH
        FIXTURE_CANCEL=130
        show_script_intro_and_wait() { :; }
        initialize_runtime() { :; }
        read_project() { :; }
        leave_terminal() { :; }
        choose_device() { print selector >> "$FIXTURE_CALLS"; }
        prepare_session() { print business >> "$FIXTURE_CALLS"; }
        watch_session() { :; }
        main
      SH
      out, err, status = invoke(File.join(ROOT, relative), body)
      assert_equal 130, status.exitstatus, err+out
      refute_match(/selector|business/, File.read(@calls))
    end
  end
  def test_runner_platform_resources_are_separate_sdk_acquisition
    RUNNERS.each do |relative|
      FileUtils.rm_f(@calls)
      body = runner_setup + <<~SH
        FLUTTER_BIN=#{File.join(@sdk, 'bin/flutter').shellescape}
        DEVICE_ID=device
        json_helper() { print android; }
        jobs_flutter_sdk_retry() { print -r -- "${JOBS_FLUTTER_ROUTE_MODE}|$3|$*" >> "$FIXTURE_CALLS"; }
        prepare_target_sdk_resources
      SH
      _out, err, status = invoke(File.join(ROOT, relative), body)
      assert status.success?, err
      assert_includes File.read(@calls), "platform|#{File.realpath(@sdk)}|"
      assert_includes File.read(@calls), 'precache --android'
      refute_match(/flutter run|flutter build/, File.read(@calls))
    end
  end
  def test_distributed_shell_modules_match_canonical
    canonical = File.read(File.join(TOOLS, '【MacOS】FlutterSDK网络选路.zsh/【MacOS】FlutterSDK网络选路.zsh'))[/# JOBS_FLUTTER_ROUTE_BEGIN\n.*?# JOBS_FLUTTER_ROUTE_END/m]
    paths = Dir.glob(File.join(ROOT, 'JobsFlutter*/Scripts/**/*.zsh')).select { |p| File.file?(p) && File.read(p).include?('# JOBS_FLUTTER_ROUTE_BEGIN') }
    assert_operator paths.length, :>=, 14
    paths.each do |path|
      block = File.read(path)[/# JOBS_FLUTTER_ROUTE_BEGIN\n.*?# JOBS_FLUTTER_ROUTE_END/m]
      assert_equal canonical, block, path
      _out, err, status = Open3.capture3('/bin/zsh', '-n', path)
      assert status.success?, "#{path}: #{err}"
    end
  end

  def test_sourcetree_runner_platform_identity_and_runtime_parity
    tree = File.expand_path('../../SourceTree.command', ROOT)
    skip 'SourceTree companion repository absent' unless Dir.exist?(tree)
    paths = Dir.glob(File.join(tree, 'MacOS/**/*')).select { |p| File.file?(p) && p.end_with?('.command', '.zsh') && File.read(p).include?('# JOBS_FLUTTER_ROUTE_BEGIN') }
    assert_equal 8, paths.length
    paths.each do |path|
      runtime = File.join(Dir.home, 'SourceTree.command', path.delete_prefix(tree + '/'))
      assert_equal File.binread(path), File.binread(runtime), runtime if File.exist?(runtime)
      _out, err, status = Open3.capture3('/bin/zsh', '-n', path)
      assert status.success?, "#{path}: #{err}"
    end
    helper = Dir.glob(File.join(tree, 'MacOS/*运行Flutter项目.command/Scripts/FlutterRunner.jxa')).first
    refute_nil helper
    { 'android-arm64' => 'android', 'ios' => 'ios', 'darwin' => 'macos', 'web-javascript' => 'web', 'ohos-arm64' => 'ohos' }.each do |target, expected|
      list = File.join(@tmp, 'devices.json')
      File.write(list, JSON.generate([{ id: 'device', targetPlatform: target }]))
      out, err, status = Open3.capture3('/usr/bin/osascript', '-l', 'JavaScript', helper, 'precache-platform', list, 'device')
      assert status.success?, err
      assert_equal expected, out.strip
    end
  end

  def test_sourcetree_implicit_builds_prepare_sdk_before_once_only_business
    tree = File.expand_path('../../SourceTree.command', ROOT)
    skip 'SourceTree companion repository absent' unless Dir.exist?(tree)
    %w[android iOS].each do |platform|
      FileUtils.rm_f(@calls)
      path = Dir.glob(File.join(tree, "MacOS/*打包Flutter.#{platform}.command/*.command")).first
      refute_nil path
      FileUtils.mkdir_p([File.join(@project, 'android'), File.join(@project, 'ios')])
      File.write(File.join(@project, 'android/gradlew'), '# fixture')
      body = <<~SH
        LOG_FILE=#{File.join(@tmp, 'log').shellescape}
        SCRIPT_BASENAME=fixture
        parse_flutter_build_options() { BUILD_BASE=#{@project.shellescape}; BUILD_TARGET=apk; BUILD_MODE=debug; FLAVOR=''; }
        resolve_flutter_project() { FLUTTER_ROOT=#{@project.shellescape}; }
        choose_project_flutter() { FLUTTER_CMD=(#{File.join(@sdk, 'bin/flutter').shellescape}); }
        ensure_project_java17() { :; }
        xcodebuild() { :; }
        stop_build_heartbeat() { :; }
        run_flutter_step() { print -r -- "step|$*" >> "$FIXTURE_CALLS"; }
        jobs_flutter_sdk_retry() { print -r -- "sdk|${JOBS_FLUTTER_ROUTE_MODE:-dart}|$*" >> "$FIXTURE_CALLS"; }
        run_build_with_heartbeat() { print -r -- "business|$*" >> "$FIXTURE_CALLS"; return 42; }
        run_original_logic
      SH
      _out, err, status = invoke(path, body)
      assert_equal 42, status.exitstatus, err
      calls = File.readlines(@calls).map(&:strip)
      sdk = calls.select { |v| v.start_with?('sdk|') }
      assert_equal 2, sdk.length
      assert_includes sdk[0], '--version'
      assert_includes sdk[1], "precache --#{platform == 'iOS' ? 'ios' : 'android'}"
      assert_equal 1, calls.count { |v| v.start_with?('business|') }
      assert calls.index(sdk[1]) < calls.index { |v| v.start_with?('business|') }
    end
  end

  def test_shared_dart_keeps_both_platform_bridges_identical
    mac = File.join(TOOLS, 'FlutterProjectTools.dart')
    win = File.expand_path('../WindowsOS@Extension/JobsFlutterTools/Scripts/FlutterProjectTools.dart', ROOT)
    assert_equal File.read(mac), File.read(win)
    assert_includes File.read(mac), 'sdkAcquisition && Platform.isMacOS'
    assert_includes File.read(mac), 'macSdkRouteTaskCache'
    assert_includes File.read(mac), 'JOBS_FLUTTER_ROUTE_CAPTURE_OUTPUT'
  end
end
