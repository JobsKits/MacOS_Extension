//
//  DiskCleanupTransportTests.swift
//  JobsDiskSpaceInfoTests
//
//  Created by Jobs on 2026年11月15日，星期日.
//

import AppKit

@main
enum DiskCleanupTransportTests {

    static func main() throws {
        let request = DiskCleanupRequest()
        precondition(DiskCleanupRequest(url: request.url!)?.identifier == request.identifier)
        let invalid = [
            "jobsdiskspaceinfo://clean", "jobsdiskspaceinfo://clean?id=invalid",
            "jobsdiskspaceinfo://clean/path?id=\(request.identifier)",
            "jobsdiskspaceinfo://clean?id=\(request.identifier)&p=/tmp",
            "jobsdiskspaceinfo://clean?id=\(request.identifier)&id=\(request.identifier)",
            "jobsdiskspaceinfo://user@clean?id=\(request.identifier)",
            "jobsdiskspaceinfo://clean:123?id=\(request.identifier)",
            "jobsdiskspaceinfo://clean?id=\(request.identifier)#extra",
            "https://clean?id=\(request.identifier)"
        ]
        for value in invalid {
            precondition(DiskCleanupRequest(url: URL(string: value)!) == nil, value)
        }
        let delegate = AppDelegate.make()
        var launches = 0
        delegate.launchCleanup = {
            launches += 1
        }
        delegate.application(NSApplication.shared, open: [request.url!, request.url!, URL(string: invalid[0])!])
        precondition(launches == 1, "重复 AppleEvent 只能转发一次")
        let terminalSource = DiskCleanupTerminalLauncher.terminalScript(command: "/bin/zsh '中文 \\\" $() ` path'")
        let terminalScript = NSAppleScript(source: terminalSource)
        var compileError: NSDictionary?
        precondition(terminalScript?.compileAndReturnError(&compileError) == true && compileError == nil)
        precondition(terminalSource.hasPrefix("tell application \"Terminal\"\nlaunch\ndo script "))
        precondition(terminalSource.components(separatedBy: "\ndo script ").count == 2)
        precondition(terminalSource.contains("\nactivate\nend tell") && !terminalSource.contains("\nactivate\ndo script"))
        precondition(!terminalSource.contains("in window") && !terminalSource.contains("in tab"))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("JobsDiskCleanupTransport-空格 ' \" $(touch injected) `touch injected`\n-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let source = root.appendingPathComponent("空格 ' \" $(touch injected) `touch injected`\n.command")
        try "#!/bin/zsh\nprint -r -- fixture-only\nexit 7\n".write(to: source, atomically: true, encoding: .utf8)
        let carrier = try DiskCleanupTerminalLauncher.prepareCarrier(script: source, temporaryRoot: root)
        let snapshot = carrier.deletingLastPathComponent().appendingPathComponent("Cleanup.command")
        let mode = try FileManager.default.attributesOfItem(atPath: snapshot.path)[.posixPermissions] as! NSNumber
        precondition(mode.intValue == 0o600)
        let snapshotText = try String(contentsOf: snapshot, encoding: .utf8)
        let sourceText = try String(contentsOf: source, encoding: .utf8)
        precondition(snapshotText == sourceText)
        try FileManager.default.removeItem(at: source)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [carrier.path]
        process.currentDirectoryURL = root
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        precondition(process.terminationStatus == 7)
        precondition(!FileManager.default.fileExists(atPath: carrier.deletingLastPathComponent().path))
        precondition(!FileManager.default.fileExists(atPath: root.appendingPathComponent("injected").path))
        let external = root.appendingPathComponent("external.command")
        try "exit 0".write(to: external, atomically: true, encoding: .utf8)
        let link = root.appendingPathComponent("link.command")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        do {
            _ = try DiskCleanupTerminalLauncher.prepareCarrier(script: link, temporaryRoot: root)
            preconditionFailure("不能运输符号链接业务脚本")
        } catch {}
        precondition(DiskCleanupHost.applicationURL(forExtension: root) == nil)
        let app = root.appendingPathComponent("搬迁 中文 Host.app", isDirectory: true)
        let plugin = app.appendingPathComponent("Contents/PlugIns/JobsDiskSpaceInfoFinderSync.appex", isDirectory: true)
        try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
        let info: [String: String] = [
            "CFBundleIdentifier": "com.jobs.diskspaceinfo",
            "CFBundleExecutable": "JobsDiskSpaceInfo",
            "CFBundlePackageType": "APPL"
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        precondition(DiskCleanupHost.applicationURL(forExtension: plugin) == app.standardizedFileURL)
        precondition(DiskCleanupHost.applicationURL(forExtension: app.appendingPathComponent("Other/JobsDiskSpaceInfoFinderSync.appex")) == nil)
        print("PASS: 请求白名单、重复请求去重、危险路径引用、私有快照、App移走后独立执行、真实退出码与载体回收")
    }
}
