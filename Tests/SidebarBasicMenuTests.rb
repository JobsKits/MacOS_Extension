# frozen_string_literal: true
# 编译真实菜单、候选目录和点击回调；只替换剪贴板、提示、远程解析和应用打开等系统副作用。

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
require 'tmpdir'

class SidebarBasicMenuTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  EXTENSIONS = [
    ['JobsPathCopier/JobsPathCopyFinderSync/FinderSync.swift', '📋 复制绝对路径'],
    ['JobsGitRemoteCopier/JobsGitRemoteCopyFinderSync/FinderSync.swift', '🔗 复制 Git 远程地址'],
    ['JobsGitRemoteOpener/JobsGitRemoteFinderSync/FinderSync.swift', '🌐 打开 Git 远程地址']
  ].freeze

  def test_sidebar_uses_the_clicked_folder_and_preserves_item_only_boundaries
    Dir.mktmpdir('jobs-sidebar-basic-menu-') do |directory|
      source_path = File.join(directory, 'main.swift')
      binary_path = File.join(directory, 'sidebar-basic-menu-tests')
      sources = EXTENSIONS.each_with_index.map { |(path, _), index| isolated_source(path, index) }
      request = File.read(File.join(ROOT, 'JobsGitRemoteOpener/JobsGitRemoteOpener/GitRemoteOpenRequest.swift'))
      File.write(source_path, [swift_stubs, request, *sources, swift_checks].join("\n"))

      output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', source_path, '-o', binary_path)
      assert status.success?, output
      output, status = Open3.capture2e(binary_path, directory)
      assert status.success?, output
      assert_match(/PASS: \d+ basic sidebar menu assertions/, output)
      puts output.lines.grep(/^PASS:/)
    end
  end

  def test_remote_host_deduplicates_url_delivery_and_preserves_manual_startup
    Dir.mktmpdir('jobs-remote-host-') do |directory|
      source_path = File.join(directory, 'main.swift')
      binary_path = File.join(directory, 'remote-host-tests')
      request = File.read(File.join(ROOT, 'JobsGitRemoteOpener/JobsGitRemoteOpener/GitRemoteOpenRequest.swift'))
      host = File.read(File.join(ROOT, 'JobsGitRemoteOpener/JobsGitRemoteOpener/AppDelegate.swift'))
      host = host.gsub(/^@main\s*$/, '')
      host = host.gsub('private extension AppDelegate {', 'fileprivate extension AppDelegate {')
      host = host.gsub('@objc private func', '@objc fileprivate func')
      host = host.sub(': NSObject, NSApplicationDelegate {', ': NSObject {')
      host = host.sub('URL(fileURLWithPath: "/tmp/JobsGitRemoteOpener.log")', 'URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("host.log")')
      host = host.sub("        scheduleFinderRefreshIfNeeded()\n", '')
      host = host.gsub('NSAppleEventManager.shared()', 'TestAppleEventManager.shared()')
      host = host.gsub(/\bNSApplication\b/, 'TestApplication')
      host = host.gsub(/\bNSWindow\b/, 'TestWindow')
      host = host.gsub(/\bNSAlert\b/, 'TestAlert')
      host = host.gsub(/\bNSApp\b/, 'TestApplication.shared')
      File.write(source_path, [remote_host_stubs, request, host, remote_host_checks].join("\n"))
      output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', source_path, '-o', binary_path)
      assert status.success?, output
      output, status = Open3.capture2e(binary_path, directory)
      assert status.success?, output
      assert_match(/PASS: \d+ remote host assertions/, output)
      puts output.lines.grep(/^PASS:/)
    end
  end

  private

  def remote_host_stubs
    <<~'SWIFT'
      import AppKit
      enum HostEffects {
          static var opened: [URL] = []
          static var windows = 0
          static var alerts: [String] = []
          static var terminated = 0
          static var failBrowser = false
          static var browserWasBackground = false
      }
      final class TestApplication: NSObject {
          static let shared = TestApplication()
          func activate(ignoringOtherApps: Bool) {}
          func terminate(_ sender: Any?) { HostEffects.terminated += 1 }
      }
      final class TestAppleEventManager {
          static let instance = TestAppleEventManager()
          static func shared() -> TestAppleEventManager { instance }
          var registrations = 0
          func setEventHandler(_ handler: Any, andSelector: Selector, forEventClass: AEEventClass, andEventID: AEEventID) {
              registrations += 1
          }
      }
      final class MainViewController { var view = "view" }
      final class TestWindow {
          struct StyleMask: OptionSet {
              let rawValue: Int
              static let titled = StyleMask(rawValue: 1)
              static let closable = StyleMask(rawValue: 2)
              static let miniaturizable = StyleMask(rawValue: 4)
          }
          enum Backing { case buffered }
          var title = ""
          var contentViewController: MainViewController?
          var isVisible = false
          init(contentRect: NSRect, styleMask: StyleMask, backing: Backing, defer: Bool) {
              HostEffects.windows += 1
          }
          func center() {}
          func makeKeyAndOrderFront(_ sender: Any?) { isVisible = true }
      }
      final class TestAlert {
          enum Style { case warning }
          var alertStyle = Style.warning
          var messageText = ""
          var informativeText = ""
          func addButton(withTitle: String) {}
          func runModal() { HostEffects.alerts.append(informativeText) }
      }
      struct GitRemoteBrowserOpener {
          func open(from url: URL) throws {
              HostEffects.browserWasBackground = !Thread.isMainThread
              HostEffects.opened.append(url)
              if HostEffects.failBrowser {
                  throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "browser failed"])
              }
          }
      }
    SWIFT
  end

  def remote_host_checks
    <<~'SWIFT'
      var assertions = 0
      func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
          assertions += 1
          guard condition() else { fatalError(message) }
      }
      func wait(_ duration: TimeInterval = 0.3) {
          let deadline = Date().addingTimeInterval(duration)
          while Date() < deadline {
              _ = RunLoop.current.run(mode: .default, before: deadline)
          }
      }
      let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
      let request = GitRemoteOpenRequest.url(for: root)!
      let notification = Notification(name: Notification.Name("test-launch"))
      let host = AppDelegate()
      host.applicationWillFinishLaunching(notification)
      expect(TestAppleEventManager.shared().registrations == 1, "Register the AppleEvent URL receiver before launch finishes")
      host.applicationDidFinishLaunching(notification)
      host.application(TestApplication.shared, open: [request])
      let event = NSAppleEventDescriptor(eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL), targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
      event.setParam(NSAppleEventDescriptor(string: request.absoluteString), forKeyword: keyDirectObject)
      host.handleOpenURL(event, withReplyEvent: NSAppleEventDescriptor.null())
      wait()
      expect(HostEffects.opened == [root], "Two URL delivery callbacks dispatch one browser operation")
      expect(HostEffects.browserWasBackground, "Resolve and dispatch outside the main thread")
      expect(HostEffects.windows == 0, "URL cold launch never creates the management window")
      expect(HostEffects.alerts.isEmpty, "Valid URL dispatch has no error prompt")
      host.application(TestApplication.shared, open: [])
      host.application(TestApplication.shared, open: [request, request])
      host.application(TestApplication.shared, open: [URL(string: "jobsgitremoteopener://open?path=relative")!])
      expect(HostEffects.alerts.count == 3, "Empty, multiple and malformed requests are rejected")
      expect(HostEffects.opened.count == 1, "Rejected requests do not start browser operations")
      let other = root.appendingPathComponent("another folder 中文", isDirectory: true)
      try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
      HostEffects.failBrowser = true
      host.application(TestApplication.shared, open: [GitRemoteOpenRequest.url(for: other)!])
      wait()
      expect(HostEffects.alerts.last == "browser failed", "Background failure reaches the main-thread prompt")
      HostEffects.failBrowser = false
      wait(0.8)
      expect(HostEffects.terminated == 1, "Completed URL-only host exits after dispatch")
      let manualHost = AppDelegate()
      manualHost.applicationDidFinishLaunching(notification)
      wait()
      expect(HostEffects.windows == 1, "Manual app startup keeps the management window")
      expect(manualHost.applicationShouldHandleReopen(TestApplication.shared, hasVisibleWindows: true), "Manual reopen is accepted")
      expect(HostEffects.windows == 1, "Reopen reuses the existing management window")
      print("PASS: \(assertions) remote host assertions")
    SWIFT
  end

  def isolated_source(path, index)
    source = File.read(File.join(ROOT, path))
    marker = '    func showFailureAlert(messages: [String]) {'
    assert_includes source, marker, "Missing isolation boundary in #{path}"
    source = source.split(marker, 2).first
    source = source.gsub(/^import (?:AppKit|CoreFoundation|FinderSync|UserNotifications)\s*$/, '')
    source = source.gsub(/\bFinderSync\b/, "BasicFinderSync#{index}")
    # 日志属性的目录创建也限定在临时目录，不写真实 Application Support。
    source = source.sub(
      'FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory',
      'URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)'
    )
    source + <<~'SWIFT'
          func showFailureAlert(messages: [String]) { TestActions.failures += 1 }
          func showSuccessPrompt(path: String) {}
          func showSuccessPrompt(remoteURLString: String) {}
          func copyToPasteboard(_ value: String) throws { TestActions.copied.append(value) }
          func writeLog(_ message: String) {}
      }
    SWIFT
  end

  def swift_stubs
    <<~'SWIFT'
      import Foundation

      enum FIMenuKind: Int {
          case contextualMenuForItems, contextualMenuForContainer, contextualMenuForSidebar, toolbarItemMenu
      }
      class FIFinderSync: NSObject {
          func menu(for menuKind: FIMenuKind) -> NSMenu? { return nil }
      }
      final class FIFinderSyncController {
          static let shared = FIFinderSyncController()
          var directoryURLs: Set<URL> = []
          var selected: [URL]?
          var targeted: URL?
          static func `default`() -> FIFinderSyncController { return shared }
          func selectedItemURLs() -> [URL]? { return selected }
          func targetedURL() -> URL? { return targeted }
      }
      final class NSMenu: NSObject {
          var items: [NSMenuItem] = []
          init(title: String) { super.init() }
          func addItem(_ item: NSMenuItem) { items.append(item) }
      }
      final class NSMenuItem: NSObject {
          let title: String
          let action: Selector?
          var target: AnyObject?
          var isEnabled = true
          init(title: String, action: Selector?, keyEquivalent: String) {
              self.title = title
              self.action = action
              super.init()
          }
      }
      enum TestActions {
          static var inputs: [URL] = []
          static var opened: [URL] = []
          static var copied: [String] = []
          static var failures = 0
          static var openSucceeds = true
          static let remoteURL = URL(string: "https://example.test/jobs/repository")!
          static func reset() {
              inputs = []
              opened = []
              copied = []
              failures = 0
              openSucceeds = true
          }
      }
      final class PathClipboardWriter {
          func copyAbsolutePath(from url: URL) throws -> String {
              TestActions.inputs.append(url)
              TestActions.copied.append(url.path)
              return url.path
          }
      }
      final class GitRemoteResolver {
          func remoteURLString(from url: URL) throws -> String {
              TestActions.inputs.append(url)
              return TestActions.remoteURL.absoluteString
          }
          func webURL(from url: URL) throws -> URL {
              TestActions.inputs.append(url)
              return TestActions.remoteURL
          }
      }
      final class NSWorkspace {
          static let shared = NSWorkspace()
          @discardableResult func open(_ url: URL) -> Bool {
              TestActions.opened.append(url)
              if let request = GitRemoteOpenRequest(url: url) {
                  TestActions.inputs.append(request.projectURL)
              }
              return TestActions.openSucceeds
          }
      }
    SWIFT
  end

  def swift_checks
    cases = EXTENSIONS.each_with_index.map { |(_, title), index| "(BasicFinderSync#{index}(), #{title.inspect}, #{index})" }.join(",\n    ")
    <<~SWIFT
      var assertionCount = 0
      func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
          assertionCount += 1
          guard condition() else { fatalError(message) }
      }
      func click(_ menu: NSMenu) {
          guard let item = menu.items.first, let target = item.target as? NSObject,
                let action = item.action else {
              fatalError("Missing actual menu target or selector")
          }
          expect(target.responds(to: action), "Actual menu selector must resolve")
          _ = target.perform(action, with: item)
      }
      func expectDispatch(_ expected: URL, index: Int) {
          expect(TestActions.inputs == [expected], "Action must use the intended context URL")
          expect(TestActions.failures == 0, "Valid target must dispatch successfully")
          if index == 2 {
              expect(TestActions.opened.count == 1, "Remote opener dispatches one host request")
              expect(TestActions.opened.first?.scheme == "jobsgitremoteopener", "Remote opener routes through its host")
              expect(TestActions.opened.first.flatMap(GitRemoteOpenRequest.init(url:))?.projectURL == expected, "Host request preserves the intended context URL")
              expect(TestActions.copied.isEmpty, "Open action must not copy")
          } else {
              let value = index == 0 ? expected.path : TestActions.remoteURL.absoluteString
              expect(TestActions.copied == [value], "Copy action uses clipboard replacement")
              expect(TestActions.opened.isEmpty, "Copy action must not open an application")
          }
      }
      let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
      let folderA = root.appendingPathComponent("selected-A", isDirectory: true)
      let folderB = root.appendingPathComponent("sidebar B 中文", isDirectory: true)
      let regularFile = root.appendingPathComponent("ordinary.txt")
      try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
      try Data("fixture".utf8).write(to: regularFile)
      var nonLocal = URLComponents(url: folderB, resolvingAgainstBaseURL: false)!
      nonLocal.host = "untrusted.example"
      let invalidTargets: [URL?] = [
          nil,
          URL(string: "https://example.test/folder"),
          nonLocal.url!,
          regularFile,
          root.appendingPathComponent("missing", isDirectory: true)
      ]
      let controller = FIFinderSyncController.default()
      let extensions: [(FIFinderSync, String, Int)] = [
          #{cases}
      ]
      for (finder, title, index) in extensions {
          expect(controller.directoryURLs.contains(URL(fileURLWithPath: "/", isDirectory: true)), "Monitor real folders")
          controller.selected = [folderA]
          controller.targeted = folderB
          guard let sidebar = finder.menu(for: .contextualMenuForSidebar) else {
              fatalError("Sidebar folder must produce a menu")
          }
          expect(sidebar.items.map(\\.title) == [title], "Sidebar preserves the existing action title")
          TestActions.reset()
          click(sidebar)
          expectDispatch(folderB, index: index)

          // 主内容区的多选或无选中项不能覆盖侧边栏实际右键的目录。
          for selection: [URL]? in [nil, [], [folderA, regularFile]] {
              controller.selected = selection
              guard let menu = finder.menu(for: .contextualMenuForSidebar) else {
                  fatalError("Sidebar target must not depend on the main pane selection")
              }
              TestActions.reset()
              click(menu)
              expectDispatch(folderB, index: index)
          }

          controller.selected = [folderA]
          for target in invalidTargets {
              controller.targeted = target
              expect(finder.menu(for: .contextualMenuForSidebar) == nil, "Invalid sidebar target hides the menu")
              TestActions.reset()
              click(sidebar)
              expect(TestActions.inputs.isEmpty, "Stale sidebar action must not fall back to the selected folder")
              expect(TestActions.opened.isEmpty && TestActions.copied.isEmpty, "Invalid target has no external action")
              expect(TestActions.failures == 1, "Invalid action reports its failure through the replacement")
          }

          controller.targeted = folderB
          for selection in [folderA, regularFile] {
              controller.selected = [selection]
              guard let menu = finder.menu(for: .contextualMenuForItems) else {
                  fatalError("Existing single item selection must remain supported")
              }
              expect(menu.items.map(\\.title) == [title], "Items preserve the existing title")
              TestActions.reset()
              click(menu)
              if index == 2 && selection == regularFile {
                  expectDispatch(root, index: index)
              } else {
                  expectDispatch(selection, index: index)
              }
          }
          for selection: [URL]? in [nil, [], [folderA, folderB]] {
              controller.selected = selection
              expect(finder.menu(for: .contextualMenuForItems) == nil, "Existing empty/multiple selection rejection remains")
          }
          controller.selected = [folderA]
          for kind in [FIMenuKind.contextualMenuForContainer, .toolbarItemMenu] {
              expect(finder.menu(for: kind) == nil, "Container and toolbar do not gain folder actions")
          }
          if index == 2 {
              controller.targeted = folderB
              let sidebar = finder.menu(for: .contextualMenuForSidebar)!
              TestActions.reset()
              TestActions.openSucceeds = false
              click(sidebar)
              expect(TestActions.opened.count == 1, "Failed host launch is attempted once")
              expect(TestActions.failures == 1, "Failed host launch reports an error")
              expect(TestActions.copied.isEmpty, "Failed host launch never copies a remote")
          }
      }
      let special = root.appendingPathComponent("引号 ' & ?# + 中文", isDirectory: true)
      try FileManager.default.createDirectory(at: special, withIntermediateDirectories: true)
      let validRequest = GitRemoteOpenRequest.url(for: special)!
      expect(GitRemoteOpenRequest(url: validRequest)?.projectURL == special, "Request round trip preserves path punctuation and Unicode")
      for invalid in [regularFile, nonLocal.url!, root.appendingPathComponent("absent"), URL(string: "https://example.test/path")!] {
          expect(GitRemoteOpenRequest.url(for: invalid) == nil, "Invalid local directory cannot form a host request")
      }
      let linkedFolder = root.appendingPathComponent("linked-folder")
      try FileManager.default.createSymbolicLink(at: linkedFolder, withDestinationURL: folderB)
      expect(GitRemoteOpenRequest.url(for: linkedFolder) == nil, "Symbolic links are rejected by the folder contract")
      let package = root.appendingPathComponent("Example.app", isDirectory: true)
      try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
      expect(GitRemoteOpenRequest.url(for: package) == nil, "Application packages are rejected by the folder contract")
      let validComponents = URLComponents(url: validRequest, resolvingAgainstBaseURL: false)!
      var malformed: [URLComponents] = []
      var candidate = validComponents
      candidate.queryItems!.append(URLQueryItem(name: "path", value: folderA.path))
      malformed.append(candidate)
      candidate = validComponents
      candidate.queryItems!.append(URLQueryItem(name: "unexpected", value: "true"))
      malformed.append(candidate)
      for path in ["", "relative/path", "bad\\0path", regularFile.path, linkedFolder.path, package.path, root.appendingPathComponent("missing").path] {
          candidate = validComponents
          candidate.queryItems = [URLQueryItem(name: "path", value: path)]
          malformed.append(candidate)
      }
      candidate = validComponents
      candidate.scheme = "unexpected"
      malformed.append(candidate)
      candidate = validComponents
      candidate.host = "other"
      malformed.append(candidate)
      candidate = validComponents
      candidate.path = "/extra"
      malformed.append(candidate)
      candidate = validComponents
      candidate.fragment = "unexpected"
      malformed.append(candidate)
      candidate = validComponents
      candidate.user = "user"
      malformed.append(candidate)
      candidate = validComponents
      candidate.password = "password"
      malformed.append(candidate)
      candidate = validComponents
      candidate.port = 1234
      malformed.append(candidate)
      for components in malformed {
          expect(components.url.flatMap(GitRemoteOpenRequest.init(url:)) == nil, "Malformed or stale host request is rejected")
      }
      print("PASS: \\(assertionCount) basic sidebar menu assertions")
    SWIFT
  end
end
