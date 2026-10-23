# frozen_string_literal: true
# 复用原生管理器夹具，只替换包内 worker；验证受管 CPF 鸿蒙 SDK 能安全切回官方 SDK。
require_relative '../../JobsFlutterVersionMgr/Tests/FlutterVersionCommandTests'

class NativeFlutterReturnTests < FlutterVersionCommandTests
  WORKER = File.expand_path('../Scripts/Tools/ManageFlutterVersion.zsh', __dir__)

  def setup
    super
    @source = File.read(WORKER).sub(/^main "\$@"\s*\z/, '')
    @source = @source.gsub('/opt/homebrew', File.join(@root, 'system-arm')).gsub('/usr/local', File.join(@root, 'system-intel'))
  end

  def prepare_managed_harmony
    @cache = File.join(@root, 'native-cache', 'versions')
    @environment['TEST_CACHE'] = @cache
    @environment['TEST_NATIVE_ROOT'] = File.dirname(@cache)
    write_mock('git', '[[ "$1" == ls-remote && "$2" == --get-url ]] || exit 1; print -r -- "$3"')
    @bootstrap += "\nFM_GIT=\"$TEST_BIN/git\"\n"
    @oh_version = 'custom_jobs_ohos_' + ('a' * 40)
    @oh_root = File.join(@root, 'Library/Caches/JobsFlutter/fvm/harmony')
    @oh_sdk = File.join(@oh_root, 'versions', @oh_version)
    FileUtils.mkdir_p([@oh_sdk, @cache, File.join(@project, '.fvm')])
    File.symlink(@oh_sdk, File.join(@project, '.fvm/flutter_sdk'))
    @original = {
      'flutter' => @oh_version, 'flutterUrl' => 'https://gitcode.com/CPF-Flutter/flutter_flutter.git',
      'cachePath' => @oh_root, 'flavors' => { 'dev' => '3.29.3' }, 'customField' => { 'preserve' => true },
      'useGitCache' => false
    }
    File.write(File.join(@project, '.fvmrc'), JSON.generate(@original))
    add_cached_sdk('3.29.3')
    # 查询上下文只读解析临时 .fvmrc，模拟 FVM 的 cachePath -> versionsCachePath。
    fixture = File.read(File.join(@bin, 'fvm'))
    fixture = fixture.sub('api) [[ "$*" == *--help* ]] && exit 0; exit 1 ;;', <<~'ZSH'.strip)
      api)
        [[ "$*" == *--help* ]] && exit 0
        [[ "$2" == context ]] || exit 1
        /usr/bin/perl -MJSON::PP -0777 -e '$c=decode_json(<>); $r=$c->{cachePath}//$ENV{TEST_NATIVE_ROOT}; print encode_json({context=>{flutterUrl=>$c->{flutterUrl}//"https://github.com/flutter/flutter.git",versionsCachePath=>"$r/versions"}})' .fvmrc
        ;;
    ZSH
    fixture = fixture.sub('/bin/ln -s ', '/bin/ln -sfn ')
    File.write(File.join(@bin, 'fvm'), fixture)
  end

  def native_return_flow
    <<~'ZSH'
      cd -- "$FM_PROJECT" || exit 1
      fm_check_project_boundaries
      fm_prepare_inspection_config
      FM_CACHE_PATH=""
      fm_read_effective_context
      FM_SELECTED=3.29.3
      FM_SELECTED_ROW=$'3.29.3\tfixture\tstable'
      FM_CHANNEL=cached
      fm_prepare_project_config
      fm_apply_and_verify
    ZSH
  end

  def test_managed_harmony_shadow_uses_official_source_without_mutating_project
    prepare_managed_harmony
    before = File.binread(File.join(@project, '.fvmrc'))
    output, status = execute('fm_check_project_boundaries; fm_prepare_inspection_config; FM_CACHE_PATH=""; fm_read_effective_context')
    assert status.success?, output
    shadow = JSON.parse(File.read(File.join(@run, 'inspection/.fvmrc')))
    assert_equal 'https://github.com/flutter/flutter.git', shadow['flutterUrl']
    refute shadow.key?('cachePath')
    refute shadow.key?('flutter')
    assert_equal before, File.binread(File.join(@project, '.fvmrc'))
    assert_equal @oh_sdk, File.realpath(File.join(@project, '.fvm/flutter_sdk'))
    assert_includes output, '本菜单管理的 CPF 鸿蒙 SDK'
    assert_includes output, @cache
  end

  def test_managed_harmony_switches_back_to_native_and_preserves_custom_fields
    prepare_managed_harmony
    output, status = execute(native_return_flow, env: { 'TEST_FVM_REWRITES_CONFIG' => '1' })
    assert status.success?, output
    native = JSON.parse(File.read(File.join(@project, '.fvmrc')))
    assert_equal '3.29.3', native['flutter']
    assert_equal 'https://github.com/flutter/flutter.git', native['flutterUrl']
    assert_equal File.dirname(@cache), native['cachePath']
    assert_equal @original['customField'], native['customField']
    assert_equal @original['flavors'], native['flavors']
    assert_equal File.join(@cache, '3.29.3'), File.realpath(File.join(@project, '.fvm/flutter_sdk'))
    assert File.directory?(@oh_sdk)
  end

  def test_failed_native_use_restores_managed_harmony_config_and_original_link
    prepare_managed_harmony
    before = File.binread(File.join(@project, '.fvmrc'))
    output, status = execute(native_return_flow, env: { 'TEST_USE_FAIL' => '1' })
    assert_equal 31, status.exitstatus, output
    assert_equal before, File.binread(File.join(@project, '.fvmrc'))
    assert_equal @oh_sdk, File.realpath(File.join(@project, '.fvm/flutter_sdk'))
    assert_includes output, '还原为运行前'
  end

  def test_unknown_forks_and_uncontrolled_harmony_cache_are_rejected
    prepare_managed_harmony
    [{ 'flutterUrl' => 'https://example.invalid/unknown/flutter.git' },
     { 'cachePath' => File.join(@root, 'uncontrolled') },
     { 'flutter' => 'custom_not_jobs_ohos' }].each do |override|
      File.write(File.join(@project, '.fvmrc'), JSON.generate(@original.merge(override)))
      output, status = execute('fm_check_project_boundaries')
      refute status.success?, output
      assert_equal @original.merge(override), JSON.parse(File.read(File.join(@project, '.fvmrc')))
    end
  end

  def test_native_shadow_must_not_reuse_harmony_cache_from_process_configuration
    prepare_managed_harmony
    output, status = execute('fm_check_project_boundaries; fm_prepare_inspection_config; FM_CACHE_PATH=""; fm_read_effective_context',
                             env: { 'TEST_NATIVE_ROOT' => @oh_root })
    refute status.success?, output
    assert_includes output, '仍继承了鸿蒙专属缓存'
    assert_equal @original, JSON.parse(File.read(File.join(@project, '.fvmrc')))
  end
end
