//
//  OrderedDesktopMenuCoordinator.swift
//  JobsOrderedDesktopMenu
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit
import CoreFoundation
import Darwin
import FinderSync
import Foundation

/// 同一联合 App 的背景菜单只由安装事务指定的一个扩展输出；业务仍交给各自宿主。
final class OrderedDesktopMenuCoordinator: NSObject {

    struct Manifest: Codable {
        let schemaVersion: Int
        let owner: String
        let providers: [String]

        var isValid: Bool {
            return schemaVersion == 1 && !providers.isEmpty &&
                Set(providers).count == providers.count &&
                providers.allSatisfy({ Self.priority.contains($0) }) &&
                Self.priority.first(where: { providers.contains($0) }) == owner
        }

        static let priority = ["JobsFileCreator", "JobsDesktopTools", "JobsEnvironmentUpdater", "JobsDiskSpaceInfo"]
    }

    private struct Snapshot {
        let container: URL
        let manifest: Manifest
        let applications: [String: URL]

        var identity: String {
            return container.path + "|" + manifest.owner + "|" + manifest.providers.sorted().joined(separator: ",")
        }
    }

    private struct Ticket {
        let action: String
        let provider: String
        let directory: URL?
        let showHiddenFiles: Bool?
        let snapshotIdentity: String
    }

    private let extensionURL: URL
    private var nextTag = 0
    private var tickets: [Int: Ticket] = [:]
    var accountHome: () -> URL? = { accountHomeDirectory() }
    var diskTitle: () -> String = { DiskSpaceSummary.menuTitle() }
    var hiddenValue: () throws -> Bool = { try readHiddenFiles() }
    var openHost: (URL, URL) -> Void = { request, application in
        NSWorkspace.shared.open([request], withApplicationAt: application,
                                configuration: NSWorkspace.OpenConfiguration.makeOrderedDesktop()) { _, error in
            if let error {
                NSLog("JobsOrderedDesktopMenu host launch failed: %@", error.localizedDescription)
            }
        }
    }

    init(extensionURL: URL) {
        self.extensionURL = extensionURL
        super.init()
    }

    /// handled=true 包括非 owner 和损坏清单，不能再回落输出第二份同组菜单。
    func menu(isContainer: Bool,
              targetedURL: URL?,
              actionTarget: FIFinderSync) -> (handled: Bool, menu: NSMenu?) {
        guard isContainer, let manifestURL = manifestURL() else {
            return (false, nil)
        }
        guard FileManager.default.fileExists(atPath: manifestURL.path) ||
                (try? FileManager.default.attributesOfItem(atPath: manifestURL.path)) != nil else {
            return (false, nil)
        }
        guard let snapshot = snapshot(at: manifestURL),
              ownProvider == snapshot.manifest.owner else {
            return (true, nil)
        }
        let directory = validDirectory(targetedURL)
        let desktop = isDesktop(targetedURL)
        let menu = NSMenu.makeOrderedDesktop()
        for action in actions(snapshot: snapshot, directory: directory, desktop: desktop,
                              allowsHidden: allowsHiddenFiles(targetedURL)) {
            let visible: Bool?
            if action == "hidden-files-toggle" {
                visible = try? hiddenValue()
            } else {
                visible = nil
            }
            let title = title(action: action, hidden: visible)
            guard nextTag < Int.max else {
                return (true, nil)
            }
            nextTag += 1
            let ticket = Ticket(action: action, provider: provider(for: action), directory: targetedURL,
                                showHiddenFiles: visible.map { !$0 }, snapshotIdentity: snapshot.identity)
            tickets[nextTag] = ticket
            if tickets.count > 256, let oldest = tickets.keys.min() {
                tickets.removeValue(forKey: oldest)
            }
            menu.addItem(NSMenuItem.makeOrderedDesktop(title: title, tag: nextTag,
                                                        action: #selector(performOrderedAction(_:)), target: actionTarget,
                                                        enabled: action != "hidden-files-toggle" || visible != nil))
        }
        return (true, menu.items.isEmpty ? nil : menu)
    }

