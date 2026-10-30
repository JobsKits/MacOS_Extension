# frozen_string_literal: true
# 运行生产 Finder 菜单与宿主定位；系统目录观察、App 唤起和警告窗口均由硬边界替身承接。
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class FinderDispatchTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_production_menu_keeps_clicked_directory_and_opens_exact_containing_app
    finder = File.read(File.join(ROOT, 'JobsFileCreatorFinderSync/FinderSync.swift'))
    finder = finder.gsub('FIFinderSyncController', 'TestFinderSyncController')
                   .gsub('class FinderSync: FIFinderSync', 'class FinderSync: TestFinderSync')
                   .gsub('Bundle.main.bundleURL', 'testExtensionURL')
                   .gsub('NSWorkspace.shared', 'TestWorkspace.shared')
                   .gsub('NSAlert.make()', 'TestAlert.make()')
    Dir.mktmpdir('jobs-file-creator-dispatch-') do |directory|
      source = File.join(directory, 'main.swift')
      File.write(source, BOUNDARIES + "\n" + finder + "\n" + SCENARIOS)
      sources = %w[FileCreationContext FileCreationRequest FileCreatorFactories FileCreatorHost].map do |name|
        File.join(ROOT, 'Shared', name, "#{name}.swift")
      end
      binary = File.join(directory, 'dispatch')
      output, result = Open3.capture2e('/usr/bin/xcrun', 'swiftc', *sources, source, '-o', binary)
      assert result.success?, output
      output, result = Open3.capture2e(binary)
      assert result.success?, output
      assert_match(/PASS: \d+ Finder dispatch assertions/, output)
    end
  end

  BOUNDARIES = <<~'SWIFT'
    import AppKit
    import FinderSync

    var assertions = 0
    func expect(_ value: Bool, _ reason: String) {
        assertions += 1
        precondition(value, reason)
    }

    class TestFinderSync: NSObject {
        func menu(for menuKind: FIMenuKind) -> NSMenu? {
            return nil
        }
    }

    final class TestFinderSyncController {
        static let instance = TestFinderSyncController()
        var target: URL?
        var observed: Set<URL> = []
        static func `default`() -> TestFinderSyncController {
            return instance
        }
        func targetedURL() -> URL? {
            return target
        }
        @discardableResult
        func byDirectoryURLs(_ urls: Set<URL>) -> Self {
            observed = urls
            return self
        }
    }

    final class TestWorkspace {
        static let shared = TestWorkspace()
        var calls: [(urls: [URL], application: URL)] = []
        var error: Error?
        @discardableResult
        func byOpenURLs(_ urls: [URL],
                        withApplicationAt application: URL,
                        configuration: NSWorkspace.OpenConfiguration,
                        completionHandler: @escaping (NSRunningApplication?, Error?) -> Void) -> Self {
            expect(!configuration.allowsRunningApplicationSubstitution, "a running stale copy cannot replace the containing app")
            expect(!configuration.promptsUserIfNeeded, "system URL-handler or application-selection errors cannot obscure the own failure message")
            expect(!configuration.addsToRecentItems && configuration.activates, "creation dialog activates without adding request URLs to Recents")
            calls.append((urls, application))
            let result = error
            DispatchQueue.global().async {
                completionHandler(nil, result)
            }
            return self
        }
        func open(_ url: URL) -> Bool {
            fatalError("Default URL scheme handler must never be used")
        }
    }

    final class TestAlert {
        static var messages: [String] = []
        private var message = ""
        static func make() -> TestAlert {
            return TestAlert()
        }
        func byMessageText(_ value: String) -> Self {
            return self
        }
        func byInformativeText(_ value: String) -> Self {
            message = value
            return self
        }
        func byAlertStyle(_ value: NSAlert.Style) -> Self {
            return self
        }
        func byAddButton(_ value: String) -> Self {
            return self
        }
        @discardableResult
        func runModal() -> NSApplication.ModalResponse {
            expect(Thread.isMainThread, "launch errors show on the main thread")
            TestAlert.messages.append(message)
            return .alertFirstButtonReturn
        }
    }
  SWIFT

  SCENARIOS = <<~'SWIFT'
    NSApplication.shared.setActivationPolicy(.prohibited)
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("FinderDispatch-\(UUID().uuidString)", isDirectory: true)
    try manager.createDirectory(at: root, withIntermediateDirectories: false)
    defer {
        try? manager.removeItem(at: root)
    }

    func fixtureApp(_ name: String, identifier: String = "com.jobs.filecreator", executable: String = "JobsFileCreator") throws -> URL {
        let app = root.appendingPathComponent(name + ".app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let plugin = contents.appendingPathComponent("PlugIns/JobsFileCreatorFinderSync.appex", isDirectory: true)
        try manager.createDirectory(at: plugin, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": identifier, "CFBundleExecutable": executable, "CFBundlePackageType": "APPL"]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return plugin
    }

    var testExtensionURL = try fixtureApp("搬迁 包 ' $() (new)")
    let actualApp = testExtensionURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    expect(FileCreatorHost.applicationURL(forExtension: testExtensionURL) == actualApp, "host path comes from the current extension after copying or renaming")
    expect(FileCreatorHost.applicationURL(forExtension: try fixtureApp("wrong-id", identifier: "other.application")) == nil, "another app identity is rejected")
    expect(FileCreatorHost.applicationURL(forExtension: try fixtureApp("wrong-executable", executable: "other")) == nil, "unexpected host executable is rejected")
    expect(FileCreatorHost.applicationURL(forExtension: root.appendingPathComponent("JobsFileCreatorFinderSync.appex")) == nil, "loose extension outside an app is rejected")
    expect(FileCreatorHost.applicationURL(forExtension: actualApp.appendingPathComponent("Contents/Resources/JobsFileCreatorFinderSync.appex")) == nil, "incorrect containing app layout is rejected")
    expect(FileCreatorHost.applicationURL(forExtension: URL(string: "https://example.com/JobsFileCreatorFinderSync.appex")!) == nil, "remote app path is rejected")

    let clicked = root.appendingPathComponent("右键 ' $() `id` 文件夹", isDirectory: true)
    let other = root.appendingPathComponent("另一个 Finder 窗口", isDirectory: true)
    try manager.createDirectory(at: clicked, withIntermediateDirectories: false)
    try manager.createDirectory(at: other, withIntermediateDirectories: false)
    let controller = TestFinderSyncController.instance
    controller.target = clicked
    let finder = FinderSync()
    func finderCopy(_ original: NSMenuItem) -> NSMenuItem {
        // 仅复制 Finder 支持的菜单属性，不能将原 NSMenuItem 或 representedObject 直接送回。
        let copy = NSMenuItem(title: original.title, action: original.action, keyEquivalent: "")
        copy.image = original.image
        copy.isEnabled = original.isEnabled
        copy.tag = original.tag
        copy.state = original.state
        copy.indentationLevel = original.indentationLevel
        copy.target = original.target
        expect(copy.representedObject == nil, "Finder copied item has no representedObject")
        return copy
    }
    for kind in [FIMenuKind.contextualMenuForItems, .contextualMenuForSidebar, .toolbarItemMenu] {
        expect(finder.menu(for: kind) == nil, "only a directory background offers file creation")
    }
    let menu = finder.menu(for: .contextualMenuForContainer)!
    expect(menu.items.count == 1, "background menu exposes one file action")
    let item = finderCopy(menu.items[0])
    expect(item.tag > 0, "background menu assigns a supported nonzero tag")
    controller.target = other
    let otherItem = finderCopy(finder.menu(for: .contextualMenuForContainer)!.items[0])
    expect(otherItem.tag > item.tag, "simultaneous menus receive distinct increasing tags")
    _ = finder.perform(item.action!, with: item)
    expect(TestWorkspace.shared.calls.count == 1, "one action opens the host once")
    let call = TestWorkspace.shared.calls[0]
    expect(call.application == actualApp, "action explicitly uses the exact containing app")
    expect(call.urls.count == 1, "one request is sent")
    let request = FileCreationRequest(url: call.urls[0])!
    expect(request.directoryURL == clicked, "moving Finder focus after right-click cannot redirect creation")
    expect(TestAlert.messages.isEmpty, "success does not show an error")
    _ = finder.perform(otherItem.action!, with: otherItem)
    expect(FileCreationRequest(url: TestWorkspace.shared.calls.last!.urls[0])!.directoryURL == other, "another concurrent menu keeps its own directory")
    expect(FileCreationRequest(url: TestWorkspace.shared.calls.last!.urls[0])!.identifier != request.identifier, "distinct menus have fresh request identities")
    let completedLaunches = TestWorkspace.shared.calls.count
    _ = finder.perform(item.action!, with: item)
    expect(TestWorkspace.shared.calls.count == completedLaunches && TestAlert.messages.last?.contains("菜单已失效") == true, "a consumed tag cannot launch twice")

    controller.target = clicked
    let next = finderCopy(finder.menu(for: .contextualMenuForContainer)!.items[0])
    expect(next.tag > otherItem.tag, "reopening a menu never reuses an earlier tag")
    TestWorkspace.shared.error = NSError(domain: "FinderDispatchTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "fixture launch failure"])
    TestAlert.messages.removeAll()
    _ = finder.perform(next.action!, with: next)
    let deadline = Date().addingTimeInterval(3)
    while TestAlert.messages.isEmpty && Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    expect(TestAlert.messages.last?.contains("fixture launch failure") == true, "asynchronous launch failure keeps the system reason")

    let launches = TestWorkspace.shared.calls.count
    let deletedItem = finderCopy(finder.menu(for: .contextualMenuForContainer)!.items[0])
    try manager.removeItem(at: clicked)
    _ = finder.perform(deletedItem.action!, with: deletedItem)
    expect(TestWorkspace.shared.calls.count == launches && TestAlert.messages.last?.contains("目标文件夹已失效") == true, "a deleted captured directory cannot silently fall back to another folder")
    controller.target = other
    let missingHostItem = finderCopy(finder.menu(for: .contextualMenuForContainer)!.items[0])
    let realExtensionURL = testExtensionURL
    testExtensionURL = root.appendingPathComponent("loose/JobsFileCreatorFinderSync.appex")
    _ = finder.perform(missingHostItem.action!, with: missingHostItem)
    expect(TestWorkspace.shared.calls.count == launches && TestAlert.messages.last?.contains("缺少完整") == true, "a missing containing app reports repair without generic scheme fallback")
    testExtensionURL = realExtensionURL
    TestWorkspace.shared.error = nil
    let expiredItem = finderCopy(finder.menu(for: .contextualMenuForContainer)!.items[0])
    var latestItem = expiredItem
    for _ in 0..<200 {
        latestItem = finderCopy(finder.menu(for: .contextualMenuForContainer)!.items[0])
    }
    expect(latestItem.tag > expiredItem.tag, "request cache eviction never reuses stale tags")
    _ = finder.perform(expiredItem.action!, with: expiredItem)
    expect(TestWorkspace.shared.calls.count == launches && TestAlert.messages.last?.contains("菜单已失效") == true, "bounded cache rejects evicted tags without targeting a newer menu")
    _ = finder.perform(latestItem.action!, with: latestItem)
    expect(TestWorkspace.shared.calls.count == launches + 1 && FileCreationRequest(url: TestWorkspace.shared.calls.last!.urls[0])!.directoryURL == other, "latest menu remains actionable after eviction")
    expect(try manager.contentsOfDirectory(atPath: other.path).isEmpty, "Finder transport never creates files in another directory")
    print("PASS: \(assertions) Finder dispatch assertions")
  SWIFT
end
