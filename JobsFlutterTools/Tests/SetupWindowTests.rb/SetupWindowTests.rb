# frozen_string_literal: true
# Jobs：真实 WKWebView + PTY + fzf，全部业务均为临时脚本，不安装或下载 SDK。
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
require 'json'

require_relative '../../../Tests/SourceLayoutHelper.rb/SourceLayoutHelper'

class SetupWindowTests < Minitest::Test
  ROOT = File.expand_path('..', File.dirname(__dir__))
  def test_real_embedded_terminal_fzf_input_resize_events_and_complete_private_log
    source = File.read(JobsSourceLayout.file(File.join(ROOT, 'Scripts/Tools/SetupProjectWindow.swift'))).split('if CommandLine.arguments.count == 5').first
    fzf = ['/opt/homebrew/bin/fzf', '/usr/local/bin/fzf'].find { |path| File.executable?(path) }
    refute_nil fzf, 'native fzf is required for the embedded terminal interaction test'
    Dir.mktmpdir('jobs-setup-window-test-') do |directory|
      directory = File.realpath(directory)
      tools = File.join(directory, 'Tools')
      FileUtils.mkdir_p(tools)
      FileUtils.cp_r(JobsSourceLayout.file(File.join(ROOT, 'Scripts/Tools/SetupGUIAssets')), tools)
      JobsSourceLayout.copy(JobsSourceLayout.file(File.join(ROOT, 'Scripts/Tools/SetupVersion.json')), tools)
      File.write(File.join(tools, 'SetupFlutterProject.zsh'), <<~ZSH)
        #!/bin/zsh
        [[ -t 0 && -t 1 ]] || exit 91
        print -r -- '{"id":"flutter","title":"Flutter SDK","state":"running","message":"请选择","version":"Flutter 3.47.8 · Dart 3.13.7"}' >> "$JOBS_FLUTTER_SETUP_EVENTS"
        print -r -- '{"id":"platforms.android.sdk","parent":"platforms.android","title":"Android SDK","state":"attention","message":"fixture","version":"API 36 · Build-tools 36.0.0"}' >> "$JOBS_FLUTTER_SETUP_EVENTS"
        print -r -- FZF_READY
        selected="$(print -l first second | #{fzf} --height=8 --layout=reverse --no-sort --prompt='SDK > ')" || exit 92
        print -r -- "SELECTION:$selected"
        print -r -- INPUT_READY
        IFS= read -r answer || exit 93
        print -r -- "LITERAL:$answer"
        stty size
        print -r -- '{"id":"flutter","title":"Flutter SDK","state":"succeeded"}' >> "$JOBS_FLUTTER_SETUP_EVENTS"
        print -r -- 'RAW_COMPLETE_最后一行'
      ZSH
      harness = <<~'SWIFT'
        extension SetupProjectWindow {
            func verifyEmbeddedTerminal() throws {
                applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
                guard heading.stringValue == "Flutter 项目配置", projectLabel.stringValue == URL(fileURLWithPath: project).lastPathComponent,
                      split.subviews[0].frame.height <= 80, web.frame.height > split.bounds.height * 0.75 else { fatalError("Title/project must be separate and initial milestones must stay compact") }
                update(SetupEvent(id: "flutter.download", parent: "flutter", title: "下载 SDK", state: "running", message: nil))
                window.contentView!.layoutSubtreeIfNeeded()
                var counts = Set<Int>()
                var cycledToZero = false
                let animationDeadline = Date().addingTimeInterval(2.5)
                let originalStatusFrame = statusLabels["flutter.download"]!.frame
                while Date() < animationDeadline {
                    let text = statusLabels["flutter.download"]!.stringValue
                    let count = text.reversed().prefix(while: { $0 == "." }).count
                    if counts.contains(5), count == 0 { cycledToZero = true }
                    counts.insert(count)
                    _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.04))
                }
                guard counts == Set(0...5), cycledToZero,
                      statusLabels["flutter.download"]!.frame.size == originalStatusFrame.size,
                      labels["flutter"]?.stringValue == "Flutter SDK",
                      split.subviews[0].frame.height < 200 else { fatalError("Running dots must cycle 0...5 without title/layout jitter or large blank area: counts=\(counts), reset=\(cycledToZero), status=\(statusLabels["flutter.download"]!.frame) / \(originalStatusFrame), title=\(labels["flutter"]!.stringValue), height=\(split.subviews[0].frame.height)") }
                update(SetupEvent(id: "flutter.download", parent: "flutter", title: "下载 SDK", state: "failed", message: nil))
                guard statusLabels["flutter.download"]?.stringValue.hasSuffix("失败") == true else { fatalError("Stopped nodes must immediately clear animated dots") }
                print("PASS: separate titles, compact content height, stable 0...5 looping dots and stopped-node cleanup")
                var sentChoice = false
                var sentLiteral = false
                var choiceReadyAt: Date?
                var originalRows = 0
                var draggedRows = 0
                let deadline = Date().addingTimeInterval(25)
                while Date() < deadline && !finished {
                    _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                    let text = String(decoding: (try? Data(contentsOf: session.appendingPathComponent("terminal.raw.log"))) ?? Data(), as: UTF8.self)
                    if text.contains("FZF_READY"), choiceReadyAt == nil { choiceReadyAt = Date() }
                    if let ready = choiceReadyAt, Date().timeIntervalSince(ready) > 0.5, !sentChoice {
                        sentChoice = true
                        // Directly use an encoded JSON value to preserve raw key bytes through JS.
                        let data = try JSONSerialization.data(withJSONObject: ["type": "input", "data": "\u{1b}[B\r"])
                        let json = String(decoding: data, as: UTF8.self)
                        web.evaluateJavaScript("window.webkit.messageHandlers.pty.postMessage(\(json))", completionHandler: nil)
                    }
                    if text.contains("INPUT_READY"), !sentLiteral {
                        sentLiteral = true
                        var before = winsize()
                        _ = ioctl(master, TIOCGWINSZ, &before)
                        originalRows = Int(before.ws_row)
                        let divider = split.subviews[0].frame.height
                        split.setPosition(divider + 80, ofDividerAt: 0)
                        let resizeDeadline = Date().addingTimeInterval(3)
                        while Date() < resizeDeadline {
                            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                            var after = winsize()
                            _ = ioctl(master, TIOCGWINSZ, &after)
                            draggedRows = Int(after.ws_row)
                            if draggedRows > 0 && draggedRows != originalRows { break }
                        }
                        guard !split.isVertical, split.dividerThickness >= 14, draggedRows > 0, draggedRows < originalRows else { fatalError("Dragging the actual vertical split did not resize xterm and PTY rows") }
                        resize(cols: 131, rows: 37)
                        let data = try JSONSerialization.data(withJSONObject: ["type": "input", "data": "literal '$ touch NEVER\r"])
                        let json = String(decoding: data, as: UTF8.self)
                        web.evaluateJavaScript("window.webkit.messageHandlers.pty.postMessage(\(json))", completionHandler: nil)
                    }
                }
                for _ in 0..<5 { _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
                let log = session.appendingPathComponent("terminal.raw.log")
                let text = String(decoding: try Data(contentsOf: log), as: UTF8.self)
                guard finished, text.contains("SELECTION:second"), text.contains("LITERAL:literal '$ touch NEVER"), text.contains("RAW_COMPLETE_最后一行"), text.contains("37 131") else { fatalError("PTY/fzf/input/resize failure:\n\(text)") }
                guard states["flutter"] == "succeeded", states["platforms.android.sdk"] == "attention", statusLabels["platforms.android.sdk"]?.stringValue.contains("需用户处理") == true,
                      animationTimer == nil, dotCount == 0, statusLabels.values.allSatisfy({ !$0.stringValue.hasSuffix(".") }) else { fatalError("Milestone state events were lost or animation survived completion") }
                let connectorFields = columns["flutter"]?.superview?.subviews.compactMap { $0 as? NSTextField }.filter { $0.stringValue == ">>>>>" } ?? []
                let milestoneScroll = split.subviews.compactMap { $0 as? NSScrollView }.first!
                guard connectorFields.count == 5, connectorFields.allSatisfy({ $0.frame.width >= 44 }),
                      milestoneScroll.documentView!.frame.width <= milestoneScroll.contentView.bounds.width + 0.5 else { fatalError("ASCII milestone connectors or 6-column viewport overflow") }
                print("PASS: five visible monospace >>>>> connectors between six milestone columns")
                print("PASS: real NSSplitView divider drag changes xterm and PTY rows from \(originalRows) to \(draggedRows)")
                guard window.title.contains("v1.1.0"), window.title.contains("2026.10.29.2"), versionLabels["flutter"]?.stringValue.contains("3.47.8") == true,
                      versionLabels["platforms.android.sdk"]?.stringValue.contains("36.0.0") == true, versionLabels["flutter"]?.isHidden == false,
                      versionLabels["platforms.android.sdk"]?.maximumNumberOfLines == 2 else { fatalError("Actual tool/SDK/component versions must be visible, including after a later state event omits version") }
                print("PASS: tool build, SDK/Dart and Android component versions are visible with 2-line limits")
                let normalSize = window.contentView!.bounds.size
                for width in [800.0, 1440.0] {
                    window.setContentSize(NSSize(width: width, height: 700))
                    window.contentView!.layoutSubtreeIfNeeded()
                    guard labels.values.allSatisfy({ !$0.stringValue.contains("进行中") }),
                          columns.values.allSatisfy({ $0.frame.width >= 145 }),
                          web.frame.height >= 180 else { fatalError("Narrow/wide window must preserve phase titles, scrolling and terminal space") }
                }
                split.setPosition(300, ofDividerAt: 0)
                split.didDragDivider?()
                window.setContentSize(NSSize(width: 800, height: 538))
                window.contentView!.layoutSubtreeIfNeeded()
                guard manuallySizedMilestones, web.frame.height >= 180 else { fatalError("Manual divider height must preserve the terminal minimum when shrinking the window") }
                let manualHeight = split.subviews[0].frame.height
                update(SetupEvent(id: "pub", parent: nil, title: "依赖与插件", state: "pending", message: nil))
                guard abs(split.subviews[0].frame.height - manualHeight) < 1 else { fatalError("State updates must preserve the manually chosen divider height") }
                window.setContentSize(normalSize)
                window.contentView!.layoutSubtreeIfNeeded()
                let attrs = try FileManager.default.attributesOfItem(atPath: log.path)
                guard (attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600 else { fatalError("Raw log must be private") }
                guard text.contains("\u{1b}[") else { fatalError("Raw log must retain ANSI output") }
                print("PASS: real WKWebView + PTY, fzf, raw literal keys, resize, nested milestone events, private complete ANSI log")
                window.delegate = nil
                window.close()
                reader?.cancel()
                if master >= 0 { Darwin.close(master); master = -1 }
                try rawLog.close()
                try FileManager.default.removeItem(at: session)
            }
        }
        extension SetupProjectWindow {
            func verifyCancellationFallback() throws {
                try "#!/bin/zsh\ntrap '' INT\nprint -r -- IGNORING_INTERRUPT_READY\n/bin/sleep 60\n".write(to: tools.appendingPathComponent("SetupFlutterProject.zsh"), atomically: true, encoding: .utf8)
                applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
                var cancelled = false
                let deadline = Date().addingTimeInterval(14)
                while Date() < deadline && !finished {
                    _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                    let text = String(decoding: (try? Data(contentsOf: session.appendingPathComponent("terminal.raw.log"))) ?? Data(), as: UTF8.self)
                    if text.contains("IGNORING_INTERRUPT_READY"), !cancelled { cancelled = true; cancelTask() }
                }
                guard cancelled, finished, kill(child, 0) != 0 else { fatalError("Cancellation did not stop and reap the owned PTY child") }
                print("PASS: Ctrl+C ignored branch bounded TERM stops only the owned PTY process group")
                window.delegate = nil
                window.close()
                reader?.cancel()
                if master >= 0 { Darwin.close(master); master = -1 }
                try rawLog.close()
                try FileManager.default.removeItem(at: session)
            }
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let test = try SetupProjectWindow(project: CommandLine.arguments[1], tools: URL(fileURLWithPath: CommandLine.arguments[2]))
        try test.verifyEmbeddedTerminal()
        let cancelTest = try SetupProjectWindow(project: CommandLine.arguments[1], tools: URL(fileURLWithPath: CommandLine.arguments[2]))
        try cancelTest.verifyCancellationFallback()
      SWIFT
      # Only the encoded key path is used; avoid a redundant synthetic key sequence.
      main = File.join(directory, 'main.swift')
      File.write(main, source + harness)
      binary = File.join(directory, 'window-tests')
      out, err, status = Open3.capture3('/usr/bin/xcrun', 'swiftc', main, '-o', binary)
      assert status.success?, out + err
      out, err, status = Open3.capture3(binary, directory, tools)
      assert status.success?, out + err
      assert_includes out, 'PASS: real WKWebView + PTY'
      assert_includes out, 'PASS: Ctrl+C ignored branch'
      assert_includes out, 'PASS: tool build, SDK/Dart'
      assert_includes out, 'PASS: five visible monospace'
      assert_includes out, 'PASS: real NSSplitView'
      assert_includes out, 'PASS: separate titles, compact content height'
      refute File.exist?(File.join(directory, 'NEVER'))
    end
  end
end
