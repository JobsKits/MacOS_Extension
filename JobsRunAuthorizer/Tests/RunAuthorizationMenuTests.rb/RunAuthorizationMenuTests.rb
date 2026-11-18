# frozen_string_literal: true
# 编译真实菜单与共享源码，仅用内存替身承接 Finder/AppKit；不打开应用或注册扩展。

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

class RunAuthorizationMenuTests < Minitest::Test
  ROOT = File.expand_path('..', File.dirname(__dir__))
  SOURCES = %w[
    JobsRunAuthorizerFinderSync/FinderSync.swift
    JobsRunAuthorizationShared/RunAuthorizationValidator/RunAuthorizationValidator.swift
    JobsRunAuthorizationShared/RunAuthorizationRequest/RunAuthorizationRequest.swift
    JobsRunAuthorizationShared/JobsAuthorizationFactories.swift
  ].freeze

  def test_real_menu_and_click_callbacks_enforce_single_file_boundary
    Dir.mktmpdir('jobs-run-authorization-menu-tests-') do |directory|
      swift_path = File.join(directory, 'main.swift')
      binary_path = File.join(directory, 'run-authorization-menu-tests')
      sources = SOURCES.map do |relative_path|
        File.read(File.join(ROOT, relative_path)).gsub(/^import (?:AppKit|FinderSync)[ \t]*$/, '')
      end
      File.write(swift_path, swift_stubs + "\n" + sources.join("\n") + "\n" + swift_checks)
      output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', swift_path, '-o', binary_path)
      assert status.success?, output
      output, status = Open3.capture2e(binary_path, directory)
      assert status.success?, output
      assert_match(/PASS: \d+ run authorization menu assertions/, output)
      puts output.lines.grep(/^PASS:/)
    end
  end

  private

  def swift_stubs
    <<~'SWIFT'
      import Foundation
      import Darwin

      enum FIMenuKind: Int, CaseIterable {
          case contextualMenuForItems
          case contextualMenuForContainer
          case contextualMenuForSidebar
          case toolbarItemMenu
          case unsupportedMenuKind = 99
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
          let title: String
          var autoenablesItems = true
          var items: [NSMenuItem] = []
          init(title: String) {
              self.title = title
              super.init()
          }
          func addItem(_ item: NSMenuItem) { items.append(item) }
      }
      final class NSMenuItem: NSObject {
          let title: String
          let action: Selector?
          var isEnabled = true
          var target: AnyObject?
          init(title: String, action: Selector?, keyEquivalent: String) {
              self.title = title
              self.action = action
              super.init()
          }
      }
      enum TestAlerts { static var count = 0 }
      final class NSAlert {
          enum Style { case warning }
          var alertStyle = Style.warning
          var messageText = ""
          var informativeText = ""
          func addButton(withTitle: String) {}
          func runModal() { TestAlerts.count += 1 }
      }
      enum TestWorkspace {
          static var urls: [URL] = []
          static var openSucceeds = true
          static func reset() {
              urls.removeAll()
              openSucceeds = true
              TestAlerts.count = 0
          }
      }
      final class NSWorkspace {
          static let shared = NSWorkspace()
          func open(_ url: URL) -> Bool {
              TestWorkspace.urls.append(url)
              return TestWorkspace.openSucceeds
          }
      }
      protocol NSApplicationDelegate: AnyObject {}
      final class NSApplication {
          var delegate: NSApplicationDelegate?
      }
    SWIFT
  end

  def swift_checks
    <<~'SWIFT'
      var assertionCount = 0
      func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
          assertionCount += 1
          if !condition() {
              fputs("FAILED: \(message)\n", stderr)
              exit(1)
          }
      }
      func click(_ menu: NSMenu?) {
          guard let item = menu?.items.first, let target = item.target as? NSObject,
                let action = item.action else {
              expect(false, "real menu must expose a target/action selector")
              return
          }
          expect(target.responds(to: action), "real Objective-C selector is available")
          _ = target.perform(action, with: item)
      }
      let manager = FileManager.default
      let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
      let file = root.appendingPathComponent("普通文件.command")
      let otherFile = root.appendingPathComponent("另一个文件.sh")
      let document = root.appendingPathComponent("README.md")
      let textFile = root.appendingPathComponent("ordinary.txt")
      let special = root.appendingPathComponent("中文 空格 ' 双引号\" $ $(touch SUBSTITUTED) `touch BACKTICK`\n下一行.command")
      let folder = root.appendingPathComponent("普通文件夹", isDirectory: true)
      let package = root.appendingPathComponent("Application.app", isDirectory: true)
      let link = root.appendingPathComponent("符号链接.command")
      let brokenLink = root.appendingPathComponent("失效链接.command")
      let missing = root.appendingPathComponent("已删除文件.command")
      let fifo = root.appendingPathComponent("named-pipe.command")
      for regularFile in [file, otherFile, special] {
          try Data("#!/bin/zsh\ntouch EXECUTED\n".utf8).write(to: regularFile)
          try manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: regularFile.path)
      }
      try Data("# ordinary document\n".utf8).write(to: document)
      try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: document.path)
      try Data("ordinary text\n".utf8).write(to: textFile)
      for directory in [folder, package] {
          try manager.createDirectory(at: directory, withIntermediateDirectories: true)
      }
      try manager.createSymbolicLink(at: link, withDestinationURL: file)
      try manager.createSymbolicLink(at: brokenLink, withDestinationURL: missing)
      expect(mkfifo(fifo.path, 0o600) == 0, "isolated FIFO fixture created")

      let controller = FIFinderSyncController.default()
      let extensionInstance = FinderSync()
      expect(controller.directoryURLs == [URL(fileURLWithPath: "/", isDirectory: true)], "root monitoring is configured")
      controller.targeted = folder
      controller.selected = [file]
      let singleMenu = extensionInstance.menu(for: .contextualMenuForItems)
      expect(singleMenu?.items.map(\.title) == ["➕ 授予执行权限（chmod +x）"], "one regular file exposes exactly one action")
      expect(singleMenu?.autoenablesItems == false, "automatic AppKit validation cannot override explicit permission state")
      expect(singleMenu?.items.first?.isEnabled == true, "authorization is enabled without execute bits")
      expect(singleMenu?.items.first?.target === extensionInstance, "menu target is the real extension instance")

      for mode in [0o755, 0o654, 0o645] {
          try manager.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path)
          let executableMenu = extensionInstance.menu(for: .contextualMenuForItems)
          expect(executableMenu?.items.map(\.title) == ["➕ 授予执行权限（chmod +x）"], "execute bits retain the authorization menu")
          expect(executableMenu?.items.first?.isEnabled == true, "partial or existing execute bits permit idempotent chmod +x")
          TestWorkspace.reset()
          click(singleMenu)
          expect(TestWorkspace.urls.count == 1, "permission changes preserve an idempotent chmod +x dispatch")
          expect(TestAlerts.count == 0, "a regular file remains eligible after a permission change")
      }
      try manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

      for menuKind in FIMenuKind.allCases where menuKind != .contextualMenuForItems {
          expect(extensionInstance.menu(for: menuKind) == nil, "non-item context \(menuKind) is always hidden")
      }
      let invalidSelections: [(String, [URL]?)] = [
          ("directory", [folder]),
          ("application package", [package]),
          ("symbolic link", [link]),
          ("dangling symbolic link", [brokenLink]),
          ("missing file", [missing]),
          ("named pipe", [fifo]),
          ("multiple ordinary files", [file, otherFile]),
          ("file and directory", [file, folder]),
          ("empty selection", []),
          ("nil selection", nil),
          ("non-file URL", [URL(string: "https://example.invalid/a.command")!])
      ]
      for ordinary in [document, textFile] {
          controller.selected = [ordinary]
          let ordinaryMenu = extensionInstance.menu(for: .contextualMenuForItems)
          expect(ordinaryMenu?.items.count == 1 && ordinaryMenu?.items.first?.isEnabled == true, "arbitrary single-file formats remain available")
          TestWorkspace.reset()
          click(ordinaryMenu)
          expect(TestWorkspace.urls.count == 1 && TestAlerts.count == 0, "ordinary documents dispatch once without executing the target")
      }
      controller.targeted = file
      for (name, selection) in invalidSelections {
          controller.selected = selection
          expect(extensionInstance.menu(for: .contextualMenuForItems) == nil, "\(name) has no item menu or targetedURL fallback")
      }

      for (name, selection) in invalidSelections {
          controller.selected = selection
          TestWorkspace.reset()
          click(singleMenu)
          expect(TestWorkspace.urls.isEmpty, "stale menu for \(name) never calls workspace.open")
          expect(TestAlerts.count == 1, "stale menu for \(name) reports the boundary failure")
      }

      controller.selected = [missing]
      try Data("deleted fixture".utf8).write(to: missing)
      let deletedMenu = extensionInstance.menu(for: .contextualMenuForItems)
      expect(deletedMenu?.items.count == 1, "file exists when menu opens")
      try manager.removeItem(at: missing)
      TestWorkspace.reset()
      click(deletedMenu)
      expect(TestWorkspace.urls.isEmpty, "file deleted after menu opens never calls workspace.open")
      expect(TestAlerts.count == 1, "deleted file reports the failure")

      controller.selected = [file]
      TestWorkspace.reset()
      click(singleMenu)
      expect(TestWorkspace.urls.count == 1, "valid ordinary file dispatches exactly once")
      expect(TestWorkspace.urls.first.flatMap(RunAuthorizationRequest.fileURL(from:))?.path == file.path,
             "ordinary file dispatch carries the selected path")
      expect(TestAlerts.count == 0, "successful dispatch shows no failure alert")

      controller.selected = [special]
      let specialMenu = extensionInstance.menu(for: .contextualMenuForItems)
      expect(specialMenu?.items.count == 1, "special-character regular file is eligible")
      TestWorkspace.reset()
      click(specialMenu)
      expect(TestWorkspace.urls.count == 1, "special-character file dispatches exactly once")
      guard let request = TestWorkspace.urls.first,
            let components = URLComponents(url: request, resolvingAgainstBaseURL: false) else {
          fatalError("request URL missing")
      }
      expect(components.scheme == "jobsrunauthorizer", "dispatch uses the real request scheme")
      expect(components.host == "authorize", "dispatch uses the real action host")
      expect(components.queryItems?.count == 1, "path remains one query item")
      expect(components.queryItems?.first?.name == "path", "path query item retains its name")
      expect(components.queryItems?.first?.value == special.path, "special path survives URL query encoding exactly")
      expect(RunAuthorizationRequest.fileURL(from: request)?.path == special.path, "real request decoder restores the exact special path")
      expect(TestAlerts.count == 0, "special-character dispatch shows no failure alert")
      for marker in ["SUBSTITUTED", "BACKTICK", "EXECUTED"] {
          expect(!manager.fileExists(atPath: root.appendingPathComponent(marker).path), "\(marker) was never executed")
      }

      controller.selected = [file]
      TestWorkspace.reset()
      TestWorkspace.openSucceeds = false
      click(singleMenu)
      expect(TestWorkspace.urls.count == 1, "workspace failure has no automatic retry")
      expect(TestAlerts.count == 1, "workspace failure reports the failure")
      print("PASS: \(assertionCount) run authorization menu assertions")
    SWIFT
  end
end
