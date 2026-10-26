# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'json'
require 'digest'

class IOSToolsTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  TOOLS = File.join(ROOT, 'Scripts', 'Tools')
  MANIFEST = JSON.parse(File.read(File.join(TOOLS, 'SourceManifest.json')))
  INSTALL = File.join(ROOT, '【MacOS】安装iOS辅助工具Finder扩展.command')
  UNINSTALL = File.join(ROOT, '【MacOS】卸载iOS辅助工具Finder扩展.command')

  def test_shell_syntax_and_source_provenance
    Dir.glob(File.join(ROOT, '**', '*')).select { |p| p.end_with?('.command', '.zsh') }.each do |path|
      out, status = Open3.capture2e('/bin/zsh', '-n', path)
      assert status.success?, "#{path}: #{out}"
    end
    assert_operator MANIFEST.size, :>=, 9
    MANIFEST.each do |row|
      assert_equal row['bundledSHA256'], Digest::SHA256.file(File.join(TOOLS, row['file'])).hexdigest
      original = File.expand_path("../../../../JobsCommand@iOS/#{row['source']}", __dir__)
      assert_equal row['sourceSHA256'], Digest::SHA256.file(original).hexdigest if File.file?(original)
    end
  end

  def test_all_nine_read_only_routes_and_podspec_gate
    Dir.mktmpdir('JobsIOSRoute') do |root|
      project = File.join(root, "中文 ' $() `x`\n工程")
      FileUtils.mkdir_p(project)
      File.write(File.join(project, 'Podfile'), '')
      MANIFEST.each do |row|
        out, status = Open3.capture2e('/bin/zsh', File.join(TOOLS, 'DispatchIOSTools.zsh'), '--plan', row['feature'], project)
        assert_equal row['feature'] != 'ios-pod-build-check', status.success?, out
        assert_includes out, '只读计划通过' if status.success?
      end
      nested = File.join(project, 'Nested')
      FileUtils.mkdir_p(nested)
      File.write(File.join(nested, 'Nested.podspec'), '')
      _, status = Open3.capture2e('/bin/zsh', File.join(TOOLS, 'DispatchIOSTools.zsh'), '--plan', 'ios-pod-build-check', project)
      refute status.success?
      File.write(File.join(project, 'Current.podspec'), '')
      out, status = Open3.capture2e('/bin/zsh', File.join(TOOLS, 'DispatchIOSTools.zsh'), '--plan', 'ios-pod-build-check', project)
      assert status.success?, out
      assert_includes out, '只读计划通过'
      assert_equal %w[Current.podspec Nested Podfile], Dir.children(project).sort
      _, status = Open3.capture2e('/bin/zsh', File.join(TOOLS, 'DispatchIOSTools.zsh'), '--plan', 'unknown', project)
      refute status.success?
      _, status = Open3.capture2e('/bin/zsh', File.join(TOOLS, 'DispatchIOSTools.zsh'), '--plan', 'ios-clean-cache', root)
      refute status.success?
    end
  end

  def test_build_cleanup_reuses_canonical_script_and_checks_native_ios_only
    canonical = File.expand_path('../../JobsTerminalOpener/Scripts/CleanBuildArtifacts.zsh', __dir__)
    assert_equal File.binread(canonical), File.binread(File.join(TOOLS, 'CleanBuildArtifacts.zsh'))
    validator = File.expand_path('../../JobsTerminalOpener/JobsTerminalShared/DependencyProjectValidator.swift', __dir__)
    assert_equal File.binread(validator), File.binread(File.join(ROOT, 'JobsIOSToolsShared/DependencyProjectValidator.swift'))
    Dir.mktmpdir('JobsIOSCleanRoute') do |root|
      project = File.join(root, "中文 ' $() `x`\n工程")
      xcode = File.join(project, 'App.xcodeproj')
      FileUtils.mkdir_p(xcode)
      File.write(File.join(xcode, 'project.pbxproj'), 'SDKROOT = iphoneos;')
      FileUtils.mkdir_p(File.join(project, 'build'))
      File.write(File.join(project, 'build', 'keep-until-confirmed'), 'intact')
      out, status = Open3.capture2e('/bin/zsh', File.join(TOOLS, 'DispatchIOSTools.zsh'), '--plan', 'ios-clean-build-artifacts', project)
      assert status.success?, out
      assert File.file?(File.join(project, 'build', 'keep-until-confirmed'))
      out, status = Open3.capture2e('/bin/zsh', File.join(TOOLS, 'DispatchIOSTools.zsh'), '--plan', 'ios-clean-cache', project)
      assert status.success?, out
      assert_includes out, '动作：ios-clean-build-artifacts'
      assert_includes out, 'CleanBuildArtifacts.zsh'
      refute File.exist?(File.join(TOOLS, '【MacOS】🧹双击清理iOS缓存.command'))
      File.write(File.join(project, 'pubspec.yaml'), "dependencies: {flutter: {sdk: flutter}}\n")
      out, status = Open3.capture2e('/bin/zsh', File.join(TOOLS, 'DispatchIOSTools.zsh'), '--plan', 'ios-clean-build-artifacts', project)
      refute status.success?, out
      assert File.file?(File.join(project, 'build', 'keep-until-confirmed'))
      File.delete(File.join(project, 'pubspec.yaml'))
      File.write(File.join(xcode, 'project.pbxproj'), 'SDKROOT = macosx;')
      out, status = Open3.capture2e('/bin/zsh', File.join(TOOLS, 'DispatchIOSTools.zsh'), '--plan', 'ios-clean-build-artifacts', project)
      refute status.success?, out
      assert File.file?(File.join(project, 'build', 'keep-until-confirmed'))
    end
  end

  def definitions(path)
    File.read(path).sub(/\nmain "\$@"\s*\z/, "\n")
  end

  def run_fixture(source, body)
    Dir.mktmpdir('JobsIOSFeatures') do |root|
      config = File.join(root, 'EnabledFeatures.txt')
      script = File.join(root, 'fixture.zsh')
      File.write(script, definitions(source) + "\nFEATURE_CONFIG=#{config.dump}\nlog() { print -r -- \"$*\"; }\n" + body)
      out, status = Open3.capture2e('/bin/zsh', '-f', script)
      assert status.success?, out
      yield config, out
    end
  end

  def test_subset_install_is_union_and_partial_uninstall_keeps_other_actions
    run_fixture(INSTALL, <<~ZSH) do |config, _out|
      parse_feature_options --features ios-clean-cache,ios-pod-build-check
      persist_feature_selection
      parse_feature_options --features=ios-pod-update
      persist_feature_selection
    ZSH
      assert_equal 'ios-pod-update,ios-pod-build-check,ios-clean-build-artifacts', File.read(config).strip
    end
    run_fixture(UNINSTALL, <<~ZSH) do |config, out|
      print -r -- 'ios-clean-cache,ios-pod-update' > "$FEATURE_CONFIG"
      parse_feature_options --features ios-clean-cache
      plan_feature_removal
      uninstall_extension
    ZSH
      assert_equal 'ios-pod-update', File.read(config).strip
      assert_includes out, '仅关闭所选功能'
    end
    run_fixture(UNINSTALL, <<~ZSH) do |_config, out|
      parse_feature_options --non-interactive
      plan_feature_removal
      (( ${#REMAINING_FEATURES[@]} == 0 )) || exit 1
    ZSH
      assert_includes out, '关闭功能'
    end
  end

  def test_bad_feature_stops_before_mutation
    run_fixture(INSTALL, <<~ZSH) do |config, _out|
      ( parse_feature_options --features 'ios-clean-cache,unexpected' )
      (( $? != 0 )) || exit 1
    ZSH
      refute File.exist?(config)
    end
  end

  def test_existing_cache_selection_migrates_when_installing_or_removing_another_feature
    run_fixture(INSTALL, <<~ZSH) do |config, _out|
      print -r -- 'ios-clean-cache' > "$FEATURE_CONFIG"
      parse_feature_options --features ios-pod-update
      persist_feature_selection
    ZSH
      assert_equal 'ios-pod-update,ios-clean-build-artifacts', File.read(config).strip
    end
    run_fixture(UNINSTALL, <<~ZSH) do |config, _out|
      print -r -- 'ios-clean-cache,ios-pod-update' > "$FEATURE_CONFIG"
      parse_feature_options --features ios-pod-update
      plan_feature_removal
      uninstall_extension
    ZSH
      assert_equal 'ios-clean-build-artifacts', File.read(config).strip
    end
  end

  def test_podspec_gate_matches_hidden_files_and_rejects_directories_or_uppercase
    Dir.mktmpdir('JobsIOSPodGate') do |root|
      fixture = File.join(root, 'Project')
      FileUtils.mkdir_p(fixture)
      File.write(File.join(fixture, 'Podfile'), '')
      candidates = [['.Current.podspec', false, true], ['Current.podspec', false, true],
                    ['Directory.podspec', true, false], ['Upper.PODSPEC', false, false]]
      candidates.each do |name, directory, expected|
        path = File.join(fixture, name)
        directory ? FileUtils.mkdir_p(path) : File.write(path, '')
        out, status = Open3.capture2e('/bin/zsh', File.join(TOOLS, 'DispatchIOSTools.zsh'), '--plan', 'ios-pod-build-check', fixture)
        assert_equal expected, status.success?, "#{name}: #{out}"
        directory ? Dir.rmdir(path) : File.delete(path)
      end
      nested = File.join(fixture, 'Nested')
      FileUtils.mkdir_p(nested)
      File.write(File.join(nested, 'Current.podspec'), '')
      _, status = Open3.capture2e('/bin/zsh', File.join(TOOLS, 'DispatchIOSTools.zsh'), '--plan', 'ios-pod-build-check', fixture)
      refute status.success?
    end
  end

  def test_pod_target_and_sibling_dependency_paths_without_compiling
    row = MANIFEST.find { |entry| entry['feature'] == 'ios-pod-build-check' }
    Dir.mktmpdir('JobsIOSPodAdapter') do |root|
      target = File.join(root, '目标 Pod')
      sibling = File.join(root, 'Sibling')
      FileUtils.mkdir_p([target, sibling])
      File.write(File.join(target, 'Target.podspec'), "s.name = 'Target'\ns.dependency 'Sibling'\n")
      File.write(File.join(sibling, 'Sibling.podspec'), "s.name = 'Sibling'\n")
      fixture = File.join(root, 'adapter.zsh')
      File.write(fixture, definitions(File.join(TOOLS, row['file'])) + <<~ZSH)
        log() { :; }
        ask_for_workspace_root
        [[ "$WORKSPACE_ROOT" == "${JOBS_IOS_PROJECT_DIR:h}" ]] || exit 2
        ask_for_target_pod_name
        [[ "$TARGET_PODSPEC_PATH" == "$JOBS_IOS_PROJECT_DIR/Target.podspec" ]] || exit 3
        [[ "$TARGET_POD_NAME" == Target ]] || exit 4
        [[ "$(collect_smart_dependency_podspecs "$TARGET_PODSPEC_PATH")" == "$WORKSPACE_ROOT/Sibling/Sibling.podspec" ]] || exit 5
        [[ -z "$(find_x_command_candidates)" ]] || exit 6
      ZSH
      out, status = Open3.capture2e({ 'JOBS_IOS_PROJECT_DIR' => target }, '/bin/zsh', '-f', fixture)
      assert status.success?, "#{status.exitstatus}: #{out}"
      assert_equal ['Target.podspec'], Dir.children(target)
      assert_equal ['Sibling.podspec'], Dir.children(sibling)
    end
  end

  def test_swift_validator_request_and_shell_transport
    Dir.mktmpdir('JobsIOSSwift') do |root|
      binary = File.join(root, 'IOSToolsBehaviorTests')
      sources = [
        'JobsIOSToolsShared/IOSProjectValidator/IOSProjectValidator.swift',
        'JobsIOSToolsShared/DependencyProjectValidator.swift',
        'JobsIOSToolsShared/IOSToolsRequest/IOSToolsRequest.swift',
        'JobsIOSToolsShared/JobsIOSFactories.swift',
        'JobsIOSTools/IOSToolsLauncher/IOSToolsLauncher.swift',
        'Tests/IOSToolsBehaviorTests.swift'
      ].map { |p| File.join(ROOT, p) }
      out, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', *sources, '-o', binary)
      assert status.success?, out
      out, status = Open3.capture2e(binary)
      assert status.success?, out
      assert_includes out, 'checks passed'
    end
  end

  def test_real_app_delegate_deduplicates_both_system_callbacks
    Dir.mktmpdir('JobsIOSDelegate') do |root|
      binary = File.join(root, 'IOSToolsAppDelegateTests')
      sources = [
        'JobsIOSTools/AppDelegate.swift',
        'JobsIOSToolsShared/IOSToolsRequest/IOSToolsRequest.swift',
        'JobsIOSToolsShared/JobsIOSFactories.swift',
        'Tests/IOSToolsAppDelegateTests.swift'
      ].map { |p| File.join(ROOT, p) }
      out, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', *sources, '-o', binary)
      assert status.success?, out
      out, status = Open3.capture2e(binary)
      assert status.success?, out
      assert_includes out, 'URL 回调去重回归通过'
    end
  end
end
