# frozen_string_literal: true
require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class BuildArtifactCleanerTests < Minitest::Test
  SCRIPT = File.expand_path('../Scripts/CleanBuildArtifacts.zsh', __dir__)

  def self.detector
    return @detector if @detector
    build = Dir.mktmpdir('jobs-build-detector-')
    @detector = File.join(build, 'detector')
    output, status = Open3.capture2e('/usr/bin/swiftc',
      File.expand_path('../JobsTerminalShared/DependencyProjectValidator.swift', __dir__),
      File.join(__dir__, 'DependencyProjectValidatorTests.swift'), '-o', @detector)
    raise output unless status.success?
    Minitest.after_run { FileUtils.remove_entry(build) }
    @detector
  end

  def setup
    @temporary = File.realpath(Dir.mktmpdir('jobs-build-clean-'))
    @root = File.join(@temporary, "工程 [test] ' $(touch SHOULD_NOT_EXIST)\n第二行")
    @home = File.join(@temporary, 'home')
    FileUtils.mkdir_p([@root, @home])
  end

  def teardown
    FileUtils.remove_entry(@temporary)
  end

  def file(path, text = 'keep')
    path = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    path
  end

  def flutter
    file('pubspec.yaml', "name: demo\ndependencies:\n  flutter:\n    sdk: flutter\n")
    file('lib/main.dart')
  end

  def android(prefix = '')
    file(File.join(prefix, 'settings.gradle.kts'), 'include(":app", ":feature:chat")')
    file(File.join(prefix, 'app/build.gradle.kts'), 'plugins { id("com.android.application") }')
    file(File.join(prefix, 'feature/chat/build.gradle'), "apply plugin: 'com.android.library'")
  end

  def ios(prefix = '')
    file(File.join(prefix, 'Demo.xcodeproj/project.pbxproj'), 'SDKROOT = iphoneos;')
  end

  def harmony(prefix = '')
    file(File.join(prefix, 'hvigorfile.ts'), "throw new Error('must never execute project scripts');")
    file(File.join(prefix, 'build-profile.json5'), '{ app: {}, modules: [{name: "entry", srcPath: "./entry"}] }')
    file(File.join(prefix, 'oh-package.json5'), '{}')
    file(File.join(prefix, 'AppScope/app.json5'), '{ app: { bundleName: "com.example.demo" } }')
    %w[entry features/chat].each do |mod|
      file(File.join(prefix, mod, 'build-profile.json5'), '{}')
      file(File.join(prefix, mod, 'src/main/module.json5'), '{ module: { type: "entry" } }')
      file(File.join(prefix, mod, 'hvigorfile.ts'), 'export default {};')
      file(File.join(prefix, mod, 'oh-package.json5'), '{}')
    end
  end

  def run_clean(mode = '--yes', input = '', target = @root, scope = nil)
    # 用相同磁盘夹具核对真实 Finder 检测器与终端脚本，防止标题和删除范围分歧。
    kind, swift_status = Open3.capture2e(self.class.detector, '--build-artifact-kind', target)
    assert swift_status.success?, kind
    detected, detect_status = Open3.capture2e({ 'HOME' => @home }, '/bin/zsh', SCRIPT, target, '--detect', *[scope].compact)
    assert_equal kind.strip, detect_status.success? ? detected.strip : 'unknown', detected
    Open3.capture2e({ 'HOME' => @home }, '/bin/zsh', SCRIPT, target, *[mode, scope].compact, stdin_data: input)
  end

  def test_harmony_native_multimodule_preserves_dependencies_signing_and_nested_projects
    harmony
    outputs = %w[build .hvigor entry/build entry/.hvigor features/chat/build]
    outputs.each { |p| file(p + '/artifact') }
    preserved = %w[oh_modules/library/build/keep node_modules/package/build/keep oh-package-lock.json5 entry/oh-package-lock.json5 entry/libs/flutter.har signing/key.p12 hvigor/hvigor-config.json5 unrelated/build/keep]
    preserved.each { |p| file(p) }
    harmony('independent')
    file('independent/entry/build/keep')
    %w[vendored generated_flutter].each do |nested|
      harmony(nested)
      FileUtils.rm_f(File.join(@root, nested, 'AppScope/app.json5'))
      file(File.join(nested, nested == 'vendored' ? '.git' : 'pubspec.yaml'))
      file(File.join(nested, 'entry/build/keep'))
    end
    global = File.join(@home, '.hvigor/cache/keep')
    FileUtils.mkdir_p(File.dirname(global))
    File.write(global, 'global cache')
    output, status = run_clean
    assert status.success?, output
    assert_includes output, '工程类型：OpenHarmony'
    outputs.each { |p| refute File.exist?(File.join(@root, p)), p }
    (preserved + %w[independent/entry/build/keep vendored/entry/build/keep generated_flutter/entry/build/keep]).each { |p| assert File.exist?(File.join(@root, p)), p }
    assert File.exist?(global)
  end

  def test_flutter_cleans_recognized_ohos_and_native_entry_does_not_touch_flutter_parent
    flutter
    harmony('ohos')
    outputs = %w[build/ohos .dart_tool ohos/build ohos/.hvigor ohos/entry/build ohos/features/chat/build]
    outputs.each { |p| file(p + '/artifact') }
    file('ohos/entry/libs/flutter.har')
    output, status = run_clean('--yes', '', File.join(@root, 'ohos'))
    assert status.success?, output
    assert_includes output, '工程类型：OpenHarmony'
    assert File.exist?(File.join(@root, 'build/ohos/artifact'))
    assert File.exist?(File.join(@root, '.dart_tool/artifact'))
    outputs.each { |p| file(p + '/artifact') }
    output, status = run_clean
    assert status.success?, output
    assert_includes output, '工程类型：Flutter'
    outputs.each { |p| refute File.exist?(File.join(@root, p)), p }
    assert File.exist?(File.join(@root, 'ohos/entry/libs/flutter.har'))
  end

  def test_harmony_module_can_be_selected_and_invalid_or_linked_ohos_is_preserved
    harmony
    file('entry/build/artifact')
    file('features/chat/build/keep')
    output, status = run_clean('--yes', '', File.join(@root, 'entry'))
    assert status.success?, output
    assert_includes output, '工程类型：OpenHarmony'
    assert File.exist?(File.join(@root, 'features/chat/build/keep'))
    flutter
    file('ohos/build/keep')
    output, status = run_clean
    assert status.success?, output
    assert File.exist?(File.join(@root, 'ohos/build/keep'))
    FileUtils.rm_r(File.join(@root, 'ohos'))
    outside = File.join(@temporary, 'native-outside')
    FileUtils.mkdir_p(outside)
    File.symlink(outside, File.join(@root, 'ohos'))
    output, status = run_clean
    assert status.success?, output
    assert File.symlink?(File.join(@root, 'ohos'))
  end

  def test_harmony_incomplete_markers_and_module_output_links_are_safe
    harmony
    file('build/keep')
    FileUtils.rm_f(File.join(@root, 'AppScope/app.json5'))
    output, status = run_clean
    refute status.success?, output
    assert File.exist?(File.join(@root, 'build/keep'))
    harmony
    outside = File.join(@temporary, 'outside')
    FileUtils.mkdir_p(outside)
    File.write(File.join(outside, 'keep'), 'safe')
    File.symlink(outside, File.join(@root, 'entry/build'))
    output, status = run_clean
    refute status.success?, output
    assert File.exist?(File.join(@root, 'build/keep'))
    assert File.exist?(File.join(outside, 'keep'))
  end

  def test_flutter_has_priority_and_cleans_only_recognized_platforms
    flutter
    android('android')
    ios('ios')
    outputs = %w[build .dart_tool android/build android/.gradle android/app/build android/feature/chat/build android/app/.cxx ios/build ios/DerivedData ios/Flutter/ephemeral windows/flutter/ephemeral]
    outputs.each { |p| file(p + '/artifact') }
    preserved = %w[pubspec.lock ios/Podfile.lock ios/Pods/source ios/Flutter/Generated.xcconfig android/local.properties unknown/build/user.txt]
    preserved.each { |p| file(p) }
    output, status = run_clean
    assert status.success?, output
    assert_includes output, '工程类型：Flutter'
    outputs.each { |p| refute File.exist?(File.join(@root, p)), p }
    preserved.each { |p| assert File.exist?(File.join(@root, p)), p }
    assert File.exist?(File.join(@root, 'lib/main.dart'))
    refute File.exist?(File.join(@root, 'SHOULD_NOT_EXIST'))
  end

  def test_android_kotlin_multimodule_and_nested_project_boundary
    android
    outputs = %w[build .gradle .kotlin app/build feature/chat/build feature/chat/.externalNativeBuild]
    outputs.each { |p| file(p + '/artifact') }
    file('independent/settings.gradle', 'include(":app")')
    file('independent/build.gradle', 'plugins { id("com.android.application") }')
    file('independent/build/keep')
    file('gradle/wrapper/gradle-wrapper.properties')
    output, status = run_clean
    assert status.success?, output
    assert_includes output, '工程类型：Android'
    outputs.each { |p| refute File.exist?(File.join(@root, p)), p }
    assert File.exist?(File.join(@root, 'independent/build/keep'))
    assert File.exist?(File.join(@root, 'gradle/wrapper/gradle-wrapper.properties'))
  end

  def test_flutter_android_openharmony_scope_preserves_ios_desktop_and_shared_artifacts
    flutter
    android('android')
    harmony('ohos')
    ios('ios')
    outputs = %w[android/build android/.gradle android/.kotlin android/app/build android/feature/chat/.cxx build/app build/ohos ohos/build ohos/.hvigor ohos/entry/build]
    preserved = %w[build/ios/artifact build/windows/artifact build/shared/artifact .dart_tool/artifact ios/build/artifact ios/DerivedData/artifact ios/Flutter/ephemeral/artifact windows/flutter/ephemeral/artifact pubspec.lock ohos/entry/libs/flutter.har]
    outputs.each { |path| file(path + '/artifact') }
    preserved.each { |path| file(path) }

    output, status = run_clean('--dry-run', '', @root, '--android-openharmony')
    assert status.success?, output
    assert_includes output, '清理范围：Android / OpenHarmony'
    outputs.each { |path| assert File.exist?(File.join(@root, path)), path }
    output, status = run_clean(nil, "CLEAN\n", @root, '--android-openharmony')
    assert status.success?, output
    outputs.each { |path| refute File.exist?(File.join(@root, path)), path }
    preserved.each { |path| assert File.exist?(File.join(@root, path)), path }
  end

  def test_flutter_android_openharmony_scope_is_empty_without_recognized_platforms
    flutter
    %w[build/app/keep build/ohos/keep android/build/keep ohos/build/keep .dart_tool/keep].each { |path| file(path) }
    output, status = run_clean('--yes', '', @root, '--android-openharmony')
    assert status.success?, output
    assert_includes output, '没有可清理'
    assert File.exist?(File.join(@root, 'build/app/keep'))
    assert File.exist?(File.join(@root, 'ohos/build/keep'))
    assert File.exist?(File.join(@root, '.dart_tool/keep'))
  end

  def test_android_openharmony_scope_rejects_native_ios_and_unknown_flags_before_deleting
    ios
    file('build/keep')
    [['--yes', '--android-openharmony'], ['--yes', '--unknown'], ['--yes', '--dry-run']].each do |arguments|
      output, status = Open3.capture2e({ 'HOME' => @home }, '/bin/zsh', SCRIPT, @root, *arguments)
      refute status.success?, output
      assert File.exist?(File.join(@root, 'build/keep'))
    end
  end

  def test_android_version_catalog_project_uses_manifest_evidence
    file('settings.gradle.kts')
    file('app/build.gradle.kts', 'plugins { alias(libs.plugins.android.application) }')
    file('app/src/main/AndroidManifest.xml', '<manifest/>')
    file('app/build/artifact')
    output, status = run_clean
    assert status.success?, output
    refute File.exist?(File.join(@root, 'app/build'))
  end

  def test_ios_preserves_pods_locks_and_global_cache
    ios
    file('build/artifact')
    file('DerivedData/artifact')
    file('Pods/source')
    file('Podfile.lock')
    global = File.join(@home, 'Library/Developer/Xcode/DerivedData/Other/Build/keep')
    FileUtils.mkdir_p(File.dirname(global))
    File.write(global, 'other project')
    output, status = run_clean
    assert status.success?, output
    assert_includes output, '工程类型：iOS'
    refute File.exist?(File.join(@root, 'build'))
    refute File.exist?(File.join(@root, 'DerivedData'))
    %w[Pods/source Podfile.lock Demo.xcodeproj/project.pbxproj].each { |p| assert File.exist?(File.join(@root, p)) }
    assert File.exist?(global)
  end

  def test_only_owned_xcode_derived_data_build_is_deleted
    ios
    own = File.join(@home, 'Library/Developer/Xcode/DerivedData/Demo-123')
    FileUtils.mkdir_p([File.join(own, 'Build'), File.join(own, 'SourcePackages')])
    File.write(File.join(own, 'Build/artifact'), 'generated')
    File.write(File.join(own, 'SourcePackages/keep'), 'dependency')
    # Generate a real plist without interpolating path text into XML.
    output, status = Open3.capture2e('/usr/bin/plutil', '-create', 'xml1', File.join(own, 'info.plist'))
    assert status.success?, output
    output, status = Open3.capture2e('/usr/bin/plutil', '-insert', 'WorkspacePath', '-string', File.join(@root, 'Demo.xcodeproj'), File.join(own, 'info.plist'))
    assert status.success?, output
    output, status = run_clean
    assert status.success?, output
    refute File.exist?(File.join(own, 'Build'))
    assert File.exist?(File.join(own, 'SourcePackages/keep'))
    assert File.exist?(File.join(own, 'info.plist'))
  end

  def test_unknown_java_gradle_and_macos_are_rejected_without_deleting
    file('build/keep')
    [nil, ['build.gradle', 'plugins { id("java") }'], ['Mac.xcodeproj/project.pbxproj', 'SDKROOT = macosx;']].each do |fixture|
      file(*fixture) if fixture
      output, status = run_clean
      refute status.success?, output
      assert File.exist?(File.join(@root, 'build/keep'))
    end
  end

  def test_no_ancestor_or_child_project_search
    flutter
    file('build/keep')
    file('lib/build/keep')
    output, status = run_clean('--yes', '', File.join(@root, 'lib'))
    refute status.success?, output
    assert File.exist?(File.join(@root, 'lib/build/keep'))
    output, status = run_clean('--yes', '', @temporary)
    refute status.success?, output
    assert File.exist?(File.join(@root, 'build/keep'))
  end

  def test_preview_cancel_eof_and_idempotence
    flutter
    file('build/artifact')
    [['--dry-run', ''], [nil, "no\n"], [nil, '']].each do |mode, input|
      run_clean(mode, input)
      assert File.exist?(File.join(@root, 'build/artifact'))
    end
    output, status = run_clean(nil, "CLEAN\n")
    assert status.success?, output
    refute File.exist?(File.join(@root, 'build'))
    output, status = run_clean
    assert status.success?, output
    assert_includes output, '没有可清理'
  end

  def test_link_target_rejected_before_any_deletion_and_internal_link_never_followed
    flutter
    outside = File.join(@temporary, 'outside')
    FileUtils.mkdir_p(outside)
    File.write(File.join(outside, 'keep'), 'safe')
    file('build/artifact')
    File.symlink(outside, File.join(@root, '.dart_tool'))
    output, status = run_clean
    refute status.success?, output
    assert File.exist?(File.join(@root, 'build/artifact'))
    File.unlink(File.join(@root, '.dart_tool'))
    File.symlink(outside, File.join(@root, 'build/link'))
    output, status = run_clean
    assert status.success?, output
    assert File.exist?(File.join(outside, 'keep'))
    refute File.exist?(File.join(@root, 'build'))
  end

  def test_file_named_build_is_never_deleted
    flutter
    file('build', 'user file')
    output, status = run_clean
    refute status.success?, output
    assert_equal 'user file', File.read(File.join(@root, 'build'))
  end
end
