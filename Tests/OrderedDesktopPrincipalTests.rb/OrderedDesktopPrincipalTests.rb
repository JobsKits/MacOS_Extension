# frozen_string_literal: true
# OrderedDesktopPrincipalTests.rb | JobsOrderedDesktopMenuTests
# Created by Jobs on 2026年11月18日，星期三.
# 只编译临时测试进程；不注册扩展、不启动业务宿主或真实 clean。

require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class OrderedDesktopPrincipalTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  PROVIDERS = %w[JobsFileCreator JobsDesktopTools JobsEnvironmentUpdater JobsDiskSpaceInfo].freeze

  def test_every_real_principal_receives_copied_menu_selector
    PROVIDERS.each do |provider|
      Dir.mktmpdir('jobs-principal-dispatch-') do |directory|
        principal = File.join(ROOT, provider, provider + 'FinderSync', 'FinderSync.swift')
        # 同文件 extension 只注入业务运输替身；principal 与 selector 实现逐字使用生产源码。
        source = File.read(principal) + <<~'SWIFT' + harness

          extension FinderSync {
              func bindForPrincipalVerification(_ coordinator: OrderedDesktopMenuCoordinator) {
                  orderedDesktopMenu = coordinator
              }
          }
        SWIFT
        main = File.join(directory, 'main.swift')
        binary = File.join(directory, 'principal-tests')
        File.write(main, source)
        dependencies = Dir.glob(File.join(ROOT, provider, 'Shared/**/*.swift')).sort
        if provider == 'JobsDesktopTools'
          dependencies += %w[FinderHiddenFilesPreferences HiddenFilesToggleService].map do |name|
            File.join(ROOT, provider, 'Core', name, name + '.swift')
          end
        end
        output, result = Open3.capture2e('/usr/bin/xcrun', 'swiftc', main, *dependencies, '-o', binary)
        assert result.success?, "#{provider} compile:\n#{output}"
        output, result = Open3.capture2e(binary, provider, directory)
        assert result.success?, "#{provider} runtime:\n#{output}"
        assert_match(/PASS: #{provider} actual principal selector dispatch/, output)
        puts output.lines.grep(/^PASS:/)
      end
    end
  end

  def harness
    <<~'SWIFT'

      import Foundation

      let provider = CommandLine.arguments[1]
      let root = URL(fileURLWithPath: CommandLine.arguments[2])
      let container = root.appendingPathComponent("中文 空格联合.app")
      let home = root.appendingPathComponent("测试账户")
      let desktop = home.appendingPathComponent("Desktop")
      let providers = OrderedDesktopMenuCoordinator.Manifest.priority
      let selected = Array(providers.drop(while: { $0 != provider }))

      func writeInfo(_ bundle: URL, _ values: [String: Any]) throws {
          let contents = bundle.appendingPathComponent("Contents")
          try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
          try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
              .write(to: contents.appendingPathComponent("Info.plist"))
      }

      func pluginURL(_ name: String) -> URL {
          return container.appendingPathComponent("Contents/Applications/" + name + ".app/Contents/PlugIns/" + name + "FinderSync.appex")
      }

      let identities = ["JobsFileCreator": "com.jobs.filecreator", "JobsDesktopTools": "com.jobs.desktoptools",
                        "JobsEnvironmentUpdater": "com.jobs.environmentupdater", "JobsDiskSpaceInfo": "com.jobs.diskspaceinfo"]
      try writeInfo(container, ["CFBundleIdentifier": "com.jobs.finderextensions.manager"])
      try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: container.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
      let features = home.appendingPathComponent("Library/Application Support/JobsDesktopTools/EnabledFeatures.txt")
      try FileManager.default.createDirectory(at: features.deletingLastPathComponent(), withIntermediateDirectories: true)
      try "ios-simulator-create,android-simulator-create,harmony-simulator-create,android-simulator-repair,harmony-simulator-repair,hidden-files-toggle"
          .write(to: features, atomically: true, encoding: .utf8)
      for name in selected {
          let app = container.appendingPathComponent("Contents/Applications/" + name + ".app")
          let plugin = pluginURL(name)
          try writeInfo(app, ["CFBundleIdentifier": identities[name]!, "CFBundleExecutable": name, "JobsOrderedDesktopMenuVersion": 1])
          try writeInfo(plugin, ["CFBundleIdentifier": identities[name]! + ".findersync", "CFBundleExecutable": name + "FinderSync"])
          for (bundle, executable) in [(app, name), (plugin, name + "FinderSync")] {
              let file = bundle.appendingPathComponent("Contents/MacOS/" + executable)
              try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
              try Data("fixture".utf8).write(to: file)
              try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
          }
      }
      let manifest = OrderedDesktopMenuCoordinator.Manifest(schemaVersion: 1, owner: provider, providers: selected)
      try JSONEncoder().encode(manifest).write(to: container.appendingPathComponent("Contents/Resources/DesktopMenu.json"))

      NSApplication.shared.setActivationPolicy(.prohibited)
      let principal = FinderSync()
      let coordinator = OrderedDesktopMenuCoordinator(extensionURL: pluginURL(provider))
      coordinator.accountHome = { home }
      coordinator.hiddenValue = { true }
      coordinator.diskTitle = { "💽 磁盘剩余：测试快照" }
      var launches: [(URL, URL)] = []
      coordinator.openHost = { launches.append(($0, $1)) }
      principal.bindForPrincipalVerification(coordinator)
      guard let menu = principal.menu(for: .contextualMenuForContainer) else {
          fatalError("real principal did not produce a coordinated menu")
      }
      precondition(menu.items.contains(where: { $0.title == "💽 磁盘剩余：测试快照" }))
      for item in menu.items {
          precondition(item.target === principal, "production menu must target the extension principal")
          let copied = item.copy() as! NSMenuItem
          copied.target = nil
          copied.representedObject = nil
          guard let action = copied.action else {
              fatalError("copied menu action missing")
          }
          precondition(principal.responds(to: action), "actual FIFinderSync principal lacks copied action selector")
          precondition(NSApplication.shared.sendAction(action, to: principal, from: copied), "selector was not delivered")
      }
      precondition(launches.count == menu.items.count, "every copied menu action reaches its exact host once")
      guard let disk = launches.first(where: { $0.0.scheme == "jobsdiskspaceinfo" }) else {
          fatalError("disk cleanup selector did not reach the host transport")
      }
      precondition(disk.0.host == "clean" && URLComponents(url: disk.0, resolvingAgainstBaseURL: false)?.queryItems?.first?.name == "id")
      precondition(disk.1 == container.appendingPathComponent("Contents/Applications/JobsDiskSpaceInfo.app"))
      let copiedAgain = menu.items.last!.copy() as! NSMenuItem
      copiedAgain.target = nil
      precondition(NSApplication.shared.sendAction(copiedAgain.action!, to: principal, from: copiedAgain))
      precondition(launches.count == menu.items.count, "consumed ticket must not launch twice")
      print("PASS: \(provider) actual principal selector dispatch; \(menu.items.count) actions")
    SWIFT
  end
end
