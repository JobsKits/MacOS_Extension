# frozen_string_literal: true
# 用系统命令替身验证真实安装脚本；只在临时夹具中读写，不注册扩展或刷新 Finder。

require 'minitest/autorun'
require 'open3'
require 'pty'
require 'timeout'
require 'tmpdir'
require 'fileutils'

class InstallerRegistrationTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  INSTALLER = File.join(ROOT, '【MacOS】安装运行授权Finder扩展.command')
  UNINSTALLER = File.join(ROOT, '【MacOS】卸载运行授权Finder扩展.command')
  HELPER = File.join(ROOT, 'Scripts/EnableFinderExtension.zsh')
  APP_ID = 'com.jobs.JobsRunAuthorizer'
  EXTENSION_ID = "#{APP_ID}.FinderSyncExtension"
  LSREGISTER = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
  REPLACEMENTS = {
    '/usr/bin/pluginkit' => 'jobs_fake_pluginkit',
    '/usr/bin/pkill' => 'jobs_fake_pkill',
    '/usr/bin/killall' => 'jobs_fake_killall',
    '/usr/bin/open' => 'jobs_fake_open',
    '/usr/bin/xcodebuild' => 'jobs_fake_xcodebuild',
    '/usr/bin/xcrun' => 'jobs_fake_xcrun',
    '/usr/bin/codesign' => 'jobs_fake_codesign',
    '/bin/rm' => 'jobs_fake_rm',
    '/bin/sleep' => 'jobs_fake_sleep',
    LSREGISTER => 'jobs_fake_lsregister'
  }.freeze

  def setup
    @directory = Dir.mktmpdir('jobs-run-authorizer-registration-')
    @calls_path = File.join(@directory, 'calls')
    @marker = File.join(@directory, 'refresh-marker')
    @app = create_app('新 path', APP_ID)
    @extension = File.join(@app, 'Contents/PlugIns/JobsRunAuthorizerFinderSync.appex')
    @old_app = create_app('old', APP_ID)
    @old_extension = File.join(@old_app, 'Contents/PlugIns/JobsRunAuthorizerFinderSync.appex')
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_helper_rejects_enabled_old_copy_and_keeps_refresh_marker
    output, status = run_source(HELPER, helper_checks(plugin_line('+', @old_extension)))
    refute status.success?, output
    assert File.exist?(@marker)
    refute_includes calls, 'killall|Finder'
    assert_includes output, 'extension not enabled'
  end

  def test_helper_accepts_only_the_current_enabled_path_and_clears_marker
    File.write(@marker, 'pending')
    records = [plugin_line('+', @old_extension), plugin_line('+', @extension)].join("\n")
    output, status = run_source(HELPER, helper_checks(records))
    assert status.success?, output
    refute File.exist?(@marker)
    assert_includes calls, 'killall|Finder'
  end

  def test_helper_registration_failure_preserves_marker_and_stops_activation
    output, status = run_source(HELPER, helper_checks(plugin_line('+', @extension), 'JOBS_TEST_REGISTER_RESULT=7'))
    refute status.success?, output
    assert File.exist?(@marker)
    refute calls.any? { |line| line.start_with?('pluginkit|-e|') }
    refute_includes calls, 'killall|Finder'
    assert_includes output, 'registration failed'
  end

  def test_helper_activation_failure_preserves_marker_and_does_not_refresh
    output, status = run_source(HELPER, helper_checks(plugin_line('+', @extension), 'JOBS_TEST_ENABLE_RESULT=8'))
    refute status.success?, output
    assert File.exist?(@marker)
    refute_includes calls, 'killall|Finder'
    assert_includes output, 'activation failed'
  end

  def test_helper_refresh_failure_preserves_marker
    output, status = run_source(HELPER, helper_checks(plugin_line('+', @extension), 'JOBS_TEST_REFRESH_RESULT=9'))
    refute status.success?, output
    assert File.exist?(@marker)
    assert_includes output, 'killall Finder exit=9'
  end

  def test_independent_install_cleans_exact_old_host_and_extension_before_new_registration
    wrong_app = create_app('wrong-id', 'com.jobs.unrelated')
    records = [@old_app, @app, wrong_app].map do |path|
      "--------------------------------------------------------------------------------\npath: #{path} (0x7f0c)\nidentifier: #{APP_ID}\n"
    end.join
    checks = <<~'ZSH'
      setopt PIPE_FAIL NO_NOMATCH
      APP_PATH="$JOBS_TEST_APP"
      EXTENSION_PATH="$JOBS_TEST_EXTENSION"
      LOG_FILE="$JOBS_TEST_LOG"
      LSREGISTER=jobs_fake_lsregister
      register_extension
    ZSH
    output, status = run_source(INSTALLER, checks, records: records,
                                plugin_records: "Path = #{@old_extension}\nPath = #{@extension}\n")
    assert status.success?, output
    assert_includes calls, "pluginkit|-r|#{@old_extension}"
    refute_includes calls, "pluginkit|-r|#{@extension}"
    assert_includes calls, "lsregister|-u|#{@old_app}"
    refute_includes calls, "lsregister|-u|#{@app}"
    refute_includes calls, "lsregister|-u|#{wrong_app}"
    assert_operator calls.index("lsregister|-u|#{@old_app}"), :<, calls.index("lsregister|-f|#{@app}")
    assert_includes calls, "open|-n|#{@app}|--args|--initialize-finder-extension"
    assert File.directory?(@old_app), '旧 App 文件只注销登记，保留文件。'
  end

  def test_independent_install_registration_error_does_not_report_success
    checks = <<~'ZSH'
      setopt PIPE_FAIL NO_NOMATCH
      APP_PATH="$JOBS_TEST_APP"
      EXTENSION_PATH="$JOBS_TEST_EXTENSION"
      LOG_FILE="$JOBS_TEST_LOG"
      LSREGISTER=jobs_fake_lsregister
      JOBS_TEST_REGISTER_RESULT=7
      register_extension
    ZSH
    output, status = run_source(INSTALLER, checks)
    refute status.success?, output
    refute_includes output, '✔ 已请求启用扩展'
    refute calls.any? { |line| line.start_with?('open|') || line.start_with?('killall|') }
  end

  def test_independent_uninstall_removes_only_verified_app_and_keeps_authorized_file
    authorized_file = File.join(@directory, '曾授权文件/keep.command')
    FileUtils.mkdir_p(File.dirname(authorized_file))
    File.write(authorized_file, 'previously authorized content')
    checks = <<~'ZSH'
      setopt PIPE_FAIL NO_NOMATCH
      LOG_FILE="$JOBS_TEST_LOG"
      collect_registered_paths
      uninstall_extension
    ZSH
    output, status = run_source(UNINSTALLER, checks, plugin_records: "Path = #{@extension}\n")
    assert status.success?, output
    assert_includes calls, "pluginkit|-r|#{@extension}"
    assert_includes calls, "rm|-rf|--|#{@app}"
    assert_equal ["rm|-rf|--|#{@app}", 'rm|-f|--|/tmp/JobsRunAuthorizerNeedsFinderRestart'], calls.grep(/^rm\|/)
    assert_equal 'previously authorized content', File.read(authorized_file)
    refute calls.any? { |line| line.include?('chmod') }
    assert_includes calls, "lsregister|-u|#{@app}"
  end

  def test_independent_install_rejects_noninteractive_input_before_any_mutation
    output, status = run_source(INSTALLER, 'main "$@"', input: "\n")
    refute status.success?, output
    assert_includes output, '请在可交互终端运行'
    assert_empty calls
    refute File.exist?(File.join(@directory, 'JobsRunAuthorizerInstall.log'))
  end

  def test_independent_install_nonempty_input_skips_before_any_mutation
    output, status = run_source(INSTALLER, 'main "$@"', input: "skip\n", interactive: true)
    assert status.success?, output
    assert_includes output, '直接回车安装；输入任意字符后回车跳过'
    assert_empty calls
    refute File.exist?(File.join(@directory, 'JobsRunAuthorizerInstall.log'))
  end

  def test_install_log_path_accepts_temporary_directory_with_or_without_trailing_slash
    [@directory, "#{@directory}/"].each do |temporary_directory|
      output, status = run_source(INSTALLER, 'prepare_display_context; print -r -- "$LOG_FILE"',
                                  temporary_directory: temporary_directory)
      assert status.success?, output
      assert_equal File.join(@directory, 'JobsRunAuthorizerInstall.log'), output.strip
      assert_empty calls
    end
  end

  def test_uninstall_log_path_accepts_temporary_directory_with_or_without_trailing_slash
    [@directory, "#{@directory}/"].each do |temporary_directory|
      output, status = run_source(UNINSTALLER, 'prepare_display_context; print -r -- "$LOG_FILE"',
                                  temporary_directory: temporary_directory)
      assert status.success?, output
      assert_equal File.join(@directory, 'fixture.zsh.log'), output.strip
      assert_empty calls
    end
  end

