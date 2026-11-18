# frozen_string_literal: true
# Jobs：隔离验证真实功能行命中与原生按钮输入；不运行安装器或注册扩展。

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

class ManagerFeatureRowTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  # 使用真实窗口派发鼠标，并为原生NSButton预排mouseup以完成tracking。
  def test_real_row_hit_testing_and_native_checkbox_actions
    original = File.read(ENV.fetch('JOBS_FINDER_PANEL_TEST_SOURCE', File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift')))
    marker = %r{// MARK: - Entry point.*?// MARK: - Feature catalog}m
    assert_match marker, original, 'refuse to compile the production interactive entrypoint'
    source = original.sub(marker, '')
    harness = <<~'SWIFT'
      var checks = 0
      var eventSequence = 100
      func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
          checks += 1
          if !condition() {
              FileHandle.standardError.write(Data("FAILED: \(message)\n".utf8))
              exit(1)
          }
      }
      func pump() { RunLoop.current.run(until: Date().addingTimeInterval(0.015)) }
      func mouse(_ type: NSEvent.EventType, _ point: NSPoint, in window: NSWindow) -> NSEvent {
          eventSequence += 1
          return NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                   timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window.windowNumber, context: nil,
                                   eventNumber: eventSequence, clickCount: 1,
                                   pressure: type == .leftMouseUp ? 0 : 1)!
      }
      final class RowActionProbe: NSObject {
          var count = 0
          var forward: ((NSButton) -> Void)?
          @objc func activated(_ sender: NSButton) { count += 1; forward?(sender) }
      }
      extension FeatureSelectionController {
          // 把待测行放在视口下部，避开真实吸顶标题覆盖的区域。
          func reveal(_ button: NSButton) {
              let scroll = featureScrollView!
              let document = featureDocument!
              let center = button.convert(NSPoint(x: 0, y: button.bounds.midY), to: document).y
              let offset = min(44, scroll.contentSize.height * 0.3)
              let y = max(0, min(document.bounds.height - scroll.contentSize.height, center - offset))
              scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
              scroll.reflectScrolledClipView(scroll.contentView)
              document.updatePinnedHeaders()
              window!.makeKeyAndOrderFront(nil)
              pump()
          }
          func hit(_ point: NSPoint) -> NSView? {
              let content = window!.contentView!
              let inParent = content.superview!.convert(point, from: nil)
              return content.hitTest(inParent)
          }
          // 让NSWindow走原生命中；未被cell tracking消费的mouseup再交给window。
          func click(_ point: NSPoint) {
              let w = window!
              let down = mouse(.leftMouseDown, point, in: w)
              let up = mouse(.leftMouseUp, point, in: w)
              expect(down.window === w && up.window === w, "mouse fixture belongs to the actual window")
              NSApplication.shared.postEvent(up, atStart: true)
              w.sendEvent(down)
              if let pending = NSApplication.shared.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .eventTracking, dequeue: true) {
                  w.sendEvent(pending)
              }
              pump()
          }
          private func point(_ role: String, button: NSButton, column: ManagerFeatureColumn, status: NSTextField, icon: NSImageView) -> NSPoint {
              let local: NSPoint
              switch role {
              case "checkbox": local = NSPoint(x: button.frame.minX + 7, y: button.frame.midY)
              case "title": local = NSPoint(x: button.frame.minX + min(60, button.frame.width - 5), y: button.frame.midY)
              case "status": local = NSPoint(x: status.frame.midX, y: status.frame.midY)
              case "icon": local = NSPoint(x: icon.frame.midX, y: icon.frame.midY)
              default:
                  expect(icon.frame.minX > button.frame.maxX, "real row retains a blank gap before status icons")
                  local = NSPoint(x: (button.frame.maxX + icon.frame.minX) / 2, y: button.frame.midY)
              }
              return column.convert(local, to: nil)
          }
          func verifyRows(_ screen: NSSize, root: URL) {
              buildWindow(screenSize: screen)
              window!.makeKeyAndOrderFront(nil)
              NSApplication.shared.activate(ignoringOtherApps: true)
              defer { worker = nil; window?.orderOut(nil) }
              let identifier = "git-pull"
              let button = checkboxes.first { $0.option.identifier == identifier }!.button
              let column = button.superview as! ManagerFeatureColumn
              let status = statusLabels[identifier]!
              let icon = statusIcons[identifier]!
              let probe = RowActionProbe()
              let originalTarget = button.target
              let originalAction = button.action!
              probe.forward = { sender in
                  expect(NSApplication.shared.sendAction(originalAction, to: originalTarget, from: sender), "row forwards the original selection action")
              }
              button.target = probe
              button.action = #selector(RowActionProbe.activated(_:))
              defer { button.target = originalTarget; button.action = originalAction }
              func reset() {
                  worker = nil; featureStates.removeAll(); logURL = nil
                  clearAllClicked()
              }
              func single(_ role: String) {
                  reset(); reveal(button)
                  let target = point(role, button: button, column: column, status: status, icon: icon)
                  let receiver = hit(target)
                  if role == "checkbox" || role == "title" {
                      expect(receiver === button || receiver?.isDescendant(of: button) == true, "native checkbox and title keep their original mouse target")
                  } else { expect(receiver === column, "ordinary \(role) routes to the row interaction owner") }
                  let before = probe.count
                  click(target)
                  expect(probe.count == before + 1 && button.state == .on, "\(role) activates exactly once")
                  expect(checkedIdentifiers() == [identifier], "row click selects only its own feature")
                  let expectedSummary = preferences.text("已选 1 / \(checkboxes.count) 项；空选不能执行，切换操作保留勾选。")
                  expect(summaryLabel!.stringValue == expectedSummary, "row click refreshes localized selection count: \(summaryLabel!.stringValue), expected \(expectedSummary)")
              }
              for language in ManagerPanelPreferences.languages where language != "system" {
                  preferences.language = language
                  preferences.theme = language == "bo" ? "dark" : "light"
                  applyPanelPreferences()
                  for role in ["checkbox", "title", "status", "icon", "blank"] { single(role) }
              }
              preferences.language = "zh-Hans"; applyPanelPreferences()
              reset(); reveal(button)
              let accessible = NSAccessibility.unignoredDescendant(of: button) as! NSButtonCell
              expect(accessible.accessibilityRole() == .checkBox && accessible.isAccessibilityEnabled(), "native unignored checkbox accessibility remains enabled")
              let beforeAX = probe.count
              _ = accessible.accessibilityPerformPress()
              expect(button.state == .on && probe.count == beforeAX + 1, "native accessibility press toggles once")
              reset(); reveal(button)
              expect(window!.makeFirstResponder(button), "checkbox remains a native keyboard responder")
              let keyDown = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                            windowNumber: window!.windowNumber, context: nil, characters: " ",
                                            charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
              let keyUp = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: window!.windowNumber, context: nil, characters: " ",
                                          charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
              NSApplication.shared.postEvent(keyUp, atStart: true)
              let beforeKey = probe.count
              window!.sendEvent(keyDown)
              if let pending = NSApplication.shared.nextEvent(matching: .keyUp, until: Date(), inMode: .eventTracking, dequeue: true) { window!.sendEvent(pending) }
              pump()
              expect(button.state == .on && probe.count == beforeKey + 1, "native Space key toggles once: state=\(button.state.rawValue), actions=\(probe.count-beforeKey), first=\(String(describing:window!.firstResponder)), key=\(window!.isKeyWindow), active=\(NSApplication.shared.isActive)")
              reset(); reveal(button)
              let blank = point("blank", button: button, column: column, status: status, icon: icon)
              let down = mouse(.leftMouseDown, blank, in: window!)
              let up = mouse(.leftMouseUp, blank, in: window!)
              let beforeCanceled = probe.count
              column.mouseDown(with: down)
              column.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: blank.x + 4, y: blank.y), in: window!))
              column.mouseUp(with: up)
              expect(button.state == .off && probe.count == beforeCanceled, "4px drag cancels row activation even after returning")
              column.mouseDown(with: down)
              column.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: blank.x + 4, y: blank.y), in: window!))
              expect(button.state == .off, "release distance alone also cancels a drag")
              column.mouseDown(with: down)
              let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0)!
              cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
              column.scrollWheel(with: NSEvent(cgEvent: cg)!)
              column.mouseUp(with: up)
              expect(button.state == .off && probe.count == beforeCanceled, "native wheel cancels pending activation")
              reveal(button)
              let currentBlank = point("blank", button: button, column: column, status: status, icon: icon)
              let currentDown = mouse(.leftMouseDown, currentBlank, in: window!)
              let currentUp = mouse(.leftMouseUp, currentBlank, in: window!)
              column.mouseDown(with: currentDown)
              worker = Process(); refreshSelectionState()
              column.mouseUp(with: currentUp)
              expect(button.state == .off && probe.count == beforeCanceled, "task beginning between press and release cannot select")
              column.mouseDown(with: currentDown); column.mouseUp(with: currentUp)
              _ = accessible.accessibilityPerformPress()
              expect(button.state == .off && probe.count == beforeCanceled, "busy row and native AX cannot bypass disabled state")
              worker = nil; refreshSelectionState()
              reveal(button)
              let beforeHidden = probe.count
              let hiddenPoint = point("blank", button: button, column: column, status: status, icon: icon)
              window!.resignKey()
              column.mouseDown(with: mouse(.leftMouseDown, hiddenPoint, in: window!))
              sendPanelToBackground()
              restorePanelWindow()
              column.mouseUp(with: mouse(.leftMouseUp, hiddenPoint, in: window!))
              expect(button.state == .off && probe.count == beforeHidden, "background and restore cannot commit a press from an already non-key window")
              let alien = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
              column.mouseDown(with: currentDown)
              column.mouseUp(with: mouse(.leftMouseUp, currentBlank, in: alien))
              expect(button.state == .off, "mouseup from a different window cannot commit")
              for cancel in ["focus", "resize", "layout"] {
                  reveal(button)
                  let p = point("blank", button: button, column: column, status: status, icon: icon)
                  column.mouseDown(with: mouse(.leftMouseDown, p, in: window!))
                  if cancel == "focus" { windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: window)) }
                  else if cancel == "resize" { windowDidResize(Notification(name: NSWindow.didResizeNotification, object: window)) }
                  else { layoutFeatureGroups() }
                  column.mouseUp(with: mouse(.leftMouseUp, p, in: window!))
                  expect(button.state == .off && probe.count == beforeCanceled, "\(cancel) invalidates an old row press")
              }
              let ownRow = column.rows.first { $0.button === button }!
              let border = button.frame.midY - max(ownRow.height, button.frame.height) / 2 - column.rowSpacing / 2
              let localBlankX = column.convert(currentBlank, from: nil).x
              let justInside = column.convert(NSPoint(x: localBlankX, y: border + 0.5), to: nil)
              let neighboring = column.convert(NSPoint(x: localBlankX, y: border - 0.5), to: nil)
              column.mouseDown(with: mouse(.leftMouseDown, justInside, in: window!))
              column.mouseDragged(with: mouse(.leftMouseDragged, neighboring, in: window!))
              column.mouseDragged(with: mouse(.leftMouseDragged, justInside, in: window!))
              column.mouseUp(with: mouse(.leftMouseUp, justInside, in: window!))
              expect(button.state == .off && probe.count == beforeCanceled, "crossing another row then returning under 4px still cancels")
              let lastRow = column.rows.min { $0.button.frame.midY < $1.button.frame.midY }!
              let lastButton = lastRow.button
              clearAllClicked()
              let localX = column.bounds.maxX - 1
              let inside = column.convert(NSPoint(x: localX, y: column.bounds.minY + 0.5), to: nil)
              let outside = column.convert(NSPoint(x: localX, y: column.bounds.minY - 1.5), to: nil)
              column.mouseDown(with: mouse(.leftMouseDown, inside, in: window!))
              column.mouseUp(with: mouse(.leftMouseUp, outside, in: window!))
              expect(lastButton.state == .off, "half-spacing outside the column never commits")
              column.mouseDown(with: mouse(.leftMouseDown, inside, in: window!))
              column.mouseDragged(with: mouse(.leftMouseDragged, outside, in: window!))
              column.mouseDragged(with: mouse(.leftMouseDragged, inside, in: window!))
              column.mouseUp(with: mouse(.leftMouseUp, inside, in: window!))
              expect(lastButton.state == .off, "leaving bounds and returning under 4px still cancels")
              reset(); reveal(button)
              var logActions = 0
              logURL = root.appendingPathComponent("missing-log-never-opens-Terminal")
              logErrorPresenter = { _ in logActions += 1 }
              featureStates[identifier] = "failed"
              refreshExecutionState()
              let logPoint = point("status", button: button, column: column, status: status, icon: icon)
              expect(hit(logPoint) === status, "enabled failure link retains the real NSTextField target")
              let beforeLog = probe.count
              click(logPoint)
              expect(logActions == 1 && probe.count == beforeLog && button.state == .off, "failure link invokes its independent action without selecting")
              worker = Process(); refreshSelectionState(); reveal(button)
              click(point("status", button: button, column: column, status: status, icon: icon))
              expect(logActions == 2 && probe.count == beforeLog && button.state == .off, "failure diagnostics stay usable while feature selection is busy")
              worker = nil; featureStates.removeAll(); logURL = nil; refreshSelectionState()
              single("blank")
              let selected = checkedIdentifiers()
              let oldButton = button
              let originalColumnWidth = column.bounds.width
              expect(moveFeatureGroup("git", toColumn: 1, before: nil), "production group movement succeeds")
              expect(checkboxes.first { $0.option.identifier == identifier }!.button === oldButton && checkedIdentifiers() == selected, "group movement reuses controls and preserves selection")
              expect(column.bounds.width >= originalColumnWidth - 1, "equal-column relayout retains full row width")
              single("status")
              let box = featureBoxes["git"]!
              let headerPoint = box.convert(NSPoint(x: box.bounds.midX, y: box.bounds.maxY - 10), to: nil)
              expect(hit(headerPoint) !== column && hit(headerPoint) !== button, "group drag title is outside the row interaction target")
              let beforeHeader = probe.count
              click(headerPoint)
              expect(probe.count == beforeHeader && checkedIdentifiers() == [identifier], "group title press and release never toggles a feature")
              print("rows \(Int(screen.width)) checks complete")
          }
      }
      let application = NSApplication.shared
      application.setActivationPolicy(.accessory)
      application.finishLaunching()
      let suite = "local.jobs.row-regression.\(UUID().uuidString)"
      let defaults = UserDefaults(suiteName: suite)!
      defer { defaults.removePersistentDomain(forName: suite) }
      let preferences = ManagerPanelPreferences(defaults: defaults, systemLanguages: { ["zh-Hans"] })
      let scope = ["git-pull", "git-rollback", "path_copier", "file-hash", "flutter-native-dependencies", "flutter-gradle-download", "pod_install"]
      let bootstrap = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
      bootstrap.makeKeyAndOrderFront(nil)
      application.activate(ignoringOtherApps: true)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
          for size in [NSSize(width: 1440, height: 900), NSSize(width: 800, height: 600)] {
              FeatureSelectionController(scope: scope, preferences: preferences).verifyRows(size, root: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
          }
          print("feature row checks passed: \(checks)")
          application.stop(nil)
          let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                       windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!
          application.postEvent(wake, atStart: false)
      }
      application.run()
      bootstrap.orderOut(nil)
    SWIFT
    Dir.mktmpdir('jobs-manager-feature-row-') do |dir|
      path = File.join(dir, 'main.swift')
      binary = File.join(dir, 'row-regression')
      File.write(path, source + "\n" + harness)
      output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', path, '-o', binary)
      assert status.success?, output
      output, status = Open3.capture2e(binary, dir)
      artifacts = ENV.fetch('JOBS_MANAGER_ROW_ARTIFACTS_DIR', '')
      FileUtils.mkdir_p(artifacts) unless artifacts.empty?
      File.write(File.join(artifacts, 'appkit-stdout.log'), output) unless artifacts.empty?
      assert status.success?, output
      assert_match(/feature row checks passed: \d+/, output)
      total = output[/passed: (\d+)/, 1].to_i
      assert_operator total, :>=, 500
      puts "AppKit feature-row checks: #{total}"
      unless artifacts.empty?
        File.write(File.join(artifacts, 'receipt.json'), JSON.pretty_generate({ source_sha256: Digest::SHA256.hexdigest(original),
          appkit_checks: total, sizes: [1440, 800], languages: 10, installed_or_registered: false }) + "\n")
        puts "AppKit feature-row artifacts: #{File.expand_path(artifacts)}"
      end
    end
  end
end
