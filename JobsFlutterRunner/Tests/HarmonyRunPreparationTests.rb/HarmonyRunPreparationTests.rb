# Created by Jobs on 2026年11月10日，星期二.
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'shellwords'

class HarmonyRunPreparationTests < Minitest::Test
  PACKAGE = File.expand_path('../../Scripts/【MacOS】Flutter运行前体检.zsh/【MacOS】鸿蒙运行环境准备.zsh', __dir__)
  ENTRY = File.join(PACKAGE, '【MacOS】鸿蒙运行环境准备.zsh')

  def setup
    @root = File.realpath(Dir.mktmpdir('harmony-run-preparation-'))
    @project = File.join(@root, "project 中文 ' $(touch NEVER)")
    @package = File.join(@root, 'copied preparation package')
    @toolchain = File.join(@root, 'DevEco CLT')
    @original_sdk = File.join(@root, 'original sdk')
    @ohos_sdk = File.join(@root, 'ohos sdk')
    @trace = File.join(@root, 'calls')
    FileUtils.mkdir_p([File.join(@project, 'lib'), File.join(@package, 'Resources/Tools'), File.join(@root, 'unrelated'),
                       File.join(@toolchain, 'sdk/default/openharmony/ets'), File.join(@toolchain, 'sdk/default/openharmony/native')])
    File.write(File.join(@project, 'pubspec.yaml'), "name: fixture_app\ndependencies:\n  flutter:\n    sdk: flutter\n")
    File.write(File.join(@project, 'lib/main.dart'), 'existing business')
    File.write(File.join(@project, 'README.md'), 'existing readme')
    write_flutter(@original_sdk, supported: false)
    write_flutter(@ohos_sdk, supported: true)
    executable(File.join(@package, 'Resources/Tools/ManageHarmonyFlutterVersion.zsh'), <<~'ZSH')
      if [[ "$*" == *--verify-sdk* ]]; then
        print VERIFY_CURRENT_SDK >> "$FAKE_TRACE"
        exit "${FAKE_CURRENT_CONSTRAINT_EXIT:-0}"
      fi
      [[ "$*" == *--prepare-for-run* ]] || exit 70
      print MANAGER >> "$FAKE_TRACE"
      [[ -z "${FAKE_MANAGER_EXIT:-}" ]] || exit "$FAKE_MANAGER_EXIT"
      mkdir -p "$FAKE_PROJECT/.fvm"
      ln -s "$FAKE_OHOS_SDK" "$FAKE_PROJECT/.fvm/flutter_sdk"
      print '{"flutter":"fixture-ohos"}' > "$FAKE_PROJECT/.fvmrc"
    ZSH
    executable(File.join(@package, 'Resources/Tools/CreateHarmonySimulator.zsh'), <<~'ZSH')
      [[ "$1" == --tools-only ]] || exit 71
      print TOOLS_ONLY >> "$FAKE_TRACE"
      [[ -z "${FAKE_TOOLS_EXIT:-}" ]] || exit "$FAKE_TOOLS_EXIT"
      print -r -- "$FAKE_TOOLCHAIN" > "$JOBS_HARMONY_TOOLS_RECEIPT"
    ZSH
    File.write(File.join(@package, 'Resources/Flutter运行前体检.jxa'), <<~'JXA')
      function run(a) {
        ObjC.import('Foundation');
        if (ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('FAKE_PLUGIN_FAILURE')) === '1') throw Error('vendor plugin missing ohos');
        return 'plugin declarations verified';
      }
    JXA
    {'node' => 'node/bin', 'ohpm' => 'ohpm/bin', 'hvigorw' => 'hvigor/bin'}.each do |name, directory|
      executable(File.join(@toolchain, directory, name), "print -r -- '#{name}|'\"$*\"'|'\"$PWD\" >> \"$FAKE_TRACE\"\nprint fixture-version\n")
    end
    executable(File.join(@toolchain, 'jbr/bin/java'), "print 'openjdk version \"17.0.1\"'\n")
    executable(File.join(@toolchain, 'jbr/bin/javac'), "print 'javac 17.0.1'\n")
    executable(File.join(@toolchain, 'sdk/default/openharmony/toolchains/hdc'), "print hdc-version\n")
    @environment = {
      'HOME' => @root, 'TMPDIR' => @root + '/', 'PATH' => '/usr/bin:/bin:/usr/sbin:/sbin',
      'JAVA_HOME' => '', 'DEVECO_STUDIO_HOME' => '', 'TOOL_HOME' => '', 'DEVECO_SDK_HOME' => '', 'OHOS_SDK_HOME' => '',
      'NO_COLOR' => '1', 'FAKE_PROJECT' => @project, 'FAKE_OHOS_SDK' => @ohos_sdk,
      'FAKE_TOOLCHAIN' => @toolchain, 'FAKE_TRACE' => @trace
    }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def executable(path, body)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/bin/zsh\n#{body}\n")
    File.chmod(0o700, path)
  end

  def write_flutter(root, supported:)
    executable(File.join(root, 'bin/flutter'), <<~ZSH)
      case "$1" in
        build) [[ '#{supported}' == true ]] && print '  hap  Build HAP' || print '  apk  Build APK' ;;
        create)
          print CREATE >> "$FAKE_TRACE"
          [[ "$PWD" != "$FAKE_PROJECT" ]] || exit 77
          mkdir -p ohos/AppScope
          for name in build-profile.json5 oh-package.json5 AppScope/app.json5; do print '{}' > "ohos/$name"; done
          print '#!/bin/sh' > ohos/hvigorw
          print 'printf "HVIGOR_SYNC\\n" >> "$FAKE_TRACE"' >> ohos/hvigorw
          if [[ "${FAKE_CONCURRENT_OHOS:-0}" == 1 ]]; then mkdir "$FAKE_PROJECT/ohos"; print external > "$FAKE_PROJECT/ohos/external"; fi
          ;;
        pub)
          print -r -- "PUB|$PWD" >> "$FAKE_TRACE"
          [[ -z "${FAKE_PUB_EXIT:-}" ]] || exit "$FAKE_PUB_EXIT"
          ;;
        *) print UNEXPECTED_FLUTTER >> "$FAKE_TRACE"; exit 76 ;;
      esac
    ZSH
  end

  def shell(body = 'jobs_flutter_prepare_harmony_for_run __harmony_usb__:fixture', env: {}, sdk: @original_sdk)
    code = <<~ZSH
      source #{ENTRY.shellescape}
      setopt NO_NOMATCH
      JOBS_HARMONY_PREPARE_PACKAGE=#{@package.shellescape}
      PROJECT_PATH=#{@project.shellescape}
      FLUTTER_BIN=#{File.join(sdk, 'bin/flutter').shellescape}
      LOG_FILE=#{File.join(@root, 'run.log').shellescape}
      log() { print -r -- "$*"; }
      jobs_hpr_system_java17() { return 1; }
      run_bounded() {
        local output="$2" result=0
        shift 2
        "$@" > "$output" 2>&1 || result=$?
        /bin/cat "$output"
        return "$result"
      }
      #{body}
    ZSH
    Open3.capture3(@environment.merge(env), '/bin/zsh', '-f', '-c', code, chdir: File.join(@root, 'unrelated'))
  end

  def calls
    File.exist?(@trace) ? File.read(@trace) : ''
  end

  def platform
    FileUtils.mkdir_p(File.join(@project, 'ohos/AppScope'))
    %w[build-profile.json5 oh-package.json5 AppScope/app.json5].each { |name| File.write(File.join(@project, 'ohos', name), '{}') }
    File.write(File.join(@project, 'ohos/hvigorw'), "#!/bin/sh\nprintf 'HVIGOR_SYNC\\n' >> \"$FAKE_TRACE\"\n")
  end

  def test_missing_environment_prepares_in_same_flow_and_never_runs_app
    before = %w[pubspec.yaml README.md lib/main.dart].to_h { |path| [path, File.binread(File.join(@project, path))] }
    out, err, result = shell("jobs_flutter_prepare_harmony_for_run '__harmony_usb__:fixture' || exit $?; print -r -- \"RETURN=$REPLY|$FLUTTER_BIN|$TOOL_HOME\"")
    assert result.success?, out + err
    assert_match(/MANAGER.*CREATE.*TOOLS_ONLY.*PUB.*ohpm\|install.*HVIGOR_SYNC/m, calls)
    assert_includes calls, "PUB|#{@project}"
    assert_includes out, "RETURN=__harmony_usb__:fixture|#{@ohos_sdk}/bin/flutter|#{@toolchain}"
    before.each { |path, contents| assert_equal contents, File.binread(File.join(@project, path)) }
    refute_includes calls, 'UNEXPECTED_FLUTTER'
    refute File.exist?(File.join(@project, 'NEVER'))
    assert Dir.glob(File.join(@root, 'JobsHarmonyRun.*/before/pubspec.yaml')).any?
  end

  def test_healthy_sdk_and_existing_platform_are_reused
    platform
    out, err, result = shell(env: {}, sdk: @ohos_sdk)
    assert result.success?, out + err
    refute_includes calls, 'MANAGER'
    refute_includes calls, 'CREATE'
    assert_equal '{}', File.read(File.join(@project, 'ohos/build-profile.json5'))
  end

  def test_installed_hap_sdk_below_project_constraint_enters_upgrade_chain
    out, err, result = shell(env: {'FAKE_CURRENT_CONSTRAINT_EXIT' => '65'}, sdk: @ohos_sdk)
    assert result.success?, out + err
    assert_match(/VERIFY_CURRENT_SDK.*MANAGER.*CREATE/m, calls)
  end

  def test_unparseable_installed_sdk_constraint_stops_without_guessing_upgrade
    out, err, result = shell(env: {'FAKE_CURRENT_CONSTRAINT_EXIT' => '66'}, sdk: @ohos_sdk)
    assert_equal 66, result.exitstatus, out + err
    refute_includes calls, 'MANAGER'
    refute_includes calls, 'CREATE'
    refute_includes calls, 'TOOLS_ONLY'
  end

  def test_existing_incomplete_platform_is_preserved_without_regeneration
    FileUtils.mkdir_p(File.join(@project, 'ohos'))
    File.write(File.join(@project, 'ohos/keep'), 'owned existing')
    out, err, result = shell(sdk: @ohos_sdk)
    refute result.success?, out + err
    assert_includes out, '不重新生成覆盖'
    assert_equal 'owned existing', File.read(File.join(@project, 'ohos/keep'))
    refute_includes calls, 'CREATE'
    refute_includes calls, 'TOOLS_ONLY'
  end

  def test_sdk_failure_stops_all_later_steps
    out, err, result = shell(env: {'FAKE_MANAGER_EXIT' => '41'})
    assert_equal 41, result.exitstatus, out + err
    assert_equal "MANAGER\n", calls
  end

  def test_tools_cancel_stops_before_pub_and_native_dependencies
    out, err, result = shell(env: {'FAKE_TOOLS_EXIT' => '130'})
    assert_equal 130, result.exitstatus, out + err
    refute_includes calls, 'PUB|'
    refute_includes calls, 'ohpm|install'
  end

  def test_pub_failure_is_preserved_without_native_sync
    out, err, result = shell(env: {'FAKE_PUB_EXIT' => '42'})
    assert_equal 42, result.exitstatus, out + err
    refute_includes calls, 'ohpm|install'
    refute_includes calls, 'HVIGOR_SYNC'
  end

  def test_vendor_plugin_gap_stops_without_editing_vendor_or_syncing
    vendor = File.join(@project, 'vendor/plugin.dart')
    FileUtils.mkdir_p(File.dirname(vendor))
    File.write(vendor, 'vendor original')
    out, err, result = shell(env: {'FAKE_PLUGIN_FAILURE' => '1'})
    refute result.success?, out + err
    assert_includes out, '保留供应商源码'
    assert_equal 'vendor original', File.read(vendor)
    refute_includes calls, 'ohpm|install'
    refute_includes calls, 'HVIGOR_SYNC'
  end

  def test_concurrent_platform_creation_is_not_overwritten_or_nested
    out, err, result = shell(env: {'FAKE_CONCURRENT_OHOS' => '1'})
    refute result.success?, out + err
    assert_equal "external\n", File.read(File.join(@project, 'ohos/external'))
    refute Dir.exist?(File.join(@project, 'ohos/ohos'))
    refute_includes calls, 'TOOLS_ONLY'
  end

  def test_source_from_function_keeps_api_and_package_location_after_return
    out, err, result = shell("load_again() { source #{ENTRY.shellescape}; }; load_again; print -r -- \"LOCATION=$JOBS_HARMONY_PREPARE_PACKAGE\"; (( ${+functions[jobs_flutter_prepare_harmony_for_run]} ))")
    assert result.success?, out + err
    assert_includes out, "LOCATION=#{PACKAGE}"
    assert_empty calls
  end

  def test_missing_jdk_is_installed_in_process_and_rechecked
    FileUtils.remove_entry(File.join(@toolchain, 'jbr'))
    prefix = File.join(@root, 'brew-java')
    bin = File.join(@root, 'bin')
    executable(File.join(bin, 'brew'), <<~'ZSH')
      print -r -- "BREW|$*" >> "$FAKE_TRACE"
      case "$1" in
        install)
          [[ -z "${FAKE_JAVA_INSTALL_EXIT:-}" ]] || exit "$FAKE_JAVA_INSTALL_EXIT"
          mkdir -p "$FAKE_JAVA_PREFIX/libexec/openjdk.jdk/Contents/Home/bin"
          printf '#!/bin/sh\nprintf '\''openjdk version "17.0.1"\n'\''\n' > "$FAKE_JAVA_PREFIX/libexec/openjdk.jdk/Contents/Home/bin/java"
          printf '#!/bin/sh\nprintf '\''javac 17.0.1\n'\''\n' > "$FAKE_JAVA_PREFIX/libexec/openjdk.jdk/Contents/Home/bin/javac"
          chmod 700 "$FAKE_JAVA_PREFIX/libexec/openjdk.jdk/Contents/Home/bin/"* ;;
        --prefix) print -r -- "$FAKE_JAVA_PREFIX" ;;
        *) exit 79 ;;
      esac
    ZSH
    out, err, result = shell("jobs_flutter_prepare_harmony_for_run fixture || exit $?; print -r -- \"JAVA=$JAVA_HOME\"", env: {'PATH' => "#{bin}:/usr/bin:/bin", 'FAKE_JAVA_PREFIX' => prefix})
    assert result.success?, out + err
    assert_includes calls, 'BREW|install openjdk@17'
    assert_includes out, "JAVA=#{prefix}/libexec/openjdk.jdk/Contents/Home"
    assert_includes calls, 'HVIGOR_SYNC'
  end

  def test_java_install_failure_does_not_continue_to_pub_or_run
    FileUtils.remove_entry(File.join(@toolchain, 'jbr'))
    bin = File.join(@root, 'bin')
    executable(File.join(bin, 'brew'), 'print JAVA_INSTALL_FAILED; exit 58')
    out, err, result = shell(env: {'PATH' => "#{bin}:/usr/bin:/bin"})
    assert_equal 58, result.exitstatus, out + err
    refute_includes calls, 'PUB|'
    refute_includes calls, 'ohpm|install'
  end
end
