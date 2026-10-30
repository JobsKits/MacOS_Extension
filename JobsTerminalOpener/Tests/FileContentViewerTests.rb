# frozen_string_literal: true
# 在临时文件与 PTY 中运行真实查看器；不启动 Terminal、不登记 Finder 扩展。

require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'pty'
require 'timeout'
require 'tmpdir'

class FileContentViewerTests < Minitest::Test
  PROJECT = File.expand_path('..', __dir__)
  SCRIPT = File.join(PROJECT, 'Scripts/ViewFileContent.zsh')

  def setup
    @root = Dir.mktmpdir('jobs-file-content-')
    @file = File.join(@root, "中文 空格 ' $(touch SHOULD_NOT_EXIST)\n正文.txt")
    @env = { 'NO_COLOR' => '1', 'JOBS_FILE_VIEWER_MAX_BYTES' => nil }
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def run_script(path = @file, env: {}, input: '')
    Open3.capture2e(@env.merge(env), '/bin/zsh', SCRIPT, path, stdin_data: input)
  end

  def test_small_unicode_text_is_shown_and_filename_is_literal
    File.binwrite(@file, "正文是中文 é 😀\n$(touch SHOULD_NOT_EXIST)\n")
    output, status = run_script
    assert status.success?, output
    assert_includes output, '正文是中文 é 😀'
    assert_includes output, '$(touch SHOULD_NOT_EXIST)'
    assert_includes output, '\x{0A}正文.txt'
    refute File.exist?(File.join(@root, 'SHOULD_NOT_EXIST'))
  end

  def test_empty_file_has_a_complete_readout
    File.write(@file, '')
    output, status = run_script
    assert status.success?, output
    assert_includes output, '大小：0 字节'
    assert_includes output, '查看结束'
  end

  def test_control_characters_are_not_executed_by_the_terminal
    File.binwrite(@file, "正文\e[31m\a\r\b\u009b\u202e完\n")
    output, status = run_script
    assert status.success?, output
    assert_includes output, '\x{1B}[31m'
    assert_includes output, '\x{07}'
    assert_includes output, '\x{0D}'
    assert_includes output, '\x{08}'
    assert_includes output, '\x{9B}'
    assert_includes output, '\x{202E}'
    refute_includes output, "\e"
  end

  def test_threshold_is_strictly_greater_and_invalid_values_stop
    File.write(@file, 'EXACT')
    output, status = run_script(env: { 'JOBS_FILE_VIEWER_MAX_BYTES' => '5' })
    assert status.success?, output
    assert_includes output, 'EXACT'
    output, status = run_script(env: { 'JOBS_FILE_VIEWER_MAX_BYTES' => '4' })
    assert status.success?, output
    assert_includes output, '超过确认阈值'
    refute_includes output, 'EXACT'
    %w[0 -1 01 1.5 abc 9223372036854775808].push('').each do |value|
      output, status = run_script(env: { 'JOBS_FILE_VIEWER_MAX_BYTES' => value })
      refute status.success?, value
      assert_includes output, '必须是 1 到'
      refute_includes output, 'EXACT'
    end
  end

  def test_default_one_mib_gate_happens_before_sample_and_content
    File.binwrite(@file, 'SECRET' + 'a' * 1_048_571)
    output, status = run_script
    assert status.success?, output
    assert_includes output, '大小：1048577 字节；确认阈值：1048576 字节'
    assert_includes output, '超过确认阈值'
    refute_includes output, 'SECRET'
    refute_includes output, '二进制或未知编码，继续将'
  end

  def test_utf8_split_at_sampling_boundary_remains_text
    [8190, 8191, 8192].each do |prefix_length|
      File.binwrite(@file, 'a' * prefix_length + "中文 😀\n")
      output, status = run_script
      assert status.success?, output[-300..]
      assert_includes output, '中文 😀'
      refute_includes output, '二进制或未知编码，继续将'
    end
  end

  def test_invalid_utf8_at_real_eof_requests_hex_confirmation
    File.binwrite(@file, "UNKNOWN\xC2".b)
    output, status = run_script
    assert status.success?, output
    assert_includes output, '二进制或未知编码，继续将'
    refute_includes output, 'UNKNOWN'
  end

  def test_missing_directory_symlink_fifo_and_multiple_targets_are_rejected
    File.write(@file, 'DO_NOT_SHOW')
    link = File.join(@root, 'link')
    File.symlink(@file, link)
    fifo = File.join(@root, 'fifo')
    assert system('/usr/bin/mkfifo', fifo)
    [@root, link, fifo, File.join(@root, 'missing')].each do |path|
      output, status = Timeout.timeout(3) { run_script(path) }
      refute status.success?, output
      refute_includes output, 'DO_NOT_SHOW'
    end
    output, status = Open3.capture2e(@env, '/bin/zsh', SCRIPT, @file, @file)
    refute status.success?, output
    refute_includes output, 'DO_NOT_SHOW'
  end

  def test_yes_in_a_pipe_is_not_interactive_approval
    File.write(@file, 'PRIVATE_TEXT')
    output, status = run_script(env: { 'JOBS_FILE_VIEWER_MAX_BYTES' => '1' }, input: "YES\n")
    assert status.success?, output
    refute_includes output, 'PRIVATE_TEXT'
    assert_includes output, '没有可交互终端'
  end

  def test_terminal_confirmation_accepts_only_exact_yes
    File.write(@file, 'VISIBLE_AFTER_YES')
    ['', 'yes', ' YES', 'YES '].each do |answer|
      output, status = in_terminal(env: { 'JOBS_FILE_VIEWER_MAX_BYTES' => '1' }, inputs: [answer])
      assert_equal 0, status, output
      refute_includes output, 'VISIBLE_AFTER_YES'
    end
    output, status = in_terminal(env: { 'JOBS_FILE_VIEWER_MAX_BYTES' => '1' }, inputs: ['YES'])
    assert_equal 0, status, output
    assert_includes output, 'VISIBLE_AFTER_YES'
  end

  def test_large_binary_requires_two_confirmations_and_safe_hex
    File.binwrite(@file, "BIN\x00\e[31m".b)
    output, status = in_terminal(env: { 'JOBS_FILE_VIEWER_MAX_BYTES' => '1' }, inputs: ['YES', 'YES'])
    assert_equal 0, status, output
    assert_equal 2, output.scan('输入 YES 继续').length
    assert_includes output, '42 49 4e 00 1b'
    refute_includes output, "\e[31m"
  end

  def test_ctrl_c_and_eof_cancel_before_content
    File.write(@file, 'SECRET_ON_CANCEL')
    ["\u0003", "\u0004"].each do |control|
      output, status = in_terminal(env: { 'JOBS_FILE_VIEWER_MAX_BYTES' => '1' }, controls: [control])
      assert_includes [0, 130], status, output
      refute_includes output, 'SECRET_ON_CANCEL'
    end
  end

  def test_file_growth_after_confirmation_does_not_exceed_initial_length
    File.write(@file, 'ORIGINAL')
    output, status = in_terminal(env: { 'JOBS_FILE_VIEWER_MAX_BYTES' => '1' }, inputs: ['YES']) do
      File.open(@file, 'a') { |file| file.write('APPENDED_DO_NOT_SHOW') }
    end
    assert_equal 0, status, output
    assert_includes output, 'ORIGINAL'
    refute_includes output, 'APPENDED_DO_NOT_SHOW'
  end

  def test_private_carrier_executes_literal_target_and_cleans_itself
    File.write(@file, 'CARRIER_CONTENT')
    build = File.join(@root, 'build')
    FileUtils.mkdir_p(build)
    executable = File.join(build, 'transport-fixture')
    output, status = Open3.capture2e(
      '/usr/bin/swiftc', '-module-cache-path', File.join(build, 'ModuleCache'),
      File.join(PROJECT, 'JobsTerminalShared/DependencyProjectValidator.swift'),
      File.join(PROJECT, 'JobsTerminalFinderSync/TerminalOpener.swift'),
      File.join(__dir__, 'TerminalRequestTransportFixture.swift'), '-o', executable
    )
    assert status.success?, output
    FileUtils.cp(SCRIPT, build)
    output, status = Open3.capture2e(executable, 'prepare', @file, 'file-content')
    assert status.success?, output
    request = JSON.parse(output)
    refute_match(/[\r\n]/, request.fetch('commandLine'))
    refute_includes request.fetch('commandLine'), @file
    output, status = Open3.capture2e(@env, '/bin/zsh', request.fetch('scriptPath'))
    assert status.success?, output
    assert_includes output, 'CARRIER_CONTENT'
    refute File.exist?(request.fetch('scriptPath'))
    refute File.exist?(request.fetch('runtimeDirectory'))
  end

  def test_independent_manager_preserves_sibling_features_when_installing_and_removing_one_leaf
    config = File.join(@root, 'Library/Application Support/JobsTerminalOpener/EnabledFinderMenuFeatures.txt')
    FileUtils.mkdir_p(File.dirname(config))
    File.write(config, 'open,pod-install')
    output, status = manager_run(<<~'ZSH')
      manager_parse_options --action install --non-interactive --features file-content || exit $?
      manager_validate_existing_configuration || exit $?
      manager_plan_shared_install || exit $?
      print -r -- "PLAN=$MANAGER_INSTALL_FEATURES"
      manager_save_shared_install || exit $?
      manager_restart_finder() { print -r -- 'FIXTURE_REFRESH'; }
      manager_plan_shared_removal || exit $?
      print -r -- "PARTIAL=$MANAGER_PARTIAL_REMOVAL"
    ZSH
    assert status.success?, output
    assert_includes output, 'PLAN=open,file-content,pod-install'
    assert_includes output, 'PARTIAL=1'
    assert_includes output, 'FIXTURE_REFRESH'
    assert_equal 'open,pod-install', File.read(config)
  end

  def test_old_installation_without_metadata_does_not_invent_a_new_enabled_leaf
    app = File.join(@root, 'JobsTerminalOpener.app')
    extension = File.join(app, 'Contents/PlugIns/JobsTerminalFinderSync.appex')
    FileUtils.mkdir_p(extension)
    output, status = manager_run(<<~'ZSH', extra_env: { 'FIXTURE_EXTENSION' => extension })
      fixture_pluginkit() { print -r -- "+ com.jobs.JobsTerminalOpener.FinderSyncExtension" "  Path = $FIXTURE_EXTENSION"; }
      fixture_plistbuddy() { return 1; }
      manager_restart_finder() { return 0; }
      MANAGER_REQUESTED_FEATURES=file-content
      EXTENSION_ID=com.jobs.JobsTerminalOpener.FinderSyncExtension
      manager_plan_shared_removal || exit $?
      print -r -- "PARTIAL=$MANAGER_PARTIAL_REMOVAL"
    ZSH
    assert status.success?, output
    config = File.join(@root, 'Library/Application Support/JobsTerminalOpener/EnabledFinderMenuFeatures.txt')
    assert_equal 'open,pod-install,flutter-pub-get,clean-build-artifacts,codegraph-bootstrap,git-empty-commit-push', File.read(config)
    assert File.directory?(app)
  end

  private

  def manager_run(driver, extra_env: {})
    source = File.read(File.join(PROJECT, 'Scripts/ManageExtension.zsh'))
    source = source.sub(/\nmanager_main "\$@"\s*\z/, "\n")
    source = source.gsub('/usr/bin/pluginkit', 'fixture_pluginkit').gsub('/usr/libexec/PlistBuddy', 'fixture_plistbuddy')
    source << "\nfixture_pluginkit() { return 0; }\nfixture_plistbuddy() { return 1; }\n"
    library = File.join(@root, 'manager-library.zsh')
    File.write(library, source)
    Open3.capture2e(
      @env.merge('HOME' => @root).merge(extra_env), '/bin/zsh', '-fc',
      "source \"$1\"\n#{driver}", '--', library
    )
  end

  def in_terminal(env: {}, inputs: [], controls: [])
    output = +''.b
    code = nil
    Timeout.timeout(10) do
      PTY.spawn(@env.merge(env), '/bin/zsh', SCRIPT, @file) do |reader, writer, pid|
        decisions = inputs.map { |answer| "#{answer}\n" } + controls
        decisions.each do |answer|
          target_count = output.scan('输入 YES 继续'.b).length + 1
          output << reader.readpartial(4096) until output.scan('输入 YES 继续'.b).length >= target_count
          yield if block_given?
          writer.write(answer)
        end
        begin
          loop { output << reader.readpartial(4096) }
        rescue EOFError, Errno::EIO
          # PTY 在子进程结束后以 EOF / EIO 结束读取。
        end
        _, status = Process.wait2(pid)
        code = status.exitstatus || 128 + status.termsig
      end
    end
    [output.force_encoding(Encoding::UTF_8), code]
  end
end
