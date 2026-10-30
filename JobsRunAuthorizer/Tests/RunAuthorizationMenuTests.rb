# frozen_string_literal: true
# 编译真实菜单与共享源码，仅用内存替身承接 Finder/AppKit；不打开应用或注册扩展。

require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class RunAuthorizationMenuTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
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
      expect(singleMenu?.items.map(\.title) == ["🔒 运行授权"], "one executable-format file exposes exactly one action")
      expect(singleMenu?.autoenablesItems == false, "automatic AppKit validation cannot override explicit permission state")
      expect(singleMenu?.items.first?.isEnabled == true, "authorization is enabled without execute bits")
      expect(singleMenu?.items.first?.target === extensionInstance, "menu target is the real extension instance")

      for mode in [0o755, 0o654, 0o645] {
          try manager.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path)
          let executableMenu = extensionInstance.menu(for: .contextualMenuForItems)
          expect(executableMenu?.items.map(\.title) == ["🔒 运行授权"], "execute bits retain the authorization menu")
          expect(executableMenu?.items.first?.isEnabled == false, "any user/group/other execute bit disables authorization")
          TestWorkspace.reset()
          click(singleMenu)
          expect(TestWorkspace.urls.isEmpty, "permission changed after menu creation prevents authorization dispatch")
          expect(TestAlerts.count == 1, "stale permission state reports one failure")
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
          ("executable-bit Markdown document", [document]),
          ("unknown plain-text format", [textFile]),
          ("multiple ordinary files", [file, otherFile]),
          ("file and directory", [file, folder]),
          ("empty selection", []),
          ("nil selection", nil),
          ("non-file URL", [URL(string: "https://example.invalid/a.command")!])
      ]
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
