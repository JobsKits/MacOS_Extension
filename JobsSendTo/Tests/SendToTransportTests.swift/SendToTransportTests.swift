//
//  SendToTransportTests.swift
//  JobsSendToTests
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit
import FinderSync
import Foundation

/// 同生产 principal 合并为一份临时编译单元，仅注入请求缓存及宿主运输替身。
extension FinderSync {

    func transportItem(_ request: SendToRequest) -> NSMenuItem {
        let tag = reserveTag()!
        requests[tag] = request
        return NSMenuItem.make(title: "fixture", action: #selector(sendToVolume(_:)), target: self).byTag(tag)
    }

    func reloadItem(_ selected: [URL]) -> NSMenuItem {
        let tag = reserveTag()!
        reloadSelections[tag] = selected
        return NSMenuItem.make(title: "fixture-reload", action: #selector(reloadDestinations(_:)), target: self).byTag(tag)
    }

    func requestIsPending(_ tag: Int) -> Bool {
        return requests[tag] != nil || reloadSelections[tag] != nil
    }
}

@main
enum SendToTransportTests {

    static var checks = 0

    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(value(), message)
    }

    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("JobsSendToTransport-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let sourceURL = root.appendingPathComponent("空格 ' \"\n$(touch injected) `touch injected` & % ?.txt")
        try Data("fixture-only".utf8).write(to: sourceURL)
        let source = try SendToCore.snapshotSources([sourceURL])[0]
        let volume = SendToVolume(url: root.appendingPathComponent("可写共享卷"), name: "Time Capsule 测试", identity: SendToIdentity(dev: 1, ino: 2), isNetwork: true)
        let request = SendToRequest(sources: [source], destination: volume)!
        let choose = SendToRequest(sources: [source], destination: nil)!
        expect(SendToRequest(url: request.url!)?.sources == [source], "special paths remain literal")
        expect(SendToRequest(url: request.url!)?.destination == volume, "volume identity round trips")
        expect(SendToRequest(url: choose.url!)?.destination == nil, "choose protocol has no implicit destination")
        expect(SendToRequest(url: request.url!)?.identifier == request.identifier, "request UUID round trips")
        expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("injected").path), "paths never become shell commands")

        let maximum = (0..<128).map {
            SendToSource(url: URL(fileURLWithPath: "/tmp/send-to-\($0)"), identity: SendToIdentity(dev: 1, ino: UInt64($0 + 1)), kind: .file)
        }
        expect(SendToRequest(sources: maximum, destination: volume) != nil, "128 selected objects are accepted")
        expect(SendToRequest(sources: maximum + [source], destination: volume) == nil, "129 objects are rejected")
        expect(SendToRequest(sources: [], destination: volume) == nil, "empty selection is rejected")
        expect(SendToRequest(sources: [source, source], destination: volume) == nil, "duplicate paths are rejected")
        for invalid in [URL(string: "https://example.com/a")!, URL(string: "file://remote/tmp/a")!,
                        URL(string: "file:///tmp/a?query=1")!, URL(string: "file:///tmp/a#fragment")!,
                        URL(fileURLWithPath: "/")] {
            let value = SendToSource(url: invalid, identity: source.identity, kind: .file)
            expect(SendToRequest(sources: [value], destination: volume) == nil, "nonlocal or decorated paths fail closed")
        }
        let underLimit = SendToSource(url: URL(fileURLWithPath: "/tmp/" + String(repeating: "a", count: 20_000)), identity: source.identity, kind: .file)
        let overLimit = SendToSource(url: URL(fileURLWithPath: "/tmp/" + String(repeating: "a", count: 100_000)), identity: source.identity, kind: .file)
        expect(SendToRequest(sources: [underLimit], destination: nil)?.url?.absoluteString.utf8.count ?? 65_537 <= 65_536, "bounded request remains within 64 KiB")
        expect(SendToRequest(sources: [overLimit], destination: nil) == nil, "oversized outgoing transport is rejected")
        expect(SendToRequest(url: URL(string: "jobssendto://choose?sources=" + String(repeating: "a", count: 65_537) + "&id=" + UUID().uuidString)!) == nil, "oversized incoming URL is rejected")

