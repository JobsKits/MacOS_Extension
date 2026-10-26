# frozen_string_literal: true
# Created by Jobs on 2026年10月22日，星期四。
# 真实 zsh/JXA 与私有替身回归；不安装工具、不注册菜单、不执行真实 Flutter 构建。

require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'pty'
require 'shellwords'
require 'timeout'
require 'tmpdir'

class PackagingShellTests < Minitest::Test
  SCRIPT = File.expand_path('../Scripts/PackageFlutter.zsh', __dir__)
  MANIFEST = "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n"

  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-flutter-packaging-'))
    @project = File.join(@root, "项目 空格 ' $(touch INJECTED) `touch BACKTICK`")
    @bin = File.join(@root, 'bin')
    @run = File.join(@root, 'run')
    @java = File.join(@root, 'jdk17')
    FileUtils.mkdir_p([@project, @bin, @run, File.join(@java, 'bin'), File.join(@project, 'android'), File.join(@project, 'ios')])
    File.write(File.join(@project, 'pubspec.yaml'), MANIFEST)
    File.write(File.join(@project, 'android/gradlew'), '# fixture')
    @source = File.read(SCRIPT).sub(/^main "\$@"\s*\z/, '')
    # 固定兜底路径只在临时副本重定向，缺失分支不能访问本机 Homebrew / JDK。
    @source = @source.gsub('/opt/homebrew', File.join(@root, 'system-arm')).gsub('/usr/local', File.join(@root, 'system-intel'))
    @source = @source.gsub('/Applications/DevEco', File.join(@root, 'system-apps/DevEco'))
    @library = File.join(@root, 'Runtime.zsh')
    File.write(@library, @source)
    @environment = {
      'HOME' => @root, 'TMPDIR' => @run + '/', 'PATH' => "#{@bin}:/usr/bin:/bin",
      'NO_COLOR' => '1', 'TERM' => 'dumb', 'JAVA_HOME' => @java,
      'OPEN_AFTER_BUILD' => '0', 'BUILD_MODE' => nil, 'FLAVOR' => nil, 'BUILD_TARGET' => nil,
      'OHOS_BUILD_TARGET' => nil, 'FLUTTER_OHOS_SDK' => nil, 'DEVECO_SDK_HOME' => nil, 'HOS_SDK_HOME' => nil,
      'DEVECO_STUDIO_HOME' => nil, 'TOOL_HOME' => nil, 'NODE_HOME' => nil, 'OHOS_SDK_HOME' => nil,
      'FP_TEST_ROOT' => @root, 'FP_TEST_PROJECT' => @project,
      'FP_TEST_ARGS' => File.join(@root, 'flutter-arguments'), 'FP_TEST_TRACE' => File.join(@root, 'trace')
    }
    write_mock(File.join(@java, 'bin/java'), <<~'ZSH')
      print -u2 -r -- 'openjdk version "17.0.12" 2024-07-16'
    ZSH
    write_mock('fzf', <<~'ZSH')
      if [[ "$1" == --version ]]; then
        [[ "${FP_TEST_FZF_BROKEN:-0}" != 1 ]] || exit 19
        print -r -- '0.60.0 (fixture)'
        exit 0
      fi
      [[ -z "${FZF_DEFAULT_OPTS+x}${FZF_DEFAULT_OPTS_FILE+x}${FZF_DEFAULT_COMMAND+x}" ]] || exit 41
      print -r -- "fzf|$*" >> "$FP_TEST_TRACE"
      rows=()
      while IFS= read -r line; do rows+=("$line"); done
      printf 'fzf-row|%s\n' "${rows[@]}" >> "$FP_TEST_TRACE"
      [[ "${FP_TEST_FZF_EXIT:-0}" == 0 ]] || exit "$FP_TEST_FZF_EXIT"
      if [[ "${rows[1]}" == Android ]]; then
        print -r -- "${FP_TEST_PLATFORM:-Android}"
      elif [[ "${rows[1]}" == HAP ]]; then
        [[ "${FP_TEST_FZF_TARGET_EXIT:-0}" == 0 ]] || exit "$FP_TEST_FZF_TARGET_EXIT"
        print -r -- "${FP_TEST_OHOS_TARGET:-HAP}"
      else
        [[ "${FP_TEST_FZF_TARGET_EXIT:-0}" == 0 ]] || exit "$FP_TEST_FZF_TARGET_EXIT"
        print -r -- "${FP_TEST_ANDROID_TARGET:-APK}"
      fi
    ZSH
    write_mock('flutter', <<~'ZSH')
      print -rn -- "$#"$'\0' >> "$FP_TEST_ARGS"
      printf '%s\0' "$@" >> "$FP_TEST_ARGS"
      print -r -- "fake-flutter|$*"
      if [[ "$1" == --version ]]; then
        print -r -- 'Flutter 3.35.0-ohos (fixture)'
        exit "${FP_TEST_VERSION_EXIT:-0}"
      fi
      case "$1:$2" in
        pub:get) exit "${FP_TEST_PUB_EXIT:-0}" ;;
        build:*)
          if [[ "$3" == --help ]]; then
            [[ "$2" != "${FP_TEST_UNSUPPORTED_TARGET:-}" ]] || exit 64
            if [[ "${FP_TEST_GENERIC_HELP:-0}" == 1 ]]; then
              print -r -- 'Usage: flutter build <subcommand> [arguments]'
              exit 0
            fi
            print -r -- "Build a $2 package. Usage: flutter build $2 [arguments]"
            print -r -- '--release --debug --profile --target'
            exit 0
          fi
          [[ "${FP_TEST_BUILD_EXIT:-0}" == 0 ]] || exit "$FP_TEST_BUILD_EXIT"
          [[ "${FP_TEST_NO_OUTPUT:-0}" != 1 ]] || exit 0
          target="$2" mode=release flavor=""
          while (( $# )); do
            case "$1" in
              --debug|--profile|--release) mode="${1#--}" ;;
              --flavor) shift; flavor="$1" ;;
            esac
            shift
          done
          suffix="$mode"
          [[ -z "$flavor" ]] || suffix="${flavor:l}-$mode"
          case "$target" in
            apk) output="$FP_TEST_PROJECT/build/app/outputs/flutter-apk/app-$suffix.apk" ;;
            appbundle) output="$FP_TEST_PROJECT/build/app/outputs/bundle/release/app-$suffix.aab" ;;
            ipa) output="$FP_TEST_PROJECT/build/ios/ipa/Runner.ipa" ;;
            hap|app)
              if [[ "${FP_TEST_OHOS_OUTPUT_STYLE:-flutter}" == module ]]; then
                output="$FP_TEST_PROJECT/ohos/entry/build/default/outputs/default/entry-default-signed.$target"
              else
                output="$FP_TEST_PROJECT/build/ohos/$target/entry-default-signed.$target"
              fi
              ;;
            *) exit 91 ;;
          esac
          /bin/mkdir -p "${output:h}"
          if [[ "${FP_TEST_EMPTY_OUTPUT:-0}" == 1 ]]; then
            : > "$output"
          else
            print -rn -- 'fixture-package' > "$output"
          fi
          ;;
        *) exit 92 ;;
      esac
    ZSH
    write_mock('xcodebuild', <<~'ZSH')
      print -r -- "xcodebuild|$*" >> "$FP_TEST_TRACE"
      print -r -- 'Xcode fixture'
      exit "${FP_TEST_XCODE_EXIT:-0}"
    ZSH
    write_mock('pod', 'exit 0')
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def write_mock(name, body)
    path = name.start_with?('/') ? name : File.join(@bin, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/bin/zsh\n#{body}\n")
    File.chmod(0o700, path)
    path
  end

  def shell(body, env: {}, input: '')
    bootstrap = <<~ZSH
      source #{@library.shellescape}
      setopt NO_NOMATCH PIPE_FAIL
      FP_PROJECT=#{@project.shellescape}
      FP_LOG_FILE=#{File.join(@root, 'test.log').shellescape}
      : > "$FP_LOG_FILE"
      function /usr/libexec/java_home() { return 1; }
    ZSH
    Open3.capture3(@environment.merge(env), '/bin/zsh', '-f', '-c', bootstrap + body, stdin_data: input, chdir: @root)
  end

  def invoke(*arguments, env: {}, input: '')
    Open3.capture3(@environment.merge(env), '/bin/zsh', '-f', SCRIPT, *arguments, stdin_data: input, chdir: @root)
  end

  def interactive(*arguments, env: {}, input: "\n")
    fixture = File.join(@root, 'Interactive.zsh')
    File.write(fixture, @source + "\nmain \"$@\"\n")
    output = +''
    pid = nil
    result = nil
    Timeout.timeout(20) do
      PTY.spawn(@environment.merge(env), '/bin/zsh', '-f', fixture, *arguments) do |reader, writer, child|
        pid = child
        writer.write(input)
        begin
          loop { output << reader.readpartial(4096) }
        rescue EOFError, Errno::EIO
          # macOS PTY 在 slave 关闭时返回 EIO。
        end
        Process.wait(child)
        result = $?
      end
    end
    [output.force_encoding('UTF-8').scrub, result]
  rescue Timeout::Error
    Process.kill('TERM', pid) if pid
    raise "隔离脚本等待超时：#{output}"
  end

  def flutter_calls
    return [] unless File.file?(@environment['FP_TEST_ARGS'])
    tokens = File.binread(@environment['FP_TEST_ARGS']).split("\0")
    result = []
    result << tokens.shift(Integer(tokens.shift)) until tokens.empty?
    result
  end

  def prepare_ohos
    FileUtils.mkdir_p(File.join(@project, 'ohos'))
    File.write(File.join(@project, 'ohos/build-profile.json5'), '{ products: [] }')
    File.write(File.join(@project, 'ohos/oh-package.json5'), '{ name: "fixture" }')
    sdk = File.join(@root, 'DevEco SDK 空格')
    FileUtils.mkdir_p(sdk)
    @environment['DEVECO_SDK_HOME'] = sdk
    { 'node' => 'v18.20.8', 'npm' => '10.8.2', 'ohpm' => '5.4.0' }.each do |name, version|
      write_mock(name, <<~ZSH)
        print -r -- '#{name}|'"$*" >> "$FP_TEST_TRACE"
        print -r -- '#{version}'
      ZSH
    end
    write_mock('hvigorw', <<~'ZSH')
      print -r -- "hvigorw|$*" >> "$FP_TEST_TRACE"
      print -r -- '5.8.0'
    ZSH
  end

  def ohos_interactive(*arguments, env: {}, input: "\n")
    interactive('--project', @project, *arguments, env: { 'FP_TEST_PLATFORM' => 'OpenHarmony' }.merge(env), input: input)
  end

  def ohos_shell(body, env: {})
    shell("FP_PLATFORM=ohos; FP_OHOS_TARGET=hap; FP_FLUTTER=(#{File.join(@bin, 'flutter').shellescape}); " + body, env: env)
  end

  def test_check_accepts_block_and_flow_flutter_manifests_without_writes
    manifests = [MANIFEST, "name: fixture\ndependencies: {flutter: {sdk: flutter}}\n",
                 "\uFEFFname: fixture\ndependencies:\n  'flutter': {sdk: 'flutter'} # SDK\n"]
    manifests.each do |manifest|
      File.write(File.join(@project, 'pubspec.yaml'), manifest)
      before = Dir.children(@run)
      out, err, status = invoke('--check', '--project', @project)
      assert status.success?, out + err
      assert_includes out, '未执行构建'
      assert_equal before, Dir.children(@run)
      assert_empty flutter_calls
      refute File.exist?(File.join(@root, 'trace'))
    end
  end

  def test_check_rejects_dart_nested_test_only_and_duplicate_dependencies
    manifests = [
      "name: dart\ndependencies:\n  collection: any\n",
      "name: nested\ndependencies:\n  custom:\n    flutter:\n      sdk: flutter\n",
      "name: test_only\ndev_dependencies:\n  flutter_test:\n    sdk: flutter\n",
      MANIFEST + "dependencies:\n  flutter:\n    sdk: flutter\n",
      "dependencies:\n  flutter:\n    sdk: flutter\n    sdk: dart\n",
      "dependencies:\n\tflutter:\n\t  sdk: flutter\n",
      "---\n" + MANIFEST
    ]
    manifests.each do |manifest|
      File.write(File.join(@project, 'pubspec.yaml'), manifest)
      out, err, status = invoke('--check', '--project', @project)
      refute status.success?, manifest + out + err
      assert_empty Dir.children(@run)
      assert_empty flutter_calls
    end
  end

  def test_actual_nul_in_manifest_is_rejected
    File.binwrite(File.join(@project, 'pubspec.yaml'), MANIFEST + "\0ignored: true\n")
    out, err, status = invoke('--check', '--project', @project)
    refute status.success?, out + err
    assert_includes err, 'NUL'
    assert_empty Dir.children(@run)
  end

  def test_project_and_manifest_symlinks_are_rejected
    link = File.join(@root, 'project-link')
    File.symlink(@project, link)
    out, err, status = invoke('--check', '--project', link)
    refute status.success?, out + err
    manifest = File.join(@root, 'real-pubspec.yaml')
    FileUtils.mv(File.join(@project, 'pubspec.yaml'), manifest)
    File.symlink(manifest, File.join(@project, 'pubspec.yaml'))
    out, err, status = invoke('--check', '--project', @project)
    refute status.success?, out + err
    assert_empty Dir.children(@run)
  end

  def test_check_does_not_search_parent_or_child_for_a_project
    child = File.join(@project, 'child')
    FileUtils.mkdir_p(child)
    [@root, child].each do |directory|
      out, err, status = invoke('--check', '--project', directory)
      refute status.success?, out + err
      assert_includes err, 'pubspec.yaml'
    end
  end

  def test_oversize_manifest_and_control_character_paths_are_rejected
    File.write(File.join(@project, 'pubspec.yaml'), MANIFEST + ('#' * 1_048_576))
    out, err, status = invoke('--check', '--project', @project)
    refute status.success?, out + err
    assert_includes err, '1 MiB'
    bad = File.join(@root, "newline\nproject")
    FileUtils.mkdir_p(bad)
    File.write(File.join(bad, 'pubspec.yaml'), MANIFEST)
    out, err, status = invoke('--check', '--project', bad)
    refute status.success?, out + err
    assert_includes err, '控制字符'
  end

  def test_invalid_arguments_stop_before_logs_or_commands
    [%w[--mode invalid], %w[--target invalid], %w[--project], %w[--unknown value], ['--flavor', "line\nbreak"]].each do |arguments|
      out, err, status = invoke('--check', '--project', @project, *arguments)
      assert_equal 2, status.exitstatus, out + err
      assert_empty Dir.children(@run)
      assert_empty flutter_calls
    end
  end

  def test_noninteractive_entry_does_not_create_logs_or_build
    out, err, status = invoke('--project', @project, input: "\n")
    refute status.success?, out + err
    assert_includes out, 'Flutter打包'
    assert_includes err, '可交互终端'
    assert_empty Dir.children(@run)
    assert_empty flutter_calls
    refute_includes out + err, "\e["
  end

  def test_help_is_readonly_without_a_project_or_terminal
    out, err, status = invoke('--help')
    assert status.success?, out + err
    assert_includes out, 'Flutter打包'
    assert_includes out, '--check'
    assert_empty Dir.children(@run)
    assert_empty flutter_calls
    refute File.exist?(File.join(@root, 'trace'))
  end

  def test_fzf_selects_each_android_output_type
    { 'APK' => 'apk', 'AAB' => 'appbundle', 'APK + AAB' => 'all' }.each_with_index do |(choice, expected), index|
      out, err, status = shell(<<~'ZSH', env: { 'FP_TEST_ANDROID_TARGET' => choice })
        fp_select_platform || exit $?
        print -r -- "CHOSEN=$FP_PLATFORM|$FP_ANDROID_TARGET"
      ZSH
      assert status.success?, out + err
      assert_includes out, "CHOSEN=android|#{expected}"
      assert_equal 2 * (index + 1), File.read(File.join(@root, 'trace')).scan('fzf|').length
    end
  end

  def test_fzf_selects_ios_without_android_artifact_menu
    out, err, status = shell(<<~'ZSH', env: { 'FP_TEST_PLATFORM' => 'iOS' })
      fp_select_platform || exit $?
      print -r -- "CHOSEN=$FP_PLATFORM"
    ZSH
    assert status.success?, out + err
    assert_includes out, 'CHOSEN=ios'
    assert_equal 1, File.read(File.join(@root, 'trace')).scan('fzf|').length
  end

  def test_fzf_defaults_are_removed_only_from_child_process
    defaults = { 'FZF_DEFAULT_OPTS' => '--filter=arbitrary --multi', 'FZF_DEFAULT_OPTS_FILE' => '/does/not/exist', 'FZF_DEFAULT_COMMAND' => 'touch UNEXPECTED' }
    out, err, status = shell(<<~'ZSH', env: defaults)
      fp_select_platform || exit $?
      print -r -- "PARENT=$FZF_DEFAULT_OPTS|$FZF_DEFAULT_OPTS_FILE|$FZF_DEFAULT_COMMAND"
    ZSH
    assert status.success?, out + err
    assert_includes out, 'PARENT=' + defaults.values.join('|')
    refute File.exist?(File.join(@root, 'UNEXPECTED'))
  end

  def test_fzf_missing_or_unhealthy_stops_before_flutter
    FileUtils.rm(File.join(@bin, 'fzf'))
    out, err, status = shell('PATH="' + @bin + '"; fp_select_platform')
    assert_equal 2, status.exitstatus, out + err
    assert_includes err, 'fzf 不可用'
    write_mock('fzf', 'exit 11')
    out, err, status = shell('fp_select_platform')
    assert_equal 2, status.exitstatus, out + err
    assert_empty flutter_calls
  end

  def test_fzf_invalid_result_is_an_error
    out, err, status = shell('fp_select_platform', env: { 'FP_TEST_PLATFORM' => 'macOS' })
    assert_equal 2, status.exitstatus, out + err
    assert_includes err, '无效平台'
  end

  def test_fzf_cancel_exit_codes_survive_pipe_fail_and_main_stops_cleanly
    [1, 130].each do |code|
      out, err, status = shell('fp_select_platform', env: { 'FP_TEST_FZF_EXIT' => code.to_s })
      assert_equal code, status.exitstatus, out + err
      out, status = interactive('--project', @project, env: { 'FP_TEST_FZF_EXIT' => code.to_s })
      assert status.success?, out
      assert_includes out, '已取消平台 / 产物选择'
      assert_empty flutter_calls
    end
  end

  def test_android_artifact_menu_cancel_stops_before_pub_get
    out, status = interactive('--project', @project, env: { 'FP_TEST_FZF_TARGET_EXIT' => '130' })
    assert status.success?, out
    assert_includes out, '已取消平台 / 产物选择'
    assert_equal 2, File.read(File.join(@root, 'trace')).scan('fzf|').length
    assert_empty flutter_calls
  end

  def test_project_fvm_sdk_has_priority_over_global_flutter
    sdk = write_mock(File.join(@project, '.fvm/flutter_sdk/bin/flutter'), 'exit 0')
    out, err, status = shell('fp_resolve_flutter || exit $?; print -rl -- "${FP_FLUTTER[@]}"')
    assert status.success?, out + err
    assert_equal sdk, out.lines.last.strip
  end

  def test_pinned_fvm_never_falls_back_to_global_flutter
    ['.fvmrc', '.fvm/fvm_config.json', '.fvm/flutter_sdk'].each do |pin|
      path = File.join(@project, pin)
      FileUtils.mkdir_p(File.dirname(path))
      pin.end_with?('flutter_sdk') ? File.symlink(File.join(@root, 'missing-sdk'), path) : File.write(path, '{}')
      out, err, status = shell('PATH="' + @bin + '"; fp_resolve_flutter')
      refute status.success?, out + err
      assert_includes err, '项目固定了 FVM'
      assert_empty flutter_calls
      FileUtils.rm(path)
    end
  end

  def test_fvm_wrapper_is_used_for_a_pinned_project
    File.write(File.join(@project, '.fvmrc'), '{"flutter":"3.29.3"}')
    fvm = write_mock('fvm', 'exit 0')
    out, err, status = shell('fp_resolve_flutter || exit $?; print -rl -- "${FP_FLUTTER[@]}"')
    assert status.success?, out + err
    assert_equal [fvm, 'flutter'], out.lines.last(2).map(&:strip)
  end

  def test_java17_is_checked_and_exported
    out, err, status = shell('fp_check_java17 || exit $?; print -r -- "JDK=$JAVA_HOME|${path[1]}"')
    assert status.success?, out + err
    assert_includes out, "JDK=#{@java}|#{@java}/bin"
  end

  def test_wrong_java_and_failed_java_health_check_are_rejected
    ['print -u2 -r -- \'openjdk version "11.0.1"\'', 'exit 27'].each do |body|
      write_mock(File.join(@java, 'bin/java'), body)
      out, err, status = shell('fp_check_java17')
      refute status.success?, out + err
      assert_includes err, 'JDK 17'
      assert_empty flutter_calls
    end
  end

  def test_android_missing_gradlew_stops_before_pub_get
    FileUtils.rm(File.join(@project, 'android/gradlew'))
    out, err, status = shell('FP_PLATFORM=android; fp_check_toolchain')
    refute status.success?, out + err
    assert_includes err, 'android / gradlew'
    assert_empty flutter_calls
  end

  def test_ios_checks_xcode_and_requires_pod_only_for_a_podfile
    FileUtils.rm(File.join(@bin, 'pod'))
    out, err, status = shell('FP_PLATFORM=ios; fp_check_toolchain')
    assert status.success?, out + err
    assert_includes File.read(File.join(@root, 'trace')), 'xcodebuild|-version'
    File.write(File.join(@project, 'ios/Podfile'), '# fixture')
    out, err, status = shell('PATH="' + @bin + '"; FP_PLATFORM=ios; fp_check_toolchain')
    refute status.success?, out + err
    assert_includes err, 'CocoaPods 不可用'
  end

  def test_failed_xcode_check_preserves_failure_and_stops_before_flutter
    out, err, status = shell('FP_PLATFORM=ios; fp_check_toolchain', env: { 'FP_TEST_XCODE_EXIT' => '32' })
    assert_equal 32, status.exitstatus, out + err
    assert_includes err, '退出码 32'
    assert_empty flutter_calls
  end

  def test_pub_failure_propagates_through_tee_and_prevents_build
    out, err, status = shell('FP_PLATFORM=android; FP_ANDROID_TARGET=all; FP_FLUTTER=("' + File.join(@bin, 'flutter') + '"); fp_build', env: { 'FP_TEST_PUB_EXIT' => '23' })
    assert_equal 23, status.exitstatus, out + err
    assert_equal [%w[pub get]], flutter_calls
    assert_includes err, '退出码 23'
    refute_includes out, 'Flutter打包完成'
  end

  def test_build_failure_propagates_and_does_not_continue_to_second_target
    out, err, status = shell('FP_PLATFORM=android; FP_ANDROID_TARGET=all; FP_FLUTTER=("' + File.join(@bin, 'flutter') + '"); fp_build', env: { 'FP_TEST_BUILD_EXIT' => '37' })
    assert_equal 37, status.exitstatus, out + err
    assert_equal [%w[pub get], %w[build apk --release]], flutter_calls
    assert_includes err, '退出码 37'
    refute_includes out, 'Flutter打包完成'
  end

  def test_android_full_main_uses_literal_special_paths_and_flavor_arguments
    flavor = "prod ' $(touch FLAVOR_INJECTED)"
    out, status = interactive('--project', @project, '--target', 'all', '--mode', 'profile', '--flavor', flavor)
    assert status.success?, out
    assert_equal [%w[pub get], ['build', 'apk', '--profile', '--flavor', flavor], ['build', 'appbundle', '--profile', '--flavor', flavor]], flutter_calls
    assert_includes out, 'Flutter打包完成'
    refute File.exist?(File.join(@root, 'INJECTED'))
    refute File.exist?(File.join(@root, 'BACKTICK'))
    refute File.exist?(File.join(@project, 'FLAVOR_INJECTED'))
    assert File.file?(File.join(@project, "build/app/outputs/flutter-apk/app-#{flavor.downcase}-profile.apk"))
    assert Dir.glob(File.join(@run, 'JobsFlutterPackager.*/PackageFlutter.log')).any?
  end

  def test_ios_full_main_builds_and_reports_ipa
    out, status = interactive('--project', @project, env: { 'FP_TEST_PLATFORM' => 'iOS' })
    assert status.success?, out
    assert_equal [%w[pub get], %w[build ipa --release]], flutter_calls
    assert_includes out, 'Runner.ipa'
    assert_includes out, 'Flutter打包完成'
  end

  def test_build_success_without_output_is_failure
    out, status = interactive('--project', @project, '--target', 'apk', env: { 'FP_TEST_NO_OUTPUT' => '1' })
    refute status.success?, out
    assert_includes out, '没有产物'
    refute_includes out, 'Flutter打包完成'
    assert_equal [%w[pub get], %w[build apk --release]], flutter_calls
  end

  def test_empty_output_is_not_reported_as_a_successful_package
    out, status = interactive('--project', @project, '--target', 'appbundle', env: { 'FP_TEST_EMPTY_OUTPUT' => '1' })
    refute status.success?, out
    assert_includes out, '没有发现 appbundle 产物'
    refute_includes out, 'Flutter打包完成'
  end

  def test_report_rejects_other_modes_and_empty_files
    directory = File.join(@project, 'build/app/outputs/flutter-apk')
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, 'app-debug.apk'), 'debug-only')
    File.write(File.join(directory, 'app-release.apk'), '')
    out, err, status = shell('FP_MODE=release; fp_report_outputs apk')
    refute status.success?, out + err
    assert_includes err, '没有发现 apk 产物'
    refute_includes out, '✔ 产物'
  end

  def test_report_rejects_another_flavor_and_accepts_only_the_selected_flavor
    directory = File.join(@project, 'build/app/outputs/bundle/prodRelease')
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, 'app-staging-release.aab'), 'another-flavor')
    out, err, status = shell("FP_MODE=release; FP_FLAVOR=Prod; fp_report_outputs appbundle")
    refute status.success?, out + err
    refute_includes out, '✔ 产物'
    File.write(File.join(directory, 'app-prod-release.aab'), 'selected-flavor')
    out, err, status = shell("FP_MODE=release; FP_FLAVOR=Prod; fp_report_outputs appbundle")
    assert status.success?, out + err
    assert_includes out, 'app-prod-release.aab'
    refute_includes out, 'app-staging-release.aab'
  end

  def test_old_ipa_is_preserved_but_not_counted_as_a_new_export
    directory = File.join(@project, 'build/ios/ipa')
    FileUtils.mkdir_p(directory)
    ipa = File.join(directory, 'Runner.ipa')
    marker = File.join(@root, 'build-start')
    File.write(ipa, 'previous-export')
    File.write(marker, '')
    File.utime(Time.at(1_000_000_000), Time.at(1_000_000_000), ipa)
    File.utime(Time.at(1_000_000_100), Time.at(1_000_000_100), marker)
    out, err, status = shell("FP_BUILD_MARKER=#{marker.shellescape}; fp_report_outputs ipa")
    refute status.success?, out + err
    assert_includes out, '保留旧 IPA，未计入本轮导出'
    assert_includes err, '没有发现 ipa 产物'
    assert_equal 'previous-export', File.read(ipa)
    File.utime(Time.at(1_000_000_200), Time.at(1_000_000_200), ipa)
    out, err, status = shell("FP_BUILD_MARKER=#{marker.shellescape}; fp_report_outputs ipa")
    assert status.success?, out + err
    assert_includes out, '✔ 产物'
  end

  def test_android_cached_output_is_accepted_with_an_explicit_reuse_log
    directory = File.join(@project, 'build/app/outputs/flutter-apk')
    FileUtils.mkdir_p(directory)
    apk = File.join(directory, 'app-release.apk')
    marker = File.join(@root, 'build-start')
    File.write(apk, 'cached-output')
    File.write(marker, '')
    File.utime(Time.at(1_000_000_000), Time.at(1_000_000_000), apk)
    File.utime(Time.at(1_000_000_100), Time.at(1_000_000_100), marker)
    out, err, status = shell("FP_BUILD_MARKER=#{marker.shellescape}; fp_report_outputs apk")
    assert status.success?, out + err
    assert_includes out, '复用现存产物'
    assert_includes out, '✔ 产物'
    assert_equal 'cached-output', File.read(apk)
  end

  def test_harmony_menu_contains_all_platforms_and_each_ohos_output_type
    { 'HAP' => 'hap', 'APP' => 'app', 'HAP + APP' => 'all' }.each do |choice, expected|
      out, err, status = shell(<<~'ZSH', env: { 'FP_TEST_PLATFORM' => 'OpenHarmony', 'FP_TEST_OHOS_TARGET' => choice })
        fp_select_platform || exit $?
        print -r -- "CHOSEN=$FP_PLATFORM|$FP_OHOS_TARGET"
      ZSH
      assert status.success?, out + err
      assert_includes out, "CHOSEN=ohos|#{expected}"
    end
    trace = File.read(File.join(@root, 'trace'))
    ['Android', 'iOS', 'OpenHarmony', 'HAP', 'APP', 'HAP + APP'].each do |label|
      assert_includes trace, "fzf-row|#{label}\n"
    end
    assert_equal 6, trace.scan('fzf|').length
  end

  def test_harmony_artifact_menu_cancel_and_invalid_choice_do_not_run_flutter
    out, status = ohos_interactive(env: { 'FP_TEST_FZF_TARGET_EXIT' => '130' })
    assert status.success?, out
    assert_includes out, '已取消平台 / 产物选择'
    assert_empty flutter_calls
    out, err, status = shell('fp_select_platform', env: { 'FP_TEST_PLATFORM' => 'OpenHarmony', 'FP_TEST_OHOS_TARGET' => 'APK' })
    assert_equal 2, status.exitstatus, out + err
    assert_empty flutter_calls
  end

  def test_harmony_target_override_skips_only_the_secondary_menu
    out, err, status = shell(<<~'ZSH', env: { 'FP_TEST_PLATFORM' => 'OpenHarmony' })
      fp_parse --ohos-target app || exit $?
      fp_select_platform || exit $?
      print -r -- "CHOSEN=$FP_PLATFORM|$FP_OHOS_TARGET"
    ZSH
    assert status.success?, out + err
    assert_includes out, 'CHOSEN=ohos|app'
    assert_equal 1, File.read(File.join(@root, 'trace')).scan('fzf|').length
  end

  def test_harmony_environment_target_is_accepted_and_invalid_arguments_are_readonly
    out, err, status = shell('fp_parse || exit $?; print -r -- "CHOSEN=$FP_OHOS_TARGET"', env: { 'OHOS_BUILD_TARGET' => 'all' })
    assert status.success?, out + err
    assert_includes out, 'CHOSEN=all'
    [%w[--ohos-target apk], %w[--ohos-target], %w[--flutter-sdk]].each do |arguments|
      out, err, status = invoke('--check', '--project', @project, *arguments)
      assert_equal 2, status.exitstatus, out + err
    end
    assert_empty Dir.children(@run)
    assert_empty flutter_calls
  end

  def test_harmony_full_main_builds_selected_hap_app_and_all_with_literal_paths
    prepare_ohos
    { 'hap' => %w[hap], 'app' => %w[app], 'all' => %w[hap app] }.each do |choice, expected|
      FileUtils.rm_f(@environment['FP_TEST_ARGS'])
      out, status = ohos_interactive('--ohos-target', choice, '--mode', 'profile')
      assert status.success?, out
      calls = flutter_calls
      assert_includes calls, ['--version']
      expected.each { |target| assert_includes calls, ['build', target, '--help'] }
      assert_equal [%w[pub get]] + expected.map { |target| ['build', target, '--profile'] }, calls.reject { |call| call == ['--version'] || call.include?('--help') }
      assert_includes out, 'Flutter打包完成'
      expected.each { |target| assert File.size?(File.join(@project, "build/ohos/#{target}/entry-default-signed.#{target}")) }
      refute File.exist?(File.join(@root, 'INJECTED'))
      refute File.exist?(File.join(@root, 'BACKTICK'))
    end
  end

  def test_harmony_full_main_reports_module_outputs
    prepare_ohos
    out, status = ohos_interactive('--ohos-target', 'all', env: { 'FP_TEST_OHOS_OUTPUT_STYLE' => 'module' })
    assert status.success?, out
    assert_includes out, 'ohos/entry/build/default/outputs/default/entry-default-signed.hap'
    assert_includes out, 'ohos/entry/build/default/outputs/default/entry-default-signed.app'
  end

  def test_harmony_explicit_sdk_takes_priority_over_environment_and_project_sdk
    prepare_ohos
    sdk = File.join(@root, "显式 SDK ' $(touch SDK_INJECTED)")
    executable = write_mock(File.join(sdk, 'bin/flutter'), File.read(File.join(@bin, 'flutter')))
    write_mock(File.join(@project, '.fvm/flutter_sdk/bin/flutter'), 'exit 51')
    out, status = ohos_interactive('--ohos-target', 'hap', '--flutter-sdk', sdk, env: { 'FLUTTER_OHOS_SDK' => File.join(@root, 'missing-env-sdk') })
    assert status.success?, out
    assert_includes out, executable
    refute File.exist?(File.join(@root, 'SDK_INJECTED'))
    assert_includes flutter_calls, %w[build hap --release]
  end

  def test_harmony_environment_sdk_is_used_and_missing_override_does_not_fall_back
    prepare_ohos
    sdk = File.join(@root, '环境 SDK')
    executable = write_mock(File.join(sdk, 'bin/flutter'), File.read(File.join(@bin, 'flutter')))
    out, status = ohos_interactive('--ohos-target', 'hap', env: { 'FLUTTER_OHOS_SDK' => sdk })
    assert status.success?, out
    assert_includes out, executable
    FileUtils.rm_f(@environment['FP_TEST_ARGS'])
    out, status = ohos_interactive('--ohos-target', 'hap', '--flutter-sdk', File.join(@root, 'missing-sdk'))
    refute status.success?, out
    assert_empty flutter_calls
  end

  def test_harmony_pinned_fvm_without_local_sdk_does_not_call_fvm_or_global_flutter
    prepare_ohos
    ['.fvmrc', '.fvm/fvm_config.json', '.fvm/flutter_sdk'].each do |pin|
      path = File.join(@project, pin)
      FileUtils.mkdir_p(File.dirname(path))
      pin.end_with?('flutter_sdk') ? File.symlink(File.join(@root, 'missing-sdk'), path) : File.write(path, '{}')
      write_mock('fvm', 'print -r -- "UNEXPECTED FVM" >> "$FP_TEST_TRACE"; exit 88')
      out, status = ohos_interactive('--ohos-target', 'hap')
      refute status.success?, out
      assert_empty flutter_calls
      refute_includes File.read(File.join(@root, 'trace')), 'UNEXPECTED FVM'
      FileUtils.rm(path)
    end
  end

  def test_harmony_rejects_flavor_before_pub_get
    prepare_ohos
    out, status = ohos_interactive('--ohos-target', 'hap', '--flavor', 'production')
    refute status.success?, out
    assert_includes out, 'flavor'
    refute flutter_calls.any? { |call| call.first == 'pub' || (call.first == 'build' && !call.include?('--help')) }
  end

  def test_harmony_project_metadata_is_required_before_flutter
    prepare_ohos
    ['ohos/build-profile.json5', 'ohos/oh-package.json5'].each do |relative|
      path = File.join(@project, relative)
      snapshot = File.read(path)
      FileUtils.rm(path)
      out, status = ohos_interactive('--ohos-target', 'hap')
      refute status.success?, out
      assert_empty flutter_calls
      File.write(path, snapshot)
    end
  end

  def test_harmony_sdk_environment_must_exist_and_supports_hos_fallback
    prepare_ohos
    out, err, status = ohos_shell('fp_check_toolchain', env: { 'DEVECO_SDK_HOME' => nil, 'HOS_SDK_HOME' => nil })
    refute status.success?, out + err
    assert_empty flutter_calls
    out, err, status = ohos_shell('fp_check_toolchain', env: { 'DEVECO_SDK_HOME' => File.join(@root, 'missing-hos-sdk') })
    refute status.success?, out + err
    assert_empty flutter_calls
    out, err, status = ohos_shell('fp_check_toolchain', env: { 'DEVECO_SDK_HOME' => nil, 'HOS_SDK_HOME' => @environment['DEVECO_SDK_HOME'] })
    assert status.success?, out + err
  end

  def test_harmony_required_tools_are_health_checked_and_fail_before_pub_get
    prepare_ohos
    %w[node npm ohpm hvigorw].each do |tool|
      path = tool.start_with?('/') ? tool : File.join(@bin, tool)
      snapshot = File.read(path)
      write_mock(path, 'exit 47')
      out, status = ohos_interactive('--ohos-target', 'hap')
      refute status.success?, out
      assert_includes out, tool.split('/').last
      refute flutter_calls.any? { |call| call.first == 'pub' || (call.first == 'build' && !call.include?('--help')) }
      File.write(path, snapshot)
      FileUtils.rm_f(@environment['FP_TEST_ARGS'])
    end
  end

  def test_harmony_unhealthy_flutter_or_unsupported_package_kind_is_rejected
    prepare_ohos
    [{ 'FP_TEST_VERSION_EXIT' => '29' }, { 'FP_TEST_UNSUPPORTED_TARGET' => 'hap' }].each do |env|
      FileUtils.rm_f(@environment['FP_TEST_ARGS'])
      out, status = ohos_interactive('--ohos-target', 'hap', env: env)
      refute status.success?, out
      refute flutter_calls.any? { |call| call.first == 'pub' || (call.first == 'build' && !call.include?('--help')) }
    end
    FileUtils.rm_f(@environment['FP_TEST_ARGS'])
    out, status = ohos_interactive('--ohos-target', 'hap', env: { 'FP_TEST_UNSUPPORTED_TARGET' => 'app' })
    assert status.success?, out
    refute_includes flutter_calls, %w[build app --help]
  end

  def test_harmony_failure_stops_before_second_target_and_preserves_exit_code
    prepare_ohos
    [{ 'FP_TEST_PUB_EXIT' => '23' }, { 'FP_TEST_BUILD_EXIT' => '37' }].each do |env|
      FileUtils.rm_f(@environment['FP_TEST_ARGS'])
      out, status = ohos_interactive('--ohos-target', 'all', env: env)
      assert_equal env.values.first.to_i, status.exitstatus, out
      refute_includes flutter_calls, %w[build app --release]
      refute_includes out, 'Flutter打包完成'
    end
  end

  def test_harmony_success_without_nonempty_outputs_is_failure
    prepare_ohos
    ['FP_TEST_NO_OUTPUT', 'FP_TEST_EMPTY_OUTPUT'].each do |flag|
      out, status = ohos_interactive('--ohos-target', 'hap', env: { flag => '1' })
      refute status.success?, out
      refute_includes out, 'Flutter打包完成'
      refute_includes out, '✔ 产物'
    end
  end

  def test_harmony_cached_outputs_are_preserved_and_explicitly_reported
    prepare_ohos
    marker = File.join(@root, 'build-start')
    File.write(marker, '')
    File.utime(Time.at(1_000_000_100), Time.at(1_000_000_100), marker)
    outputs = ['build/ohos/hap/entry-default-signed.hap', 'ohos/feature/build/default/outputs/default/feature-signed.hap']
    outputs.each do |relative|
      path = File.join(@project, relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, 'cached-harmony-package')
      File.utime(Time.at(1_000_000_000), Time.at(1_000_000_000), path)
    end
    out, err, status = ohos_shell("FP_BUILD_MARKER=#{marker.shellescape}; fp_report_outputs hap")
    assert status.success?, out + err
    assert_includes out, '复用现存产物'
    outputs.each do |relative|
      assert_includes out, relative
      assert_equal 'cached-harmony-package', File.read(File.join(@project, relative))
    end
  end

  def test_harmony_missing_commands_and_invalid_java_fail_before_flutter
    prepare_ohos
    %w[node npm ohpm hvigorw].each do |tool|
      path = File.join(@bin, tool)
      snapshot = File.read(path)
      FileUtils.rm(path)
      out, err, status = ohos_shell("PATH=#{@bin.shellescape}; fp_check_toolchain")
      refute status.success?, out + err
      assert_includes err, tool
      assert_empty flutter_calls
      write_mock(path, snapshot)
    end
    write_mock(File.join(@java, 'bin/java'), 'exit 46')
    out, err, status = ohos_shell('fp_check_toolchain')
    assert_equal 46, status.exitstatus, out + err
    assert_empty flutter_calls
  end

  def test_harmony_generic_successful_help_is_not_accepted_as_package_capability
    prepare_ohos
    out, status = ohos_interactive('--ohos-target', 'hap', env: { 'FP_TEST_GENERIC_HELP' => '1' })
    refute status.success?, out
    assert_includes out, '未确认 flutter build hap 能力'
    refute flutter_calls.any? { |call| call.first == 'pub' || (call.first == 'build' && !call.include?('--help')) }
  end

  def test_harmony_report_excludes_intermediates_dependencies_wrong_types_and_empty_files
    prepare_ohos
    %w[ohos/entry/build/intermediates/outputs/intermediate.hap ohos/entry/build/node_modules/outputs/dependency.hap ohos/entry/build/default/not-outputs/staging.hap build/ohos/hap/empty.hap build/ohos/app/another.app].each do |relative|
      path = File.join(@project, relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, relative.end_with?('empty.hap') ? '' : 'not-a-final-hap')
    end
    out, err, status = ohos_shell('fp_report_outputs hap')
    refute status.success?, out + err
    refute_includes out, '✔ 产物'
    assert_includes err, '未发现非空 .hap'
  end

  def test_harmony_sdk_override_does_not_change_android_or_ios_resolution
    %w[Android iOS].each do |platform|
      FileUtils.rm_f(@environment['FP_TEST_ARGS'])
      out, status = interactive('--project', @project, '--flutter-sdk', File.join(@root, 'missing-ohos-sdk'),
                                env: { 'FP_TEST_PLATFORM' => platform, 'FLUTTER_OHOS_SDK' => File.join(@root, 'missing-env-sdk') })
      assert status.success?, out
      assert_includes flutter_calls, %w[pub get]
      refute_includes flutter_calls, ['--version']
    end
  end
end
