# frozen_string_literal: true
# Created by Jobs on 2026年10月29日，星期四。
# 真实 zsh wrapper 与真实 Dart 标准库内核的隔离集成；不准备 SDK、不联网、不运行归档脚本。
require 'digest'
require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'pty'
require 'tmpdir'
require 'timeout'

class NativeDependencyArchiveShellTests < Minitest::Test
  TOOLS = File.expand_path(ENV.fetch('JOBS_TEST_TOOLS_DIR', '../Scripts/Tools'), __dir__)
  ENTRY = File.join(TOOLS, 'ArchiveProjectDependencies.zsh')
  DART = ENV.fetch('JOBS_TEST_DART', '/opt/homebrew/bin/dart')
  KINDS = %w[gradle pods spm ohos native precache web].freeze

  def setup
    skip "需要现有原生 Dart：#{DART}；测试不会安装工具" unless File.executable?(DART)

    @root = File.realpath(Dir.mktmpdir('jobs-native-archive-shell-'))
    @project = File.join(@root, "项目 空格 ' $(touch INJECTED) ; literal")
    @source = File.join(@root, "缓存 源 ' $literal")
    @destination = File.join(@root, "恢复 缓存 ' $literal")
    @output = File.join(@root, '快照 输出')
    @trace = File.join(@root, 'trace')
    @temporary = File.join(@root, 'temporary')
    @home = File.join(@root, 'home')
    @bin = File.join(@root, 'bin')
    FileUtils.mkdir_p([File.join(@project, 'lib'), @source, @output, @temporary, @home, @bin])
    File.write(File.join(@project, 'pubspec.yaml'), "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n")
    File.write(File.join(@project, 'pubspec.lock'), "packages: {}\n")
    write(File.join(@project, 'android/gradle/wrapper/gradle-wrapper.properties'),
          "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.10.2-bin.zip\n")
    write(File.join(@source, 'files-2.1/library/1.0/library.jar'), "fixture artifact\x00\x01".b)
    write(File.join(@source, 'scripts/never-run.sh'), "#!/bin/sh\ntouch \"$JOBS_ARCHIVE_SENTINEL\"\n", executable: true)
    @env = {
      'HOME' => @home, 'TMPDIR' => @temporary, 'PATH' => "#{@bin}:/usr/bin:/bin:/usr/sbin:/sbin",
      'TERM' => 'dumb', 'NO_COLOR' => '1', 'CI' => 'true', 'DART_SUPPRESS_ANALYTICS' => 'true',
      'TEST_ARCHIVE_ENTRY' => ENTRY, 'TEST_ARCHIVE_TOOLS' => TOOLS, 'TEST_ARCHIVE_DART' => DART,
      'TEST_ARCHIVE_PROJECT' => @project, 'TEST_ARCHIVE_ROOT' => @source,
      'TEST_ARCHIVE_DIRECTORY' => @output, 'TEST_ARCHIVE_TRACE' => @trace,
      'TEST_ARCHIVE_KIND' => 'gradle', 'TEST_ARCHIVE_PLATFORM' => 'android',
      'TEST_ARCHIVE_VERSION' => 'Gradle 8.10.2 modules', 'TEST_ARCHIVE_MODE' => 'export',
      'JOBS_ARCHIVE_SENTINEL' => File.join(@root, 'ARCHIVE_SCRIPT_WAS_RUN')
    }
    @harness = File.join(@root, 'transfer.zsh')
    File.write(@harness, <<~'ZSH')
      source "$TEST_ARCHIVE_ENTRY" || exit $?
      pe_log() { print -r -- "$*"; }
      pe_run_logged() {
        /usr/bin/printf '%s\0' "$#" "$@" >> "$TEST_ARCHIVE_TRACE"
        "$@"
      }
      PE_TOOLS_DIR="$TEST_ARCHIVE_TOOLS" SF_PROJECT="$TEST_ARCHIVE_PROJECT"
      AR_DART="$TEST_ARCHIVE_DART" AR_MODE="$TEST_ARCHIVE_MODE" AR_KIND="$TEST_ARCHIVE_KIND"
      AR_PLATFORM="$TEST_ARCHIVE_PLATFORM" AR_VERSION="$TEST_ARCHIVE_VERSION"
      AR_ROOT="$TEST_ARCHIVE_ROOT" AR_DIRECTORY="$TEST_ARCHIVE_DIRECTORY"
      ar_transfer
    ZSH
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.exist?(@root)
  end

  def write(path, contents, executable: false)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, contents)
    File.chmod(0o755, path) if executable
  end

  def invoke(*arguments, env: {}, input: '')
    Timeout.timeout(45) do
      Open3.capture2e(@env.merge(env), '/bin/zsh', '-f', *arguments, stdin_data: input)
    end
  end

  def transfer(env: {}, input: '')
    invoke(@harness, env: env, input: input)
  end

  def calls
    return [] unless File.exist?(@trace)

    values = File.binread(@trace).force_encoding('UTF-8').split("\0")
    result = []
    until values.empty?
      count = values.shift
      raise 'invalid trace framing' unless count&.match?(/\A\d+\z/)

      result << values.shift(count.to_i)
    end
    result
  end

  def export_snapshot
    output, status = transfer
    assert status.success?, output
    directory = output.lines.find { |line| line.start_with?('ARCHIVE_DIRECTORY=') }&.strip&.delete_prefix('ARCHIVE_DIRECTORY=')
    assert directory && File.directory?(directory), output
    directory
  end

  def import_environment(snapshot, version: @env['TEST_ARCHIVE_VERSION'])
    {
      'TEST_ARCHIVE_MODE' => 'import', 'TEST_ARCHIVE_ROOT' => @destination,
      'TEST_ARCHIVE_DIRECTORY' => snapshot, 'TEST_ARCHIVE_VERSION' => version
    }
  end

  def clear_trace
    FileUtils.rm_f(@trace)
  end

  def assert_no_execution
    refute File.exist?(@env['JOBS_ARCHIVE_SENTINEL']), 'restoring a script must never execute it'
    refute File.exist?(File.join(@root, 'INJECTED')), 'project path remains data'
  end

  def confirm_in_terminal(snapshot, answer)
    output = +''.b
    status = nil
    PTY.spawn(@env.merge(import_environment(snapshot)), '/bin/zsh', '-f', @harness) do |reader, writer, pid|
      sent = false
      begin
        Timeout.timeout(45) do
          loop do
            output << reader.readpartial(16_384)
            if !sent && output.include?('输入精确大写 YES 导入'.b)
              yield if block_given?
              writer.write("#{answer}\n")
              writer.flush
              sent = true
            end
          end
        end
      rescue Errno::EIO, EOFError
        _, status = Process.wait2(pid)
      ensure
        unless status
          Process.kill('TERM', pid) rescue nil
          Process.wait(pid) rescue nil
        end
      end
    end
    [output.force_encoding('UTF-8').scrub, status]
  end

  def test_export_uses_real_dart_and_produces_independently_verified_payload
    snapshot = export_snapshot
    manifest = JSON.parse(File.read(File.join(snapshot, 'manifest.json')))
    assert_equal 'JobsNativeDependencyArchive', manifest.fetch('format')
    assert_equal 'gradle', manifest.fetch('kind')
    assert_equal 'android', manifest.fetch('platform')
    assert_equal @env['TEST_ARCHIVE_VERSION'], manifest.fetch('toolVersion')
    assert_equal 2, manifest.fetch('files').length
    manifest.fetch('files').each do |record|
      payload = File.join(snapshot, 'payload', record.fetch('path'))
      assert_equal Digest::SHA256.file(payload).hexdigest, record.fetch('sha256')
      assert_equal File.binread(File.join(@source, record.fetch('path'))), File.binread(payload)
    end
    assert_equal [DART, File.join(TOOLS, 'NativeDependencyArchive.dart'), 'export'], calls.fetch(0).first(3)
    assert_no_execution
  end

  def test_import_in_real_terminal_checks_then_requires_exact_yes_and_applies
    snapshot = export_snapshot
    clear_trace
    output, status = confirm_in_terminal(snapshot, 'YES')
    assert status&.success?, output
    assert_equal 2, calls.length
    assert_includes calls[0], '--check'
    refute_includes calls[0], '--confirm'
    assert_equal ['--confirm', 'YES'], calls[1].last(2)
    assert_equal File.binread(File.join(@source, 'files-2.1/library/1.0/library.jar')),
                 File.binread(File.join(@destination, 'files-2.1/library/1.0/library.jar'))
    assert File.executable?(File.join(@destination, 'scripts/never-run.sh'))
    assert_no_execution
  end

  def test_same_content_import_can_repeat_without_overwriting_or_losing_unrelated_files
    snapshot = export_snapshot
    output, status = transfer(env: import_environment(snapshot), input: "YES\n")
    assert status.success?, output
    write(File.join(@destination, 'unrelated.txt'), 'keep')
    clear_trace
    output, status = transfer(env: import_environment(snapshot), input: "YES\n")
    assert status.success?, output
    plans = output.lines.map { |line| JSON.parse(line) if line.start_with?('{') }.compact
    assert_equal [2, 2], plans.map { |plan| plan.fetch('reuseCount') }
    assert_equal [0, 0], plans.map { |plan| plan.fetch('writeCount') }
    assert_equal 'keep', File.read(File.join(@destination, 'unrelated.txt'))
    assert_no_execution
  end

  def test_snapshot_changed_while_waiting_for_yes_is_checked_again_before_writing
    snapshot = export_snapshot
    clear_trace
    output, status = confirm_in_terminal(snapshot, 'YES') do
      File.binwrite(File.join(snapshot, 'payload/files-2.1/library/1.0/library.jar'), 'changed after precheck')
    end
    refute status&.success?, output
    assert_equal 2, calls.length
    assert_includes calls[0], '--check'
    assert_equal ['--confirm', 'YES'], calls[1].last(2)
    assert_includes output, '哈希不匹配'
    refute File.exist?(@destination)
    assert_no_execution
  end

  def test_cancel_lowercase_empty_and_eof_never_apply_the_validated_snapshot
    snapshot = export_snapshot
    ["no\n", "yes\n", "\n", ''].each do |input|
      clear_trace
      output, status = transfer(env: import_environment(snapshot), input: input)
      assert_equal 130, status.exitstatus, output
      assert_equal 1, calls.length
      assert_includes calls[0], '--check'
      refute File.exist?(@destination)
    end
    assert_no_execution
  end

  def test_existing_conflict_blocks_every_write_before_confirmation
    snapshot = export_snapshot
    write(File.join(@destination, 'scripts/never-run.sh'), 'user changed this')
    clear_trace
    output, status = transfer(env: import_environment(snapshot), input: "YES\n")
    refute status.success?, output
    assert_includes output, '冲突'
    assert_equal 1, calls.length
    refute File.exist?(File.join(@destination, 'files-2.1/library/1.0/library.jar'))
    assert_equal 'user changed this', File.read(File.join(@destination, 'scripts/never-run.sh'))
    assert_no_execution
  end

  def test_different_tool_version_is_rejected_before_yes_or_target_creation
    snapshot = export_snapshot
    clear_trace
    output, status = transfer(env: import_environment(snapshot, version: 'Gradle 8.11.1 modules'), input: "YES\n")
    refute status.success?, output
    assert_includes output, '不兼容'
    assert_equal 1, calls.length
    refute File.exist?(@destination)
  end

  def test_different_host_is_rejected_before_confirmation
    snapshot = export_snapshot
    file = File.join(snapshot, 'manifest.json')
    manifest = JSON.parse(File.read(file))
    manifest['hostOS'] = 'windows'
    File.write(file, JSON.pretty_generate(manifest))
    clear_trace
    output, status = transfer(env: import_environment(snapshot), input: "YES\n")
    refute status.success?, output
    assert_includes output, '不兼容'
    assert_equal 1, calls.length
    refute File.exist?(@destination)
  end

  def test_changed_project_lock_and_tampered_payload_each_block_before_apply
    snapshot = export_snapshot
    lock = File.join(@project, 'pubspec.lock')
    original = File.binread(lock)
    File.write(lock, "packages: {changed: true}\n")
    output, status = transfer(env: import_environment(snapshot), input: "YES\n")
    refute status.success?, output
    assert_includes output, '签名不一致'
    refute File.exist?(@destination)
    File.binwrite(lock, original)
    File.binwrite(File.join(snapshot, 'payload/files-2.1/library/1.0/library.jar'), 'tampered')
    clear_trace
    output, status = transfer(env: import_environment(snapshot), input: "YES\n")
    refute status.success?, output
    assert_includes output, '哈希不匹配'
    assert_equal 1, calls.length
    refute File.exist?(@destination)
  end

  def test_export_missing_source_reports_precondition_without_running_dart
    output, status = transfer(env: { 'TEST_ARCHIVE_ROOT' => File.join(@root, 'missing') })
    assert_equal 3, status.exitstatus, output
    assert_includes output, '先运行相应拉取/构建入口'
    refute File.exist?(@trace)
    assert_empty Dir.children(@output)
  end

  def test_cli_check_for_all_categories_and_modes_never_runs_tools_or_writes_logs
    %w[flutter fvm dart java javac xcodebuild ohpm node fzf curl brew].each do |name|
      write(File.join(@bin, name), "#!/bin/sh\ntouch \"$TEST_ARCHIVE_TRACE\"\nexit 99\n", executable: true)
    end
    before = Dir.glob(File.join(@project, '**/*'), File::FNM_DOTMATCH).sort
    KINDS.product(%w[export import]).each do |kind, mode|
      output, status = invoke(ENTRY, '--project', @project, '--mode', mode, '--kind', kind, '--check')
      assert status.success?, output
      assert_includes output, '只读计划'
      refute File.exist?(@trace), "#{mode}/#{kind} must not run any tool"
      assert_empty Dir.children(@temporary)
    end
    assert_equal before, Dir.glob(File.join(@project, '**/*'), File::FNM_DOTMATCH).sort
  end

  def test_invalid_cli_kind_and_duplicate_parameters_stop_before_business
    [%w[--kind unknown], %w[--kind gradle --kind web]].each do |arguments|
      output, status = invoke(ENTRY, '--project', @project, '--mode', 'export', *arguments, '--check')
      assert_equal 2, status.exitstatus, output
      refute File.exist?(@trace)
      assert_empty Dir.children(@temporary)
    end
  end

  def test_dispatch_preserves_all_fourteen_archive_actions_and_literal_project_path
    tools = File.join(@root, 'isolated tools')
    FileUtils.mkdir_p(tools)
    FileUtils.cp(File.join(TOOLS, 'DispatchFlutterTools.zsh'), tools)
    write(File.join(tools, 'ArchiveProjectDependencies.zsh'), <<~'ZSH')
      #!/bin/zsh
      /usr/bin/printf '%s\0' "$@" > "$TEST_ARCHIVE_TRACE"
      exit 37
    ZSH
    KINDS.product(%w[export import]).each do |kind, mode|
      output, status = invoke(File.join(tools, 'DispatchFlutterTools.zsh'), "#{mode}-#{kind}-dependencies", @project)
      assert_equal 37, status.exitstatus, output
      assert_equal ['--project', @project, '--mode', mode, '--kind', kind],
                   File.binread(@trace).force_encoding('UTF-8').split("\0")
      assert_no_execution
    end
  end
end