    @objc func performOrderedAction(_ item: NSMenuItem) {
        // Finder 的跨进程菜单副本保留 tag；不要依赖 representedObject 或当前主区选择。
        guard let ticket = tickets.removeValue(forKey: item.tag),
              let manifestURL = manifestURL(), let snapshot = snapshot(at: manifestURL),
              ownProvider == snapshot.manifest.owner, snapshot.identity == ticket.snapshotIdentity,
              actions(snapshot: snapshot, directory: validDirectory(ticket.directory),
                      desktop: isDesktop(ticket.directory), allowsHidden: allowsHiddenFiles(ticket.directory)).contains(ticket.action),
              let application = snapshot.applications[ticket.provider],
              let request = request(for: ticket) else {
            NSLog("JobsOrderedDesktopMenu request expired or installation/context changed")
            return
        }
        openHost(request, application)
    }

    private var ownProvider: String {
        return extensionURL.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingPathExtension().lastPathComponent
    }

    private func manifestURL() -> URL? {
        let app = extensionURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let applications = app.deletingLastPathComponent()
        let contents = applications.deletingLastPathComponent()
        let container = contents.deletingLastPathComponent()
        guard extensionURL.lastPathComponent == ownProvider + "FinderSync.appex",
              applications.lastPathComponent == "Applications", contents.lastPathComponent == "Contents",
              container.pathExtension == "app" else {
            return nil
        }
        return container.appendingPathComponent("Contents/Resources/DesktopMenu.json")
    }