        var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        let originalItems = components.queryItems!
        let mutations: [(inout URLComponents) -> Void] = [
            { $0.scheme = "https" }, { $0.host = "other" }, { $0.path = "/extra" },
            { $0.user = "user" }, { $0.password = "password" }, { $0.port = 123 }, { $0.fragment = "extra" },
            { $0.queryItems = originalItems + [URLQueryItem(name: "other", value: "value")] },
            { $0.queryItems = originalItems + [originalItems[0]] },
            { $0.queryItems = originalItems.filter { $0.name != "id" } + [URLQueryItem(name: "id", value: "invalid")] },
            { $0.queryItems = originalItems.filter { $0.name != "sources" } + [URLQueryItem(name: "sources", value: "!")] },
            { $0.queryItems = originalItems.filter { $0.name != "sources" } + [URLQueryItem(name: "sources", value: "W10")] },
            { $0.queryItems = originalItems.filter { $0.name != "destination" } + [URLQueryItem(name: "destination", value: "bm90LWpzb24")] }
        ]
        for mutation in mutations {
            var changed = components
            mutation(&changed)
            expect(SendToRequest(url: changed.url!) == nil, "malformed URL fields fail closed")
        }
        components.queryItems = originalItems.reversed()
        expect(SendToRequest(url: components.url!)?.sources == [source], "query order does not change the request")

        NSApplication.shared.setActivationPolicy(.prohibited)
        let host = root.appendingPathComponent("完整中文 App.app")
        let plugin = host.appendingPathComponent("Contents/PlugIns/JobsSendToFinderSync.appex")
        try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.jobs.sendto", "CFBundleExecutable": "JobsSendTo", "CFBundlePackageType": "APPL"], format: .xml, options: 0)
            .write(to: host.appendingPathComponent("Contents/Info.plist"))
        expect(SendToHost.applicationURL(forExtension: plugin) == host.standardizedFileURL, "host resolver accepts the exact owned bundle")
        let principal = FinderSync()
        principal.extensionURL = plugin
        var deliveries: [(URL, URL)] = []
        principal.openHost = { url, host, completion in
            deliveries.append((url, host))
            completion(nil, nil)
        }
        let first = principal.transportItem(request)
        let second = principal.transportItem(choose)
        let reload = principal.reloadItem([sourceURL])
        expect(Set([first.tag, second.tag, reload.tag]).count == 3, "copy and reload share one unique tag namespace")
        for (item, name) in [(first, "sendToVolume:"), (second, "sendToVolume:"), (reload, "reloadDestinations:")] {
            expect(item.target === principal, "menu targets the real extension principal")
            let copied = item.copy() as! NSMenuItem
            copied.target = nil
            copied.representedObject = nil
            expect(NSStringFromSelector(copied.action!) == name, "copied item preserves its selector")
            expect(principal.responds(to: copied.action!), "real principal implements the copied selector")
            expect(NSApplication.shared.sendAction(copied.action!, to: principal, from: copied), "AppKit dispatches to principal")
            expect(!principal.requestIsPending(item.tag), "dispatch consumes the stored request")
        }
        let deadline = Date().addingTimeInterval(5)
        while deliveries.count < 3, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        expect(deliveries.count == 3, "all three copied actions reach the injected transport once")
        expect(SendToRequest(url: deliveries[0].0)?.destination == volume, "copy selector preserves chosen volume")
        expect(SendToRequest(url: deliveries[1].0)?.destination == nil, "choose selector remains nonexecuting")
        expect(SendToRequest(url: deliveries[2].0)?.sources.map(\.url) == [source.url], "reload resnapshots the exact selected sources")
        expect(deliveries.allSatisfy { $0.1 == host.standardizedFileURL }, "all requests use the exact owned host")
        expect(principal.menu(for: .contextualMenuForContainer) == nil, "background has no copy source")

        expect(Set(SendToLocalization.languages) == Set(["zh-Hans", "zh-Hant", "bo", "en", "ja", "fr", "es", "de", "ru", "ko"]), "all ten required languages exist")
        expect(SendToLocalization.languageNames.count == 10, "all language choices have visible names")
        for (key, values) in SendToLocalization.translations {
            expect(values.count == 10 && values.allSatisfy { !$0.isEmpty }, "all ten languages cover \(key)")
        }
        for code in ["preflight", "copy", "cleanup", "post-publication", "unknown", "unexpected-value"] {
            let text = SendToLocalization.failureText(code)
            expect(!text.isEmpty && !text.hasPrefix("failure."), "dynamic failure codes have a user-facing explanation")
        }
        if CommandLine.arguments.count > 1 {
            let package = URL(fileURLWithPath: CommandLine.arguments[1])
            let pattern = try NSRegularExpression(pattern: #"SendToLocalization\.text\("([^"\n]+)"\)"#)
            let enumerator = FileManager.default.enumerator(at: package, includingPropertiesForKeys: nil)!
            for case let file as URL in enumerator where file.pathExtension == "swift" && !file.path.contains("/work/") && !file.path.contains("/Tests/") {
                let text = try String(contentsOf: file, encoding: .utf8)
                for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    let key = (text as NSString).substring(with: match.range(at: 1))
                    expect(SendToLocalization.translations[key] != nil, "production language key exists: \(key)")
                }
            }
        }
        print("PASS: \(checks) strict request, principal selector and localization assertions")
    }
}
