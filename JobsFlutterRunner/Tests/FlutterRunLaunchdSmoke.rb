# Created by Jobs on 2026年10月20日，星期二.
# 隔离集成验证：只创建临时 launchd 任务与假 Flutter，不注册 Finder、不构建业务项目。
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

require 'tmpdir'
require 'fileutils'
require 'open3'
require 'digest'
require 'json'
require 'timeout'

runtime = File.expand_path('../Scripts/RunFlutterProject.zsh', __dir__)
temporary = File.realpath(Dir.mktmpdir('jobs-flutter-launchd-'))
project = File.join(temporary, "项目 空格 ' $(literal)")
home = File.join(temporary, 'home')
bin = File.join(temporary, 'bin')
FileUtils.mkdir_p([project, home, bin])
FileUtils.mkdir_p(File.join(project, 'android'))
File.write(File.join(project, 'pubspec.yaml'), "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n")
mock = File.join(bin, 'flutter')
File.write(mock, <<~'ZSH')
  #!/bin/zsh
  case "$1" in
    --version) print '{"frameworkVersion":"fixture"}'; exit 0 ;;
    devices) print '[{"id":"mock-device","name":"模拟设备","targetPlatform":"android-arm64","supported":true}]'; exit 0 ;;
    run)
      [[ "$*" == 'run --machine -d mock-device' ]] || exit 71
      print '[{"event":"app.start","params":{"appId":"smoke-app"}}]'
      while true; do
        if IFS= read -r -t 1 message; then
          if [[ "$message" == *'app.stop'* ]]; then
            print 'SMOKE_STOPPED'
            exit 0
          fi
          [[ "$message" != *'app.restart'* ]] || print 'SMOKE_RELOADED'
        fi
        print 'SMOKE_HEARTBEAT'
      done
      ;;
    *) exit 72 ;;
  esac
ZSH
FileUtils.chmod(0o700, mock)
digest = Digest::SHA256.hexdigest(project + "\0mock-device")
label = "com.jobs.flutterrunner.#{digest}"
target = "gui/#{Process.uid}/#{label}"
session = File.join(home, 'Library/Application Support/JobsFlutterRunner/sessions', digest)
environment = { 'HOME' => home, 'PATH' => "#{bin}:/usr/bin:/bin:/usr/sbin:/sbin", 'NO_COLOR' => '1' }

begin
  out, err, result = Open3.capture3(environment, '/bin/zsh', runtime, '--project', project, stdin_data: "\n1\nd\n")
  raise "启动入口失败：#{out}\n#{err}" unless result.success?
  raise '任务未注册到 launchd' unless system('/bin/launchctl', 'print', target, out: File::NULL, err: File::NULL)
  30.times do
    break if File.exist?(File.join(session, 'run.log')) && File.read(File.join(session, 'run.log')).include?('SMOKE_HEARTBEAT')
    sleep 0.1
  end
  before = File.size(File.join(session, 'run.log'))
  sleep 1.2
  raise '入口退出后后台日志未继续增长' unless File.size(File.join(session, 'run.log')) > before
  # HUP 对应关闭终端的断连；只终止本次日志入口，launchd 持有的 worker 必须继续。
  Open3.popen3(environment, '/bin/zsh', runtime, '--project', project) do |input, output, errors, process|
    captured = ''
    reader = Thread.new { captured << output.read }
    input.write("\n1\n")
    input.flush
    sleep 2.5
    Process.kill('HUP', process.pid)
    input.close
    Timeout.timeout(10) { process.value; reader.join }
    raise "HUP 入口异常：#{captured}\n#{errors.read}" unless process.value.success?
  end
  before = File.size(File.join(session, 'run.log'))
  sleep 1.2
  raise '终端 HUP 后后台日志未继续增长' unless File.size(File.join(session, 'run.log')) > before
  # 模拟 worker 意外崩溃，没有 exitcode 标记时也必须允许重新启动。
  raise '无法注入隔离 worker 崩溃' unless system('/bin/launchctl', 'kill', 'SIGKILL', target)
  30.times do
    current, = Open3.capture2('/bin/launchctl', 'print', target)
    break unless current.match?(/^\s*pid = [1-9]/)
    sleep 0.1
  end
  out, err, result = Open3.capture3(environment, '/bin/zsh', runtime, '--project', project, stdin_data: "\n1\nd\n")
  raise "失效任务无法重启：#{out}\n#{err}" unless result.success? && out.include?('后台任务已提交')
  sleep 0.5
  out, err, result = Open3.capture3(environment, '/bin/zsh', runtime, '--project', project, stdin_data: "\n1\nr\ns\n")
  raise "重连 / 停止失败：#{out}\n#{err}" unless result.success?
  raw = File.read(File.join(session, 'run.log'))
  raise '热重载协议未到达 Flutter' unless raw.include?('SMOKE_RELOADED')
  raise '停止协议未到达 Flutter' unless raw.include?('SMOKE_STOPPED')
  raise '退出码记录错误' unless File.read(File.join(session, 'exitcode')).strip == '0'
  raise '停止后 launchd 任务仍存在' if system('/bin/launchctl', 'print', target, out: File::NULL, err: File::NULL)
  puts 'PASS: launchd 托管、退出及 HUP 后存活、日志增长、崩溃后重启、重连、热重载和停止；特殊路径按数据传递。'
ensure
  system('/bin/launchctl', 'bootout', target, out: File::NULL, err: File::NULL)
  FileUtils.remove_entry(temporary)
end