    private func snapshot(at manifestURL: URL) -> Snapshot? {
        let container = manifestURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard ordinary(container, directory: true),
              ordinary(container.appendingPathComponent("Contents"), directory: true),
              ordinary(container.appendingPathComponent("Contents/Applications"), directory: true),
              ordinary(container.appendingPathComponent("Contents/Resources"), directory: true),
              ordinary(manifestURL, directory: false),
              info(container)?["CFBundleIdentifier"] as? String == "com.jobs.finderextensions.manager",
              let data = try? Data(contentsOf: manifestURL), data.count <= 16_384,
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data), manifest.isValid else {
            NSLog("JobsOrderedDesktopMenu rejected invalid installation manifest")
            return nil
        }
        var applications: [String: URL] = [:]
        for provider in manifest.providers {
            let app = container.appendingPathComponent("Contents/Applications/" + provider + ".app")
            let plugin = app.appendingPathComponent("Contents/PlugIns/" + provider + "FinderSync.appex")
            guard ordinary(app, directory: true), ordinary(app.appendingPathComponent("Contents"), directory: true),
                  ordinary(app.appendingPathComponent("Contents/MacOS"), directory: true),
                  ordinary(app.appendingPathComponent("Contents/PlugIns"), directory: true),
                  ordinary(plugin, directory: true), ordinary(plugin.appendingPathComponent("Contents"), directory: true),
                  let hostInfo = info(app), hostInfo["CFBundleIdentifier"] as? String == bundleID(provider),
                  hostInfo["CFBundleExecutable"] as? String == provider,
                  hostInfo["JobsOrderedDesktopMenuVersion"] as? Int == 1,
                  ordinary(app.appendingPathComponent("Contents/MacOS/" + provider), directory: false),
                  FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/" + provider).path),
                  ordinary(plugin.appendingPathComponent("Contents/MacOS"), directory: true),
                  ordinary(plugin.appendingPathComponent("Contents/MacOS/" + provider + "FinderSync"), directory: false),
                  FileManager.default.isExecutableFile(atPath: plugin.appendingPathComponent("Contents/MacOS/" + provider + "FinderSync").path),
                  info(plugin)?["CFBundleExecutable"] as? String == provider + "FinderSync",
                  info(plugin)?["CFBundleIdentifier"] as? String == bundleID(provider) + ".findersync" else {
                NSLog("JobsOrderedDesktopMenu provider missing or identity changed: %@", provider)
                return nil
            }
            applications[provider] = app
        }
        guard let ownApp = applications[ownProvider],
              ownApp.appendingPathComponent("Contents/PlugIns/" + ownProvider + "FinderSync.appex").standardizedFileURL == extensionURL.standardizedFileURL else {
            return nil
        }
        return Snapshot(container: container, manifest: manifest, applications: applications)
    }

    private func ordinary(_ url: URL, directory: Bool) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return false
        }
        return attributes[.type] as? FileAttributeType == (directory ? .typeDirectory : .typeRegular)
    }

    private func info(_ app: URL) -> [String: Any]? {
        let url = app.appendingPathComponent("Contents/Info.plist")
        guard ordinary(url, directory: false), let data = try? Data(contentsOf: url), data.count <= 65_536 else {
            return nil
        }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    private func bundleID(_ provider: String) -> String {
        switch provider {
        case "JobsFileCreator":
            return "com.jobs.filecreator"
        case "JobsDesktopTools":
            return "com.jobs.desktoptools"
        case "JobsEnvironmentUpdater":
            return "com.jobs.environmentupdater"
        case "JobsDiskSpaceInfo":
            return "com.jobs.diskspaceinfo"
        default:
            return ""
        }
    }

    private func actions(snapshot: Snapshot, directory: URL?, desktop: Bool, allowsHidden: Bool) -> [String] {
        var result: [String] = []
        if directory != nil, snapshot.applications["JobsFileCreator"] != nil {
            result.append("file-create")
        }
        if snapshot.applications["JobsDesktopTools"] != nil {
            let enabled = desktopFeatures()
            if desktop {
                result += Self.desktopActions.filter { enabled.contains($0) }
            }
            if allowsHidden, enabled.contains("hidden-files-toggle") {
                result.append("hidden-files-toggle")
            }
        }
        if desktop, snapshot.applications["JobsEnvironmentUpdater"] != nil {
            result.append("environment-update")
        }
        if snapshot.applications["JobsDiskSpaceInfo"] != nil {
            result.append("disk-space-info")
        }
        return result
    }

    private static let desktopActions = ["ios-simulator-create", "android-simulator-create", "harmony-simulator-create",
                                         "android-simulator-repair", "harmony-simulator-repair"]

    private func desktopFeatures() -> Set<String> {
        guard let home = accountHome() else {
            return []
        }
        let url = home.appendingPathComponent("Library/Application Support/JobsDesktopTools/EnabledFeatures.txt")
        guard ordinary(url, directory: false), let data = try? Data(contentsOf: url), data.count <= 4096,
              let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return []
        }
        let entries = text.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let allowed = Self.desktopActions + ["hidden-files-toggle"]
        guard entries.allSatisfy({ allowed.contains($0) }), Set(entries).count == entries.count else {
            return []
        }
        return Set(entries)
    }

    private func provider(for action: String) -> String {
        switch action {
        case "file-create":
            return "JobsFileCreator"
        case "environment-update":
            return "JobsEnvironmentUpdater"
        case "disk-space-info":
            return "JobsDiskSpaceInfo"
        default:
            return "JobsDesktopTools"
        }
    }

    private func title(action: String, hidden: Bool?) -> String {
        switch action {
        case "file-create":
            return "📃 新建文件…"
        case "ios-simulator-create":
            return "🍎 新建 iOS 模拟器"
        case "android-simulator-create":
            return "📱 新建 Android 模拟器"
        case "harmony-simulator-create":
            return "🌈 新建 Harmony 模拟器"
        case "android-simulator-repair":
            return "🩺 Android 模拟器检测与修复"
        case "harmony-simulator-repair":
            return "🧰 Harmony 模拟器检测与修复"
        case "hidden-files-toggle":
            return hidden.map { $0 ? "🙈 隐藏文件" : "👁️ 显示文件" } ?? "⚠️ 隐藏文件状态不可用"
        case "environment-update":
            return "🔄 更新开发环境（update）"
        default:
            return diskTitle()
        }
    }

    private func request(for ticket: Ticket) -> URL? {
        if ticket.provider == "JobsDesktopTools" {
            guard ticket.action != "hidden-files-toggle" || ticket.showHiddenFiles != nil else {
                return nil
            }
            let suffix = ticket.showHiddenFiles.map { "?show=" + ($0 ? "1" : "0") } ?? ""
            return URL(string: "jobsdesktoptools://perform/" + ticket.action + suffix)
        }
        var parts = URLComponents()
        var items = [URLQueryItem(name: "id", value: UUID().uuidString)]
        switch ticket.action {
        case "file-create":
            guard let directory = validDirectory(ticket.directory) else {
                return nil
            }
            let encoded = Data(directory.path.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            parts.scheme = "jobsfilecreator"
            parts.host = "create"
            items.insert(URLQueryItem(name: "p", value: encoded), at: 0)
        case "environment-update":
            parts.scheme = "jobsenvironmentupdater"
            parts.host = "update"
        case "disk-space-info":
            parts.scheme = "jobsdiskspaceinfo"
            parts.host = "clean"
        default:
            return nil
        }
        parts.queryItems = items
        return parts.url
    }

    private func localTarget(_ url: URL) -> Bool {
        return url.isFileURL && url.path.hasPrefix("/") && !url.path.contains("\0") &&
            url.query == nil && url.fragment == nil &&
            (url.host == nil || url.host == "" || url.host == "localhost")
    }

    private func validDirectory(_ url: URL?) -> URL? {
        var directory: ObjCBool = false
        guard let url, localTarget(url),
              FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
            return nil
        }
        return url.standardizedFileURL
    }

    private func isDesktop(_ url: URL?) -> Bool {
        guard let home = accountHome() else {
            return false
        }
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        let candidate = url ?? desktop
        guard localTarget(candidate) else {
            return false
        }
        return candidate.standardizedFileURL == desktop.standardizedFileURL ||
            candidate.resolvingSymlinksInPath().standardizedFileURL == desktop.resolvingSymlinksInPath().standardizedFileURL
    }

    private func allowsHiddenFiles(_ url: URL?) -> Bool {
        guard let url else {
            return true
        }
        guard localTarget(url) else {
            return false
        }
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) {
            return values.isDirectory != false && values.isPackage != true
        }
        return true
    }

    private static func accountHomeDirectory() -> URL? {
        var bufferSize = max(16_384, Int(sysconf(_SC_GETPW_R_SIZE_MAX)))
        while bufferSize <= 1_048_576 {
            var account = passwd()
            var result: UnsafeMutablePointer<passwd>?
            var buffer = [CChar](repeating: 0, count: bufferSize)
            let lookup = buffer.withUnsafeMutableBufferPointer { storage -> (Int32, String?) in
                let code = getpwuid_r(getuid(), &account, storage.baseAddress, storage.count, &result)
                guard code == 0, let home = result?.pointee.pw_dir else {
                    return (code, nil)
                }
                return (code, String(cString: home))
            }
            if lookup.0 == 0, let path = lookup.1, path.hasPrefix("/") {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            guard lookup.0 == ERANGE else {
                return nil
            }
            bufferSize *= 2
        }
        return nil
    }

    private static func readHiddenFiles() throws -> Bool {
        let domain = "com.apple.finder" as CFString
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw NSError(domain: "JobsOrderedDesktopMenu", code: 1)
        }
        guard let value = CFPreferencesCopyValue("AppleShowAllFiles" as CFString, domain,
                                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            return false
        }
        if let number = value as? NSNumber, number == 0 || number == 1 {
            return number.boolValue
        }
        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                break
            }
        }
        throw NSError(domain: "JobsOrderedDesktopMenu", code: 2)
    }
}

private extension NSMenu {

    static func makeOrderedDesktop() -> NSMenu {
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false
        return menu
    }
}

private extension NSMenuItem {

    static func makeOrderedDesktop(title: String, tag: Int, action: Selector, target: AnyObject, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.tag = tag
        item.target = target
        item.isEnabled = enabled
        return item
    }
}

private extension NSWorkspace.OpenConfiguration {

    static func makeOrderedDesktop() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.allowsRunningApplicationSubstitution = false
        configuration.promptsUserIfNeeded = false
        configuration.addsToRecentItems = false
        configuration.activates = true
        return configuration
    }
}
