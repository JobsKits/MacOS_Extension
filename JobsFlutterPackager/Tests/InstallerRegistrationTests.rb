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
  INSTALLER = File.join(ROOT, 'Scripts/ManageExtension.zsh')
  UNINSTALLER = File.join(ROOT, 'Scripts/ManageExtension.zsh')
  HELPER = File.join(ROOT, 'Scripts/EnableFinderExtension.zsh')
  APP_ID = 'com.jobs.JobsFlutterPackager'
  EXTENSION_ID = "#{APP_ID}.findersync"
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
    @directory = Dir.mktmpdir('jobs-packager-registration-')
    @calls_path = File.join(@directory, 'calls')
    @marker = File.join(@directory, 'refresh-marker')
    @app = create_app('新 path', APP_ID)
    @extension = File.join(@app, 'Contents/PlugIns/JobsFlutterPackagerFinderSync.appex')
    @old_app = create_app('old', APP_ID)
    @old_extension = File.join(@old_app, 'Contents/PlugIns/JobsFlutterPackagerFinderSync.appex')
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

  def test_manager_install_forwards_only_the_three_packaging_actions
    output, status = run_alias('install')
    assert status.success?, output
    assert_includes output, 'forward:--action|install|--features|package-ios,package-android,package-ohos|--non-interactive'
    assert_empty calls
  end

  def test_manager_uninstall_forwards_the_same_actions_and_preserves_other_flutter_menus
    output, status = run_alias('uninstall', args: ['--skip-finder-restart'])
    assert status.success?, output
    assert_includes output, 'forward:--action|uninstall|--features|package-ios,package-android,package-ohos|--non-interactive|--skip-finder-restart'
    assert_empty calls
  end

  def test_manager_propagates_the_aggregate_failure
    output, status = run_alias('install', exit_status: 7)
    assert_equal 7, status.exitstatus, output
    assert_empty calls
  end

def test_manager_non_tty_opens_gui_without_installing
  source = File.read(INSTALLER).sub(/^manager_main "\$@"\s*\z/, '')
  source += <<~'ZSH'
    manager_open_gui() { print -r -- OPEN_GUI; }
    run_install_operation() { return 99; }
    run_uninstall_operation() { return 99; }
    manager_main --action install
  ZSH
  output, status = Open3.capture2e('/bin/zsh', '-c', source, INSTALLER)
  assert status.success?, output
  assert_includes output, 'OPEN_GUI'
  assert_empty calls
end


  def test_manager_rejects_unknown_options_before_forwarding
    output, status = run_alias('install', args: ['--unexpected'])
    assert_equal 2, status.exitstatus, output
    refute_includes output, 'forward:'
    assert_empty calls
  end

  private

  def run_alias(operation, exit_status: 0, args: [])
    leaf = File.join(@directory, 'JobsFlutterPackager')
    aggregate = File.join(@directory, 'JobsFlutterTools')
    FileUtils.mkdir_p([leaf, aggregate])
    entry = File.join(leaf, 'Scripts/ManageExtension.zsh')
    target = File.join(aggregate, 'Scripts/ManageExtension.zsh')
    FileUtils.mkdir_p(File.dirname(entry))
    FileUtils.cp(INSTALLER, entry)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, "#!/bin/zsh\nprint -r -- \"forward:${(j:|:)@}\"\nexit #{exit_status}\n")
    Open3.capture2e('/bin/zsh', entry, '--action', operation, '--non-interactive', *args)
  end

  def create_app(parent, identifier)
    app = File.join(@directory, parent, 'JobsFlutterPackager.app')
    plugin = File.join(app, 'Contents/PlugIns/JobsFlutterPackagerFinderSync.appex')
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

  def run_source(path, checks, records: '', plugin_records: '', input: '', interactive: false)
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
      'NO_COLOR' => '1', 'TMPDIR' => "#{@directory}/", 'JOBS_TEST_CALLS' => @calls_path,
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
