# frozen_string_literal: true
# Created by Jobs on 2026年10月29日，星期四。
# 临时项目与假命令验证依赖内核、工作目录和失败边界；不联网、不安装工具、不操作用户工程。
require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'pty'
require 'shellwords'
require 'tmpdir'
require 'timeout'

class ProjectDependencyTests < Minitest::Test
  TOOLS = File.expand_path(ENV.fetch('JOBS_TEST_TOOLS_DIR', '../Scripts/Tools'), __dir__)
  ENTRY = File.join(TOOLS, 'FetchProjectDependencies.zsh')
  SOURCES = %w[ProjectEnvironment.zsh ManageProjectJava.zsh DownloadProjectGradle.zsh
               SetupFlutterProject.zsh SetupFlutterRun.zsh ProjectDependencies.zsh].freeze

  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-project-dependencies-'))
    @project = File.join(@root, "中文 项目 ' $(touch INJECTED)")
    @bin = File.join(@root, 'bin')
    @run = File.join(@root, 'run')
    @home = File.join(@root, 'home')
    @sdk = File.join(@root, 'Flutter SDK')
    @jdk = File.join(@root, 'Java Home')
    @trace = File.join(@root, 'trace')
    @events = File.join(@root, 'events')
    FileUtils.mkdir_p([@project, @bin, @run, @home, File.join(@project, 'lib'), @jdk])
    File.write(File.join(@project, 'pubspec.yaml'), "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n")
    File.write(File.join(@project, 'lib/main.dart'), 'void main() {}')
    @env = {
      'HOME' => @home, 'TMPDIR' => @run, 'PATH' => "#{@bin}:/usr/bin:/bin:/usr/sbin:/sbin",
      'NO_COLOR' => '1', 'TERM' => 'dumb', 'JAVA_HOME' => @jdk,
      'PD_TEST_ROOT' => @root, 'PD_TEST_PROJECT' => @project, 'PD_TEST_RUN' => @run,
      'PD_TEST_BIN' => @bin, 'PD_TEST_SDK' => @sdk, 'PD_TEST_JDK' => @jdk,
      'PD_TEST_TRACE' => @trace, 'PD_TEST_EVENTS' => @events
    }
    write_command(File.join(@sdk, 'bin/flutter'), 'flutter', <<~'ZSH')
      if [[ "${PD_TEST_JAVA_BINDING:-0}" == 1 ]]; then
        /usr/bin/printf '%s\0' "$JAVA_HOME" "$GRADLE_OPTS" > "$PD_TEST_ROOT/native-java"
      fi
      if [[ "$*" == *--help* ]]; then
        [[ "${PD_TEST_CONFIG_ONLY:-1}" == 0 ]] || print -- '--config-only'
        exit 0
      fi
      [[ "${PD_TEST_FLUTTER_FAIL:-0}" == 0 ]] || exit "$PD_TEST_FLUTTER_FAIL"
      print 'Flutter fixture completed'
    ZSH
    write_command(File.join(@bin, 'gradle'), 'gradle', <<~'ZSH')
      init=""
      while (( $# )); do
        if [[ "$1" == --init-script ]]; then init="$2"; shift 2; else shift; fi
      done
      [[ -f "$init" ]] || exit 90
      /bin/cp "$init" "$PD_TEST_ROOT/observed.init.gradle"
      [[ "${PD_TEST_GRADLE_FAIL:-0}" == 0 ]] || exit "$PD_TEST_GRADLE_FAIL"
      [[ "${PD_TEST_GRADLE_NO_MARKER:-0}" == 1 ]] || print 'JOBS_PROJECT_DEPENDENCIES_RESOLVED'
    ZSH
    %w[pod xcodebuild ohpm npm pnpm yarn].each do |name|
      write_command(File.join(@bin, name), name, <<~'ZSH')
        if [[ "$1" == --version ]]; then
          [[ "${PD_TEST_VERSION_FAIL:-0}" == 0 ]] || exit "$PD_TEST_VERSION_FAIL"
          print -- "${PD_TEST_TOOL_VERSION:-1.22.22}"
          exit 0
        fi
        [[ "${PD_TEST_PACKAGE_FAIL:-0}" == 0 ]] || exit "$PD_TEST_PACKAGE_FAIL"
      ZSH
    end
    write_command(File.join(@bin, 'fzf'), 'fzf', <<~'ZSH')
      [[ "$1" != --version ]] || { print '0.66.0 fixture'; exit 0; }
      /bin/cat >/dev/null
      exit 130
    ZSH
    %w[brew gem curl flutter fvm java node].each do |name|
      write_command(File.join(@bin, name), "forbidden-#{name}", 'exit 99')
    end
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def write_command(path, label, body)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, <<~SH)
      #!/bin/zsh
      /usr/bin/printf '%s\\0' #{label.shellescape} "$PWD" "$#" "$@" >> "$PD_TEST_TRACE"
      #{body}
    SH
    FileUtils.chmod(0o755, path)
  end

  def records
    return [] unless File.exist?(@trace)

    values = File.binread(@trace).force_encoding('UTF-8').split("\0")
    result = []
    until values.empty?
      tool, directory, count = values.shift(3)
      raise 'invalid command trace' unless count&.match?(/\A\d+\z/)

      result << { tool: tool, cwd: directory, args: values.shift(count.to_i) }
    end
    result
  end

  def calls(tool)
    records.select { |row| row[:tool] == tool }
  end

  def shell(body, env: {}, xcode: false)
    source = SOURCES.map { |file| "source #{File.join(TOOLS, file).shellescape} || exit $?" }.join("\n")
    bootstrap = <<~'ZSH'
      SF_PROJECT="$PD_TEST_PROJECT" SF_FLUTTER="$PD_TEST_SDK/bin/flutter" SF_JAVA_HOME="$PD_TEST_JDK"
      PE_PROJECT="$SF_PROJECT" PE_RUN_DIR="$PD_TEST_RUN" PE_LOG_FILE="$PD_TEST_RUN/environment.log"
      DG_GRADLE="$PD_TEST_BIN/gradle" DG_JAVA_HOME="$PD_TEST_JDK"
      typeset -a SR_ARGS=(--debug) SR_POD_COMMAND=("$PD_TEST_BIN/pod")
      pe_event() { /usr/bin/printf '%s|%s\n' "$1" "$4" >> "$PD_TEST_EVENTS"; }
      cd -- "$SF_PROJECT" || exit 1
    ZSH
    # 只把系统固定的 Xcode 路径映射到假命令，其余步骤运行真实有界诊断与工作目录逻辑。
    bridge = <<~'ZSH'
      functions[pd_test_real_diagnostic]="$functions[sf_run_diagnostic]"
      sf_run_diagnostic() {
        local name="$1"
        shift
        if [[ "$1" == /usr/bin/xcodebuild ]]; then
          shift
          pd_test_real_diagnostic "$name" "$PD_TEST_BIN/xcodebuild" "$@"
        else
          pd_test_real_diagnostic "$name" "$@"
        fi
      }
    ZSH
    Open3.capture3(@env.merge(env), '/bin/zsh', '-f', '-c', "#{source}\n#{bootstrap}\n#{xcode ? bridge : ''}\n#{body}")
  end

  def assert_success(result)
    out, err, status = result
    assert status.success?, "#{out}\n#{err}"
    [out, err, status]
  end

  def terminal_entry(kind, input:, extra: [])
    output = +''
    exit_status = nil
    PTY.spawn(@env, '/bin/zsh', '-f', ENTRY, '--project', @project, '--kind', kind, *extra) do |reader, writer, pid|
      writer.write(input)
      writer.flush
      begin
        Timeout.timeout(15) { loop { output << reader.readpartial(4096) } }
      rescue EOFError, Errno::EIO
        _, exit_status = Process.wait2(pid)
      ensure
        begin
          Process.kill('KILL', pid) unless exit_status
        rescue Errno::ESRCH
        end
      end
    end
    [output.force_encoding('UTF-8'), exit_status]
  end

  def platform(name)
    FileUtils.mkdir_p(File.join(@project, name))
  end

  def web_project(directory = File.join(@project, 'web'), lock: 'package-lock.json')
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, 'package.json'), '{"name":"fixture","private":true}')
    File.write(File.join(directory, lock), 'fixture-locked-content') if lock
    directory
  end

  def apple_project(platform_name = 'ios', name: 'Custom App')
    directory = File.join(@project, platform_name, "#{name}.xcodeproj")
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, 'project.pbxproj'), '// fixture')
    directory
  end

  def test_source_is_pure
    source = SOURCES.map { |file| "source #{File.join(TOOLS, file).shellescape} || exit $?" }.join("\n")
    out, err, status = Open3.capture3(@env, '/bin/zsh', '-f', '-c', source, chdir: @project)
    assert status.success?, out + err
    assert_empty records
    assert_empty Dir.children(@run)
    refute File.exist?(File.join(@project, 'INJECTED'))
  end

  def test_android_uses_real_resolution_task_in_android_directory_and_preserves_failure
    platform('android')
    assert_success shell('SR_TARGET=android; pd_android_dependencies')
    row = calls('gradle').fetch(0)
    assert_equal File.join(@project, 'android'), row[:cwd]
    assert_includes row[:args], 'jobsResolveAllProjectDependencies'
    refute_includes row[:args], 'help'
    assert_includes row[:args], '--no-configuration-cache'
    assert_includes row[:args], "-Dorg.gradle.java.home=#{@jdk}"
    init = File.read(File.join(@root, 'observed.init.gradle'))
    assert_includes init, 'canBeResolved'
    assert_includes init, 'buildscript.configurations'
    assert_match(/cfg\.resolve\(\)/, init)
    refute_match(/lenient\s*[:=]\s*true/, init)
    assert_match(/beforeProject.*?tasks\.register/m, init)
    assert_match(/dependsOn.*?allprojects/m, init)
    _, _, status = shell('SR_TARGET=android; pd_android_dependencies', env: { 'PD_TEST_GRADLE_FAIL' => '47' })
    assert_equal 47, status.exitstatus
    _, _, status = shell('SR_TARGET=android; pd_android_dependencies', env: { 'PD_TEST_GRADLE_NO_MARKER' => '1' })
    refute status.success?, 'Gradle空成功不能替代所有配置解析完成'
    refute File.exist?(File.join(@project, 'INJECTED'))
  end

  def test_pods_reuses_selected_command_and_install_lock_policy
    platform('ios')
    lock = File.join(@project, 'ios/Podfile.lock')
    File.write(File.join(@project, 'ios/Podfile'), "platform :ios, '15.0'")
    File.write(lock, 'PODS: locked')
    assert_success shell('SR_TARGET=ios; pd_pods_dependencies')
    row = calls('pod').fetch(0)
    assert_includes row[:args], 'install'
    assert_includes row[:args], "--project-directory=#{File.join(@project, 'ios')}"
    refute_includes row[:args], 'update'
    assert_equal 'PODS: locked', File.read(lock)
    _, _, status = shell('SR_TARGET=ios; pd_pods_dependencies', env: { 'PD_TEST_PACKAGE_FAIL' => '41' })
    assert_equal 41, status.exitstatus
  end

  def test_no_podfile_is_explicitly_inapplicable_without_installing_cocoapods
    platform('ios')
    assert_success shell('SR_TARGET=ios; SR_POD_COMMAND=(); pd_pods_dependencies')
    assert_empty records
  end

  def test_spm_prefers_top_level_workspace_and_keeps_locked_versions
    apple_project
    workspace = File.join(@project, 'ios/Workspace name.xcworkspace')
    FileUtils.mkdir_p(File.join(workspace, 'xcshareddata/swiftpm'))
    lock = File.join(workspace, 'xcshareddata/swiftpm/Package.resolved')
    File.write(lock, '{"pins":[]}')
    FileUtils.mkdir_p(File.join(@project, 'ios/Pods/Pods.xcodeproj'))
    assert_success shell('SR_TARGET=ios; pd_spm_dependencies', xcode: true)
    row = calls('xcodebuild').fetch(0)
    assert_equal ['-resolvePackageDependencies', '-workspace', workspace, '-clonedSourcePackagesDirPath', File.join(@project, '.jobs/dependencies/spm'), '-onlyUsePackageVersionsFromResolvedFile'], row[:args]
    assert_equal '{"pins":[]}', File.read(lock)
    configuration = calls('flutter').reject { |call| call[:args].include?('--help') }.fetch(0)
    assert_includes configuration[:args], '--config-only'
    assert_includes configuration[:args], '--no-codesign'
  end

  def test_spm_custom_project_lock_is_honored
    project = apple_project
    lock = File.join(project, 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved')
    FileUtils.mkdir_p(File.dirname(lock))
    File.write(lock, '{"pins":[]}')
    assert_success shell('SR_TARGET=ios; pd_spm_dependencies', xcode: true)
    row = calls('xcodebuild').fetch(0)
    assert_includes row[:args], '-project'
    assert_includes row[:args], project
    assert_includes row[:args], '-onlyUsePackageVersionsFromResolvedFile'
  end

  def test_spm_multiple_workspaces_cancel_before_xcode_and_preserve_failure
    apple_project
    %w[One Two].each { |name| FileUtils.mkdir_p(File.join(@project, "ios/#{name}.xcworkspace")) }
    _, _, status = shell('SR_TARGET=ios; PE_FZF="$PD_TEST_BIN/fzf"; pd_spm_dependencies', xcode: true)
    assert_equal 130, status.exitstatus
    assert_empty calls('xcodebuild')
    FileUtils.remove_entry(File.join(@project, 'ios/Two.xcworkspace'))
    _, _, status = shell('SR_TARGET=ios; pd_spm_dependencies', env: { 'PD_TEST_PACKAGE_FAIL' => '49' }, xcode: true)
    assert_equal 49, status.exitstatus
  end

  def test_spm_older_flutter_uses_existing_project_without_config_only
    project = apple_project('macos')
    assert_success shell('SR_TARGET=macos; pd_spm_dependencies', env: { 'PD_TEST_CONFIG_ONLY' => '0' }, xcode: true)
    assert_equal 1, calls('flutter').length
    assert_equal ['-resolvePackageDependencies', '-project', project, '-clonedSourcePackagesDirPath', File.join(@project, '.jobs/dependencies/spm')], calls('xcodebuild').fetch(0)[:args]
  end

  def test_ohpm_and_fixed_hvigor_run_in_ohos_root_with_lock_unchanged
    directory = File.join(@project, 'ohos')
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, 'oh-package.json5'), '{name:"fixture",dependencies:{"@scope/library":"1.2.3"}}')
    lock = File.join(directory, 'oh-package-lock.json5')
    File.write(lock, '{locked:"1.2.3"}')
    write_command(File.join(directory, 'hvigorw'), 'hvigor', 'exit "${PD_TEST_HVIGOR_FAIL:-0}"')
    assert_success shell('SR_TARGET=ohos; pd_ohos_dependencies')
    install = calls('ohpm').find { |row| row[:args].first == 'install' }
    assert_equal directory, install[:cwd]
    refute_includes install[:args], 'update'
    assert_equal directory, calls('hvigor').fetch(0)[:cwd]
    assert_equal ['--sync'], calls('hvigor').fetch(0)[:args]
    assert_equal '{locked:"1.2.3"}', File.read(lock)
  end

  def test_ohpm_failure_does_not_start_hvigor_and_hvigor_failure_is_preserved
    directory = File.join(@project, 'ohos')
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, 'oh-package.json5'), '{}')
    write_command(File.join(directory, 'hvigorw'), 'hvigor', 'exit "${PD_TEST_HVIGOR_FAIL:-0}"')
    _, _, status = shell('SR_TARGET=ohos; pd_ohos_dependencies', env: { 'PD_TEST_PACKAGE_FAIL' => '51' })
    assert_equal 51, status.exitstatus
    assert_empty calls('hvigor')
    _, _, status = shell('SR_TARGET=ohos; pd_ohos_dependencies', env: { 'PD_TEST_HVIGOR_FAIL' => '52' })
    assert_equal 52, status.exitstatus
  end

  def test_web_npm_uses_ci_and_each_package_directory
    directory = web_project
    web_project(@project, lock: 'npm-shrinkwrap.json')
    before = File.binread(File.join(directory, 'package-lock.json'))
    assert_success shell('SR_TARGET=web; pd_web_dependencies')
    assert_equal [directory, @project], calls('npm').map { |row| row[:cwd] }
    assert calls('npm').all? { |row| row[:args] == ['ci'] }
    assert_equal before, File.binread(File.join(directory, 'package-lock.json'))
    assert_empty calls('flutter')
  end

  def test_web_missing_or_ambiguous_lock_stops_without_guessing_install
    directory = web_project(lock: nil)
    _, _, status = shell('pd_web_dependencies')
    assert_equal 3, status.exitstatus
    assert_empty records
    File.write(File.join(directory, 'package-lock.json'), '{}')
    File.write(File.join(directory, 'yarn.lock'), 'fixture')
    _, _, status = shell('pd_web_dependencies')
    assert_equal 3, status.exitstatus
    assert_empty records
  end

  def test_web_frozen_pnpm_and_yarn_generations
    directory = web_project(lock: 'pnpm-lock.yaml')
    assert_success shell('pd_web_dependencies')
    assert_equal ['install', '--frozen-lockfile'], calls('pnpm').fetch(0)[:args]
    File.delete(File.join(directory, 'pnpm-lock.yaml'))
    File.write(File.join(directory, 'yarn.lock'), 'fixture')
    assert_success shell('pd_web_dependencies', env: { 'PD_TEST_TOOL_VERSION' => '1.22.22' })
    assert_equal ['install', '--frozen-lockfile'], calls('yarn').last[:args]
    assert_success shell('pd_web_dependencies', env: { 'PD_TEST_TOOL_VERSION' => '4.9.0' })
    assert_equal ['install', '--immutable'], calls('yarn').last[:args]
  end

  def test_web_failure_stops_before_the_next_package_directory
    web_project
    web_project(@project)
    _, _, status = shell('pd_web_dependencies', env: { 'PD_TEST_PACKAGE_FAIL' => '53' })
    assert_equal 53, status.exitstatus
    assert_equal 1, calls('npm').length
  end

  def test_no_js_manifest_adds_no_node_dependency
    platform('web')
    assert_success shell('pd_web_dependencies')
    assert_empty records
  end

  def test_native_build_uses_target_mapping_config_args_and_no_device_install
    { 'android' => 'apk', 'ios' => 'ios', 'macos' => 'macos', 'web' => 'web', 'ohos' => 'hap' }.each do |target, command|
      assert_success shell("SR_TARGET=#{target}; SR_ARGS=(--debug --flavor demo '--dart-define=VALUE=$(touch INJECTED)'); pd_native_dependencies")
      row = calls('flutter').last
      assert_equal ['build', command], row[:args].first(2)
      assert_includes row[:args], '--flavor'
      assert_includes row[:args], 'demo'
      assert_includes row[:args], '--dart-define=VALUE=$(touch INJECTED)'
      assert_equal target == 'ios', row[:args].include?('--no-codesign')
      assert_equal @project, row[:cwd]
      refute_includes row[:args], 'run'
      refute_includes row[:args], 'install'
    end
    refute File.exist?(File.join(@project, 'INJECTED'))
  end

  def test_native_configuration_cancel_invalid_target_and_build_failure
    _, _, status = shell('SR_TARGET=android; SR_ARGS=(); sr_choose_configuration() { return 130; }; pd_native_dependencies')
    assert_equal 130, status.exitstatus
    assert_empty calls('flutter')
    _, _, status = shell('SR_TARGET=ios; SR_ARGS=(--target ../outside.dart); pd_native_dependencies')
    refute status.success?
    assert_empty calls('flutter')
    _, _, status = shell('SR_TARGET=ios; pd_native_dependencies', env: { 'PD_TEST_FLUTTER_FAIL' => '54' })
    assert_equal 54, status.exitstatus
  end

  def test_native_android_build_keeps_selected_jdk_for_gradle_daemon
    assert_success shell('SF_JAVA_HOME="$PD_TEST_JDK"; SR_TARGET=android; SR_ARGS=(--debug); pd_native_dependencies',
                         env: { 'PD_TEST_JAVA_BINDING' => '1', 'JAVA_HOME' => '/unselected-jdk', 'GRADLE_OPTS' => '-Dkeep=1' })
    selected, options = File.binread(File.join(@root, 'native-java')).force_encoding('UTF-8').split("\0")
    assert_equal @jdk, selected
    assert_includes options, '-Dkeep=1'
    assert_includes options, "-Dorg.gradle.java.home=\"#{@jdk}\""
  end

  def test_one_click_dependency_failure_does_not_reach_native_build_or_success_event
    platform('android')
    _, _, status = shell('SR_TARGET=android; pd_run_target_dependencies', env: { 'PD_TEST_GRADLE_FAIL' => '55' })
    assert_equal 55, status.exitstatus
    assert_empty calls('flutter')
    assert_includes File.read(@events), 'pub.android|failed'
    refute_includes File.read(@events), 'pub.android|succeeded'
    refute_includes File.read(@events), 'pub.native|'
  end

  def test_one_click_reuses_same_web_and_native_workers_in_order
    web_project
    assert_success shell('SR_TARGET=web; pd_run_target_dependencies')
    business = records.reject { |row| row[:args].include?('--version') }
    assert_equal %w[npm flutter], business.map { |row| row[:tool] }
    assert_includes File.read(@events), 'pub.web|succeeded'
    assert_includes File.read(@events), 'pub.native|succeeded'
  end

  def test_platform_selection_filters_absent_or_unsupported_targets_and_cancel
    platform('android')
    out, = assert_success shell('pd_choose_platform android android && print -r -- "$PD_PLATFORM|$SR_TARGET"')
    assert_includes out, 'android|android'
    _, _, status = shell('pd_choose_platform pods android')
    assert_equal 3, status.exitstatus
    platform('ios')
    _, _, status = shell('PE_FZF="$PD_TEST_BIN/fzf"; pd_choose_platform native')
    assert_equal 130, status.exitstatus
    _, _, status = shell('pd_choose_platform native windows')
    assert_equal 3, status.exitstatus
    assert_empty calls('flutter')
  end

  def test_real_diagnostic_obeys_explicit_command_directory_and_failure
    platform('ohos')
    write_command(File.join(@bin, 'directory-probe'), 'directory-probe', 'exit 61')
    _, _, status = shell('SF_COMMAND_DIRECTORY="$SF_PROJECT/ohos" sf_run_diagnostic cwd-probe "$PD_TEST_BIN/directory-probe" "space argument"')
    assert_equal 61, status.exitstatus
    assert_equal File.join(@project, 'ohos'), calls('directory-probe').fetch(0)[:cwd]
    assert_equal ['space argument'], calls('directory-probe').fetch(0)[:args]
  end

  def test_check_all_kinds_never_calls_tools_or_writes_logs
    %w[android pods spm ohos native precache web].each do |kind|
      before = Dir.children(@run)
      out, err, status = Open3.capture3(@env, '/bin/zsh', '-f', ENTRY, '--project', @project, '--kind', kind, '--check')
      assert status.success?, "#{kind}: #{out}\n#{err}"
      assert_includes out, '只读'
      assert_empty records
      assert_equal before, Dir.children(@run)
    end
  end

  def test_independent_web_entry_runs_only_js_install_without_preparing_sdk_or_java
    web_project
    output, status = terminal_entry('web', input: "\n", extra: ['--platform', 'web'])
    assert status.success?, output
    assert_equal ['ci'], calls('npm').fetch(0)[:args]
    assert_empty records.select { |row| row[:tool].start_with?('forbidden-') }
    assert_empty calls('flutter')
    refute File.exist?(File.join(@project, '.jobs/flutter-environment.json'))
    refute File.exist?(File.join(@project, '.fvmrc'))
  end

  def test_check_rejects_invalid_project_and_unknown_kind_before_tools
    out, err, status = Open3.capture3(@env, '/bin/zsh', '-f', ENTRY, '--project', @root, '--kind', 'android', '--check')
    refute status.success?, out + err
    out, err, status = Open3.capture3(@env, '/bin/zsh', '-f', ENTRY, '--project', @project, '--kind', 'unknown', '--check')
    assert_equal 2, status.exitstatus, out + err
    assert_empty records
    assert_empty Dir.children(@run)
  end

  def test_entry_cancel_and_noninteractive_call_never_prepare_anything
    out, err, status = Open3.capture3(@env, '/bin/zsh', '-f', ENTRY, '--project', @project, '--kind', 'android')
    assert_equal 2, status.exitstatus, out + err
    output, status = terminal_entry('android', input: "cancel\n")
    assert_equal 130, status&.exitstatus, output
    assert_empty records
    assert_empty Dir.children(@run)
  end

  def test_precache_intro_explains_command_artifacts_and_boundary_before_confirmation
    output, status = terminal_entry('precache', input: "cancel\n")
    assert_equal 130, status.exitstatus
    command = output.index('    flutter precache --<所选平台>')
    prompt = output.index('👉 已了解影响，回车继续')
    refute_nil command
    refute_nil prompt
    assert_operator command, :<, prompt
    ['    Android 示例：', '    iOS 示例：Flutter.xcframework', '    Web 示例：',
     '    不执行 flutter pub get 或 pod install。', '    Android 预缓存可能包含 Flutter 自身的 Maven 制品。',
     '    这不等于解析工程全部 Maven / 第三方依赖。', '    不代替完整 Android SDK / NDK 或 Xcode 的安装。'].each do |point|
      assert output.lines.any? { |line| line.start_with?(point) }, "missing separate indented point: #{point}"
    end
    assert_empty records
    refute File.exist?(File.join(@run, 'environment.log'))
  end

  def test_native_intro_explains_composite_fetch_and_real_build_before_confirmation
    output, status = terminal_entry('native', input: "cancel\n")
    assert_equal 130, status.exitstatus
    purpose = output.index('本项说明：准备原生库与构建依赖（组合操作）')
    assert_operator purpose, :<, output.index('👉 已了解影响，回车继续')
    ['  1、包含前置准备：', '  2、包含所选目标的依赖拉取，与对应单项菜单有重叠。',
     '    Android：', '    iOS / macOS：', '    OpenHarmony：', '    Web：',
     '  3、实际执行：', '    通过真实构建触发 FFI Hooks、CMake',
     '    不安装或启动 App，不修改工程签名配置。'].each do |point|
      assert output.lines.any? { |line| line.start_with?(point) }, "missing separate indented point: #{point}"
    end
    assert_empty records
    refute File.exist?(File.join(@run, 'environment.log'))
  end
end
