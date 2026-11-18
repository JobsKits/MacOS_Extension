//
//  OrderedDesktopMenuTests.swift
//  JobsOrderedDesktopMenuTests
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit
import FinderSync
import Foundation

/// 模拟 Finder 把菜单 action 发送给扩展 principal；实际 principal 另由四包回归编译核验。
final class OrderedMenuReceiver: FIFinderSync {
    var coordinator: OrderedDesktopMenuCoordinator?

    @objc func performOrderedAction(_ sender: NSMenuItem) {
        coordinator?.performOrderedAction(sender)
    }
}

/// 真实 AppKit 菜单与生产 URL 协议的隔离验证；不注册扩展或启动任何业务宿主。
@main
struct OrderedDesktopMenuTests {

    static var checks = 0
    static let providers = OrderedDesktopMenuCoordinator.Manifest.priority
    static let desktopActions = ["ios-simulator-create", "android-simulator-create", "harmony-simulator-create",
                                 "android-simulator-repair", "harmony-simulator-repair", "hidden-files-toggle"]

    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(value(), message)
    }

    static func main() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let coordinatorSource = try Data(contentsOf: sourceRoot.appendingPathComponent("JobsDesktopTools/Shared/OrderedDesktopMenu/OrderedDesktopMenuCoordinator.swift"))
        let diskSource = try Data(contentsOf: sourceRoot.appendingPathComponent("JobsDiskSpaceInfo/Shared/DiskSpaceSummary.swift"))
        for provider in providers {
            let ownSource = try Data(contentsOf: sourceRoot.appendingPathComponent(provider + "/Shared/OrderedDesktopMenu/OrderedDesktopMenuCoordinator.swift"))
            expect(ownSource == coordinatorSource, "all standalone packages ship identical menu coordination")
            if provider != "JobsDiskSpaceInfo" {
                let copy = try Data(contentsOf: sourceRoot.appendingPathComponent(provider + "/Shared/OrderedDesktopMenu/DiskSpaceSummary.swift"))
                expect(copy == diskSource, "disk capacity fixes must reach every elected renderer")
            }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("jobs-ordered-menu-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = root.appendingPathComponent("中文 空格'\n联合.app")
        let home = root.appendingPathComponent("测试账户")
        let desktop = home.appendingPathComponent("Desktop")
        let directory = root.appendingPathComponent("目标 '中文\n目录")
        let features = home.appendingPathComponent("Library/Application Support/JobsDesktopTools/EnabledFeatures.txt")
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: features.deletingLastPathComponent(), withIntermediateDirectories: true)
        try desktopActions.joined(separator: ",").write(to: features, atomically: true, encoding: .utf8)
        try writeInfo(container, ["CFBundleIdentifier": "com.jobs.finderextensions.manager"])
        try FileManager.default.createDirectory(at: container.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        for provider in providers {
            try makeProvider(provider, container: container)
        }
        let manifest = container.appendingPathComponent("Contents/Resources/DesktopMenu.json")
        let coordinators = providers.map { provider -> OrderedDesktopMenuCoordinator in
            let url = extensionURL(provider, container: container)
            let coordinator = OrderedDesktopMenuCoordinator(extensionURL: url)
            coordinator.accountHome = { home }
            coordinator.hiddenValue = { true }
            coordinator.diskTitle = { "💽 磁盘剩余：测试快照" }
            return coordinator
        }
        let receivers = coordinators.map { coordinator -> OrderedMenuReceiver in
            let receiver = OrderedMenuReceiver()
            receiver.coordinator = coordinator
            return receiver
        }
        expect(!coordinators[0].menu(isContainer: true, targetedURL: desktop, actionTarget: receivers[0]).handled, "missing manifest retains standalone rendering")
        expect(!coordinators[3].menu(isContainer: false, targetedURL: directory, actionTarget: receivers[3]).handled, "items and sidebar remain original disk menus")
        for mask in 1..<16 {
            let selected = providers.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
            try writeManifest(manifest, selected)
            for (index, coordinator) in coordinators.enumerated() {
                let result = coordinator.menu(isContainer: true, targetedURL: desktop, actionTarget: receivers[index])
                expect(result.handled, "manifest handles every participating renderer")
                if providers[index] == selected[0] {
                    let expected = (selected.contains("JobsFileCreator") ? ["📃 新建文件…"] : []) +
                        (selected.contains("JobsDesktopTools") ? ["🍎 新建 iOS 模拟器", "📱 新建 Android 模拟器", "🌈 新建 Harmony 模拟器", "🩺 Android 模拟器检测与修复", "🧰 Harmony 模拟器检测与修复", "🙈 隐藏文件"] : []) +
                        (selected.contains("JobsEnvironmentUpdater") ? ["🔄 更新开发环境（update）"] : []) +
                        (selected.contains("JobsDiskSpaceInfo") ? ["💽 磁盘剩余：测试快照"] : [])
                    expect(result.menu?.items.map(\.title) == expected, "every installed subset keeps screenshot ordering")
                } else {
                    expect(result.menu == nil, "non owner never produces duplicate or competing menus")
                }
            }
        }
        try writeManifest(manifest, providers.reversed())
        expect(coordinators[0].menu(isContainer: true, targetedURL: desktop, actionTarget: receivers[0]).menu?.items.count == 9, "manifest order cannot reorder presentation")
        let owner = coordinators[0]
        let folderMenu = owner.menu(isContainer: true, targetedURL: directory, actionTarget: receivers[0]).menu!
        expect(folderMenu.items.map(\.title) == ["📃 新建文件…", "🙈 隐藏文件", "💽 磁盘剩余：测试快照"], "ordinary folder has ordered applicable actions only")
        var launches: [(URL, URL)] = []
        owner.openHost = { launches.append(($0, $1)) }
        for item in folderMenu.items {
            let copied = item.copy() as! NSMenuItem
            copied.representedObject = nil
            dispatch(copied, principal: receivers[0])
        }
        expect(launches.count == 3, "copied menu tags route exactly once")
        expect(FileCreationRequest(url: launches[0].0)?.directoryURL == directory.standardizedFileURL, "file path round trips through production protocol")
        expect(DesktopMenuRequest(url: launches[1].0)?.showsHiddenFiles == false, "hidden state routes explicit hide request")
        expect(DiskCleanupRequest(url: launches[2].0) != nil, "disk request uses existing protocol")
        for (index, provider) in ["JobsFileCreator", "JobsDesktopTools", "JobsDiskSpaceInfo"].enumerated() {
            expect(launches[index].1 == container.appendingPathComponent("Contents/Applications/" + provider + ".app"), "host opens exact relative installed app")
        }
        dispatch(folderMenu.items[0], principal: receivers[0])
        expect(launches.count == 3, "consumed requests cannot launch twice")
        let fullMenu = owner.menu(isContainer: true, targetedURL: desktop, actionTarget: receivers[0]).menu!
        for item in fullMenu.items {
            dispatch(item, principal: receivers[0])
        }
        expect(launches.count == 12, "all desktop actions dispatch once")
        expect(launches[10].0.scheme == "jobsenvironmentupdater" && EnvironmentUpdateRequest(url: launches[10].0) != nil,
               "environment update uses original UUID protocol")
        for index in 4...9 {
            expect(DesktopMenuRequest(url: launches[index].0) != nil, "simulator and hidden transport retain production protocol")
        }
        let stale = owner.menu(isContainer: true, targetedURL: desktop, actionTarget: receivers[0]).menu!
        try writeManifest(manifest, ["JobsDesktopTools", "JobsDiskSpaceInfo"])
        dispatch(stale.items[0], principal: receivers[0])
        expect(launches.count == 12, "owner or provider change invalidates old menu")
        expect(coordinators[1].menu(isContainer: true, targetedURL: desktop, actionTarget: receivers[1]).menu?.items.count == 7, "uninstall reelects next renderer")
        try writeManifest(manifest, providers)
        try "harmony-simulator-create,hidden-files-toggle".write(to: features, atomically: true, encoding: .utf8)
        expect(owner.menu(isContainer: true, targetedURL: desktop, actionTarget: receivers[0]).menu?.items.map(\.title) == ["📃 新建文件…", "🌈 新建 Harmony 模拟器", "🙈 隐藏文件", "🔄 更新开发环境（update）", "💽 磁盘剩余：测试快照"], "individual desktop leaf switches remain independent")
        try "unknown,hidden-files-toggle".write(to: features, atomically: true, encoding: .utf8)
        expect(owner.menu(isContainer: true, targetedURL: desktop, actionTarget: receivers[0]).menu?.items.count == 3, "invalid leaf configuration never enables guessed actions")
        try desktopActions.joined(separator: ",").write(to: features, atomically: true, encoding: .utf8)
        owner.hiddenValue = { throw NSError(domain: "test", code: 1) }
        let unreadable = owner.menu(isContainer: true, targetedURL: desktop, actionTarget: receivers[0]).menu!
        expect(!unreadable.items[6].isEnabled && unreadable.items[6].title == "⚠️ 隐藏文件状态不可用", "unreadable hidden state is explicitly disabled")
        dispatch(unreadable.items[6], principal: receivers[0])
        expect(launches.count == 12, "disabled hidden request cannot launch when invoked directly")
        for invalid: [String: Any] in [
            ["schemaVersion": 2, "owner": providers[0], "providers": providers],
            ["schemaVersion": 1, "owner": providers[3], "providers": providers],
            ["schemaVersion": 1, "owner": providers[0], "providers": [providers[0], providers[0]]],
            ["schemaVersion": 1, "owner": "../other", "providers": ["../other"]]
        ] {
            try JSONSerialization.data(withJSONObject: invalid).write(to: manifest)
            let result = owner.menu(isContainer: true, targetedURL: desktop, actionTarget: receivers[0])
            expect(result.handled && result.menu == nil, "malformed or injected manifest fails closed")
        }
        try writeManifest(manifest, providers)
        let targetHost = container.appendingPathComponent("Contents/Applications/JobsDiskSpaceInfo.app")
        let old = targetHost.appendingPathExtension("saved")
        try FileManager.default.moveItem(at: targetHost, to: old)
        try FileManager.default.createSymbolicLink(at: targetHost, withDestinationURL: old)
        expect(owner.menu(isContainer: true, targetedURL: desktop, actionTarget: receivers[0]).menu == nil, "symlinked provider is rejected")
        try FileManager.default.removeItem(at: targetHost)
        try FileManager.default.moveItem(at: old, to: targetHost)
        let expired = owner.menu(isContainer: true, targetedURL: directory, actionTarget: receivers[0]).menu!
        try FileManager.default.removeItem(at: directory)
        dispatch(expired.items[0], principal: receivers[0])
        expect(launches.count == 12, "deleted target cannot create file")
        try FileManager.default.removeItem(at: manifest)
        expect(!owner.menu(isContainer: true, targetedURL: desktop, actionTarget: receivers[0]).handled, "removed shared manifest restores standalone fallback")
        print("PASS: \(checks) ordered desktop menu assertions")
    }

    /// Finder 不保留原对象 target；按公开协议将复制项 action 交给 principal。
    static func dispatch(_ item: NSMenuItem, principal: FIFinderSync) {
        let copied = item.copy() as! NSMenuItem
        copied.target = nil
        copied.representedObject = nil
        guard let action = copied.action else {
            preconditionFailure("menu action missing")
        }
        expect(principal.responds(to: action), "principal responds to every copied menu action")
        expect(NSApplication.shared.sendAction(action, to: principal, from: copied), "AppKit sends action to principal")
    }

    static func writeManifest(_ url: URL, _ selected: [String]) throws {
        let owner = providers.first(where: { selected.contains($0) })!
        let manifest = OrderedDesktopMenuCoordinator.Manifest(schemaVersion: 1, owner: owner, providers: selected)
        try JSONEncoder().encode(manifest).write(to: url, options: .atomic)
    }

    static func extensionURL(_ provider: String, container: URL) -> URL {
        return container.appendingPathComponent("Contents/Applications/" + provider + ".app/Contents/PlugIns/" + provider + "FinderSync.appex")
    }

    static func writeInfo(_ app: URL, _ info: [String: Any]) throws {
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
    }

    static func makeProvider(_ name: String, container: URL) throws {
        let ids = ["JobsFileCreator": "com.jobs.filecreator", "JobsDesktopTools": "com.jobs.desktoptools",
                   "JobsEnvironmentUpdater": "com.jobs.environmentupdater", "JobsDiskSpaceInfo": "com.jobs.diskspaceinfo"]
        let app = container.appendingPathComponent("Contents/Applications/" + name + ".app")
        let plugin = extensionURL(name, container: container)
        try writeInfo(app, ["CFBundleIdentifier": ids[name]!, "CFBundleExecutable": name, "JobsOrderedDesktopMenuVersion": 1])
        try writeInfo(plugin, ["CFBundleIdentifier": ids[name]! + ".findersync", "CFBundleExecutable": name + "FinderSync"])
        for (bundle, executable) in [(app, name), (plugin, name + "FinderSync")] {
            let directory = bundle.appendingPathComponent("Contents/MacOS")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(executable)
            try Data("fixture".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }
}
