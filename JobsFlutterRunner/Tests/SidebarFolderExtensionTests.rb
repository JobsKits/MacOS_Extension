# frozen_string_literal: true
# 编译真实独立扩展，以内存 Finder 和宿主替身验证侧边栏路径及点击；不登记扩展、不打开 App。

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

class SidebarFolderExtensionTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  EXTENSIONS = %w[
    JobsFlutterCodegen/JobsFlutterCodegenFinderSync/FinderSync.swift
    JobsFlutterDependencyExtractor/JobsFlutterDependencyFinderSync/FinderSync.swift
    JobsFlutterDoctor/JobsFlutterDoctorFinderSync/FinderSync.swift
    JobsFlutterPackager/JobsFlutterPackagerFinderSync/FinderSync.swift
    JobsFlutterRunner/JobsFlutterRunFinderSync/FinderSync.swift
    JobsFlutterSdkInspector/JobsFlutterSdkInspectorFinderSync/FinderSync.swift
    JobsFlutterVersionMgr/JobsFlutterVersionFinderSync/FinderSync.swift
    JobsGitPuller/JobsGitPullFinderSync/FinderSync.swift
    JobsGitRollback/JobsGitRollbackFinderSync/FinderSync.swift
    JobsVSCodeOpener/JobsVSCodeFinderSync/FinderSync.swift
    JobsXcodeOpener/JobsXcodeFinderSync/FinderSync.swift
    JobsAndroidStudioOpener/JobsAndroidStudioFinderSync/FinderSync.swift
  ].freeze

  def test_sidebar_menus_and_clicks_use_only_the_targeted_local_directory
    Dir.mktmpdir('jobs-sidebar-folders-') do |directory|
      sources = EXTENSIONS.each_with_index.map do |relative, index|
        isolated_source(relative).gsub(/\bFinderSync\b/, "FinderSync#{index}")
                                 .gsub(/\bFinderDesktopMenuPolicy\b/, "FinderDesktopMenuPolicy#{index}")
      end
      sources << isolated_source('JobsFlutterPackager/JobsFlutterPackagingShared/FlutterPackagingMenuContext/FlutterPackagingMenuContext.swift')
      instances = EXTENSIONS.each_index.map { |index| "(\"#{EXTENSIONS[index].split('/').first}\", FinderSync#{index}())" }.join(",\n")
      checks = <<~SWIFT
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            assertions += 1
            guard condition() else { fatalError(message) }
        }
        func actionItem(_ menu: NSMenu?) -> NSMenuItem? {
            guard let item = menu?.items.first else { return nil }
            return item.submenu?.items.first ?? item
        }
        func click(_ menu: NSMenu?) {
            guard let item = actionItem(menu), let target = item.target as? NSObject,
                  let action = item.action else { fatalError("missing menu action") }
            _ = target.perform(action, with: item)
        }
        let manager = FileManager.default
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let folder = root.appendingPathComponent("侧边栏 项目#一", isDirectory: true)
        let other = root.appendingPathComponent("主区域旧选中项", isDirectory: true)
        let desktop = TestSandboxEnvironment.desktopURLs[0]
        for url in [folder, other, desktop] {
            try manager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let file = root.appendingPathComponent("普通文件.txt")
        try Data("fixture".utf8).write(to: file)
        let controller = FIFinderSyncController.default()
        let extensions: [(String, FIFinderSync)] = [#{instances}]
        for (name, finder) in extensions {
            TestProjectRules.qualifies = true
            controller.selected = [other, file]
            controller.targeted = folder
            let menu = finder.menu(for: .contextualMenuForSidebar)
            expect(menu?.items.count == 1, "\\(name): sidebar remains available despite unrelated multiselection")
            expect(NSStringFromSelector(actionItem(menu)!.action!).contains("Sidebar"), "\\(name): sidebar has its own action context")
            TestActions.reset()
            click(menu)
            expect(TestActions.count == 1, "\\(name): sidebar click dispatched once")
            expect(TestActions.lastPath == folder.path, "\\(name): sidebar click uses clicked folder rather than main selection")

            controller.targeted = desktop
            let desktopMenu = finder.menu(for: .contextualMenuForSidebar)
            expect(desktopMenu?.items.count == 1, "\\(name): Desktop favorite is a folder selection")
            TestActions.reset()
            click(desktopMenu)
            expect(TestActions.lastPath == desktop.path, "\\(name): Desktop favorite click keeps targeted folder")
            expect(finder.menu(for: .contextualMenuForContainer) == nil, "\\(name): desktop background policy is preserved")

            controller.targeted = folder
            TestProjectRules.qualifies = false
            expect(finder.menu(for: .contextualMenuForSidebar) == nil, "\\(name): sidebar respects project-type filter")
            TestActions.reset()
            click(menu)
            expect(TestActions.count == 0, "\\(name): click revalidates project type")
            TestProjectRules.qualifies = true

            for invalid in [nil, file, root.appendingPathComponent("目录已移走"), URL(string: "https://example.test/folder")!, URL(string: "file://other-host\\(folder.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)")!] as [URL?] {
                controller.targeted = invalid
                controller.selected = [other]
                expect(finder.menu(for: .contextualMenuForSidebar) == nil, "\\(name): invalid sidebar target must never fall back to main selection")
                TestActions.reset()
                click(menu)
                expect(TestActions.count == 0, "\\(name): invalidated sidebar callback does not dispatch")
            }
            controller.targeted = folder
            controller.selected = [other]
            expect(finder.menu(for: .toolbarItemMenu) == nil, "\\(name): toolbar behavior is unchanged")
            TestActions.reset()
            click(finder.menu(for: .contextualMenuForItems))
            expect(TestActions.lastPath == other.path, "\\(name): original item callback still uses main selection")
            TestActions.reset()
            click(finder.menu(for: .contextualMenuForContainer))
            expect(TestActions.lastPath == folder.path, "\\(name): original background callback still uses target")
        }
        print("PASS: \\(assertions) independent sidebar routing assertions")
      SWIFT
      source_path = File.join(directory, 'main.swift')
      binary_path = File.join(directory, 'sidebar-tests')
      File.write(source_path, [swift_stubs, *sources, checks].join("\n"))
      output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', source_path, '-o', binary_path)
      assert status.success?, output
      output, status = Open3.capture2e(binary_path, directory)
      assert status.success?, output
      assert_includes output, 'independent sidebar routing assertions'
      puts output.lines.grep(/^PASS:/)
    end
  end

  private

  def isolated_source(relative)
    File.read(File.join(ROOT, relative))
        .gsub(/^import (?:AppKit|FinderSync)\s*$/, '')
        .gsub('FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)', 'TestSandboxEnvironment.desktopURLs')
  end

  def swift_stubs
    <<~'SWIFT'
      import Foundation
      import Darwin

      enum TestSandboxEnvironment {
          static var desktopURLs: [URL] {
              return [URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).appendingPathComponent("Desktop", isDirectory: true)]
          }
      }
      enum FIMenuKind: Int { case contextualMenuForItems, contextualMenuForContainer, contextualMenuForSidebar, toolbarItemMenu }
      class FIFinderSync: NSObject {
          func menu(for kind: FIMenuKind) -> NSMenu? { return nil }
      }
      final class FIFinderSyncController {
          static let shared = FIFinderSyncController()
          var directoryURLs: Set<URL> = []
          var selected: [URL]?
          var targeted: URL?
          static func `default`() -> FIFinderSyncController { return shared }
          func selectedItemURLs() -> [URL]? { return selected }
          func targetedURL() -> URL? { return targeted }
          @discardableResult func byDirectoryURLs(_ urls: Set<URL>) -> Self {
              directoryURLs = urls
              return self
          }
      }
      final class NSMenu: NSObject {
          var items: [NSMenuItem] = []
          init(title: String) { super.init() }
          func addItem(_ item: NSMenuItem) { items.append(item) }
          static func make(title: String) -> NSMenu { return NSMenu(title: title) }
          @discardableResult func byAddItem(_ item: NSMenuItem) -> Self {
              addItem(item)
              return self
          }
      }
      final class NSMenuItem: NSObject {
          let title: String
          let action: Selector?
          var target: AnyObject?
          var submenu: NSMenu?
          init(title: String, action: Selector?, keyEquivalent: String) {
              self.title = title
              self.action = action
              super.init()
          }
          static func make(title: String, action: Selector?, keyEquivalent: String, configure: (NSMenuItem) -> Void) -> NSMenuItem {
              let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
              configure(item)
              return item
          }
          @discardableResult func byTarget(_ object: AnyObject) -> Self {
              target = object
              return self
          }
      }
      final class NSAlert {
          enum Style { case warning }
          var alertStyle = Style.warning
          var messageText = ""
          var informativeText = ""
          func addButton(withTitle: String) {}
          func runModal() {}
          static func jobsMake(configure: (NSAlert) -> Void) -> NSAlert {
              let alert = NSAlert()
              configure(alert)
              return alert
          }
          @discardableResult func byAlertStyle(_ value: Style) -> Self { alertStyle = value; return self }
          @discardableResult func byMessageText(_ value: String) -> Self { messageText = value; return self }
          @discardableResult func byInformativeText(_ value: String) -> Self { informativeText = value; return self }
          @discardableResult func byAddButton(_ value: String) -> Self { return self }
      }
      enum TestActions {
          static var count = 0
          static var lastPath: String?
          static func reset() { count = 0; lastPath = nil }
          static func capture(_ url: URL) {
              count += 1
              lastPath = url.isFileURL ? url.path : URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "path" })?.value
          }
      }
      enum TestProjectRules { static var qualifies = true }
      final class NSWorkspace {
          final class OpenConfiguration { var activates = false }
          static let shared = NSWorkspace()
          func open(_ url: URL) -> Bool { TestActions.capture(url); return true }
          func open(_ url: URL, configuration: OpenConfiguration, completionHandler: (NSObject?, Error?) -> Void) {
              TestActions.capture(url)
              completionHandler(nil, nil)
          }
      }
      struct ProjectOpener {
          static func canOpen(_ url: URL) -> Bool { return TestProjectRules.qualifies }
          func canOpen(_ url: URL) -> Bool { return TestProjectRules.qualifies }
          func open(_ url: URL) { TestActions.capture(url) }
      }
      enum XcodeProjectDetector {
          static func canOpen(_ url: URL) -> Bool { return TestProjectRules.qualifies }
      }
      struct FlutterProjectValidator {
          func isFlutterProject(at: URL) -> Bool { return TestProjectRules.qualifies }
      }
      struct GitFolderValidator {
          func isFolder(at: URL) -> Bool { return TestProjectRules.qualifies }
      }
      struct GitRollbackMenuContext {
          func isFolder(at: URL) -> Bool { return TestProjectRules.qualifies }
      }
      struct FixtureRequest {
          static let notificationName = Notification.Name("fixture")
          static let distributedObject = "fixture"
          static let pathUserInfoKey = "path"
          static func url(for target: URL) -> URL? { return url(forPath: target.path) }
          static func url(forPath path: String) -> URL? {
              var components = URLComponents()
              components.scheme = "fixture"
              components.host = "open"
              components.queryItems = [URLQueryItem(name: "path", value: path)]
              return components.url
          }
      }
      typealias ProjectRequest = FixtureRequest
      typealias FlutterManagerRequest = FixtureRequest
      typealias FlutterDependencyRequest = FixtureRequest
      typealias FlutterDoctorRequest = FixtureRequest
      typealias FlutterCodegenRequest = FixtureRequest
      typealias FlutterRunRequest = FixtureRequest
      typealias FlutterInspectorRequest = FixtureRequest
      typealias FlutterPackagingRequest = FixtureRequest
      typealias GitPullRequest = FixtureRequest
      typealias GitRollbackRequest = FixtureRequest
      final class DistributedNotificationCenter {
          static func `default`() -> DistributedNotificationCenter { return DistributedNotificationCenter() }
          func postNotificationName(_ name: Notification.Name, object: String?, userInfo: [String: String], deliverImmediately: Bool) {}
      }
    SWIFT
  end
end
