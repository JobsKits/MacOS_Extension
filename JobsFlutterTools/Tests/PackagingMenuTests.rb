# frozen_string_literal: true
# 复用打包隔离夹具；同时回归旧 CLI 与统一菜单内的 FVM worker。
require_relative '../../JobsFlutterPackager/Tests/PackagingShellTests'

class PackagingShellTests
  def each_menu_worker
    original = @source
    [SCRIPT, File.expand_path('../Scripts/Tools/PackageFlutter.zsh', __dir__)].each do |worker|
      @source = File.read(worker).sub(/^main "\$@"\s*\z/, '')
      File.write(@library, @source)
      yield worker
    end
  ensure
    @source = original
    File.write(@library, original)
  end

  def test_menu_platform_builds_only_selected_platform_using_project_fvm
    prepare_ohos
    write_mock(File.join(@project, '.fvm/flutter_sdk/bin/flutter'), File.read(File.join(@bin, 'flutter')))
    write_mock('flutter', 'exit 97') # 禁止悄悄调用全局 SDK。
    each_menu_worker do |worker|
      { 'ios' => 'ipa', 'android' => 'apk', 'ohos' => 'hap' }.each do |platform, target|
        FileUtils.rm_f([@environment['FP_TEST_ARGS'], @environment['FP_TEST_TRACE']])
        # iOS 即使 fzf 损坏也可构建；其他平台仍选择产物，但不能选择平台。
        env = { 'FP_TEST_PLATFORM' => 'invalid-platform', 'FP_TEST_FZF_BROKEN' => platform == 'ios' ? '1' : '0' }
        out, status = interactive('--project', @project, '--platform', platform, env: env)
        assert status.success?, worker + out
        assert_equal [%w[pub get], ['build', target, '--release']], flutter_calls.reject { |call| call == ['--version'] || call.include?('--help') }
        trace = File.exist?(@environment['FP_TEST_TRACE']) ? File.read(@environment['FP_TEST_TRACE']) : ''
        refute_includes trace, '--prompt=打包平台'
        assert_equal platform == 'ios' ? 0 : 1, trace.scan('fzf|').length
        refute File.exist?(File.join(@root, 'INJECTED'))
        refute File.exist?(File.join(@root, 'BACKTICK'))
      end
    end
  end

  def test_menu_explicit_targets_do_not_require_fzf
    each_menu_worker do |worker|
      [%w[ios], %w[android --target all], %w[ohos --ohos-target all]].each do |args|
        out, err, status = shell("fp_parse --platform #{args.shelljoin} && fp_select_platform", env: { 'FP_TEST_FZF_BROKEN' => '1' })
        assert status.success?, worker + out + err
        refute File.exist?(@environment['FP_TEST_TRACE'])
      end
    end
  end

  def test_menu_invalid_missing_or_duplicate_platform_is_rejected
    each_menu_worker do |worker|
      [%w[--platform macos], %w[--platform IOS], %w[--platform], %w[--platform ios --platform android]].each do |args|
        out, err, status = shell("fp_parse #{args.shelljoin}")
        assert_equal 2, status.exitstatus, worker + out + err
        assert_empty flutter_calls
        assert_empty Dir.children(@run)
      end
    end
  end

  def test_menu_cancel_artifact_selection_does_not_build
    each_menu_worker do |worker|
      %w[android ohos].each do |platform|
        out, status = interactive('--project', @project, '--platform', platform, env: { 'FP_TEST_FZF_TARGET_EXIT' => '130' })
        assert status.success?, worker + out
        assert_includes out, '已取消平台 / 产物选择'
        assert_empty flutter_calls
      end
    end
  end

  def test_menu_dispatch_passes_platform_and_literal_path
    tools = File.join(@root, 'tools')
    FileUtils.mkdir_p([tools, File.join(@project, 'lib')])
    File.write(File.join(@project, '.fvmrc'), '{"flutter":"fixture"}')
    write_mock(File.join(@project, '.fvm/flutter_sdk/bin/flutter'), 'exit 97')
    write_mock(File.join(@project, '.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart'), 'exit 97')
    FileUtils.cp(File.expand_path('../Scripts/Tools/DispatchFlutterTools.zsh', __dir__), tools)
    write_mock(File.join(tools, 'PackageFlutter.zsh'), 'printf "%s\\0" "$@" > "$FP_TEST_ARGS"; exit 19')
    %w[ios android ohos].each do |platform|
      out, err, status = Open3.capture3(@environment, '/bin/zsh', File.join(tools, 'DispatchFlutterTools.zsh'), "package-#{platform}", @project)
      assert_equal 19, status.exitstatus, out + err
      assert_equal ['--project', @project, '--platform', platform], File.binread(@environment['FP_TEST_ARGS']).force_encoding('UTF-8').split("\0")
    end
  end
end
