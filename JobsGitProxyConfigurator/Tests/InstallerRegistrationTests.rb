# frozen_string_literal: true
# 用系统命令替身验证真实安装脚本；只在临时夹具中读写，不注册扩展或刷新 Finder。

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
  APP_ID = 'com.jobs.gitproxyconfigurator'
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
    @directory = Dir.mktmpdir('jobs-simulator-registration-')
    @calls_path = File.join(@directory, 'calls')
    @marker = File.join(@directory, 'refresh-marker')
    @app = create_app('新 path', APP_ID)
    @extension = File.join(@app, 'Contents/PlugIns/JobsGitProxyFinderSync.appex')
    @old_app = create_app('old', APP_ID)
    @old_extension = File.join(@old_app, 'Contents/PlugIns/JobsGitProxyFinderSync.appex')
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

  def test_manager_forwards_only_the_selected_menu_and_restart_policy
    %w[install uninstall].each do |operation|
      directory = File.join(@directory, 'JobsGitProxyConfigurator')
      group = File.join(@directory, 'JobsProjectTools', 'Scripts')
      FileUtils.mkdir_p([directory, group])
      entry = File.join(directory, 'Scripts/ManageExtension.zsh')
      FileUtils.mkdir_p(File.dirname(entry))
      FileUtils.cp(INSTALLER, entry)
      target = File.join(group, 'ManageProjectTools.zsh')
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, "#!/bin/zsh\nprint -r -- \"forward:${(j:|:)@}|restart=$JOBS_SKIP_FINDER_RESTART\"\n")
      output, status = Open3.capture2e('/bin/zsh', entry, '--action', operation, '--non-interactive', '--skip-finder-restart')
      assert status.success?, output
      assert_includes output, "forward:#{operation}|git-proxy-configure|restart=1"
      assert_empty calls
    end
  end

def test_group_manager_non_tty_opens_gui_without_installing
  entry = File.join(ROOT, '..', 'JobsProjectTools', 'Scripts/ManageExtension.zsh')
  source = File.read(entry).sub(/^manager_main "\$@"\s*\z/, '')
  source += <<~'ZSH'
    manager_open_gui() { print -r -- OPEN_GUI; }
    run_install_operation() { return 99; }
    run_uninstall_operation() { return 99; }
    manager_main --action install --features git-proxy-configure
  ZSH
  output, status = Open3.capture2e('/bin/zsh', '-c', source, entry)
  assert status.success?, output
  assert_includes output, 'OPEN_GUI'
  assert_empty calls
end


  private

  def create_app(parent, identifier)
    app = File.join(@directory, parent, 'JobsGitProxyConfigurator.app')
    plugin = File.join(app, 'Contents/PlugIns/JobsGitProxyFinderSync.appex')
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