def test_independent_uninstall_skips_wrong_extension_identity
  File.write(File.join(@extension, 'Contents/Info.plist'), <<~XML)
    <?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.jobs.unrelated</string></dict></plist>
  XML
  checks = <<~'ZSH'
    setopt PIPE_FAIL NO_NOMATCH
    LOG_FILE="$JOBS_TEST_LOG"
    collect_registered_paths
    uninstall_extension
  ZSH
  output, status = run_source(UNINSTALLER, checks, plugin_records: "Path = #{@extension}\n")
  assert status.success?, output
  refute_includes calls, "pluginkit|-r|#{@extension}"
  refute calls.any? { |line| line.start_with?('rm|-rf|') }
end

def test_independent_install_whitespace_input_skips_before_any_mutation
  output, status = run_source(INSTALLER, 'main "$@"', input: " \n", interactive: true)
  assert status.success?, output
  assert_empty calls
  refute File.exist?(File.join(@directory, 'JobsRunAuthorizerInstall.log'))
end

def test_build_phase_skip_does_not_run_system_commands
  output, status = run_source(HELPER, 'JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1; main "$@"')
  assert status.success?, output
  assert_includes output, 'skip build phase enable'
  assert_empty calls
end

  private

  def create_app(parent, identifier)
    app = File.join(@directory, parent, 'JobsRunAuthorizer.app')
    plugin = File.join(app, 'Contents/PlugIns/JobsRunAuthorizerFinderSync.appex')
    [[app, identifier], [plugin, EXTENSION_ID]].each do |bundle, bundle_id|
      FileUtils.mkdir_p(File.join(bundle, 'Contents'))
      File.write(File.join(bundle, 'Contents/Info.plist'), <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>#{bundle_id}</string></dict></plist>
      XML
    end
    app
  end

  def plugin_line(state, path)
    "#{state} #{EXTENSION_ID}(1.0)\tfixture-uuid\t2026-10-20 12:00:00 +0000\t#{path}"
  end

  def helper_checks(records, extra = '')
    <<~ZSH
      EXTENSION_PATH="$JOBS_TEST_EXTENSION"
      APP_PATH="$JOBS_TEST_APP"
      REFRESH_MARKER="$JOBS_TEST_MARKER"
      JOBS_TEST_PLUGIN_RECORDS=#{shell_word(records)}
      #{extra}
      run_enable_flow
    ZSH
  end

  def shell_word(value)
    "'#{value.gsub("'") { "'\\''" }}'"
  end

  def calls
    File.exist?(@calls_path) ? File.readlines(@calls_path, chomp: true) : []
  end

  def run_source(path, checks, records: '', plugin_records: '', input: '', interactive: false, temporary_directory: nil)
    source = File.read(path)
    raise '没有真实 main 入口' unless source.sub!(/^main "\$@"\s*\z/, '')
    REPLACEMENTS.each { |from, to| source = source.gsub(from, to) }
    # 只缩短轮询次数；状态匹配、退出码传播和 marker 逻辑保持原样。
    source = source.gsub('for attempt in {1..90}', 'for attempt in {1..2}')
    fixture = File.join(@directory, 'fixture.zsh')
    File.write(fixture, source + "\n" + fake_commands + "\n" + checks)
    ls_dump = File.join(@directory, 'lsregister-dump')
    File.write(ls_dump, records)
    environment = {
      'NO_COLOR' => '1', 'TMPDIR' => temporary_directory || "#{@directory}/", 'JOBS_TEST_CALLS' => @calls_path,
      'JOBS_TEST_MARKER' => @marker, 'JOBS_TEST_APP' => @app, 'JOBS_TEST_EXTENSION' => @extension,
      'JOBS_TEST_LOG' => File.join(@directory, 'run.log'), 'JOBS_TEST_LS_DUMP' => ls_dump,
      'JOBS_TEST_PLUGIN_RECORDS' => plugin_records
    }
    return Open3.capture2e(environment, '/bin/zsh', '-f', fixture, stdin_data: input) unless interactive

    output = +''
    status = nil
    Timeout.timeout(10) do
      PTY.spawn(environment, '/bin/zsh', '-f', fixture) do |reader, writer, pid|
        writer.write(input)
        begin
          loop { output << reader.readpartial(4096) }
        rescue EOFError, Errno::EIO
          _, status = Process.wait2(pid)
        end
      end
    end
    [output.force_encoding(Encoding::UTF_8), status]
  end

  def fake_commands
    <<~'ZSH'
      jobs_trace() {
        print -r -- "${(j:|:)@}" >> "$JOBS_TEST_CALLS"
      }
      jobs_fake_pluginkit() {
        jobs_trace pluginkit "$@"
        if [[ "$1" == -m ]]; then
          print -r -- "$JOBS_TEST_PLUGIN_RECORDS"
        elif [[ "$1" == -a ]]; then
          return "${JOBS_TEST_REGISTER_RESULT:-0}"
        elif [[ "$1" == -e ]]; then
          return "${JOBS_TEST_ENABLE_RESULT:-0}"
        fi
        return 0
      }
      jobs_fake_lsregister() {
        jobs_trace lsregister "$@"
        if [[ "$1" == -dump ]]; then
          /bin/cat "$JOBS_TEST_LS_DUMP"
        fi
        return 0
      }
      jobs_fake_pkill() { jobs_trace pkill "$@"; }
      jobs_fake_killall() { jobs_trace killall "$@"; return "${JOBS_TEST_REFRESH_RESULT:-0}"; }
      jobs_fake_open() { jobs_trace open "$@"; }
      jobs_fake_xcodebuild() { jobs_trace xcodebuild "$@"; return 99; }
      jobs_fake_xcrun() { jobs_trace xcrun "$@"; return 99; }
      jobs_fake_codesign() { jobs_trace codesign "$@"; return 99; }
      jobs_fake_sleep() { return 0; }
      jobs_fake_rm() {
        jobs_trace rm "$@"
        if [[ "${@: -1}" == "$JOBS_TEST_MARKER" ]]; then
          /bin/rm -f -- "$JOBS_TEST_MARKER"
        fi
        return 0
      }
    ZSH
  end
end
