# frozen_string_literal: true
# Created by Jobs on 2026年10月28日，星期三。
# 使用真实分发器、完整 wrapper 和原生 Dart 验证导出到导入全链路；只操作临时夹具。
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'shellwords'
require 'find'
require 'uri'
require 'timeout'

class DependencyImportEndToEndTests < Minitest::Test
  TOOLS = File.expand_path(ENV.fetch('JOBS_TEST_TOOLS_DIR', '../Scripts/Tools'), __dir__)
  DISPATCHER = File.join(TOOLS, 'DispatchFlutterTools.zsh')
  EXPORTER = File.join(TOOLS, 'ExtractFlutterDependencies.dart')
  PUBSPEC = <<~YAML.freeze
    name: demo_project
    dependencies:
      flutter:
        sdk: flutter
      alpha: ^1.0.0
  YAML
  ORIGINAL_OVERRIDES = "\uFEFF# 保留原配置\r\ndependency_overrides:\r\n    another: ^2.0.0 # 原注释\r\nresolution: null\r\n".freeze

  def setup
    skip '此测试需要 macOS 原生 Dart' unless RUBY_PLATFORM.include?('darwin')
    candidate = ENV['JOBS_TEST_DART'] || ENV.fetch('PATH', '').split(File::PATH_SEPARATOR)
                                             .map { |entry| File.join(entry, 'dart') }
                                             .find { |path| File.file?(path) && File.executable?(path) }
    skip '未安装可执行的 Dart；请先安装 SDK 或设置 JOBS_TEST_DART' unless candidate
    resolved = File.realpath(candidate)
    sdk_binary = File.join(File.dirname(resolved), 'cache', 'dart-sdk', 'bin', 'dart')
    @dart = File.file?(sdk_binary) ? File.realpath(sdk_binary) : resolved
    kind, kind_status = Open3.capture2e('/usr/bin/file', '-b', @dart)
    assert kind_status.success? && kind.include?('Mach-O'), "需要真实原生 Dart 二进制：#{kind}"
    @root = Dir.mktmpdir('JobsFlutter 导入端到端 ')
    @source = File.join(@root, '来源 Flutter 工程')
    @target = File.join(@root, '目标 Flutter 无 lib 工程')
    @logs = File.join(@root, '临时日志')
    @home = File.join(@root, '测试 HOME')
    @pub_cache = File.join(@root, '空 Pub Cache')
    @flutter_marker = File.join(@root, '不应调用 Flutter')
    FileUtils.mkdir_p([@source, @target, @logs, @home, @pub_cache])
    @environment = {
      'HOME' => @home,
      'TMPDIR' => @logs + '/',
      'PUB_CACHE' => @pub_cache,
      'DART_SUPPRESS_ANALYTICS' => 'true',
      'CI' => 'true',
      'NO_COLOR' => '1',
      'TERM' => 'dumb',
      'JOBS_E2E_FLUTTER_MARKER' => @flutter_marker
    }
    install_fvm_fixture
    prepare_real_export
    File.binwrite(File.join(@target, 'pubspec.yaml'), PUBSPEC)
    File.binwrite(File.join(@target, 'pubspec.lock'), "# 原锁文件逐字保留\n")
    File.binwrite(File.join(@target, 'pubspec_overrides.yaml'), ORIGINAL_OVERRIDES)
    @target_before = snapshot_tree(@target)
    @source_before = snapshot_tree(@source)
    @snapshot_before = snapshot_tree(@snapshot)
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  # Dart 指向现有原生二进制；Flutter 只满足分发器门禁，任何调用都会留下失败标记。
  def install_fvm_fixture
    sdk = File.join(@target, '.fvm', 'flutter_sdk')
    dart_bin = File.join(sdk, 'bin', 'cache', 'dart-sdk', 'bin')
    FileUtils.mkdir_p(dart_bin)
    File.symlink(@dart, File.join(dart_bin, 'dart'))
    flutter = File.join(sdk, 'bin', 'flutter')
    File.write(flutter, <<~'ZSH')
      #!/bin/zsh
      print -r -- "$*" >> "$JOBS_E2E_FLUTTER_MARKER"
      exit 97
    ZSH
    File.chmod(0o755, flutter)
    File.write(File.join(@target, '.fvmrc'), JSON.generate('flutter' => 'test-native-dart'))
  end

  # 用生产 exporter 实际生成 alpha→beta 快照，而非手写 manifest 冒充产物。
  def prepare_real_export
    File.write(File.join(@source, 'pubspec.yaml'), PUBSPEC)
    roots = {}
    %w[alpha beta flutter].each do |name|
      package = File.join(@root, '来源 Pub 缓存', name)
      FileUtils.mkdir_p(File.join(package, 'lib'))
      manifest = "name: #{name}\nversion: 1.0.0\n"
      manifest += "dependencies:\n  beta: ^1.0.0\n" if name == 'alpha'
      File.write(File.join(package, 'pubspec.yaml'), manifest)
      File.binwrite(File.join(package, 'lib', "#{name}.dart"), "// #{name} 原始第三方源码\n")
      File.binwrite(File.join(package, 'LICENSE'), "#{name} 原有许可证\n")
      roots[name] = file_uri(package)
    end
    lock = "packages:\n"
    roots.each_key do |name|
      lock += "  #{name}:\n    version: \"1.0.0\"\n    source: #{name == 'flutter' ? 'sdk' : 'hosted'}\n"
    end
    File.write(File.join(@source, 'pubspec.lock'), lock)
    FileUtils.mkdir_p(File.join(@source, '.dart_tool'))
    packages = [{ 'name' => 'demo_project', 'rootUri' => file_uri(@source) }]
    roots.each { |name, uri| packages << { 'name' => name, 'rootUri' => uri } }
    File.write(File.join(@source, '.dart_tool', 'package_config.json'),
               JSON.generate('configVersion' => 2, 'packages' => packages))
    output_root = File.join(@root, '导出 快照目录')
    output, status = capture(@dart, EXPORTER, '--project', @source, '--destination', output_root)
    assert status.success?, "真实 exporter 失败：#{output}"
    directories = Dir.children(output_root).map { |name| File.join(output_root, name) }
                     .select { |path| File.directory?(path) }
    assert_equal 1, directories.length, output
    @snapshot = directories.first
    manifest = JSON.parse(File.read(File.join(@snapshot, 'manifest.json')))
    assert_equal 'complete', manifest['status']
    assert_equal %w[alpha beta], manifest['packages'].map { |entry| entry['name'] }.sort
  end

  def file_uri(path)
    URI::DEFAULT_PARSER.escape("file://#{path}/")
  end

  # 整个进程执行生产脚本；不 source、删 main、替换 wrapper 或拦截 Dart 业务。
  def capture(*command, input: '')
    Timeout.timeout(30) do
      Open3.capture2e(@environment, *command, stdin_data: input)
    end
  end

  def dispatch(input)
    capture('/bin/zsh', DISPATCHER, 'import-dependencies', @target, input: input)
  end

  # 同时记录目录、链接、文件内容和模式，取消必须连额外项目目录也没有。
  def snapshot_tree(root)
    result = {}
    Find.find(root) do |path|
      next if path == root
      relative = path.delete_prefix(root + '/')
      stat = File.lstat(path)
      result[relative] = if stat.symlink?
                           ['link', File.readlink(path)]
                         elsif stat.directory?
                           ['directory', stat.mode & 0o777]
                         else
                           ['file', stat.mode & 0o777, File.binread(path)]
                         end
    end
    result
  end

  def assert_sources_unchanged
    assert_equal @source_before, snapshot_tree(@source), '来源工程被导入过程改写'
    assert_equal @snapshot_before, snapshot_tree(@snapshot), '导出快照被导入过程改写'
  end

  # wrapper 的私有 umask 会收紧新建目录权限；源码文件及其模式仍须逐字保留。
  def copied_source_tree(root)
    snapshot_tree(root).transform_values do |entry|
      entry.first == 'directory' ? ['directory'] : entry
    end
  end

  def assert_no_flutter_or_pub_get
    refute File.exist?(@flutter_marker), '导入不应调用 Flutter，包括 flutter pub get'
    assert_empty Dir.children(@pub_cache), '导入不应通过 Pub 下载依赖或填充缓存'
    refute File.directory?(File.join(@target, '.dart_tool')), '不应自动解析目标依赖'
  end

  def test_dispatcher_imports_real_snapshot_with_native_dart_and_no_lib_target
    refute File.exist?(File.join(@target, 'lib')), '夹具必须能复现没有 lib 的有效项目'
    output, status = dispatch("\n\n\n\n#{Shellwords.escape(@snapshot)}\u00a0\nYES\n")
    assert status.success?, output
    assert_equal 3, output.scan('尚未输入依赖目录').length, output
    assert_includes output, '导入 Flutter 第三方依赖'
    assert_includes output, '✔ 项目 FVM Dart：'
    assert_equal 2, output.scan('✔ 已识别完整 Flutter 依赖快照').length, output
    assert_includes output, '✔ 导入完成'
    refute_includes output, "\e["
    imports = Dir.glob(File.join(@target, 'vendor', 'flutter_dependencies', 'import-*'))
    assert_equal 1, imports.length, output
    run_directory = imports.first
    assert_equal ORIGINAL_OVERRIDES.b, File.binread(File.join(run_directory, 'pubspec_overrides.yaml.before-import'))
    receipt = JSON.parse(File.read(File.join(run_directory, 'import.json')))
    assert_equal %w[alpha beta], receipt['packages'].keys.sort
    overrides = File.binread(File.join(@target, 'pubspec_overrides.yaml'))
    assert overrides.start_with?("\xEF\xBB\xBF".b), '配置 BOM 丢失'
    assert_includes overrides, "    another: ^2.0.0 # 原注释\r\n".b
    receipt['packages'].each do |name, relative_path|
      assert_includes overrides, "    #{name}:\r\n      path: #{JSON.generate(relative_path)}\r\n".b
      copied = File.join(@target, relative_path)
      assert_equal copied_source_tree(File.join(@snapshot, 'packages', name)), copied_source_tree(copied)
    end
    @target_before.each do |relative_path, before|
      next if relative_path == 'pubspec_overrides.yaml'
      assert_equal before, snapshot_tree(@target)[relative_path], "已有文件或链接被改写：#{relative_path}"
    end
    refute File.exist?(File.join(run_directory, '.incomplete'))
    refute File.exist?(File.join(@target, 'lib')), '导入不应为了通过门禁创建 lib'
    assert_sources_unchanged
    assert_no_flutter_or_pub_get
  end

  def test_invalid_complete_looking_snapshot_fails_before_confirmation_and_project_writes
    invalid = File.join(@root, '无效 依赖快照')
    FileUtils.cp_r(@snapshot, invalid)
    manifest_path = File.join(invalid, 'manifest.json')
    manifest = JSON.parse(File.read(manifest_path))
    manifest['packages'].first['fileCount'] += 1
    File.write(manifest_path, JSON.generate(manifest))
    output, status = dispatch("\n#{Shellwords.escape(invalid)} \nYES\n")
    refute status.success?, output
    assert_includes output, '快照文件数量不符'
    refute_includes output, '校验通过，输入 YES'
    refute_includes output, '✔ 导入完成'
    assert_equal @target_before, snapshot_tree(@target), '校验失败后项目产生写入'
    assert_sources_unchanged
    assert_no_flutter_or_pub_get
  end

  def test_cancel_after_real_native_dart_validation_has_zero_project_writes
    output, status = dispatch("\n#{Shellwords.escape(@snapshot)} \nNO\n")
    assert status.success?, output
    assert_includes output, '✔ 已识别完整 Flutter 依赖快照'
    assert_includes output, '已取消，项目未写入'
    refute_includes output, '✔ 导入完成'
    assert_equal @target_before, snapshot_tree(@target), '取消后项目产生写入'
    assert_sources_unchanged
    assert_no_flutter_or_pub_get
  end

  def test_intro_cancel_does_not_create_import_log_or_project_files
    logs_before = snapshot_tree(@logs)
    output, status = dispatch("NO\n")
    assert status.success?, output
    assert_includes output, '导入 Flutter 第三方依赖'
    refute_includes output, '日志：'
    assert_equal logs_before, snapshot_tree(@logs), '初始取消仍创建了日志'
    assert_equal @target_before, snapshot_tree(@target), '初始取消后项目产生写入'
    assert_sources_unchanged
    assert_no_flutter_or_pub_get
  end

  def test_non_snapshot_folder_reprompts_then_empty_input_cancels_without_project_writes
    ordinary = File.join(@root, '普通 无依赖目录')
    FileUtils.mkdir_p(ordinary)
    output, status = dispatch("\n#{Shellwords.escape(ordinary)} \n\n")
    assert status.success?, output
    assert_includes output, '不是依赖导出目录'
    refute_includes output, '✔ 项目 FVM Dart：'
    refute_includes output, '✔ 导入完成'
    assert_equal @target_before, snapshot_tree(@target), '无效目录取消后项目产生写入'
    assert_sources_unchanged
    assert_no_flutter_or_pub_get
  end
end
