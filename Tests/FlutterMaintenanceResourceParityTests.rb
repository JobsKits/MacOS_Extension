# frozen_string_literal: true
# 比较本机同级 SourceTree 标准源与可独立运行的打包副本；从不执行业务。

require 'minitest/autorun'

class FlutterMaintenanceResourceParityTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  SOURCES = {
    'JobsFlutterDoctor/Scripts/InspectFlutterProject.zsh' => '【MacOS@SourceTree】🐦Flutter项目体检.command/【MacOS@SourceTree】🐦Flutter项目体检.command',
    'JobsFlutterCodegen/Scripts/GenerateFlutterCode.zsh' => '【MacOS@SourceTree】🐦Flutter自动化生产代码.command/【MacOS@SourceTree】🐦Flutter自动化生产代码.command'
  }.freeze

  def test_packaged_resources_are_self_contained_copies_of_the_standard_source
    source_root = File.expand_path('../../SourceTree.command', ROOT)
    skip '独立工程不要求同级存在 SourceTree 标准源' unless File.directory?(source_root)
    SOURCES.each do |resource, source|
      source_path = File.join(source_root, source)
      assert File.file?(source_path), source_path
      assert_equal File.binread(source_path), File.binread(File.join(ROOT, resource)), resource
    end
  end
end
