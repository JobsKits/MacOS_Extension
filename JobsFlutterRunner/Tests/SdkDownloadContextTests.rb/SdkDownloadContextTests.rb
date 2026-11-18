# Created by Jobs. Read-only metadata fixtures; never executes Flutter/Dart or downloads SDKs.
# JOBS_TERMINAL_STYLE_GUARD_V1_BEGIN
if $PROGRAM_NAME == __FILE__
  # 直接运行时由 fork 父进程保护配色；子进程继续原文件，不重放 Ruby 参数和预载模块。
  def jobs_terminal_style_bootstrap_v1
    return unless $PROGRAM_NAME == __FILE__
    plain = lambda do
      ENV.update('PLAIN_OUTPUT' => '1', 'NO_COLOR' => '1', 'FORCE_COLOR' => '0',
                 'CLICOLOR' => '0', 'ANSI_COLORS_DISABLED' => '1', 'npm_config_color' => 'false')
    end
    notify = lambda do |message|
      encoding = $stderr.external_encoding || Encoding::UTF_8
      $stderr.write((message + "\n").encode(encoding, invalid: :replace, undef: :replace))
    end
    return unless $stdin.tty? && $stdout.tty?
    return if ENV.key?('NO_COLOR') || ENV['PLAIN_OUTPUT'] == '1' ||
              ENV['IS_SOURCETREE_RUNTIME'] == '1' ||
              ENV.keys.any? { |key| key.match?(/\A(?:SOURCETREE|SOURCE_TREE)/i) }
    return if ['', 'dumb'].include?(ENV.fetch('TERM', ''))
    if File::ALT_SEPARATOR == '\\' || !Process.respond_to?(:fork) ||
       Thread.list.length > 1 || ENV['TMUX'] || ENV['STY']
      plain.call
      return
    end
    tty_name = IO.popen(['tty'], err: File::NULL, &:read).strip
    groups = IO.popen(['ps', '-o', 'pgid=', '-o', 'tpgid=', '-p', Process.pid.to_s], err: File::NULL, &:read).split
    unless tty_name.match?(%r{\A/dev/[A-Za-z0-9_./-]+\z}) && groups.length == 2 &&
           groups.all? { |group| group.match?(/\A\d+\z/) } && groups[0].to_i > 0 && groups[0] == groups[1]
      plain.call
      return
    end
    owner = ENV['JOBS_TERMINAL_STYLE_OWNER']
    if ENV['JOBS_TERMINAL_STYLE_TTY'] == tty_name && owner && owner.match?(/\A\d+\z/)
      begin
        Process.kill(0, owner.to_i)
        return
      rescue Errno::ESRCH, Errno::EPERM
      end
    end
    require 'io/console'
    require 'tmpdir'
    if Thread.list.length > 1
      plain.call
      return
    end
    tty = File.open('/dev/tty', 'r+')
    tty.binmode
    tty.sync = true
    keys = ['10', '11', '12'] + (0..15).map { |index| "4;#{index}" }
    palette = %w[000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee
                 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff]
    targets = { '10' => 'ffffff', '11' => '000000', '12' => 'ffffff' }
    palette.each_with_index { |color, index| targets["4;#{index}"] = color }
    query = lambda do |key|
      tty.write("\e]#{key};?\a")
      bytes = ''.b
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.3
      loop do
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return nil if remaining <= 0 || !IO.select([tty], nil, nil, remaining)
        piece = tty.read_nonblock(256, exception: false)
        next if piece == :wait_readable
        return nil unless piece && !piece.empty?
        bytes << piece
        return nil if bytes.bytesize > 256 || !bytes.start_with?("\e".b)
        break if bytes.end_with?("\a".b) || bytes.end_with?("\e\\".b)
      end
      match = bytes.match(/\A\e\]#{Regexp.escape(key)};rgb:([0-9a-fA-F]{1,4})\/([0-9a-fA-F]{1,4})\/([0-9a-fA-F]{1,4})(?:\a|\e\\)\z/n)
      return nil unless match
      components = match.captures.map { |hex| (hex.to_i(16) * 65535.0 / (16**hex.length - 1)).round }
      { raw: bytes, rgb: components }
    rescue IOError, SystemCallError
      nil
    end
    snapshot = lambda do
      values = {}
      tty.raw(min: 0, time: 0, intr: true) do
        keys.each do |key|
          value = query.call(key)
          return nil unless value
          values[key] = value
        end
      end
      values
    rescue IOError, SystemCallError, ArgumentError
      nil
    end
    original = snapshot.call
    unless original
      notify.call('终端不支持完整配色保存，或启动时收到其它输入；保留原配色并使用纯文本。')
      tty.close
      plain.call
      return
    end
    directory = Dir.mktmpdir('jobs-terminal-style-')
    recovery = File.join(directory, 'restore.sh')
    original_bytes = keys.map { |key| original.fetch(key).fetch(:raw) }.join
    recovery_source = "#!/bin/sh\n" \
      "[ -t 0 ] && [ \"$(tty)\" = '#{tty_name}' ] || { printf '请在原终端运行恢复入口。\\n' >&2; exit 1; }\n" \
      "printf '本操作会覆盖此终端当前配色。确认恢复脚本启动前的配色，请输入 YES：' >&2\n" \
      "IFS= read -r jobs_restore_choice\n[ \"$jobs_restore_choice\" = YES ] || exit 1\n" \
      "printf '%s\\033[0m' '#{original_bytes}' > /dev/tty\n"
    File.open(recovery, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.binmode
      file.write(recovery_source.b)
    end
    notify.call("本次终端临时使用黑底白字；强退后恢复入口：sh \"#{recovery}\"")
    changed = false
    applied = nil
    # 比较仍生效的本轮颜色，只恢复未被用户另行修改的项。
    cleanup = lambda do
      current = applied && snapshot.call
      unless current
        notify.call("终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh \"#{recovery}\"")
        return false
      end
      conflicts = []
      restore_bytes = ''.b
      keys.each do |key|
        if current.fetch(key).fetch(:rgb) == applied.fetch(key).fetch(:rgb)
          restore_bytes << original.fetch(key).fetch(:raw)
        else
          conflicts << key
        end
      end
      tty.write(restore_bytes + "\e[0m".b)
      if conflicts.empty?
        File.unlink(recovery)
        Dir.rmdir(directory)
        true
      else
        notify.call("检测到运行期间的配色变更，已保留这些项：#{conflicts.join(' ')}")
        notify.call("确认要覆盖后续改色时才使用恢复入口：sh \"#{recovery}\"")
        false
      end
    rescue IOError, SystemCallError
      notify.call("终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh \"#{recovery}\"")
      false
    end
    child_pid = nil
    guardian = false
    interrupted = nil
    previous_signals = {}
    %w[INT TERM HUP].each do |name|
      previous_signals[name] = Signal.trap(name) do
        interrupted = name
        if child_pid && name != 'INT'
          begin
            Process.kill(name, child_pid)
          rescue Errno::ESRCH
          end
        end
      end
    end
    begin
      changed = true
      tty.write(targets.map { |key, color| "\e]#{key};##{color}\a" }.join + "\e[0m")
      applied = snapshot.call
      unless applied
        notify.call('无法核实本次临时配色，已停止启动业务。')
        raise SystemExit, 1
      end
      desired = targets.all? do |key, hex|
        rgb = hex.scan(/../).map { |component| component.to_i(16) * 257 }
        applied.fetch(key).fetch(:rgb).zip(rgb).all? { |actual, expected| (actual - expected).abs <= 255 }
      end
      unless desired
        notify.call('终端未接受本次配色，恢复后使用纯文本。')
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      if interrupted
        raise SystemExit, 128 + Signal.list.fetch(interrupted)
      end
      if Thread.list.length > 1
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      $stdout.flush
      $stderr.flush
      begin
        child_pid = Process.fork
      rescue NotImplementedError, SystemCallError
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      unless child_pid
        changed = false
        ENV['JOBS_TERMINAL_STYLE_TTY'] = tty_name
        ENV['JOBS_TERMINAL_STYLE_OWNER'] = Process.ppid.to_s
        raise SystemExit, 128 + Signal.list.fetch(interrupted) if interrupted
        return
      end
      guardian = true
      result = nil
      loop do
        begin
          _, result = Process.wait2(child_pid)
          break
        rescue Interrupt, Errno::EINTR
        end
      end
      status_code = result.exitstatus || 128 + result.termsig
      %w[INT TERM HUP].each { |name| Signal.trap(name, 'IGNORE') }
      restored = cleanup.call
      changed = false
      status_code = 1 if !restored && status_code.zero?
      tty.close
      Process.exit!(status_code)
    ensure
      if changed
        %w[INT TERM HUP].each { |name| Signal.trap(name, 'IGNORE') }
        cleanup.call
      end
      previous_signals.each { |name, handler| Signal.trap(name, handler) } unless guardian
      tty.close unless tty.closed?
    end
  rescue IOError, SystemCallError, LoadError => error
    if guardian
      notify.call("终端保护监督进程异常：#{error.message}")
      Process.exit!(1)
    end
    raise SystemExit, 1 if changed
    notify.call("终端保护不可用，使用纯文本：#{error.message}")
    plain.call
  end
  jobs_terminal_style_bootstrap_v1

end
# JOBS_TERMINAL_STYLE_GUARD_V1_END

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'shellwords'
require 'json'
require 'timeout'

require_relative '../../../Tests/SourceLayoutHelper.rb/SourceLayoutHelper'

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
    @manifest = File.join(@tmp, 'official.json')
    @fetches = File.join(@tmp, 'metadata-fetches.log')
    @official_hash = 'c' * 40
    File.write(@manifest, JSON.generate({ current_release: { stable: @official_hash }, releases: %w[arm64 x64].map do |arch|
      { channel: 'stable', hash: @official_hash, version: '3.50.0', dart_sdk_version: '3.13.0', dart_sdk_arch: arch, release_date: '2026-11-12T12:00:00Z' }
    end }))
    @path_sdk = File.join(@tmp, 'PATH SDK')
    FileUtils.mkdir_p(File.join(@path_sdk, 'bin/internal'))
    File.write(File.join(@path_sdk, 'version'), '3.49.2')
    File.write(File.join(@path_sdk, 'bin/internal/engine.version'), OLD_ENGINE)
    File.write(File.join(@path_sdk, 'bin/internal/dart-sdk.version'), '3.12.1')
    File.write(File.join(@path_sdk, 'bin/flutter'), "#!/bin/zsh\n/usr/bin/touch #{@marker.shellescape}\nexit 99\n")
    File.chmod(0o700, File.join(@path_sdk, 'bin/flutter'))
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def context(index = 0, overrides = {})
    library = File.read(JobsSourceLayout.file(File.join(ROOT, RUNNERS[index]))).sub(/\nmain "\$@"\s*\z/, "\n")
    body = <<~SH
      PROJECT_PATH=#{@project.shellescape}
      HELPER=#{JobsSourceLayout.file(File.join(ROOT, HELPERS[index])).shellescape}
      LOG_FILE=#{@log.shellescape}
      hash flutter=#{File.join(@path_sdk, 'bin/flutter').shellescape}
      fetch_sdk_official_metadata() {
        print -r -- "$1 $3" >> #{@fetches.shellescape}
        [[ "${JOBS_TEST_OFFICIAL_FAILURE:-0}" == 0 ]] || return "$JOBS_TEST_OFFICIAL_FAILURE"
        if [[ "$1" == *releases_macos.json* ]]; then
          /bin/cp #{@manifest.shellescape} "$2"
        else
          [[ "${JOBS_TEST_OFFICIAL_ENGINE_FAILURE:-0}" == 0 ]] || return "$JOBS_TEST_OFFICIAL_ENGINE_FAILURE"
          print -r -- #{('d' * 40).shellescape} > "$2"
        fi
      }
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

  def test_official_path_and_project_versions_remain_three_distinct_read_only_sources
    RUNNERS.each_index do |index|
      out, err, status = context(index)
      assert status.success?, err
      assert_includes out, 'SDK下载上下文（官网 / 本机 / 工程 FVM 对照）'
      assert_includes out, '官网当前最新 stable：Flutter 3.50.0 / Dart 3.13.0 / Engine ' + 'd' * 40
      assert_includes out, '官网发布日期：2026-11-12T12:00:00Z；本次查询时间：'
      assert_includes out, '官网来源：https://docs.flutter.dev/install/archive'
      assert_includes out, '本机系统：macOS '
      assert_includes out, '本机 PATH 工具发现（只读，未运行验收）：'
      assert_includes out, '  git：'
      assert_includes out, '本机 PATH Flutter：Flutter 3.49.2'
      assert_includes out, "本机 PATH Engine / Dart：#{OLD_ENGINE} / 3.12.1"
      assert_includes out, '工程 FVM 铆订：3.38.4'
      assert_includes out, 'SDK本地身份：Flutter 3.38.4'
      refute File.exist?(@marker), '版本对照不能执行项目或PATH Flutter入口'
      assert_equal '{"flutter":"3.38.4"}', File.read(File.join(@project, '.fvmrc'))
    end
    assert_equal 4, File.readlines(@fetches).length
    assert_match(/releases_macos\.json\?alt=media 4/, File.readlines(@fetches).first)
    assert_includes File.readlines(@fetches)[1], "#{@official_hash}/bin/internal/engine.version 3"
  end

  def test_failed_official_query_does_not_reuse_a_previous_success_as_current
    context
    out, err, status = context(0, 'JOBS_TEST_OFFICIAL_FAILURE' => '28')
    assert status.success?, err
    assert_includes out, '官网当前最新 stable：未知（本次官方查询失败或超时（退出码 28）'
    refute_includes out, '官网当前最新 stable：Flutter 3.50.0'
    assert_includes out, '本机 PATH Flutter：Flutter 3.49.2'
    assert_includes out, '项目声明：Flutter 3.38.4'
    refute File.exist?(@marker)
  end

  def test_malformed_official_current_pointer_is_unknown_not_the_last_release
    manifest = JSON.parse(File.read(@manifest))
    manifest['current_release']['stable'] = 'e' * 40
    File.write(@manifest, JSON.generate(manifest))
    out, err, status = context
    assert status.success?, err
    assert_includes out, '官网当前最新 stable：未知'
    refute_includes out, '官网当前最新 stable：Flutter 3.50.0'
    assert_equal 1, File.readlines(@fetches).length
  end

  def test_failed_official_engine_query_keeps_known_release_and_marks_only_engine_unknown
    out, err, status = context(0, 'JOBS_TEST_OFFICIAL_ENGINE_FAILURE' => '28')
    assert status.success?, err
    assert_includes out, '官网当前最新 stable：Flutter 3.50.0 / Dart 3.13.0 / Engine 未知'
    assert_includes out, "目标Engine：#{ENGINE}"
    refute File.exist?(@marker)
  end

  def test_harmony_sdk_cannot_be_presented_as_the_official_flutter_stable_line
    FileUtils.mkdir_p(File.join(@sdk, 'packages/flutter_tools/lib/src/ohos'))
    out, err, status = context
    assert status.success?, err
    assert_includes out, '鸿蒙适配发行线当前最新：未知（独立发行渠道'
    assert_includes out, '不能替代鸿蒙适配版本'
    refute File.exist?(@marker)
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
    File.write(File.join(@sdk, 'bin/flutter'), "#!/bin/zsh\n[[ \"$1\" != --version ]] || print BOOTSTRAP >> #{@marker.shellescape}\nprint 'Flutter fixture'\n")
    library = File.read(JobsSourceLayout.file(File.join(ROOT, RUNNERS[index]))).sub(/\nmain "\$@"\s*\z/, "\n")
    library + <<~SH
      PROJECT_PATH=#{@project.shellescape}
      HELPER=#{JobsSourceLayout.file(File.join(ROOT, HELPERS[index])).shellescape}
      LOG_FILE=#{@log.shellescape}
      # Exercise real writer gating/bootstrap wrappers; networking belongs to separate fixtures.
      jobs_flutter_route_prepare() { return 0; }
      jfs_route_curl() { print -u2 'unexpected network fixture'; return 99; }
      fetch_sdk_official_metadata() { return 99; }
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
      remaining = Thread.new { output.read }
      error_text = Thread.new { errors.read }
      status = Timeout.timeout(10) { process.value }
      assert status.success?, error_text.value.b + first + remaining.value.b
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
    out, err, status = Open3.capture3('/usr/bin/osascript', '-l', 'JavaScript', JobsSourceLayout.file(File.join(ROOT, HELPERS.first)), 'sdk-download-context', @sdk, '3.38.4', '3.38.4', 'c' * 40, 'Darwin arm64', '', '')
    assert status.success?, err
    assert_includes out, 'SDK本地身份：Flutter 3.38.4（Git HEAD精确tag）'
    refute_includes out, '1.9.9'
  end
def test_fvm_channel_alias_is_not_reported_as_an_explicit_version_mismatch
  %w[stable beta master].each do |channel|
    File.write(File.join(@project, '.fvmrc'), JSON.generate({ flutter: channel }))
    [0, 1].each do |index|
      out, err, status = context(index)
      assert status.success?, err
      assert_includes out, channel
      refute_includes out, '项目声明与SDK本地版本不同'
    end
  end
  File.write(File.join(@project, '.fvmrc'), '{"flutter":"3.0.0"}')
  out, err, status = context(0)
  assert status.success?, err
  assert_includes out, '项目声明与SDK本地版本不同'
end

end
