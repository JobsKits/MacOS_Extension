# frozen_string_literal: true
# Jobs：隔离验证日志着色、原生滚轮和自动追尾；不运行安装器或注册扩展。

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
require 'fileutils'
require 'digest'
require 'json'
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
require 'tmpdir'
require 'fileutils'
require 'digest'
require 'json'

class ManagerLogInteractionTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def test_real_appkit_log_colors_and_user_scrolling
    source = File.read(ENV.fetch('JOBS_FINDER_PANEL_TEST_SOURCE', File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift')))
    source_sha256 = Digest::SHA256.hexdigest(source)
    entrypoint = %r{// MARK: - Entry point.*?// MARK: - Feature catalog}m
    assert_match entrypoint, source, 'refuse to compile without removing the interactive production entrypoint'
    source = source.sub(entrypoint, '')
    harness = <<~'SWIFT'
      var checks = 0
      func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
          checks += 1
          if !condition() {
              FileHandle.standardError.write(Data("FAILED: \(message)\n".utf8))
              exit(1)
          }
      }
      func pump() {
          RunLoop.current.run(until: Date().addingTimeInterval(0.035))
      }
      func samePoint(_ a: NSPoint, _ b: NSPoint) -> Bool {
          return abs(a.x - b.x) < 1 && abs(a.y - b.y) < 1
      }
      func contrast(_ foreground: NSColor, _ background: NSColor) -> Double {
          func luminance(_ color: NSColor) -> Double {
              let c = color.usingColorSpace(.sRGB)!
              func linear(_ value: CGFloat) -> Double {
                  let component = Double(value)
                  return component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
              }
              return linear(c.redComponent) * 0.2126 + linear(c.greenComponent) * 0.7152 + linear(c.blueComponent) * 0.0722
          }
          let a = luminance(foreground)
          let b = luminance(background)
          return (max(a, b) + 0.05) / (min(a, b) + 0.05)
      }
      func wheel(precise: Bool, x: Int32 = 0, y: Int32 = 70, momentum: Bool = false, phase: Int64 = 0, momentumStart: Bool = false, momentumEnd: Bool = false) -> NSEvent {
          let cg = CGEvent(scrollWheelEvent2Source: nil, units: precise ? .pixel : .line,
                           wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0)!
          cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: precise ? 1 : 0)
          cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
          if momentum {
              // Public CoreGraphics enum: begin=1, continue=2.
              cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumStart ? 1 : (momentumEnd ? 3 : 2))
          }
          return NSEvent(cgEvent: cg)!
      }
      func verifyNativeMomentumParity() {
          let reference = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 250))
          let managed = ManagerLogScrollView(frame: reference.frame)
          var manualCalls = 0
          managed.manualScroll = { manualCalls += 1 }
          for scroll in [reference, managed] {
              scroll.usesPredominantAxisScrolling = false
              scroll.hasVerticalScroller = true
              scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 2200))
              scroll.contentView.scroll(to: NSPoint(x: 0, y: 900))
              scroll.reflectScrolledClipView(scroll.contentView)
          }
          let events = [wheel(precise: true, y: 8, phase: 1),
                        wheel(precise: true, y: 40, phase: 2),
                        wheel(precise: true, y: 0, phase: 4),
                        wheel(precise: true, y: 30, momentum: true, momentumStart: true),
                        wheel(precise: true, y: 22, momentum: true),
                        wheel(precise: true, y: 0, momentum: true, momentumEnd: true)]
          for event in events {
              reference.scrollWheel(with: event)
              managed.scrollWheel(with: event)
              pump()
              expect(samePoint(reference.contentView.bounds.origin, managed.contentView.bounds.origin),
                     "gesture/momentum uses unchanged native AppKit displacement")
          }
          expect(manualCalls == 4, "manual callback observes moving phases without treating ending zero delta as movement")
      }
      func verifyStyling() {
          let cases: [(String, ManagerLogKind)] = [
              ("普通编译输出 file.swift:10", .normal),
              ("/tmp/Feature.swift:12:3: error: cannot find symbol", .error),
              ("/tmp/My Feature.swift:12: warning: deprecated", .warning),
              ("../Sources/Feature.m:12:3: fatal error: header not found", .error),
              ("Feature.swift:9:2: warning: unused result", .warning),
              ("The help text says error: and warning: are log levels", .normal),
              ("Feature.swift:9:2: note: the string error: is documented", .normal),
              ("INFO output explains warning: without reporting one", .info),
              ("INFO fetching dependencies", .info), ("正在编译", .info),
              ("SUCCESS all done", .success), ("✔ 完成", .success),
              ("已完成：成功 12 项，失败 0 项。", .success),
              ("已完成：成功 12 项，失败 2 项。", .error),
              ("warning: this is deprecated", .warning), ("⚠ 请检查", .warning),
              ("错误：权限不足", .error), ("error: missing file", .error),
              ("fatal: failed to compile", .error), ("退出码：9", .error),
              ("command ended (exit code: 2)", .error), ("exit code: -2", .error),
              ("0 errors", .normal), ("3 errors", .error),
              ("** BUILD FAILED **", .error), ("** BUILD SUCCEEDED **", .success),
              ("━━━━━━━━ 阶段", .heading), ("=== stage ===", .heading)
          ]
          for (message, kind) in cases {
              expect(ManagerLogKind.classify(message) == kind, "classification: \(message)")
          }
          let kinds: [ManagerLogKind] = [.normal, .info, .success, .warning, .error, .heading]
          for dark in [false, true] {
              let palette = ManagerLogPalette(dark: dark)
              for kind in kinds {
                  expect(contrast(palette.foreground(kind), palette.background) >= 4.5,
                         "readable \(kind.rawValue) on dark=\(dark)")
              }
              let clean = ManagerLogStyling.plainText("\u{1B}[31m错误：中文 English\u{1B}[0m\n\u{1B}]0;window title\u{7}plain\n\u{1B}]8;;https://example.com\u{1B}\\link\u{1B}]8;;\u{1B}\\\n")
              expect(clean == "错误：中文 English\nplain\nlink\n", "CSI and OSC removed without losing text")
              expect(ManagerLogStyling.plainText("partial\u{1B}[31") == "partial", "unfinished CSI preview is hidden")
              let attributed = ManagerLogStyling.attributed(clean, palette: palette)
              expect(attributed.string == clean, "styling preserves Unicode text")
              expect(attributed.attribute(ManagerLogKind.attribute, at: 0, effectiveRange: nil) as? String == "error", "plain severity retained as semantic span")
              let forced = ManagerLogStyling.attributed("fallback output\n", palette: palette, kind: .warning)
              expect(forced.attribute(ManagerLogKind.attribute, at: 0, effectiveRange: nil) as? String == "warning", "explicit status controls styling")
          }
      }
      func captureLog(_ view: NSView, name: String) throws {
          guard CommandLine.arguments.count > 2, !CommandLine.arguments[2].isEmpty else { return }
          view.displayIfNeeded()
          guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
              throw NSError(domain: "JobsLogRegression", code: 1)
          }
          view.cacheDisplay(in: view.bounds, to: bitmap)
          let png = bitmap.representation(using: .png, properties: [:])!
          try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true).appendingPathComponent(name), options: .atomic)
      }
      extension FeatureSelectionController {
          // 走真实结束汇总路径，只设置控制器状态，不启动后台进程。
          func verifyCompletionSummaries() {
              let cases: [(String, Int32, String, Bool, Bool, ManagerLogKind, String)] = [
                  ("success", 0, "succeeded", false, false, .success, "已完成"),
                  ("nonzero exit", 2, "failed", false, false, .error, "任务失败"),
                  ("failed feature with zero exit", 0, "failed", false, false, .error, "任务失败"),
                  ("stopped", 0, "waiting", true, false, .warning, "已停止"),
                  ("permission blocked", 0, "waiting", false, true, .error, "需要权限检查"),
                  ("permission exit 77", 77, "waiting", false, false, .error, "需要权限检查"),
                  ("permission takes priority over stopped", 0, "waiting", true, true, .error, "需要权限检查")
              ]
              for (name, code, state, stopped, blocked, kind, prefix) in cases {
                  let controller = FeatureSelectionController(preferences: preferences)
                  let fixtureWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 300),
                                               styleMask: [.titled], backing: .buffered, defer: false)
                  controller.window = fixtureWindow
                  fixtureWindow.contentView = controller.makeLogPanel(width: 760, height: 300)
                  controller.executionLabel = NSTextField(labelWithString: "")
                  controller.runningIdentifiers = ["fixture-unit"]
                  controller.featureStates = ["fixture-unit": state]
                  controller.activeWorkerAction = "install"
                  controller.workerReportedStopped = stopped
                  controller.appManagementBlocked = blocked
                  controller.finishWorker(exitStatus: code)
                  let storage = controller.logTextView!.textStorage!
                  let result = (storage.string as NSString).range(of: prefix + "：")
                  expect(result.location != NSNotFound, "finishWorker writes actual summary: \(name)")
                  expect(storage.attribute(ManagerLogKind.attribute, at: result.location, effectiveRange: nil) as? String == kind.rawValue,
                         "finishWorker stores explicit actual-state kind: \(name)")
                  expect(controller.lastExitStatus == code, "finishWorker retains real exit status: \(name)")
                  fixtureWindow.orderOut(nil)
              }
          }
          func verifyInteractiveLog(_ temporaryDirectory: URL) throws {
              let w = NSWindow(contentRect: NSRect(x: 100, y: 120, width: 760, height: 410),
                               styleMask: [.titled], backing: .buffered, defer: false)
              window = w
              w.contentView = makeLogPanel(width: 760, height: 410)
              w.orderFront(nil)
              defer { w.orderOut(nil) }
              let path = temporaryDirectory.appendingPathComponent("only-test-output.log")
              FileManager.default.createFile(atPath: path.path, contents: Data())
              logHandle = try FileHandle(forWritingTo: path)
              defer { try? logHandle?.close(); logHandle = nil }
              let text = logTextView!
              let scroll = text.enclosingScrollView!
              expect(scroll is ManagerLogScrollView, "real log scroll subclass installed")
              expect(!text.isEditable && text.isSelectable, "log remains read-only and selectable")
              appendLog((0..<700).map { "\($0): " + String(repeating: "output ", count: 30) }.joined(separator: "\n") + "\n")
              text.layoutManager?.ensureLayout(for: text.textContainer!)
              text.scrollToEndOfDocument(nil)
              pump()
              func bottom() -> CGFloat {
                  return max(0, text.bounds.height - scroll.contentView.bounds.height)
              }
              func follow() {
                  followLogButton!.state = .off
                  followLogButton!.performClick(nil)
                  pump()
                  expect(followLogButton!.state == .on, "checkbox resumes follow")
                  expect(scroll.contentView.bounds.minY >= bottom() - 15, "resuming immediately reaches log bottom")
              }
              func hitLog() -> NSView {
                  let clip = scroll.contentView
                  let point = clip.convert(NSPoint(x: clip.bounds.minX + 80, y: clip.bounds.minY + 80), to: w.contentView)
                  let hit = w.contentView!.hitTest(point)!
                  expect(hit === text || hit.isDescendant(of: text), "viewport point hits actual text view")
                  return hit
              }
              for (precise, momentum) in [(true, false), (false, false), (true, true)] {
                  follow()
                  let before = scroll.contentView.bounds.origin
                  let event = wheel(precise: precise, y: precise ? 80 : 5, momentum: momentum)
                  expect(event.hasPreciseScrollingDeltas == precise, "fixture uses correct delta units")
                  if momentum { expect(!event.momentumPhase.isEmpty, "fixture carries native momentum") }
                  hitLog().scrollWheel(with: event)
                  pump()
                  let moved = scroll.contentView.bounds.origin
                  if !momentum {
                      expect(moved.y < before.y - 1, "native wheel moves viewport: precise=\(precise)")
                  }
                  expect(followLogButton!.state == .off, "manual scroll pauses follow")
                  appendLog("next worker output\n")
                  showLiveOutput("partial worker output")
                  pump()
                  expect(samePoint(moved, scroll.contentView.bounds.origin), "append and preview do not steal manually chosen viewport")
                  removeLiveOutput()
                  if momentum {
                      text.scrollWheel(with: wheel(precise: true, y: 0, momentum: true, momentumEnd: true))
                  }
              }
              follow()
              let unrelated = NSScrollView()
              NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: unrelated)
              expect(followLogButton!.state == .on, "unrelated scroll cannot pause this log")
              NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
              expect(followLogButton!.state == .off, "log live-scroll notification pauses thumb dragging follow")
              scroll.contentView.scroll(to: NSPoint(x: 0, y: 450))
              scroll.reflectScrolledClipView(scroll.contentView)
              let dragged = scroll.contentView.bounds.origin
              appendLog("after manual scrollbar movement\n")
              pump()
              expect(samePoint(dragged, scroll.contentView.bounds.origin), "scrollbar-selected viewport survives output")
              let functionKeys: [UInt16: UInt32] = [115: 0xF729, 116: 0xF72C, 119: 0xF72B, 121: 0xF72D,
                                                  123: 0xF702, 124: 0xF703, 125: 0xF701, 126: 0xF700]
              for keyCode: UInt16 in [115, 116, 119, 121, 123, 124, 125, 126] {
                  follow()
                  let character = String(UnicodeScalar(functionKeys[keyCode]!)!)
                  let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.function],
                                            timestamp: 0, windowNumber: w.windowNumber, context: nil,
                                            characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode)!
                  text.keyDown(with: key)
                  expect(followLogButton!.state == .off, "navigation key \(keyCode) pauses follow")
                  pump()
                  if keyCode == 115 {
                      expect(scroll.contentView.bounds.minY < 15, "native Home reaches beginning")
                  } else if keyCode == 119 {
                      expect(scroll.contentView.bounds.minY >= bottom() - 15, "native End reaches bottom")
                  }
              }
              followLogButton!.state = .off
              appendLog("\u{1B}[31m错误：真实诊断\u{1B}[0m\nINFO diagnostic\nwarning: verify configuration\n已完成：成功 2 项，失败 0 项。\n=== build stage ===\n")
              let storage = text.textStorage!
              let errorRange = (text.string as NSString).range(of: "错误：真实诊断")
              let successRange = (text.string as NSString).range(of: "已完成：成功 2 项，失败 0 项。")
              expect(storage.attribute(ManagerLogKind.attribute, at: errorRange.location, effectiveRange: nil) as? String == "error", "append records error span")
              expect(storage.attribute(ManagerLogKind.attribute, at: successRange.location, effectiveRange: nil) as? String == "success", "zero failed summary remains success")
              text.setSelectedRange(errorRange)
              scroll.contentView.scroll(to: NSPoint(x: 0, y: 600))
              scroll.reflectScrolledClipView(scroll.contentView)
              let savedText = text.string
              let savedSelection = text.selectedRanges
              let savedOrigin = scroll.contentView.bounds.origin
              for theme in ["light", "dark", "light"] {
                  preferences.theme = theme
                  applyPanelPreferences()
                  pump()
                  expect(text.string == savedText, "theme retains complete original output")
                  expect(text.selectedRanges == savedSelection, "theme retains selected diagnostic")
                  expect(samePoint(savedOrigin, scroll.contentView.bounds.origin), "theme retains manually selected viewport")
                  let palette = ManagerLogPalette(dark: theme == "dark")
                  let errorColor = storage.attribute(.foregroundColor, at: errorRange.location, effectiveRange: nil) as! NSColor
                  let successColor = storage.attribute(.foregroundColor, at: successRange.location, effectiveRange: nil) as! NSColor
                  expect(errorColor.isEqual(palette.foreground(.error)), "existing error recolored semantically")
                  expect(successColor.isEqual(palette.foreground(.success)), "existing success recolored semantically")
                  expect(text.backgroundColor.isEqual(palette.background), "text background follows theme")
                  expect(scroll.backgroundColor.isEqual(palette.background), "scroll background follows theme")
                  text.scrollToEndOfDocument(nil)
                  pump()
                  text.setSelectedRange(NSRange(location: 0, length: 0))
                  try captureLog(scroll, name: "log-\(theme).png")
                  text.selectedRanges = savedSelection
                  scroll.contentView.scroll(to: savedOrigin)
                  scroll.reflectScrolledClipView(scroll.contentView)
              }
              let logApplication = NSApplication.shared
              let oldApplicationAppearance = logApplication.appearance
              preferences.theme = "system"
              logApplication.appearance = NSAppearance(named: .aqua)
              applyPanelPreferences()
              pump()
              expect(text.backgroundColor.isEqual(ManagerLogPalette(dark: false).background), "system mode starts with application light appearance")
              logApplication.appearance = NSAppearance(named: .darkAqua)
              pump()
              let systemErrorColor = storage.attribute(.foregroundColor, at: errorRange.location, effectiveRange: nil) as! NSColor
              expect(text.backgroundColor.isEqual(ManagerLogPalette(dark: true).background), "system appearance callback updates existing background automatically")
              expect(systemErrorColor.isEqual(ManagerLogPalette(dark: true).foreground(.error)), "system appearance callback updates existing semantic colors automatically")
              expect(text.string == savedText && text.selectedRanges == savedSelection, "system appearance change preserves diagnostic and selection")
              expect(samePoint(savedOrigin, scroll.contentView.bounds.origin), "system appearance change preserves viewport")
              logApplication.appearance = oldApplicationAppearance
              try logHandle!.synchronize()
              let disk = try String(contentsOf: path, encoding: .utf8)
              expect(!disk.contains("\u{1B}"), "disk diagnostics stay plain text")
              expect(disk == text.string, "disk retains committed original Unicode output")
              let bounded = (0..<6500).map { "error: " + String(repeating: "x", count: 95) + "\($0)\n" }.joined()
              appendLog(bounded)
              expect(storage.length <= 600_000 && storage.length >= 500_000, "window log remains bounded")
              expect(storage.attribute(ManagerLogKind.attribute, at: storage.length - 2, effectiveRange: nil) as? String == "error", "truncation retains surviving semantic spans")
              try logHandle!.synchronize()
              let fullDisk = try String(contentsOf: path, encoding: .utf8)
              expect(fullDisk.utf16.count > storage.length && fullDisk.hasSuffix(bounded), "disk keeps full output after window truncation")
              if CommandLine.arguments.count > 2, !CommandLine.arguments[2].isEmpty {
                  try fullDisk.write(to: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true).appendingPathComponent("test-plain.log"), atomically: true, encoding: .utf8)
              }
          }
      }
      let application = NSApplication.shared
      application.setActivationPolicy(.prohibited)
      application.finishLaunching()
      verifyStyling()
      verifyNativeMomentumParity()
      let suite = "local.jobs.log-regression.\(UUID().uuidString)"
      let defaults = UserDefaults(suiteName: suite)!
      defer { defaults.removePersistentDomain(forName: suite) }
      let preferences = ManagerPanelPreferences(defaults: defaults, systemLanguages: { ["zh-Hans"] })
      try FeatureSelectionController(preferences: preferences).verifyInteractiveLog(URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
      FeatureSelectionController(preferences: preferences).verifyCompletionSummaries()
      print("log interaction checks passed: \(checks)")
    SWIFT
    Dir.mktmpdir('jobs-manager-log-regression-') do |dir|
      path = File.join(dir, 'main.swift')
      binary = File.join(dir, 'log-regression')
      File.write(path, source + "\n" + harness)
      output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', path, '-o', binary)
      assert status.success?, output
      artifacts = ENV.fetch('JOBS_LOG_TEST_ARTIFACTS_DIR', '')
      FileUtils.mkdir_p(artifacts) unless artifacts.empty?
      output, status = Open3.capture2e(binary, dir, artifacts)
      assert status.success?, output
      assert_match(/log interaction checks passed: \d+/, output)
      count = output[/passed: (\d+)/, 1].to_i
      assert_operator count, :>=, 125
      puts "AppKit log checks: #{count}"
      unless artifacts.empty?
        File.write(File.join(artifacts, 'appkit-stdout.log'), output)
        File.write(File.join(artifacts, 'receipt.json'), JSON.pretty_generate({
          source_sha256: source_sha256, appkit_checks: count,
          screenshots: %w[log-light.png log-dark.png], plain_log: 'test-plain.log',
          installed_or_registered: false
        }) + "\n")
        puts "AppKit log artifacts: #{File.expand_path(artifacts)}"
      end
    end
  end
end
