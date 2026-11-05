# Created by Jobs on 2026年11月4日，星期三。
# 隔离覆盖迁移范围、拖入路径、ZIP保留/删除、预检失败与写入确认，不读取真实缓存。
require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'shellwords'
require 'tmpdir'
require 'timeout'
require 'uri'

class FlutterDependencyMigrationShellTests < Minitest::Test
  TOOLS = File.expand_path('../../Scripts/Tools', __dir__)
  SCRIPT = File.join(TOOLS, '【MacOS】一键迁移Flutter依赖.zsh/【MacOS】一键迁移Flutter依赖.zsh')

  def setup
    @base = Dir.mktmpdir('jobs-migration-shell-')
    @bundle = File.join(@base, '迁移 包 $(touch NEVER)')
    FileUtils.mkdir_p(@bundle)
    File.write(File.join(@bundle, 'migration.json'), '{"status":"complete"}')
    File.write(File.join(@bundle, '.hidden'), 'hidden data')
  end

  def teardown
    FileUtils.remove_entry(@base)
  end

  def run_functions(body, *arguments, input: '', env: {})
    fixture = File.join(@base, 'fixture.zsh')
    File.write(fixture, <<~ZSH + body)
      source #{Shellwords.escape(SCRIPT)}
      setopt NO_NOMATCH PIPE_FAIL
      FM_LOG=/dev/null
    ZSH
    Open3.capture2e({ 'NO_COLOR' => '1' }.merge(env), '/bin/zsh', '-f', fixture, *arguments, stdin_data: input)
  end

  def test_scope_empty_private_nonempty_all_and_eof_cancels
    [["\n", '1'], [" \n", '0'], ["全部\n", '0']].each do |input, value|
      output, status = run_functions('fm_choose_scope; print -r -- "PRIVATE=$FM_PRIVATE"', input: input)
      assert status.success?, output
      assert_includes output, "PRIVATE=#{value}"
      assert_includes output, '私库'
    end
    output, status = run_functions('fm_choose_scope', input: '')
    assert_equal 130, status.exitstatus, output
  end

  def test_dragged_renamed_cache_path_is_data
    source = File.join(@base, '改名 缓存 ; $(touch NEVER)')
    Dir.mkdir(source)
    [source, Shellwords.escape(source), "'#{source}'\u00a0"].each do |raw|
      output, status = run_functions('fm_normalize "$1"; print -r -- "$REPLY"', raw)
      assert status.success?, output
      assert_equal source, output.strip
    end
    refute File.exist?(File.join(@base, 'NEVER'))
  end

  def test_import_empty_input_retries_and_eof_stops
    output, status = run_functions('FM_MODE=import; fm_read_directory; print -r -- "$FM_DIRECTORY"', input: "\n#{Shellwords.escape(@bundle)}\n")
    assert status.success?, output
    assert_includes output, '尚未输入依赖目录'
    assert_includes output, File.realpath(@bundle)
    output, status = run_functions('FM_MODE=import; fm_read_directory', input: '')
    assert_equal 130, status.exitstatus, output
  end

  def zip(input)
    run_functions('FM_DIRECTORY="$1"; FM_OUTPUT="$2"; fm_zip_offer', @base, @bundle, input: input)
  end

  def test_zip_default_keeps_directory_and_includes_hidden_files
    output, status = zip("\n\n")
    assert status.success?, output
    assert Dir.exist?(@bundle)
    assert File.file?(@bundle + '.zip')
    listing, result = Open3.capture2e('/usr/bin/unzip', '-Z1', @bundle + '.zip')
    assert result.success?, listing
    assert_includes listing, '/.hidden'
    assert_includes output, 'ZIP 已完成并校验'
  end

  def test_zip_nonempty_delete_removes_only_new_bundle
    unrelated = File.join(@base, '保留我')
    File.write(unrelated, 'existing')
    output, status = zip("\n \n")
    assert status.success?, output
    refute File.exist?(@bundle)
    assert File.file?(@bundle + '.zip')
    assert_equal 'existing', File.read(unrelated)
  end

  def test_no_zip_and_zip_conflict_both_preserve_original
    output, status = zip(" \n")
    assert status.success?, output
    assert Dir.exist?(@bundle)
    refute File.exist?(@bundle + '.zip')
    File.write(@bundle + '.zip', 'preexisting')
    output, status = zip("\n")
    refute status.success?, output
    assert_equal 'preexisting', File.read(@bundle + '.zip')
    assert Dir.exist?(@bundle)
  end

  def fake_dart(preview_status: 0)
    fake = File.join(@base, 'fake-dart')
    File.write(fake, <<~ZSH)
      #!/bin/zsh
      print -r -- "$*" >> "$TEST_CALLS"
      print -r -- 'preview plan'
      print -r -- 'JOBS_MIGRATION_PLAN=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      if [[ " $* " != *' --apply '* ]]; then exit #{preview_status}; fi
    ZSH
    File.chmod(0o755, fake)
    fake
  end

  def test_import_preflight_failure_cannot_apply_even_with_yes
    fake = fake_dart(preview_status: 23)
    trace = File.join(@base, 'calls')
    output, status = run_functions('FM_DART="$1"; FM_DIRECTORY="$2"; fm_import', fake, @bundle, input: "YES\n", env: { 'TEST_CALLS' => trace })
    assert_equal 23, status.exitstatus, output
    assert_equal 1, File.readlines(trace).length
    refute_includes File.read(trace), '--apply'
  end

  def test_import_requires_exact_yes
    fake = fake_dart
    ["\n", "yes\n", " YES\n", "YES\n"].each_with_index do |input, index|
      trace = File.join(@base, "calls#{index}")
      output, status = run_functions('FM_DART="$1"; FM_DIRECTORY="$2"; fm_import', fake, @bundle, input: input, env: { 'TEST_CALLS' => trace })
      assert status.success?, output
      assert_equal(input == "YES\n" ? 2 : 1, File.readlines(trace).length)
      assert_includes File.read(trace), '--expected-plan ' + 'a' * 64 if input == "YES\n"
    end
  end

  def test_export_engine_failure_propagates_without_zip
    fake = fake_dart(preview_status: 29)
    trace = File.join(@base, 'calls')
    output, status = run_functions('FM_DART="$1"; FM_DIRECTORY="$2"; fm_export', fake, @base, input: "\n \n", env: { 'TEST_CALLS' => trace })
    assert_equal 29, status.exitstatus, output
    refute File.exist?(@bundle + '.zip')
    assert Dir.exist?(@bundle)
  end
  def real_dart
    candidate = ENV['JOBS_TEST_DART'] || ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).map { |entry| File.join(entry, 'dart') }.find { |path| File.file?(path) && File.executable?(path) }
    skip '需要已有原生 Dart；本测试不会安装 SDK' unless candidate && File.executable?(candidate)
    resolved = File.realpath(candidate)
    sdk_binary = File.join(File.dirname(resolved), 'cache/dart-sdk/bin/dart')
    File.file?(sdk_binary) ? File.realpath(sdk_binary) : resolved
  end

  def prepare_real_pipeline
    dart = real_dart
    copied = File.join(@base, '打包资源/Tools')
    FileUtils.mkdir_p(File.dirname(copied))
    FileUtils.cp_r(TOOLS, copied)
    @project = File.join(@base, '原工程 不应写入')
    @target = File.join(@base, '目标 无 lib')
    manifest = "name: fixture\nenvironment:\n  sdk: '>=3.0.0 <4.0.0'\ndependencies:\n  flutter:\n    sdk: flutter\n  private_pkg:\n    git: https://private.invalid/pkg.git\n  public_pkg: ^1.0.0\n"
    [@project, @target].each do |project|
      FileUtils.mkdir_p(project)
      File.write(File.join(project, 'pubspec.yaml'), manifest)
      path = File.join(project, '.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart')
      FileUtils.mkdir_p(File.dirname(path))
      File.symlink(dart, path)
    end
    FileUtils.mkdir_p(File.join(@project, '.dart_tool'))
    lock = "packages:\n"
    packages = [{ 'name' => 'fixture', 'rootUri' => URI::DEFAULT_PARSER.escape("file://#{@project}/") }]
    %w[private_pkg public_pkg flutter].each do |name|
      package = File.join(@base, 'resolved', name)
      FileUtils.mkdir_p(File.join(package, 'lib'))
      File.write(File.join(package, 'pubspec.yaml'), "name: #{name}\nversion: 1.0.0\n")
      File.write(File.join(package, 'lib', name + '.dart'), "// #{name}\n")
      File.write(File.join(package, 'LICENSE'), 'original license')
      source = { 'private_pkg' => 'git', 'public_pkg' => 'hosted', 'flutter' => 'sdk' }.fetch(name)
      lock += "  #{name}:\n    source: #{source}\n    version: \"1.0.0\"\n"
      lock += "    description:\n      name: #{name}\n      url: https://pub.dev\n" if name == 'public_pkg'
      packages << { 'name' => name, 'rootUri' => URI::DEFAULT_PARSER.escape("file://#{package}/") }
    end
    File.write(File.join(@project, 'pubspec.lock'), lock)
    File.write(File.join(@project, '.dart_tool/package_config.json'), JSON.generate('configVersion' => 2, 'packages' => packages))
    @pubcache = File.join(@base, 'environment/pub')
    @gradle = File.join(@base, 'environment/gradle')
    @output = File.join(@base, 'output')
    @testhome = File.join(@base, 'environment/home')
    [@pubcache, @gradle, @output, @testhome].each { |dir| FileUtils.mkdir_p(dir) }
    @real_environment = {
      'HOME' => @testhome, 'PUB_CACHE' => @pubcache, 'GRADLE_USER_HOME' => @gradle,
      'MAVEN_REPO_LOCAL' => File.join(@base, 'environment/maven'),
      'NO_COLOR' => '1', 'TERM' => 'dumb', 'CI' => 'true', 'DART_SUPPRESS_ANALYTICS' => 'true',
      'TMPDIR' => @base + '/'
    }
    @dispatcher = File.join(copied, 'DispatchFlutterTools.zsh')
  end

  def actual_dispatch(action, project, input)
    Timeout.timeout(90) do
      Open3.capture2e(@real_environment, '/bin/zsh', '-f', @dispatcher, action, project, stdin_data: input, chdir: '/')
    end
  end

  def test_real_copied_dispatcher_export_zip_and_bundle_yes_import
    prepare_real_pipeline
    source_before = File.binread(File.join(@project, 'pubspec.yaml'))
    output, status = actual_dispatch('export-all-dependencies', @project, "\n\n#{@output}\n\n\n")
    assert status.success?, output
    bundles = Dir.children(@output).map { |name| File.join(@output, name) }.select { |path| File.directory?(path) }
    assert_equal 1, bundles.length, output
    bundle = bundles.first
    assert File.file?(bundle + '.zip'), output
    metadata = JSON.parse(File.read(File.join(bundle, 'migration.json')))
    assert_equal 'private-candidates', metadata.fetch('scope')
    pub_manifest = JSON.parse(File.read(File.join(bundle, metadata.fetch('pubSnapshot'), 'manifest.json')))
    assert_equal ['private_pkg'], pub_manifest.fetch('packages').map { |item| item.fetch('name') }
    output, status = actual_dispatch('import-all-dependencies', @target, "\n#{Shellwords.escape(bundle)}\nYES\n")
    assert status.success?, output
    assert_includes File.read(File.join(@target, 'pubspec_overrides.yaml')), 'private_pkg:'
    refute_includes File.read(File.join(@target, 'pubspec_overrides.yaml')), 'public_pkg:'
    assert_equal source_before, File.binread(File.join(@project, 'pubspec.yaml'))
    assert File.directory?(bundle), 'ZIP 默认必须保留原始导出目录'
    refute File.exist?(File.join(@target, 'lib')), '迁移目标允许无 lib'
  end

  def test_real_copied_dispatcher_imports_renamed_raw_caches_without_overwriting_existing_files
    prepare_real_pipeline
    donor = File.join(@base, '来件 父目录')
    pub_file = 'hosted/pub.dev/public_pkg-1.0.0/pubspec.yaml'
    jar = 'caches/modules-2/files-2.1/com.private/sdk/1.0/hash/sdk.jar'
    source_pub = File.join(donor, '改名A', pub_file)
    source_jar = File.join(donor, '改名B', jar)
    [source_pub, source_jar].each { |path| FileUtils.mkdir_p(File.dirname(path)) }
    File.write(source_pub, "name: public_pkg\nversion: 1.0.0\n")
    File.binwrite(source_jar, "jar\x00bytes")
    File.write(File.join(donor, '改名B', 'gradle.properties'), 'secret=DO_NOT_COPY')
    existing = File.join(@gradle, 'keep.txt')
    File.write(existing, 'retain')
    output, status = actual_dispatch('import-all-dependencies', @target, "\n#{Shellwords.escape(donor)}\nNO\n")
    assert status.success?, output
    refute File.exist?(File.join(@pubcache, pub_file))
    refute File.exist?(File.join(@gradle, jar))
    output, status = actual_dispatch('import-all-dependencies', @target, "\n\n#{Shellwords.escape(donor)}\nYES\n")
    assert status.success?, output
    assert_equal File.binread(source_pub), File.binread(File.join(@pubcache, pub_file))
    assert_equal File.binread(source_jar), File.binread(File.join(@gradle, jar))
    assert_equal 'retain', File.read(existing)
    refute File.exist?(File.join(@gradle, 'gradle.properties'))
    assert_includes output, '尚未输入依赖目录'
  end

  def test_missing_plan_fingerprint_stops_before_yes
    fake = File.join(@base, 'old-dart')
    File.write(fake, "#!/bin/zsh\nprint -r -- legacy-preview\n")
    File.chmod(0o755, fake)
    output, status = run_functions('FM_DART="$1"; FM_DIRECTORY="$2"; fm_import', fake, @bundle, input: "YES\n")
    refute status.success?, output
    assert_includes output, '预检指纹'
  end

  def test_real_source_change_during_confirmation_stops_all_writes
    prepare_real_pipeline
    donor = File.join(@base, '变化的原始缓存')
    first = File.join(donor, 'hosted/pub.dev/pkg-1.0.0/pubspec.yaml')
    FileUtils.mkdir_p(File.dirname(first))
    File.write(first, "name: pkg\nversion: 1.0.0\n")
    output = +''.b
    status = nil
    Timeout.timeout(90) do
      Open3.popen2e(@real_environment, '/bin/zsh', '-f', @dispatcher, 'import-all-dependencies', @target, chdir: '/') do |input, stream, waiter|
        input.write("\n#{Shellwords.escape(donor)}\n")
        input.flush
        until output.include?('JOBS_MIGRATION_PLAN=')
          output << stream.readpartial(4096).b
        end
        File.write(File.join(File.dirname(first), 'added_after_preview.dart'), '// changed')
        input.write("YES\n")
        input.close
        output << stream.read.b
        status = waiter.value
      end
    end
    output.force_encoding('UTF-8')
    refute status.success?, output
    assert_match(/变化|指纹|不一致/, output)
    assert_empty Dir.children(@pubcache), '预检后来源变化必须保持缓存零写入'
  end

  def test_native_full_archive_zip_uses_native_manifest_identity
    prepare_real_pipeline
    native = File.join(@base, 'native-module-source')
    FileUtils.mkdir_p(native)
    File.binwrite(File.join(native, 'sdk.jar'), "archive\x00")
    code = <<~'ZSH'
      source "$1/ArchiveProjectDependencies.zsh"
      ar_initialize() { return 0; }
      ar_choose_platform() { return 0; }
      ar_resolve_dart() { return 0; }
      ar_resolve_root() { return 0; }
      pe_log() { print -r -- "$*"; }
      pe_run_logged() { "$@"; }
      AR_PRIVATE=0 AR_CHECK=0 AR_MODE=export AR_KIND=gradle AR_PLATFORM=android
      AR_PROJECT="$2" SF_PROJECT="$2" AR_ROOT="$3" AR_DIRECTORY="$4" AR_DART="$5"
      PE_TOOLS_DIR="$1" PE_LOG_FILE=/dev/null AR_VERSION='Gradle 8.10.2 modules'
      ar_run
    ZSH
    output, status = run_functions(code, TOOLS, @project, native, @output, real_dart, input: "\n\n")
    assert status.success?, output
    bundles = Dir.children(@output).map { |name| File.join(@output, name) }.select { |path| File.directory?(path) }
    assert_equal 1, bundles.length, output
    assert File.file?(File.join(bundles.first, 'manifest.json'))
    assert File.file?(bundles.first + '.zip'), output
    refute File.exist?(File.join(bundles.first, 'migration.json'))
  end

  def test_zip_never_deletes_payload_changed_after_archive_verification
    code = <<~'ZSH'
      read() {
        if [[ "$*" == *'是否删除原始提取目录'* ]]; then
          print -r -- 'user changes after archive' > "$FM_OUTPUT/.hidden"
          print -r -- 'new user file' > "$FM_OUTPUT/new-after-zip.txt"
        fi
        builtin read "$@"
      }
      FM_DIRECTORY="$1" FM_OUTPUT="$2"
      fm_zip_offer
    ZSH
    original_manifest = File.binread(File.join(@bundle, 'migration.json'))
    output, status = run_functions(code, @base, @bundle, input: "\nDELETE\n")
    refute status.success?, output
    assert Dir.exist?(@bundle), output
    assert File.file?(@bundle + '.zip'), output
    assert_equal original_manifest, File.binread(File.join(@bundle, 'migration.json'))
    assert_equal "user changes after archive\n", File.read(File.join(@bundle, '.hidden'))
    assert File.file?(File.join(@bundle, 'new-after-zip.txt'))
    assert_includes output, '发生变化，未删除'
  end

end
