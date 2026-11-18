//
//  UpdateTransportTests.swift
//  JobsEnvironmentUpdaterTests
//
//  Created by Jobs on 2026年11月17日，星期二.
//

import AppKit

@main
struct UpdateTransportTests {

    static var checks = 0

    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard value() else {
            fatalError(message)
        }
    }

    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("JobsUpdateTransport-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            try? manager.removeItem(at: root)
        }
        let request = EnvironmentUpdateRequest()
        expect(EnvironmentUpdateRequest(url: request.url!)?.identifier == request.identifier, "URL round trip")
        for text in ["jobsenvironmentupdater://clean?id=\(request.identifier)",
                     "jobsenvironmentupdater://update?id=\(request.identifier)&id=\(request.identifier)",
                     "jobsenvironmentupdater://update?id=\(request.identifier)&cmd=-t",
                     "jobsenvironmentupdater://update/?id=\(request.identifier)",
                     "jobsenvironmentupdater://user@update?id=\(request.identifier)",
                     "jobsenvironmentupdater://update:123?id=\(request.identifier)",
                     "jobsenvironmentupdater://update?id=bad",
                     "jobsenvironmentupdater://update?id=\(request.identifier)#extra"] {
            expect(EnvironmentUpdateRequest(url: URL(string: text)!) == nil, "Reject malformed request: " + text)
        }
        let desktop = root.appendingPathComponent("Desktop")
        expect(EnvironmentUpdateContext.candidateURL(isContainer: true, targetedURL: desktop, selectedURLs: nil, desktopURL: desktop) != nil, "Accept desktop blank")
        expect(EnvironmentUpdateContext.candidateURL(isContainer: false, targetedURL: desktop, selectedURLs: nil, desktopURL: desktop) == nil, "Reject item context")
        expect(EnvironmentUpdateContext.candidateURL(isContainer: true, targetedURL: root, selectedURLs: nil, desktopURL: desktop) == nil, "Reject ordinary folder")
        expect(EnvironmentUpdateContext.candidateURL(isContainer: true, targetedURL: desktop, selectedURLs: [root], desktopURL: desktop) == nil, "Reject selection")
        expect(EnvironmentUpdateContext.candidateURL(isContainer: true, targetedURL: URL(string: "https://example.com/Desktop")!, selectedURLs: nil, desktopURL: desktop) == nil, "Reject remote URL")

        let resources = root.appendingPathComponent("中文 ' $() ` \\\" Resource")
        let update = resources.appendingPathComponent("【MacOS】update.command")
        let library = resources.appendingPathComponent("_lib")
        try manager.createDirectory(at: update, withIntermediateDirectories: true)
        try manager.createDirectory(at: library, withIntermediateDirectories: false)
        let payload = """
        #!/bin/zsh
        [[ -z ${JOBS_MAC_ENV_SOURCE_MODE+x} && -z ${JOBS_MAC_ENV_SKIP_README+x} ]] || exit 90
        [[ $# == 0 ]] || exit 91
        [[ $LC_ALL == en_US.UTF-8 ]] || exit 92
        [[ -f ${0:A:h:h}/_lib/Proof.txt ]] || exit 93
        print -r -- 'SAFE_PAYLOAD_ONLY'
        exit 7
        """
        try payload.write(to: update.appendingPathComponent("【MacOS】update.command"), atomically: true, encoding: .utf8)
        try "proof".write(to: library.appendingPathComponent("Proof.txt"), atomically: true, encoding: .utf8)
        let carrier = try EnvironmentUpdateTerminalLauncher.prepareCarrier(resources: resources, temporaryRoot: root)
        let carrierText = try String(contentsOf: carrier, encoding: .utf8)
        expect(!carrierText.contains(" -- ") || carrierText.contains("/bin/rm -r -- "), "Generated carrier is quoted")
        expect(!carrierText.contains(" -t"), "No unattended flag")
        let snapshotAttributes = try manager.attributesOfItem(atPath: carrier.deletingLastPathComponent().path)
        expect((snapshotAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700, "Private snapshot")
        try manager.removeItem(at: resources)
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [carrier.path]
        process.currentDirectoryURL = root
        process.environment = ProcessInfo.processInfo.environment.merging(["JOBS_MAC_ENV_SOURCE_MODE": "1", "JOBS_MAC_ENV_SKIP_README": "1", "LC_ALL": "C"]) { _, new in new }
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        expect(process.terminationStatus == 7, "Propagate payload failure")
        expect(String(decoding: data, as: UTF8.self).contains("SAFE_PAYLOAD_ONLY"), "Execute only snapshot payload after source is removed")
        expect(!manager.fileExists(atPath: carrier.deletingLastPathComponent().path), "Remove private snapshot on exit")
        expect(EnvironmentUpdateTerminalLauncher.shellQuote("a'b") == "'a'\\''b'", "Shell quote")
        expect(EnvironmentUpdateTerminalLauncher.appleScriptQuote("a\\\"b") == "\"a\\\\\\\"b\"", "AppleScript quote")
        let terminalSource = EnvironmentUpdateTerminalLauncher.terminalScript(command: "/bin/zsh '中文 \\\" $() ` path'")
        let terminalScript = NSAppleScript(source: terminalSource)
        var compileError: NSDictionary?
        expect(terminalScript?.compileAndReturnError(&compileError) == true, "Terminal request compiles with quoted command")
        expect(compileError == nil, "Terminal request has no compilation error")
        expect(terminalSource.hasPrefix("tell application \"Terminal\"\nlaunch\ndo script "), "Launch without an implicit run or reopen event")
        expect(terminalSource.components(separatedBy: "\ndo script ").count == 2, "Create exactly one execution window")
        expect(terminalSource.contains("\nactivate\nend tell") && !terminalSource.contains("\nactivate\ndo script"), "Create execution window before activation")
        expect(!terminalSource.contains("in window") && !terminalSource.contains("in tab"), "Never reuse an existing user session")

        try manager.createDirectory(at: update, withIntermediateDirectories: true)
        try "exit 0".write(to: update.appendingPathComponent("【MacOS】update.command"), atomically: true, encoding: .utf8)
        do {
            _ = try EnvironmentUpdateTerminalLauncher.prepareCarrier(resources: resources, temporaryRoot: root)
            fatalError("Missing library accepted")
        } catch {
            expect(true, "Reject missing library")
        }
        try manager.createSymbolicLink(at: library, withDestinationURL: root)
        do {
            _ = try EnvironmentUpdateTerminalLauncher.prepareCarrier(resources: resources, temporaryRoot: root)
            fatalError("Symlink library accepted")
        } catch {
            expect(true, "Reject symlink library")
        }

        let application = root.appendingPathComponent("Host.app")
        let contents = application.appendingPathComponent("Contents")
        let plugins = contents.appendingPathComponent("PlugIns")
        let extensionURL = plugins.appendingPathComponent("JobsEnvironmentUpdaterFinderSync.appex")
        try manager.createDirectory(at: extensionURL, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "com.jobs.environmentupdater", "CFBundleExecutable": "JobsEnvironmentUpdater", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        expect(EnvironmentUpdateHost.applicationURL(forExtension: extensionURL)?.path == application.path, "Resolve exact enclosing host")
        expect(EnvironmentUpdateHost.applicationURL(forExtension: root.appendingPathComponent("JobsEnvironmentUpdaterFinderSync.appex")) == nil, "Reject uncontained extension")
        let unrelated = root.appendingPathComponent("Other.app/Contents/PlugIns/JobsEnvironmentUpdaterFinderSync.appex")
        try manager.createDirectory(at: unrelated, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "unrelated", "CFBundleExecutable": "JobsEnvironmentUpdater"], format: .xml, options: 0).write(to: unrelated.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist"))
        expect(EnvironmentUpdateHost.applicationURL(forExtension: unrelated) == nil, "Reject other bundle identity")
        print("Update transport passed: \(checks) checks; no installation, registration, real update, or Terminal launch.")
    }
}
