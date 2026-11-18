# frozen_string_literal: true
# Jobs：隔离验证管理面板后台生命周期；仅执行有界假worker，不运行安装器或注册扩展。

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

class ManagerLifecycleTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  # 一次编译真实控制器，各场景在独立进程中运行事件循环。
  def test_real_run_loop_and_worker_survive_backgrounding
    original = File.read(ENV.fetch('JOBS_FINDER_PANEL_TEST_SOURCE', File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift')))
    marker = %r{// MARK: - Entry point.*?// MARK: - Feature catalog}m
    assert_match marker, original, 'refuse to compile the production interactive entrypoint'
    source = original.sub(marker, '')
    harness = <<~'SWIFT'
      var checks = 0
      func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
          checks += 1
          if !condition() {
              FileHandle.standardError.write(Data("FAILED: \(message)\n".utf8))
              exit(1)
          }
      }
      final class PreviousLifecycleDelegate: NSObject, NSApplicationDelegate { }
      extension FeatureSelectionController {
          // 构造可见管理窗口；不运行worker，适合验证异步询问的状态边界。
          func makeLifecycleFixture(_ manager: String?) {
              managerPath = manager
              buildWindow(screenSize: NSSize(width: 1024, height: 768))
              window!.makeKeyAndOrderFront(nil)
          }
          // 真实NSAlert使用当前窗口外观、十语按钮及藏文字体，逐次以取消响应结束。
          func verifyPromptAppearance(_ manager: String) {
              let prompt = FeatureSelectionController(scope: ["git-pull"], preferences: preferences)
              prompt.makeLifecycleFixture(manager)
              prompt.sendPanelToBackground()
              prompt.restorePanelWindow()
              for theme in ["light", "dark"] {
                  for language in ManagerPanelPreferences.languages where language != "system" {
                      preferences.theme = theme
                      preferences.language = language
                      prompt.applyPanelPreferences()
                      expect(prompt.backgroundStatusItem!.button!.accessibilityLabel() == preferences.text("Jobs Finder 扩展管理"),
                             "status accessibility label follows language: \(language)")
                      expect(prompt.backgroundShowItem!.title == preferences.text("显示管理面板"), "status restore title follows language")
                      prompt.requestPanelClose()
                      let alert = prompt.closeChoiceAlert!
                      expect(prompt.closeChoicePending && alert.window.sheetParent === prompt.window, "real close sheet is attached to its panel")
                      expect(alert.window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == (theme == "dark" ? .darkAqua : .aqua),
                             "real close sheet inherits explicit \(theme) appearance")
                      let titles = ["退到后台", "完全退出", "取消"].map { preferences.text($0) }
                      expect(alert.buttons.map { $0.title } == titles, "real close sheet has three current-language choices")
                      let backgroundsByDefault = alert.window.defaultButtonCell === alert.buttons[0].cell || alert.buttons[0].keyEquivalent == "\r"
                      expect(backgroundsByDefault && alert.buttons[2].keyEquivalent == "\u{1b}",
                             "default backgrounds and Escape cancels: first=\(alert.buttons[0].keyEquivalent.unicodeScalars.map { $0.value }), cancel=\(alert.buttons[2].keyEquivalent.unicodeScalars.map { $0.value }), default=\(backgroundsByDefault)")
                      if language == "bo", let font = NSFont(name: "Kailasa", size: 13) ?? NSFont(name: "Kokonor", size: 13) {
                          for button in alert.buttons {
                              expect(button.font?.familyName == font.familyName && button.font!.pointSize >= 13,
                                     "Tibetan close button uses the configured script font")
                          }
                      }
                      prompt.window!.endSheet(alert.window, returnCode: .alertThirdButtonReturn)
                      let deadline = Date().addingTimeInterval(1)
                      while prompt.closeChoicePending && Date() < deadline {
                          RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                      }
                      expect(!prompt.closeChoicePending && !prompt.isExiting && prompt.window!.isVisible,
                             "real sheet cancellation leaves the panel alive")
                  }
              }
              let previousAppearance = NSApplication.shared.appearance
              preferences.theme = "system"
              preferences.language = "en"
              NSApplication.shared.appearance = NSAppearance(named: .aqua)
              prompt.applyPanelPreferences()
              prompt.requestPanelClose()
              let systemAlert = prompt.closeChoiceAlert!
              expect(systemAlert.window.appearance == nil, "system close sheet does not freeze an explicit appearance")
              expect(systemAlert.window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua, "system close sheet begins light")
              NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
              RunLoop.current.run(until: Date().addingTimeInterval(0.03))
              expect(systemAlert.window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua, "open system close sheet follows live application appearance")
              prompt.window!.endSheet(systemAlert.window, returnCode: .alertThirdButtonReturn)
              let deadline = Date().addingTimeInterval(1)
              while prompt.closeChoicePending && Date() < deadline {
                  RunLoop.current.run(until: Date().addingTimeInterval(0.01))
              }
              expect(!prompt.closeChoicePending && !prompt.isExiting, "system close sheet still cancels normally")
              NSApplication.shared.appearance = previousAppearance
              prompt.quitFromStatusBar()
          }
          func verifyCloseStates(_ manager: String) {
              makeLifecycleFixture(manager)
              let originalWindow = window!
              var callbacks: [(CloseChoice) -> Void] = []
              closeChoicePresenter = { callbacks.append($0) }
              requestPanelClose()
              requestPanelClose()
              expect(callbacks.count == 1 && closeChoicePending, "one idle prompt survives repeated close requests")
              callbacks[0](.cancel)
              expect(!isExiting && !closeChoicePending && originalWindow.isVisible, "cancel keeps the same idle window open")
              requestPanelClose()
              expect(callbacks.count == 2, "later close request opens a fresh prompt")
              callbacks[1](.background)
              expect(isBackgrounded && !originalWindow.isVisible && backgroundStatusItem != nil, "background choice keeps a reachable status item")
              expect(backgroundQuitItem!.isEnabled, "idle status item permits exit")
              restorePanelWindow()
              expect(window === originalWindow && originalWindow.isVisible && !isBackgrounded, "restore reuses the original window")
              worker = Process()
              updateBackgroundStatus()
              expect(!backgroundQuitItem!.isEnabled, "busy state disables status quit")
              quitFromStatusBar()
              expect(isBackgrounded && !isExiting && isRunning, "direct busy quit callback also protects the transaction")
              worker = nil
              updateBackgroundStatus()
              expect(backgroundQuitItem!.isEnabled, "finished state permits exit again")
              quitFromStatusBar()
              expect(isExiting && backgroundStatusItem == nil, "explicit idle exit removes status item")
              let selector = FeatureSelectionController(scope: ["git-pull"], preferences: preferences)
              selector.makeLifecycleFixture(nil)
              var selectorPrompts = 0
              selector.closeChoicePresenter = { _ in selectorPrompts += 1 }
              selector.cancelClicked()
              expect(selector.isExiting && selectorPrompts == 0 && selector.formattedOutcome() == "__CANCELLED__", "pure selector returns cancellation without becoming resident")
              selector.window?.orderOut(nil)
              let stale = FeatureSelectionController(scope: ["git-pull"], preferences: preferences)
              stale.makeLifecycleFixture(manager)
              var staleCallbacks: [(CloseChoice) -> Void] = []
              stale.closeChoicePresenter = { staleCallbacks.append($0) }
              stale.requestPanelClose()
              stale.worker = Process()
              stale.requestPanelClose()
              expect(!stale.closeChoicePending && stale.isBackgrounded, "busy close dismisses the pending idle choice")
              stale.worker = nil
              stale.restorePanelWindow()
              stale.requestPanelClose()
              expect(staleCallbacks.count == 2 && stale.closeChoicePending, "new idle prompt is independent of the dismissed one")
              staleCallbacks[0](.quit)
              expect(!stale.isExiting && stale.closeChoicePending && stale.window!.isVisible, "dismissed sheet completion cannot consume a later prompt")
              staleCallbacks[1](.cancel)
              expect(!stale.closeChoicePending && !stale.isExiting, "current prompt still handles its own response")
              stale.quitFromStatusBar()
              verifyPromptAppearance(manager)
          }
          // 实际runModal期间驱动关闭入口，结束后检查delegate和返回合同。
          func verifyRunLoop(_ mode: String, manager: String) {
              managerPath = mode == "selector" ? nil : manager
              var prompts = 0
              var pendingChoice: ((CloseChoice) -> Void)?
              var readyToReturn = false
              closeChoicePresenter = { completion in
                  prompts += 1
                  if mode == "close-race" { pendingChoice = completion }
                  else if mode == "idle-background" { completion(.background) }
                  else if mode == "idle-quit" { completion(.quit) }
                  else if mode == "idle-cancel" { completion(.cancel) }
                  else { expect(false, "busy close never asks an idle question") }
              }
              let previous = PreviousLifecycleDelegate()
              NSApplication.shared.delegate = previous
              DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                  expect(false, "bounded run-loop watchdog: \(mode)")
              }
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [self] in
                  expect(NSApplication.shared.delegate === self, "real run registers and retains the application delegate")
                  expect(!applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared), "last window is allowed to remain backgrounded")
                  let originalWindow = window!
                  if mode == "selector" {
                      expect(NSApplication.shared.activationPolicy() == .accessory, "pure selector keeps its original Dock-free activation policy")
                      readyToReturn = true
                      cancelClicked()
                      expect(prompts == 0 && !isBackgrounded, "pure selector closes without a background prompt or resident session")
                      return
                  }
                  expect(NSApplication.shared.activationPolicy() == .regular, "management session appears in the Dock")
                  expect(NSRunningApplication.current.activationPolicy == .regular, "system running-application record exposes the Dock policy")
                  expect(NSApplication.shared.applicationIconImage != nil, "management session has an application icon for its Dock tile")
                  if mode.hasPrefix("idle-") {
                      appendLog("隐藏前保留的中文日志\n")
                      let text = logTextView!.string
                      readyToReturn = mode == "idle-quit"
                      requestPanelClose()
                      expect(prompts == 1, "idle close asks exactly once")
                      if mode == "idle-quit" { return }
                      expect(!isExiting && NSApplication.shared.isRunning, "background or cancel does not stop the real application loop")
                      expect(isBackgrounded == (mode == "idle-background"), "idle decision changes only the intended visibility")
                      DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [self] in
                          expect(!isExiting, "event loop keeps the controller alive after idle choice")
                          if mode == "idle-background" {
                              expect(!originalWindow.isVisible && backgroundStatusItem != nil, "hidden idle panel remains reachable")
                              expect(NSApplication.shared.activationPolicy() == .regular, "idle backgrounding preserves the Dock icon")
                              let result = applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)
                              expect(!result && window === originalWindow && originalWindow.isVisible, "reopen restores the same background window")
                          } else { expect(originalWindow.isVisible, "cancel keeps the panel visible") }
                          expect(logTextView!.string == text, "hide and reopen preserve diagnostic text")
                          readyToReturn = true
                          quitFromStatusBar()
                      }
                      return
                  }
                  if mode == "close-race" {
                      requestPanelClose()
                      requestPanelClose()
                      expect(prompts == 1 && closeChoicePending, "pending close prompt is not duplicated before a worker starts")
                  }
                  checkboxes.first!.button.performClick(nil)
                  installClicked()
                  expect(isRunning && worker!.isRunning, "real bounded worker started through the production action")
                  expect(closeButton!.isEnabled, "bottom close remains usable during work")
                  let process = worker!
                  let pid = process.processIdentifier
                  let storage = logTextView!.textStorage!
                  let selected = checkedIdentifiers()
                  switch mode {
                  case "busy-red": originalWindow.performClose(nil)
                  case "busy-button": closeButton!.performClick(nil)
                  case "busy-cmdq":
                      let close = NSApplication.shared.mainMenu!.items[0].submenu!.items[0]
                      expect(close.keyEquivalent == "q", "production Cmd-Q menu route is used")
                      expect(NSApplication.shared.sendAction(close.action!, to: close.target, from: close), "Cmd-Q action dispatched")
                  case "busy-terminate": NSApplication.shared.terminate(nil)
                  case "close-race": pendingChoice!(.quit)
                  default: expect(false, "known run mode")
                  }
                  expect(isBackgrounded && !originalWindow.isVisible && !isExiting, "busy close hides without exiting: \(mode)")
                  expect(NSApplication.shared.activationPolicy() == .regular, "busy backgrounding preserves the Dock icon")
                  expect(worker === process && process.processIdentifier == pid && process.isRunning, "hiding retains the exact worker process")
                  expect(executionTimer?.isValid == true && backgroundStatusItem != nil, "timer and status item survive while hidden")
                  expect(!backgroundQuitItem!.isEnabled, "hidden busy menu disables exit")
                  quitFromStatusBar()
                  expect(!isExiting && isRunning, "stale menu activation cannot bypass the busy guard")
                  let busyReopen = applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)
                  expect(!busyReopen && window === originalWindow && originalWindow.isVisible && !isBackgrounded,
                         "Dock reopen restores the original window during work")
                  expect(worker === process && process.processIdentifier == pid && process.isRunning,
                         "Dock reopen preserves the exact running worker")
                  expect(checkedIdentifiers() == selected && ObjectIdentifier(logTextView!.textStorage!) == ObjectIdentifier(storage),
                         "Dock reopen preserves the active selection and log storage")
                  requestPanelClose()
                  expect(isBackgrounded && !originalWindow.isVisible && NSApplication.shared.activationPolicy() == .regular,
                         "restored busy panel backgrounds again with its Dock icon")
                  var sawCompletedItemsBeforeExit = false
                  func awaitCompletion() {
                      if isRunning {
                          if !sawCompletedItemsBeforeExit && featureStates["git-pull"] == "succeeded" {
                              sawCompletedItemsBeforeExit = true
                              expect(!backgroundQuitItem!.isEnabled, "leaf completion does not unlock exit before process completion")
                          }
                          DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: awaitCompletion)
                          return
                      }
                      expect(sawCompletedItemsBeforeExit, "worker remained owned after reporting all item results")
                      expect(lastExitStatus == 0 && !process.isRunning, "hidden worker completed with its real exit status")
                      expect(isBackgrounded && !originalWindow.isVisible, "completion stays backgrounded without stealing focus")
                      expect(NSApplication.shared.activationPolicy() == .regular, "completed background session remains reachable from the Dock")
                      expect(logTextView!.string.contains("生命周期中文尾输出"), "hidden stdout pipe delivers the final Unicode output")
                      expect(ObjectIdentifier(logTextView!.textStorage!) == ObjectIdentifier(storage), "log storage was not rebuilt while hidden")
                      expect(executionTimer == nil && backgroundQuitItem!.isEnabled, "completion freezes timing and unlocks explicit exit")
                      let receipt = try! String(contentsOfFile: ProcessInfo.processInfo.environment["JOBS_LIFECYCLE_WORKER_RECEIPT"]!, encoding: .utf8)
                      expect(receipt == "started\ncompleted\n", "bounded fixture completed its own process lifetime")
                      let completeText = logTextView!.string
                      let reopen = applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)
                      expect(!reopen, "Dock reopen is handled by the management controller")
                      expect(window === originalWindow && originalWindow.isVisible, "restore keeps the original completed window")
                      expect(worker === nil && lastExitStatus == 0, "Dock restore never restarts a completed worker")
                      expect(checkedIdentifiers() == selected && logTextView!.string == completeText, "restore preserves selection, results and full text")
                      expect(prompts == (mode == "close-race" ? 1 : 0), "busy routes never opened an extra close prompt")
                      readyToReturn = true
                      quitFromStatusBar()
                  }
                  awaitCompletion()
              }
              let result = runModal()
              expect(readyToReturn && isExiting && result == "__CANCELLED__", "run returns only after explicit idle exit: \(mode)")
              expect(backgroundStatusItem == nil && !isRunning, "normal exit removes the status item and owns no worker")
              expect(NSApplication.shared.delegate === previous, "run restores the previous application delegate")
          }
      }
      let mode = CommandLine.arguments[1]
      let manager = CommandLine.arguments[2]
      let app = NSApplication.shared
      let suite = "local.jobs.lifecycle-regression.\(UUID().uuidString)"
      let defaults = UserDefaults(suiteName: suite)!
      defer { defaults.removePersistentDomain(forName: suite) }
      let preferences = ManagerPanelPreferences(defaults: defaults, systemLanguages: { ["zh-Hans"] })
      let controller = FeatureSelectionController(scope: ["git-pull"], preferences: preferences)
      if mode == "state" {
          app.setActivationPolicy(.prohibited)
          app.finishLaunching()
          controller.verifyCloseStates(manager)
      } else { controller.verifyRunLoop(mode, manager: manager) }
      print("lifecycle \(mode) checks passed: \(checks)")
    SWIFT
    modes = %w[state selector idle-background idle-quit idle-cancel busy-red busy-button busy-cmdq busy-terminate close-race]
    Dir.mktmpdir('jobs-manager-lifecycle-') do |dir|
      path = File.join(dir, 'main.swift')
      binary = File.join(dir, 'lifecycle-regression')
      fixture = File.join(dir, '有界假worker.zsh')
      zdot = File.join(dir, 'EmptyZdot')
      Dir.mkdir(zdot)
      File.write(path, source + "\n" + harness)
      File.write(fixture, <<~'ZSH')
        [[ "$1" == --non-interactive && "$2" == --action && "$3" == install && "$4" == --features && "$5" == git-pull ]] || exit 81
        printf 'started\n' > "$JOBS_LIFECYCLE_WORKER_RECEIPT"
        printf '生命周期中文开始\n'
        printf 'JOBS_MANAGER_EVENT\tgit-pull\trunning\t正在执行假任务\n'
        /bin/sleep 0.20
        printf 'JOBS_MANAGER_EVENT\tgit-pull\tsucceeded\t假任务结果完成\n'
        /bin/sleep 0.20
        printf '生命周期中文尾输出\n'
        printf 'completed\n' >> "$JOBS_LIFECYCLE_WORKER_RECEIPT"
        exit 0
      ZSH
      output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', path, '-o', binary)
      assert status.success?, output
      artifacts = ENV.fetch('JOBS_MANAGER_LIFECYCLE_ARTIFACTS_DIR', '')
      FileUtils.mkdir_p(artifacts) unless artifacts.empty?
      counts = {}
      modes.each do |mode|
        worker_receipt = File.join(dir, "worker-#{mode}.txt")
        output, status = Open3.capture2e({ 'ZDOTDIR' => zdot, 'JOBS_LIFECYCLE_WORKER_RECEIPT' => worker_receipt }, binary, mode, fixture)
        File.write(File.join(artifacts, "#{mode}.log"), output) unless artifacts.empty?
        assert status.success?, "#{mode}: #{output}"
        assert_match(/lifecycle #{Regexp.escape(mode)} checks passed: \d+/, output)
        counts[mode] = output[/passed: (\d+)/, 1].to_i
      end
      total = counts.values.sum
      assert_operator total, :>=, 150
      puts "AppKit lifecycle checks: #{total} across #{modes.length} isolated processes"
      unless artifacts.empty?
        File.write(File.join(artifacts, 'receipt.json'), JSON.pretty_generate({ source_sha256: Digest::SHA256.hexdigest(original),
          appkit_checks: total, scenarios: counts, actual_worker: 'bounded fixture only', installed_or_registered: false }) + "\n")
        puts "AppKit lifecycle artifacts: #{File.expand_path(artifacts)}"
      end
    end
  end
end
