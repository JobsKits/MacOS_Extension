# frozen_string_literal: true
# 编译真实聚合菜单及配置，仅以替身承接 Finder/AppKit，不注册或运行业务。
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
