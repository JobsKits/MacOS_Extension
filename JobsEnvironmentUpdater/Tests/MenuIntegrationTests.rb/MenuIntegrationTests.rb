# frozen_string_literal: true
# 非交互隔离回归：编译真实菜单源码，仅替换 Finder 回调和业务运输，不注册或启动宿主。

require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class EnvironmentUpdateMenuIntegrationTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  # 真 AppKit 菜单与生产过滤共同执行，避免仅核对源码字符串。
  def test_real_menu_routing_and_desktop_filter
    Dir.mktmpdir('JobsUpdateMenuIntegration-') do |directory|
      sources = %w[
        Shared/EnvironmentUpdateContext.swift
        Shared/EnvironmentUpdateRequest.swift
        Shared/EnvironmentUpdateHost.swift
        JobsEnvironmentUpdaterFinderSync/FinderSync.swift
      ].map do |relative|
        File.read(File.join(ROOT, relative)).sub(/^import FinderSync[ \t]*\n/, '')
      end
      main = File.join(directory, 'main.swift')
      binary = File.join(directory, 'MenuIntegrationTests')
      File.write(main, finder_boundary + "\n" + sources.join("\n") + "\n" + menu_checks)
      output, result = Open3.capture2e('/usr/bin/xcrun', 'swiftc', main, '-o', binary)
      assert result.success?, output
      output, result = Open3.capture2e(binary, directory)
      assert result.success?, output
      assert_match(/PASS: \d+ update menu integration assertions/, output)
      puts output.lines.grep(/^PASS:/)
    end
  end

  private

  # 只替换 Finder 进程边界，保留真实 NSMenu、NSMenuItem 和生产源代码。
  def finder_boundary
    <<~'SWIFT'
      import AppKit
      
      // 此套保留独立包无清单路径；联合菜单由 OrderedDesktopMenuTests.swift 编译真实协调器验证。
      final class OrderedDesktopMenuCoordinator {
          init(extensionURL: URL) {}
          func menu(isContainer: Bool, targetedURL: URL?) -> (handled: Bool, menu: NSMenu?) {
              return (false, nil)
          }
      }

      enum FIMenuKind: Int, CaseIterable {
          case contextualMenuForItems
          case contextualMenuForContainer
          case contextualMenuForSidebar
          case toolbarItemMenu
          case unsupportedMenuKind = 99
      }

      class FIFinderSync: NSObject {
          func menu(for menuKind: FIMenuKind) -> NSMenu? {
              return nil
          }

          func beginObservingDirectory(at url: URL) {}
      }

      final class FIFinderSyncController {
          static let shared = FIFinderSyncController()
          var directoryURLs: Set<URL> = []
          var targeted: URL?
          var selected: [URL]?

          static func `default`() -> FIFinderSyncController {
              return shared
          }

          func targetedURL() -> URL? {
              return targeted
          }

          func selectedItemURLs() -> [URL]? {
              return selected
          }
      }

      enum FixtureEffects {
          static var hostRequests = 0
          static var alerts = 0
      }

      extension NSWorkspace {
          @discardableResult
          func byOpenEnvironmentUpdate(_ url: URL,
                                       application: URL,
                                       completion: @escaping (NSRunningApplication?, Error?) -> Void) -> Self {
              FixtureEffects.hostRequests += 1
              completion(nil, nil)
              return self
          }
      }

      extension NSAlert {
          static func showEnvironmentUpdateFailure(_ details: String) {
              FixtureEffects.alerts += 1
          }
      }
    SWIFT
  end

  # 从控制器提供实际上下文，菜单创建不得触发任何升级运输。
  def menu_checks
    <<~'SWIFT'
      var checks = 0
      func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
          checks += 1
          guard condition() else {
              fatalError(message)
          }
      }

      let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
      let controller = FIFinderSyncController.default()
      let provider = FinderSync()
      expect(controller.directoryURLs == [URL(fileURLWithPath: "/", isDirectory: true)],
             "Finder callback routing watches the root; desktop filtering remains inside the provider")
      expect(FixtureEffects.hostRequests == 0 && FixtureEffects.alerts == 0,
             "Initializing the menu provider is passive")
      guard let desktop = EnvironmentUpdateContext.desktopURL else {
          fatalError("Real account Desktop path is unavailable")
      }

      controller.targeted = desktop
      controller.selected = nil
      guard let menu = provider.menu(for: .contextualMenuForContainer) else {
          fatalError("Desktop blank menu must return the update item")
      }
      expect(menu.numberOfItems == 1, "Exactly one desktop update action")
      let item = menu.items[0]
      expect(item.title == "🔄 更新开发环境（update）", "Real AppKit item exposes the expected action")
      expect((item.target as AnyObject?) === provider, "Menu item targets its real provider")
      expect(item.action.map(NSStringFromSelector) == "launchUpdate:", "Action selector is bound")
      expect(item.action.map { provider.responds(to: $0) } == true, "Bound action exists")
      expect(item.isEnabled && item.keyEquivalent.isEmpty, "Action is enabled without a global shortcut")

      provider.beginObservingDirectory(at: desktop)
      expect(FixtureEffects.hostRequests == 0 && FixtureEffects.alerts == 0,
             "Observation and menu construction never launch the host")

      for kind in FIMenuKind.allCases where kind != .contextualMenuForContainer {
          controller.targeted = desktop
          controller.selected = [desktop.appendingPathComponent("Selected.txt")]
          expect(provider.menu(for: kind) == nil, "Items, sidebar, toolbar and unknown kinds are excluded")
      }
      controller.selected = nil
      for ordinary in [root,
                       root.appendingPathComponent("Desktop", isDirectory: true),
                       desktop.appendingPathComponent("Child", isDirectory: true)] {
          controller.targeted = ordinary
          expect(provider.menu(for: .contextualMenuForContainer) == nil,
                 "Ordinary folders, same-name folders and desktop children do not expose global update")
      }
      controller.targeted = URL(string: "https://example.com/Desktop")!
      expect(provider.menu(for: .contextualMenuForContainer) == nil, "Remote URL is excluded")
      controller.targeted = nil
      expect(provider.menu(for: .contextualMenuForContainer)?.items.map(\.title) == [item.title],
             "Desktop background without a target uses the production desktop fallback")

      let desktopAlias = root.appendingPathComponent("Desktop Alias 中文", isDirectory: true)
      try FileManager.default.createSymbolicLink(at: desktopAlias, withDestinationURL: desktop)
      controller.targeted = desktopAlias
      expect(provider.menu(for: .contextualMenuForContainer)?.items.map(\.title) == [item.title],
             "A delivered symbolic alias of the actual desktop remains a valid desktop context")
      let ordinaryAlias = root.appendingPathComponent("Ordinary Alias", isDirectory: true)
      try FileManager.default.createSymbolicLink(at: ordinaryAlias, withDestinationURL: root)
      controller.targeted = ordinaryAlias
      expect(provider.menu(for: .contextualMenuForContainer) == nil,
             "Resolving a symbolic alias cannot promote an ordinary folder into desktop")
      expect(FixtureEffects.hostRequests == 0 && FixtureEffects.alerts == 0,
             "Every routing and filtering check remains free of host or Terminal effects")
      print("PASS: \(checks) update menu integration assertions; real AppKit menus, no host or Terminal launch")
    SWIFT
  end
end
