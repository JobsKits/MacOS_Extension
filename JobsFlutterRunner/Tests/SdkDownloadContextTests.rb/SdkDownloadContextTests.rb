# Created by Jobs. Read-only metadata fixtures; never executes Flutter/Dart or downloads SDKs.
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'shellwords'
require 'json'
require 'timeout'

class SdkDownloadContextTests < Minitest::Test
  ROOT = File.expand_path('../../..', __dir__)
  RUNNERS = %w[JobsFlutterRunner/Scripts/RunFlutterProject.zsh JobsFlutterTools/Scripts/Tools/RunFlutterProject.zsh].freeze
  HELPERS = %w[JobsFlutterRunner/Scripts/FlutterRunner.jxa JobsFlutterTools/Scripts/Tools/FlutterRunner.jxa].freeze
  ENGINE = 'a' * 40
  OLD_ENGINE = 'b' * 40

  def setup
    @tmp = Dir.mktmpdir('jobs-sdk-context-中文')
    @sdk = File.join(@tmp, 'SDK 空格')
    @project = File.join(@tmp, '工程')
    @log = File.join(@tmp, 'run.log')
    @marker = File.join(@tmp, 'SDK-WAS-EXECUTED')
    FileUtils.mkdir_p([File.join(@sdk, 'bin/internal'), File.join(@sdk, 'bin/cache/dart-sdk.old'), @project])
    File.write(File.join(@sdk, 'bin/internal/engine.version'), ENGINE + "\n")
    File.write(File.join(@sdk, 'version'), "3.38.4\n")
    File.write(File.join(@sdk, 'bin/cache/dart-sdk.old/version'), "1.2.3\n")
    File.write(File.join(@project, '.fvmrc'), '{"flutter":"3.38.4"}')
    File.write(File.join(@sdk, 'bin/flutter'), "#!/bin/zsh\n/usr/bin/touch #{@marker.shellescape}\nexit 99\n")
    File.chmod(0o700, File.join(@sdk, 'bin/flutter'))
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def context(index = 0, overrides = {})
    library = File.read(File.join(ROOT, RUNNERS[index])).sub(/\nmain "\$@"\s*\z/, "\n")
    body = <<~SH
      PROJECT_PATH=#{@project.shellescape}
      HELPER=#{File.join(ROOT, HELPERS[index]).shellescape}
      LOG_FILE=#{@log.shellescape}
      show_sdk_download_context #{File.join(@sdk, 'bin/flutter').shellescape} ios
    SH
    Open3.capture3({ 'NO_COLOR' => '1' }.merge(overrides), '/bin/zsh', '-f', '-c', library + body)
  end

  def test_download_context_precedes_execution_and_excludes_old_dart
    RUNNERS.each_index do |index|
      out, err, status = context(index)
      assert status.success?, err
      assert_includes out, '项目声明：Flutter 3.38.4'
      assert_includes out, 'SDK本地身份：Flutter 3.38.4'
      assert_includes out, "SDK根目录：#{File.realpath(@sdk)}"
      assert_match(/下载宿主：Darwin (arm64|x64)/, out)
      assert_includes out, '运行目标：ios'
      assert_includes out, "目标Engine：#{ENGINE}"
      assert_includes out, '目标Dart：版本尚未解析'
      refute_includes out, '1.2.3'
      refute File.exist?(@marker)
      assert_includes File.read(@log), '项目声明：Flutter 3.38.4'
    end
  end

  def test_matching_engine_metadata_identifies_target_dart
    File.write(File.join(@sdk, 'bin/cache/flutter.version.json'), JSON.generate({ frameworkVersion: '3.38.4', engineRevision: ENGINE, dartSdkVersion: '3.10.3' }))
    out, err, status = context
    assert status.success?, err
    assert_includes out, '目标Dart：3.10.3（与目标engine一致的flutter.version.json'
    refute File.exist?(@marker)
  end

  def test_stale_cache_and_unstamped_current_dart_cannot_identify_target
    File.write(File.join(@sdk, 'bin/cache/flutter.version.json'), JSON.generate({ engineRevision: OLD_ENGINE, dartSdkVersion: '2.3.4' }))
    FileUtils.mkdir_p(File.join(@sdk, 'bin/cache/dart-sdk'))
    File.write(File.join(@sdk, 'bin/cache/dart-sdk/version'), "4.5.6\n")
    File.write(File.join(@sdk, 'bin/cache/engine-dart-sdk.stamp'), OLD_ENGINE)
    out, err, status = context
    assert status.success?, err
    assert_includes out, '目标Dart：版本尚未解析'
    refute_includes out, '2.3.4'
    refute_includes out, '4.5.6'
    File.write(File.join(@sdk, 'bin/cache/engine-dart-sdk.stamp'), ENGINE)
    out, err, status = context
    assert status.success?, err
    assert_includes out, '目标Dart：4.5.6（与目标engine一致的当前Dart缓存'
  end

  def test_engine_override_invalidates_metadata_for_the_source_engine
    File.write(File.join(@sdk, 'bin/cache/flutter.version.json'), JSON.generate({ engineRevision: ENGINE, dartSdkVersion: '3.10.3' }))
    out, err, status = context(0, 'FLUTTER_PREBUILT_ENGINE_VERSION' => OLD_ENGINE)
    assert status.success?, err
    assert_includes out, "目标Engine：#{OLD_ENGINE}（当前进程FLUTTER_PREBUILT_ENGINE_VERSION"
    assert_includes out, '目标Dart：版本尚未解析'
  end

  def start_cache_holder(access)
    arch, = Open3.capture2('/usr/sbin/sysctl', '-n', 'hw.optional.arm64')
    archive = File.join(@sdk, "bin/cache/dart-sdk-darwin-#{arch.strip == '1' ? 'arm64' : 'x64'}.zip")
    File.write(archive, 'fixture')
    ready = File.join(@tmp, 'holder-ready')
    release = File.join(@tmp, 'holder-release')
    direction = access == :write ? '>' : '<'
    holder = Process.spawn('/bin/zsh', '-f', '-c', "exec 3#{direction} \"$1\"; : > \"$2\"; while [[ ! -f \"$3\" ]]; do /bin/sleep 0.05; done", 'fixture', archive, ready, release)
    Timeout.timeout(5) { sleep 0.02 until File.exist?(ready) }
    [holder, archive, release]
  end

  def finish_cache_holder(holder, release)
    File.write(release, '')
    Timeout.timeout(5) { Process.wait(holder) }
  rescue Errno::ECHILD
  end

  def runner_command(index, action)
    FileUtils.mkdir_p(File.join(@project, '.fvm'))
    File.symlink(@sdk, File.join(@project, '.fvm/flutter_sdk')) unless File.symlink?(File.join(@project, '.fvm/flutter_sdk'))
    File.write(File.join(@sdk, 'bin/flutter'), "#!/bin/zsh\nprint BOOTSTRAP >> #{@marker.shellescape}\nprint 'Flutter fixture'\n")
    library = File.read(File.join(ROOT, RUNNERS[index])).sub(/\nmain "\$@"\s*\z/, "\n")
    library + <<~SH
      PROJECT_PATH=#{@project.shellescape}
      HELPER=#{File.join(ROOT, HELPERS[index]).shellescape}
      LOG_FILE=#{@log.shellescape}
      # Exercise real writer gating/bootstrap wrappers; networking belongs to separate fixtures.
      jobs_flutter_route_prepare() { return 0; }
      jfs_route_curl() { print -u2 'unexpected network fixture'; return 99; }
      #{action}
    SH
  end

  def read_until_waiting(output)
    captured = ''.b
    Timeout.timeout(10) do
      until captured.include?('等待同一SDK已有下载'.b)
        captured << output.readpartial(4096)
      end
    end
    captured
  end

  def test_existing_writer_is_waited_for_then_only_one_bootstrap_runs
    holder, _archive, release = start_cache_holder(:write)
    Open3.popen3('/bin/zsh', '-f', '-c', runner_command(0, 'find_flutter')) do |input, output, errors, process|
      input.close
      begin
      first = read_until_waiting(output)
      assert first.index('项目声明：Flutter 3.38.4'.b) < first.index('等待同一SDK已有下载'.b)
      refute File.exist?(@marker)
      finish_cache_holder(holder, release)
      status = Timeout.timeout(10) { process.value }
      assert status.success?, errors.read.b + first + output.read.b
      assert_equal ["BOOTSTRAP\n"], File.readlines(@marker)
      ensure
        finish_cache_holder(holder, release)
        Process.kill('TERM', process.pid) if process.alive?
      end
    end
  ensure
    finish_cache_holder(holder, release) if holder
  end

  def test_wait_cancel_keeps_existing_writer_alive_and_never_bootstraps
    holder, _archive, release = start_cache_holder(:write)
    Open3.popen3('/bin/zsh', '-f', '-c', runner_command(1, 'find_flutter')) do |input, output, errors, process|
      input.close
      begin
      read_until_waiting(output)
      Process.kill('INT', process.pid)
      status = Timeout.timeout(5) { process.value }
      assert_equal 130, status.exitstatus, errors.read
      refute File.exist?(@marker)
      assert_equal 1, Process.kill(0, holder)
      ensure
        finish_cache_holder(holder, release)
        Process.kill('TERM', process.pid) if process.alive?
      end
    end
  ensure
    finish_cache_holder(holder, release) if holder
  end

  def test_read_only_handle_is_not_a_writer
    holder, archive, release = start_cache_holder(:read)
    action = "sdk_archive_writers #{archive.shellescape}; print -r -- \"WRITERS=${#SDK_ARCHIVE_WRITERS}\""
    out, err, status = Open3.capture3('/bin/zsh', '-f', '-c', runner_command(0, action))
    assert status.success?, err
    assert_includes out, 'WRITERS=0'
    refute File.exist?(@marker)
  ensure
    finish_cache_holder(holder, release) if holder
  end

  def test_explicit_git_identity_has_priority_over_an_old_local_version_record
    File.write(File.join(@sdk, 'version'), '1.9.9')
    out, err, status = Open3.capture3('/usr/bin/osascript', '-l', 'JavaScript', File.join(ROOT, HELPERS.first), 'sdk-download-context', @sdk, '3.38.4', '3.38.4', 'c' * 40, 'Darwin arm64', '', '')
    assert status.success?, err
    assert_includes out, 'SDK本地身份：Flutter 3.38.4（Git HEAD精确tag）'
    refute_includes out, '1.9.9'
  end
end
