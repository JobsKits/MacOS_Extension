# frozen_string_literal: true
# Created by Jobs on 2026年10月28日，星期三。
# 临时工程验证组件计划、本机配置合并与节点事件，不运行下载、安装或许可证命令。
require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class AndroidSetupPlatformTests < Minitest::Test
  TOOLS = File.expand_path('../Scripts/Tools', __dir__)

  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-android-setup-'))
    @project = File.join(@root, "项目 空格 ' $literal")
    @sdk = File.join(@root, 'Flutter SDK')
    @run = File.join(@root, 'run')
    FileUtils.mkdir_p([File.join(@project, 'android/app'), File.join(@sdk, 'bin'), @run])
    @build = File.join(@project, 'android/app/build.gradle.kts')
    File.write(@build, "android { compileSdk = 36\n buildToolsVersion = \"36.0.0\"\n ndkVersion = \"28.2.13676358\"\n externalNativeBuild { cmake { version = \"3.22.1\" } } }\n")
    @env = { 'AP_TEST_PROJECT' => @project, 'AP_TEST_SDK' => @sdk, 'AP_TEST_RUN' => @run,
             'AP_TEST_TOOLS' => TOOLS, 'AP_TEST_TRACE' => File.join(@root, 'trace') }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def run_zsh(body)
    prefix = <<~'SH'
      source "$AP_TEST_TOOLS/SetupFlutterPlatform.zsh"
      AP_PROJECT="$AP_TEST_PROJECT" AP_FLUTTER="$AP_TEST_SDK/bin/flutter"
      PE_RUN_DIR="$AP_TEST_RUN"
      pe_log() { print -r -- "$*" >&2; }
      pe_event() { printf '%s\n' "$*" >> "$AP_TEST_TRACE"; }
      sf_file_stamp() { [[ -e "$1" ]] || { print absent; return; }; /usr/bin/stat -f '%d:%i:%m:%z' "$1"; /usr/bin/shasum -a 256 "$1"; }
    SH
    Open3.capture3(@env, '/bin/zsh', '-c', prefix + body)
  end

  def test_explicit_components_are_read_without_running_project
    out, err, status = run_zsh('ap_read_requirements && printf "%s\n" "$AP_API" "$AP_BUILD" "$AP_NDK" "$AP_CMAKE"')
    assert status.success?, err
    assert_equal %w[36 36.0.0 28.2.13676358 3.22.1], out.lines.map(&:strip)
  end

  def test_flutter_extension_kotlin_typed_defaults
    File.write(@build, "android { compileSdk = flutter.compileSdkVersion\n ndkVersion = flutter.ndkVersion }\n")
    directory = File.join(@sdk, 'packages/flutter_tools/gradle/src/main/kotlin')
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, 'FlutterExtension.kt'), 'val compileSdkVersion: Int = 36; val ndkVersion: String = "28.2.13676358"')
    out, err, status = run_zsh('ap_read_requirements && printf "%s\n" "$AP_API" "$AP_NDK"')
    assert status.success?, err
    assert_equal %w[36 28.2.13676358], out.lines.map(&:strip)
  end

  def test_unresolved_flutter_ndk_stops_instead_of_installing_guess
    File.write(@build, 'ndkVersion = flutter.ndkVersion')
    _, err, status = run_zsh('ap_read_requirements')
    refute status.success?
    assert_includes err, '无法解析'
  end

  def test_comments_do_not_override_active_versions
    File.write(@build, "// compileSdk = 99\n/* ndkVersion = \"99.9.999\" */\ncompileSdkVersion 35\n")
    out, err, status = run_zsh('ap_read_requirements && print -r -- "$AP_API|$AP_NDK"')
    assert status.success?, err
    assert_equal '35|', out.strip
  end

  def test_dynamic_native_versions_remain_pending_selection
    File.write(@build, 'android { compileSdk = rootProject.ext.api; ndkVersion = versions.ndk; externalNativeBuild { cmake { version = versions.cmake } } }')
    out, err, status = run_zsh('ap_read_requirements && print -r -- "$AP_DYNAMIC_NDK|$AP_DYNAMIC_CMAKE"')
    assert status.success?, err
    assert_equal '1|1', out.strip
  end

  def test_component_version_metadata_is_read_as_data
    properties = File.join(@run, 'source.properties')
    File.write(properties, "Pkg.Revision=36.0.0\nAndroidVersion.ApiLevel=36\n")
    out, err, status = run_zsh('ap_package_value "$PE_RUN_DIR/source.properties" Pkg.Revision')
    assert status.success?, err
    assert_equal '36.0.0', out
  end

  def test_sdk_property_merge_preserves_other_keys_and_backups
    config = File.join(@project, 'android/local.properties')
    original = "sdk.dir=/old\nflutter.sdk=/existing\ncustom=value\n"
    File.write(config, original)
    sdk = File.join(@root, 'Android SDK')
    FileUtils.mkdir_p(sdk)
    out, err, status = run_zsh('ANDROID_SIM_SDK="${AP_TEST_SDK:h}/Android SDK"; ap_write_sdk_config')
    assert status.success?, out + err
    text = File.read(config)
    assert_includes text, 'flutter.sdk=/existing'
    assert_includes text, 'custom=value'
    assert_includes text, 'Android\ SDK'
    assert_equal original, File.read(File.join(@run, 'before/android-local.properties'))
    assert_includes File.read(@env['AP_TEST_TRACE']), 'platforms.android.config platforms.android 项目SDK路径 succeeded'
  end

  def test_symbolic_local_config_is_preserved
    external = File.join(@root, 'external')
    File.write(external, 'keep')
    File.symlink(external, File.join(@project, 'android/local.properties'))
    _, _, status = run_zsh('ap_check_project')
    refute status.success?
    assert_equal 'keep', File.read(external)
  end

  def test_health_checks_skip_already_installed_components
    sdk = File.join(@root, 'Android SDK')
    %w[platform-tools/adb build-tools/36.0.0/aapt2 cmake/3.22.1/bin/cmake].each do |entry|
      target = File.join(sdk, entry)
      FileUtils.mkdir_p(File.dirname(target)); File.write(target, 'fixture'); FileUtils.chmod(0o755, target)
    end
    %w[platforms/android-36/android.jar ndk/28.2.13676358/source.properties].each do |entry|
      target = File.join(sdk, entry); FileUtils.mkdir_p(File.dirname(target)); File.write(target, 'fixture')
    end
    _, err, status = run_zsh(<<~'SH')
      ap_read_requirements || exit $?
      ANDROID_SIM_SDK="${AP_TEST_SDK:h}/Android SDK"
      android_install_package() { print unexpected-install >> "$AP_TEST_TRACE"; return 41; }
      pe_run_logged() { print "health $*" >> "$AP_TEST_TRACE"; }
      ap_install_packages
    SH
    assert status.success?, err
    trace = File.read(@env['AP_TEST_TRACE'])
    refute_includes trace, 'unexpected-install'
    assert_includes trace, 'platforms.android.native platforms.android NDK / CMake succeeded'
  end

  def test_module_source_has_no_install_or_project_write
    _, err, status = run_zsh('true')
    assert status.success?, err
    assert_empty Dir.children(@run)
    refute File.exist?(@env['AP_TEST_TRACE'])
  end

  def test_license_exit_zero_without_acceptance_is_still_attention
    fake = File.join(@root, 'sdkmanager')
    File.write(fake, "#!/bin/zsh\nprint '7 of 7 SDK package licenses not accepted.'\n")
    FileUtils.chmod(0o755, fake)
    @env['AP_TEST_MANAGER'] = fake
    _, err, status = run_zsh('ANDROID_SIM_SDKMANAGER="$AP_TEST_MANAGER"; ANDROID_SIM_SDK="$AP_TEST_SDK"; LOG_FILE="$PE_RUN_DIR/android.log"; ap_review_licenses')
    assert_equal 3, status.exitstatus, err
    trace = File.read(@env['AP_TEST_TRACE'])
    assert_includes trace, 'attention'
    refute_includes trace, 'succeeded'
  end

  def test_license_acceptance_uses_official_result
    fake = File.join(@root, 'sdkmanager')
    File.write(fake, "#!/bin/zsh\nprint 'All SDK package licenses accepted.'\n")
    FileUtils.chmod(0o755, fake)
    @env['AP_TEST_MANAGER'] = fake
    _, err, status = run_zsh('ANDROID_SIM_SDKMANAGER="$AP_TEST_MANAGER"; ANDROID_SIM_SDK="$AP_TEST_SDK"; LOG_FILE="$PE_RUN_DIR/android.log"; ap_review_licenses')
    assert status.success?, err
    assert_includes File.read(@env['AP_TEST_TRACE']), 'Android许可证 succeeded'
  end
end
