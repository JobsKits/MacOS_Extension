# frozen_string_literal: true
# 比较 SourceTree 共用业务主体；仅终端 ANSI 过滤采用本仓流式适配，不执行业务。

require 'minitest/autorun'

class FlutterMaintenanceResourceParityTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  SOURCES = {
    'JobsFlutterDoctor/Scripts/InspectFlutterProject.zsh' => '【MacOS@SourceTree】🐦Flutter项目体检.command/【MacOS@SourceTree】🐦Flutter项目体检.command',
    'JobsFlutterCodegen/Scripts/GenerateFlutterCode.zsh' => '【MacOS@SourceTree】🐦Flutter自动化生产代码.command/【MacOS@SourceTree】🐦Flutter自动化生产代码.command'
  }.freeze
  AGGREGATED = {
    'JobsFlutterDoctor/Scripts/InspectFlutterProject.zsh' => 'JobsFlutterTools/Scripts/Tools/InspectFlutterProject.zsh',
    'JobsFlutterCodegen/Scripts/GenerateFlutterCode.zsh' => 'JobsFlutterTools/Scripts/Tools/GenerateFlutterCode.zsh'
  }.freeze
  FILTER_PATTERN = /^strip_ansi_text\(\) \{\n.*?^\}\n/m
  SDK_RETRY_PATTERN = /^# JOBS_SDK_RETRY_BEGIN\n(.*?)^# JOBS_SDK_RETRY_END\n\n/m

  def ansi_filter(source)
    matches = source.scan(FILTER_PATTERN)
    assert_equal 1, matches.length, '仅允许精确定位唯一 ANSI 过滤函数'
    matches.first
  end

  def test_independent_and_aggregated_stream_filters_are_identical
    AGGREGATED.each do |independent, aggregated|
      assert_equal ansi_filter(File.binread(File.join(ROOT, independent))),
                   ansi_filter(File.binread(File.join(ROOT, aggregated)))
    end
  end

  def test_packaged_resources_are_self_contained_copies_of_the_standard_source
    source_root = File.expand_path('../../SourceTree.command', ROOT)
    skip '独立工程不要求同级存在 SourceTree 标准源' unless File.directory?(source_root)
    source_root = File.join(source_root, 'MacOS') if File.directory?(File.join(source_root, 'MacOS'))
    SOURCES.each do |resource, source|
      source_path = File.join(source_root, source)
      assert File.file?(source_path), source_path
      upstream = File.binread(source_path)
      packaged = File.binread(File.join(ROOT, resource))
      # SDK前置仅属右键宿主适配；实际重试/取消由SdkAcquisitionRetryTests覆盖，主体仍严格比较。
      helper = File.binread(File.join(ROOT, 'JobsFlutterTools/Scripts/Tools/【MacOS】SDK获取重试.zsh/【MacOS】SDK获取重试.zsh'))
      expected_helper = helper[helper.index('# 只处理本轮子树'.b)..-1]
      blocks = packaged.scan(SDK_RETRY_PATTERN)
      assert_equal 1, blocks.length, resource
      assert_equal expected_helper, blocks.first.first, resource
      source_filter = ansi_filter(upstream)
      packaged_filter = ansi_filter(packaged)
      packaged = packaged.sub(SDK_RETRY_PATTERN, '')
      packaged = packaged.sub(/^  jobs_sdk_retry 'Flutter \/ Dart.*? run_flutter_step .*?--version \|\| return \$\?\n/, '')
      assert_equal upstream.sub(source_filter, '<local-streaming-ansi-filter>'),
                   packaged.sub(packaged_filter, '<local-streaming-ansi-filter>'), resource
    end
  end
end
