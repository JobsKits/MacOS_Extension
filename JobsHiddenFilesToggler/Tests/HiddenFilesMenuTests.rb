# frozen_string_literal: true
# 编译真实菜单与偏好适配器，注入内存值；不切换真实 Finder 状态。
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class HiddenFilesMenuTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  SOURCES = %w[
    JobsHiddenFilesToggler/HiddenFilesToggleService/HiddenFilesToggleService.swift
    JobsHiddenFilesToggler/FinderHiddenFilesPreferences/FinderHiddenFilesPreferences.swift
    JobsHiddenFilesShared/HiddenFilesMenuContext/HiddenFilesMenuContext.swift
    JobsHiddenFilesShared/HiddenFilesRequest/HiddenFilesRequest.swift
    JobsHiddenFilesFinderSync/FinderSync.swift
  ].freeze

  def test_real_menu_reflects_next_action_without_writing_preferences
    Dir.mktmpdir('jobs-hidden-menu-tests-') do |directory|
      sources = SOURCES.map do |relative|
        source = File.read(File.join(ROOT, relative)).gsub(/^import (?:AppKit|FinderSync)[ \t]*$/, '')
        if relative.end_with?('FinderSync.swift')
          assert_includes source, 'private let preferences = FinderHiddenFilesPreferences()'
          source = source.sub('FinderHiddenFilesPreferences()', 'FinderHiddenFilesPreferences(synchronize: { TestPreference.syncSucceeds }, copyValue: { TestPreference.value }, setValue: { _ in TestPreference.writes += 1 })')
        end
        source
      end
      path = File.join(directory, 'main.swift')
      binary = File.join(directory, 'menu-tests')
      File.write(path, [SWIFT_STUBS, sources.join("\n"), SWIFT_CHECKS].join("\n"))
      output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', path, '-o', binary)
      assert status.success?, output
      output, status = Open3.capture2e(binary, directory)
      assert status.success?, output
      assert_match(/PASS: \d+ hidden file menu assertions/, output)
      puts output.lines.grep(/^PASS:/)
    end
  end

  SWIFT_CHECKS = <<~'SWIFT'
    enum TestPreference {
        static var value: Any? = false
        static var syncSucceeds = true
        static var writes = 0
    }
    var assertions = 0
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError(message) }
    }
    func click(_ menu: NSMenu?) {
        guard let item = menu?.items.first, let target = item.target as? NSObject, let action = item.action else {
            fatalError("missing menu target")
        }
        _ = target.perform(action, with: item)
    }
    let controller = FIFinderSyncController.default()
    let finder = FinderSync()
    controller.targeted = nil
    let cases: [(Any?, String)] = [
        (false, "👁️ 显示文件"), (true, "🙈 隐藏文件"),
        (nil, "👁️ 显示文件"), ("YES", "🙈 隐藏文件"), ("0", "👁️ 显示文件")
    ]
    for (value, expectedTitle) in cases {
        TestPreference.value = value
        let menu = finder.menu(for: .contextualMenuForContainer)
        expect(menu?.items.map(\.title) == [expectedTitle], "title must describe next action")
        expect(menu?.items.first?.isEnabled == true, "valid preference enables toggle")
        expect(menu?.autoenablesItems == false, "Finder must retain explicit disabled state")
        expect(TestPreference.writes == 0, "opening a menu must never write preferences")
        TestWorkspace.reset()
        click(menu)
        expect(TestWorkspace.urls == [HiddenFilesRequest.canonicalURL], "click dispatches exactly one canonical request")
    }
    for kind in FIMenuKind.allCases where kind != .contextualMenuForContainer {
        expect(finder.menu(for: kind) == nil, "item/sidebar/toolbar menu must stay hidden")
    }
    for invalid: Any in ["invalid", 2, NSNull()] {
        TestPreference.value = invalid
        let menu = finder.menu(for: .contextualMenuForContainer)
        expect(menu?.items.first?.title == "⚠️ 隐藏文件状态不可用", "invalid state has no guessed action")
        expect(menu?.items.first?.isEnabled == false, "invalid state disables the action")
        TestWorkspace.reset()
        click(menu)
        expect(TestWorkspace.urls.isEmpty, "invalid state cannot dispatch")
    }
    TestPreference.value = false
    TestPreference.syncSucceeds = false
    let unavailable = finder.menu(for: .contextualMenuForContainer)
    expect(unavailable?.items.first?.isEnabled == false, "sync failure disables menu")
    TestWorkspace.reset()
    click(unavailable)
    expect(TestWorkspace.urls.isEmpty, "sync failure cannot dispatch")
    TestPreference.syncSucceeds = true
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let file = root.appendingPathComponent("document.txt")
    try Data("fixture".utf8).write(to: file)
    controller.targeted = file
    expect(finder.menu(for: .contextualMenuForContainer) == nil, "plain file is not a background")
    controller.targeted = root
    let enabled = finder.menu(for: .contextualMenuForContainer)
    expect(enabled?.items.first?.title == "👁️ 显示文件", "ordinary folder background retains toggle")
    TestPreference.syncSucceeds = false
    TestWorkspace.reset()
    click(enabled)
    expect(TestWorkspace.urls.isEmpty, "preference failure after menu opens is revalidated")
    expect(TestPreference.writes == 0, "all menu checks remain read-only")
    print("PASS: \(assertions) hidden file menu assertions")
  SWIFT

  SWIFT_STUBS = <<~'SWIFT'
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
