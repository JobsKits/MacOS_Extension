# frozen_string_literal: true
# 编译真实聚合菜单及配置，仅以替身承接 Finder/AppKit，不注册或运行业务。
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
class DesktopMenuTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  def test_fixed_order_permissions_context_and_requests
    Dir.mktmpdir('jobs-desktop-menu-tests-') do |directory|
      sources = %w[
        Shared/DesktopMenuAction/DesktopMenuAction.swift
        Shared/DesktopMenuRequest/DesktopMenuRequest.swift
        Shared/DesktopMenuConfiguration/DesktopMenuConfiguration.swift
        Shared/DesktopMenuContext/DesktopMenuContext.swift
        Shared/HiddenFilesMenuContext/HiddenFilesMenuContext.swift
        Shared/DesktopFactories/DesktopFactories.swift
        Core/FinderHiddenFilesPreferences/FinderHiddenFilesPreferences.swift
        Core/HiddenFilesToggleService/HiddenFilesToggleService.swift
        JobsDesktopToolsFinderSync/FinderSync.swift
      ].map { |path| File.read(File.join(ROOT, path)).gsub(/^import (?:AppKit|FinderSync)[ \t]*$/, '') }
      main = File.join(directory, 'main.swift')
      binary = File.join(directory, 'menu-tests')
      File.write(main, swift_stubs + "\n" + sources.join("\n") + "\n" + swift_checks)
      output, result = Open3.capture2e('/usr/bin/xcrun', 'swiftc', main, '-o', binary)
      assert result.success?, output
      output, result = Open3.capture2e(binary, directory)
      assert result.success?, output
      assert_match(/PASS: \d+ desktop menu assertions/, output)
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
var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError(message) }
}
func click(_ item: NSMenuItem) {
    guard let target = item.target as? NSObject, let action = item.action else {
        fatalError("click requires real selector")
    }
    expect(target.responds(to: action), "real selector exists")
    _ = target.perform(action, with: item)
}
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let configuration = root.appendingPathComponent("features")
let all = DesktopMenuAction.allCases
let finder = FIFinderSyncController.default()
let provider = FinderSync()
var enabled = Set(all)
var hidden: Any? = false
var readFails = false
provider.enabledFeatures = { enabled }
provider.readHiddenFilesValue = {
    if readFails { throw NSError(domain: "Fixture", code: 1) }
    return hidden
}
finder.targeted = nil
let expected = ["🍎 新建 iOS 模拟器", "📱 新建 Android 模拟器", "🌈 新建 Harmony 模拟器", "🩺 Android 模拟器检测与修复", "🧰 Harmony 模拟器检测与修复", "👁️ 显示文件"]
for mask in 0..<64 {
    enabled = Set(all.enumerated().compactMap { mask & (1 << $0.offset) != 0 ? $0.element : nil })
    let menu = provider.menu(for: .contextualMenuForContainer)
    let titles = all.enumerated().compactMap { enabled.contains($0.element) ? expected[$0.offset] : nil }
    expect(menu?.items.map(\.title) ?? [] == titles, "all 64 leaf subsets preserve fixed relative order")
    if mask != 0 { expect(menu?.autoenablesItems == false, "AppKit cannot override disabled state") }
}
enabled = Set(all)
hidden = true
let hideMenu = provider.menu(for: .contextualMenuForContainer)!
expect(hideMenu.items.last?.title == "🙈 隐藏文件", "shown files expose next hide action")
TestWorkspace.reset()
click(hideMenu.items.last!)
expect(TestWorkspace.urls.last?.absoluteString == "jobsdesktoptools://perform/hidden-files-toggle?show=0", "hide request expresses desired state")
hidden = nil
let showMenu = provider.menu(for: .contextualMenuForContainer)!
expect(showMenu.items.last?.title == "👁️ 显示文件", "missing key defaults to hidden")
TestWorkspace.reset()
click(showMenu.items.last!)
expect(TestWorkspace.urls.last?.absoluteString == "jobsdesktoptools://perform/hidden-files-toggle?show=1", "show request expresses desired state")
for value: Any in ["invalid", 2, NSNull()] {
    hidden = value
    let item = provider.menu(for: .contextualMenuForContainer)!.items.last!
    expect(!item.isEnabled && item.action == nil, "invalid preference leaves only disabled status item")
}
readFails = true
let failedItem = provider.menu(for: .contextualMenuForContainer)!.items.last!
expect(!failedItem.isEnabled, "preference synchronization failure disables status item")
readFails = false
hidden = false
finder.targeted = root
expect(provider.menu(for: .contextualMenuForContainer)?.items.map(\.title) == ["👁️ 显示文件"], "ordinary folder background retains only hidden action")
for kind in FIMenuKind.allCases where kind != .contextualMenuForContainer {
    expect(provider.menu(for: kind) == nil, "item/sidebar/toolbar never expose desktop actions")
}
finder.targeted = nil
let createMenu = provider.menu(for: .contextualMenuForContainer)!
finder.targeted = root
TestWorkspace.reset()
click(createMenu.items[0])
expect(TestWorkspace.urls.isEmpty && TestAlerts.count == 1, "stale desktop menu cannot dispatch from a folder")
finder.targeted = nil
enabled = []
TestWorkspace.reset()
click(createMenu.items[0])
expect(TestWorkspace.urls.isEmpty, "disabled leaf is checked again on click")
for action in all {
    let states: [Bool?] = action == .hiddenFiles ? [true, false] : [nil]
    for state in states {
        let request = DesktopMenuRequest(action: action, showsHiddenFiles: state)
        let decoded = DesktopMenuRequest(url: request.url!)!
        expect(decoded.action == action && decoded.showsHiddenFiles == state, "fixed action roundtrip")
    }
}
for raw in ["jobsdesktoptools://perform/unknown", "jobsdesktoptools://perform/ios-simulator-create?cmd=anything", "jobsdesktoptools://perform/hidden-files-toggle", "jobsdesktoptools://perform/hidden-files-toggle?show=true", "jobsdesktoptools://perform/ios-simulator-create#fragment", "JOBSDESKTOPTOOLS://perform/ios-simulator-create"] {
    expect(DesktopMenuRequest(url: URL(string: raw)!) == nil, "noncanonical request rejected")
}
expect(DesktopMenuConfiguration.enabledFeatures(at: configuration).isEmpty, "missing configuration keeps leaves closed")
for value in ["unknown", "ios-simulator-create,unknown", "ios-simulator-create,ios-simulator-create", "ios-simulator-create\n", "ios-simulator-create,", ",ios-simulator-create", ""] {
    try Data(value.utf8).write(to: configuration)
    expect(DesktopMenuConfiguration.enabledFeatures(at: configuration).isEmpty, "malformed configuration is never default-all")
}
try Data("ios-simulator-create,hidden-files-toggle".utf8).write(to: configuration)
expect(DesktopMenuConfiguration.enabledFeatures(at: configuration) == [.createIOS, .hiddenFiles], "valid leaves remain independent")
expect(DesktopMenuConfiguration.configurationURL(realHomePath: "/Users/account")?.path == "/Users/account/Library/Application Support/JobsDesktopTools/EnabledFeatures.txt", "configuration derives from account path")
let link = root.appendingPathComponent("features-link")
try FileManager.default.createSymbolicLink(at: link, withDestinationURL: configuration)
expect(DesktopMenuConfiguration.enabledFeatures(at: link).isEmpty, "linked configuration is rejected")
print("PASS: \(checks) desktop menu assertions")
    SWIFT
  end
end
