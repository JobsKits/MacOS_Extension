//
//  SendToResumeCrashTests.swift
//  JobsSendToTests
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import CryptoKit
import Darwin

/// 独立 worker 到达生产故障点后停止，父进程 SIGKILL，再以新进程恢复。
@main
enum SendToResumeCrashTests {

    struct Configuration: Codable {
        let root: URL
        let sources: [URL]
        var stopPhase: String?
        var stopNode: Int?
    }

    struct Marker: Codable {
        let taskID: UUID
        let phase: String
        let nodeIndex: Int?
        let bytes: Int64?
    }

    struct Report: Codable {
        let successes: [URL]
        let failures: [String]
        let cancelled: Bool
        let tasks: [SendToTaskSummary]
        let error: String?
    }

    struct Fixture {
        let configuration: Configuration
        let expected: [String: Data]
        var root: URL {
            return configuration.root
        }
        var destination: URL {
            return root.appendingPathComponent("destination")
        }
        var store: URL {
            return root.appendingPathComponent("journal")
        }
        var configURL: URL {
            return root.appendingPathComponent("config.json")
        }
        var markerURL: URL {
            return root.appendingPathComponent("crash-marker.json")
        }
    }

    static var checks = 0
    static let block = 4 * 1024 * 1024
    static let fileManager = FileManager.default

    static func main() {
        setbuf(stdout, nil)
        do {
            try run()
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func run() throws {
        if CommandLine.arguments.count > 1, CommandLine.arguments[1] == "--worker" {
            try worker(root: URL(fileURLWithPath: CommandLine.arguments[2]), action: CommandLine.arguments[3])
            return
        }
        for phase in ["midchunk", "checkpoint-durable", "publishing-intent", "after-rename"] {
            try fileCrash(phase)
        }
        try metadataCrash(directory: false)
        try metadataCrash(directory: true)
        try metadataCrash(directory: true, phase: "after-rename")
        try completedChildCrash()
        try publishedObjectChanged()
        try sourceMissingAfterRename()
        try ephemeralMountIdentityChanged()
        try cancelledTaskIsRetained()
        try sourceChanged()
        try destinationReplaced()
        try damagedBlock()
        try damagedReadOnlyBlock()
        try damagedManifest()
        try invalidNodePlan()
        try changedOwnerNonce()
        try unknownStageContent()
        try discardLeavesLegacyStage()
        try concurrentWorker()
        print("PASS: \(checks) independent-process crash/resume assertions")
    }

    static func expect(_ value: Bool, _ message: String) throws {
        checks += 1
        guard value else {
            throw NSError(domain: "SendToResumeCrashTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    static func fixture(_ name: String, directory: Bool = false, mode: Int16? = nil) throws -> Fixture {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "JobsSendToResumeCrash-" + name + "-" + UUID().uuidString)
        try fileManager.createDirectory(
            at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let inputs = root.appendingPathComponent("inputs")
        let destination = root.appendingPathComponent("destination")
        try fileManager.createDirectory(at: inputs, withIntermediateDirectories: false)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        try Data("unrelated destination data".utf8).write(to: destination.appendingPathComponent("unrelated.txt"))
        var data = Data()
        for index in 0..<12 {
            data.append(Data(repeating: UInt8(index * 17), count: 1024 * 1024))
        }
        var expected: [String: Data] = [:]
        let source: URL
        if directory {
            source = inputs.appendingPathComponent("tree")
            try fileManager.createDirectory(at: source, withIntermediateDirectories: false)
            for name in ["a.bin", "b.bin"] {
                try data.write(to: source.appendingPathComponent(name))
                expected["tree/" + name] = data
            }
        } else {
            source = inputs.appendingPathComponent("source.bin")
            try data.write(to: source)
            expected["source.bin"] = data
        }
        if let mode {
            try fileManager.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: source.path)
        }
        let configuration = Configuration(root: root, sources: [source], stopPhase: nil, stopNode: nil)
        let fixture = Fixture(configuration: configuration, expected: expected)
        try save(configuration, fixture.configURL)
        return fixture
    }

    static func cleanFixture(_ fixture: Fixture) {
        guard fixture.root.lastPathComponent.hasPrefix("JobsSendToResumeCrash-") else {
            return
        }
        // 仅恢复本轮夹具的权限，避免0400/0500测试留下临时文件；不跟随链接。
        let enumerator = fileManager.enumerator(at: fixture.root, includingPropertiesForKeys: nil)
        if let enumerator {
            for case let url as URL in enumerator {
                if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                    let kind = attributes[.type] as? FileAttributeType,
                    kind == .typeDirectory || kind == .typeRegular
                {
                    try? fileManager.setAttributes(
                        [.posixPermissions: kind == .typeDirectory ? 0o700 : 0o600], ofItemAtPath: url.path)
                }
            }
        }
        try? fileManager.removeItem(at: fixture.root)
    }

    static func fileCrash(_ phase: String) throws {
        let fixture = try fixture(phase)
        defer {
            cleanFixture(fixture)
        }
        let marker = try crash(fixture, phase: phase)
        if phase == "midchunk", let payload = try stagedDataFile(fixture, minimum: 1) {
            let writer = try FileHandle(forWritingTo: payload)
            try writer.seekToEnd()
            try writer.write(contentsOf: Data("uncommitted tail must not become progress".utf8))
            try writer.close()
        }
        let report = try invoke(fixture, action: "resume")
        try assertCompleted(fixture, report)
        if phase == "checkpoint-durable", let committed = marker.bytes {
            let offsets = try events(fixture, action: "resume").filter { $0.phase == "midchunk" }.compactMap(\.bytes)
            try expect(
                !offsets.isEmpty && offsets.allSatisfy { $0 > committed }, "durable prefix is reused after restart")
        }
        if phase == "after-rename" {
            let again = try invoke(fixture, action: "resume")
            try assertCompleted(fixture, again)
            try expect(
                !fileManager.fileExists(atPath: fixture.destination.appendingPathComponent("source (2).bin").path),
                "rename-before-journal does not publish twice")
        }
        print("PASS: crash \(phase)")
    }

    static func metadataCrash(directory: Bool, phase: String = "metadata-applied-before-commit") throws {
        let fixture = try fixture(
            (directory ? "readonly-directory-" : "readonly-file-") + phase, directory: directory,
            mode: directory ? 0o500 : 0o400)
        defer {
            cleanFixture(fixture)
        }
        _ = try crash(fixture, phase: phase, node: directory ? 0 : nil)
        let report = try invoke(fixture, action: "resume")
        try assertCompleted(fixture, report)
        let sourceMode =
            try fileManager.attributesOfItem(atPath: fixture.configuration.sources[0].path)[.posixPermissions]
            as! NSNumber
        let target = fixture.destination.appendingPathComponent(directory ? "tree" : "source.bin")
        let targetMode = try fileManager.attributesOfItem(atPath: target.path)[.posixPermissions] as! NSNumber
        try expect(sourceMode.intValue == (directory ? 0o500 : 0o400), "recovery never changes source permissions")
        try expect(targetMode.intValue == sourceMode.intValue, "metadata survives a crash before its completion marker")
        print("PASS: crash readonly metadata \(directory ? "directory" : "file") at \(phase)")
    }

    static func completedChildCrash() throws {
        let fixture = try fixture("completed-child", directory: true)
        defer {
            cleanFixture(fixture)
        }
        let marker = try crash(fixture, phase: "directory-child-committed")
        let report = try invoke(fixture, action: "resume")
        try assertCompleted(fixture, report)
        let rewritten = try events(fixture, action: "resume").contains {
            $0.nodeIndex == marker.nodeIndex && $0.phase == "midchunk"
        }
        try expect(!rewritten, "completed directory child is verified and not copied again")
        print("PASS: completed directory child is reused")
    }

    static func publishedObjectChanged() throws {
        let fixture = try fixture("changed-published-object")
        defer {
            cleanFixture(fixture)
        }
        _ = try crash(fixture, phase: "after-rename")
        let published = fixture.destination.appendingPathComponent("source.bin")
        let writer = try FileHandle(forWritingTo: published)
        try writer.write(contentsOf: Data([255]))
        try writer.synchronize()
        try writer.close()
        let report = try invoke(fixture, action: "resume")
        try expect(
            report.error != nil || !report.failures.isEmpty,
            "changed published object cannot be accepted as the task result")
        let data = try Data(contentsOf: published)
        try expect(data.first == 255, "uncertain published content is retained, not overwritten")
        try expect(
            !fileManager.fileExists(atPath: fixture.destination.appendingPathComponent("source (2).bin").path),
            "uncertain publication never creates a second copy")
        print("PASS: changed final object blocks ambiguous publication recovery")
    }

    static func sourceMissingAfterRename() throws {
        let fixture = try fixture("published-source-missing")
        defer {
            cleanFixture(fixture)
        }
        _ = try crash(fixture, phase: "after-rename")
        try fileManager.removeItem(at: fixture.configuration.sources[0])
        let report = try invoke(fixture, action: "resume")
        try assertCompleted(fixture, report)
        try expect(
            !fileManager.fileExists(atPath: fixture.configuration.sources[0].path),
            "published fact recovery never recreates a missing source")
        print("PASS: published fact can be committed without reopening a missing source")
    }

    static func sourceChanged() throws {
        let fixture = try fixture("source-change")
        defer {
            cleanFixture(fixture)
        }
        _ = try crash(fixture, phase: "checkpoint-durable")
        let handle = try FileHandle(forWritingTo: fixture.configuration.sources[0])
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("changed source".utf8))
        try handle.close()
        let report = try invoke(fixture, action: "resume")
        try expect(report.error != nil || !report.failures.isEmpty, "changed source blocks continuation")
        try expect(
            !fileManager.fileExists(atPath: fixture.destination.appendingPathComponent("source.bin").path),
            "changed source is not published")
        try expect(!(try stages(fixture)).isEmpty, "changed source preserves incomplete evidence")
        print("PASS: source change is blocked")
    }

    static func ephemeralMountIdentityChanged() throws {
        let fixture = try fixture("ephemeral-device-id")
        defer {
            cleanFixture(fixture)
        }
        _ = try crash(fixture, phase: "checkpoint-durable")
        let manifest = try taskManifest(fixture)
        let record = try SendToPersistentIO.load(SendToTaskRecord.self, from: manifest)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
        var summary = object["summary"] as! [String: Any]
        var destination = summary["destination"] as! [String: Any]
        var destinationIdentity = destination["identity"] as! [String: Any]
        destinationIdentity["dev"] = 1_234_567_890
        destination["identity"] = destinationIdentity
        summary["destination"] = destination
        object["summary"] = summary
        var destinationProof = object["destinationProof"] as! [String: Any]
        destinationProof["fsid"] = "previous-mount-session"
        object["destinationProof"] = destinationProof
        var sources = object["sources"] as! [[String: Any]]
        for index in sources.indices {
            var source = sources[index]["source"] as! [String: Any]
            var identity = source["identity"] as! [String: Any]
            identity["dev"] = 1_234_567_890
            source["identity"] = identity
            sources[index]["source"] = source
            var proof = sources[index]["volume"] as! [String: Any]
            proof["fsid"] = "previous-source-session"
            sources[index]["volume"] = proof
        }
        object["sources"] = sources
        let changed = try JSONDecoder().decode(
            SendToTaskRecord.self, from: JSONSerialization.data(withJSONObject: object))
        // 模拟重启后的挂载期device/fsid变化；稳定UUID、nonce、inode及内容基线保持原样。
        try SendToPersistentIO.save(changed, at: manifest)
        let report = try invoke(fixture, action: "resume")
        try assertCompleted(fixture, report)
        print("PASS: stable volume proof survives ephemeral dev/fsid changes")
    }

    static func cancelledTaskIsRetained() throws {
        let fixture = try fixture("cancel-retains-task")
        defer {
            cleanFixture(fixture)
        }
        let report = try invoke(fixture, action: "cancel")
        try expect(report.cancelled, "cancel returns an explicit paused result")
        try expect(!(try stages(fixture)).isEmpty, "cancel retains its incomplete stage")
        try expect(!report.tasks.isEmpty, "cancelled transfer remains discoverable")
        try expect(
            !fileManager.fileExists(atPath: fixture.destination.appendingPathComponent("source.bin").path),
            "cancel does not publish a partial file")
        let resumed = try invoke(fixture, action: "resume")
        try assertCompleted(fixture, resumed)
        print("PASS: cancel retains a resumable task")
    }

    static func destinationReplaced() throws {
        let fixture = try fixture("destination-replacement")
        defer {
            cleanFixture(fixture)
        }
        _ = try crash(fixture, phase: "checkpoint-durable")
        let saved = fixture.root.appendingPathComponent("saved-destination")
        try fileManager.moveItem(at: fixture.destination, to: saved)
        try fileManager.createDirectory(at: fixture.destination, withIntermediateDirectories: false)
        let sentinel = fixture.destination.appendingPathComponent("do-not-touch")
        let expected = Data("new user destination".utf8)
        try expected.write(to: sentinel)
        let report = try invoke(fixture, action: "resume")
        try expect(report.error != nil || !report.failures.isEmpty, "same path on a replacement volume is not adopted")
        try expect(try Data(contentsOf: sentinel) == expected, "replacement destination data is preserved")
        try expect(
            !fileManager.fileExists(atPath: fixture.destination.appendingPathComponent("source.bin").path),
            "replacement destination receives no publication")
        print("PASS: destination replacement is blocked")
    }

    static func damagedBlock() throws {
        let fixture = try fixture("bad-block")
        defer {
            cleanFixture(fixture)
        }
        _ = try crash(fixture, phase: "checkpoint-durable")
        guard let payload = try stagedDataFile(fixture) else {
            throw failure("no staged data block")
        }
        let writer = try FileHandle(forWritingTo: payload)
        try writer.write(contentsOf: Data([255]))
        try writer.synchronize()
        try writer.close()
        let report = try invoke(fixture, action: "resume")
        if report.error == nil, report.failures.isEmpty {
            try assertCompleted(fixture, report)
        } else {
            try expect(
                !fileManager.fileExists(atPath: fixture.destination.appendingPathComponent("source.bin").path),
                "bad committed block is never published")
            try expect(!(try stages(fixture)).isEmpty, "bad block remains available for diagnosis")
        }
        print("PASS: damaged committed block cannot produce silent corruption")
    }

    static func damagedReadOnlyBlock() throws {
        let fixture = try fixture("readonly-bad-block", mode: 0o400)
        defer {
            cleanFixture(fixture)
        }
        _ = try crash(fixture, phase: "metadata-applied-before-commit")
        guard let payload = try stagedDataFile(fixture) else {
            throw failure("readonly staged data not found")
        }
        // 模拟只读副本的坏块；仅修改本轮已知stage夹具，随后还原其0400权限。
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: payload.path)
        let writer = try FileHandle(forWritingTo: payload)
        try writer.write(contentsOf: Data([255]))
        try writer.synchronize()
        try writer.close()
        try fileManager.setAttributes([.posixPermissions: 0o400], ofItemAtPath: payload.path)
        let report = try invoke(fixture, action: "resume")
        try assertCompleted(fixture, report)
        let sourceMode =
            try fileManager.attributesOfItem(atPath: fixture.configuration.sources[0].path)[.posixPermissions]
            as! NSNumber
        let finalMode =
            try fileManager.attributesOfItem(atPath: fixture.destination.appendingPathComponent("source.bin").path)[
                .posixPermissions] as! NSNumber
        try expect(
            sourceMode.intValue == 0o400 && finalMode.intValue == 0o400,
            "bad-block repair restores output metadata and never chmods the source")
        print("PASS: readonly staged bad block is repaired without changing source permissions")
    }

    static func damagedManifest() throws {
        let fixture = try fixture("bad-manifest")
        defer {
            cleanFixture(fixture)
        }
        let marker = try crash(fixture, phase: "checkpoint-durable")
        let manifest = try taskManifest(fixture)
        try Data("{broken manifest".utf8).write(to: manifest)
        let listed = try invoke(fixture, action: "list")
        try expect(
            listed.tasks.contains { $0.id == marker.taskID && $0.state == "blocked" && !($0.detail ?? "").isEmpty },
            "bad journal remains a blocked row with diagnostics")
        let report = try invoke(fixture, action: "resume")
        try expect(report.error != nil || !report.failures.isEmpty, "bad manifest cannot resume")
        try expect(!(try stages(fixture)).isEmpty, "bad manifest never triggers stage deletion")
        print("PASS: damaged journal is visible and blocked")
    }

    static func unknownStageContent() throws {
        let fixture = try fixture("unknown-stage-entry")
        defer {
            cleanFixture(fixture)
        }
        _ = try crash(fixture, phase: "checkpoint-durable")
        guard let stage = try stages(fixture).first else {
            throw failure("stage not found")
        }
        let unknown = stage.appendingPathComponent("untracked-user-data")
        let expected = Data("must be preserved".utf8)
        try expected.write(to: unknown)
        let report = try invoke(fixture, action: "discard")
        try expect(report.error != nil || !report.failures.isEmpty, "discard refuses unjournaled stage data")
        try expect(try Data(contentsOf: unknown) == expected, "unknown stage data is preserved")
        print("PASS: unknown stage data is never deleted")
    }

    static func invalidNodePlan() throws {
        let fixture = try fixture("invalid-node-plan")
        defer {
            cleanFixture(fixture)
        }
        _ = try crash(fixture, phase: "checkpoint-durable")
        guard let nodeURL = try recursiveFiles(fixture.store).first(where: { $0.lastPathComponent == "node-0.json" })
        else {
            throw failure("node-0.json not found")
        }
        let node = try SendToPersistentIO.load(SendToPersistentNode.self, from: nodeURL)
        let invalid = SendToPersistentNode(
            index: node.index, top: node.top, relative: ["..", "outside"], kind: node.kind,
            ino: node.ino, size: node.size, modifiedSeconds: node.modifiedSeconds,
            modifiedNanoseconds: node.modifiedNanoseconds, changedSeconds: node.changedSeconds,
            changedNanoseconds: node.changedNanoseconds, link: node.link, hashes: node.hashes)
        try SendToPersistentIO.save(invalid, at: nodeURL)
        let report = try invoke(fixture, action: "resume")
        try expect(
            report.error != nil || !report.failures.isEmpty, "a correct checksum cannot authorize traversal paths")
        try expect(
            !fileManager.fileExists(atPath: fixture.root.appendingPathComponent("outside").path),
            "invalid plan never writes outside its stage")
        try expect(!(try stages(fixture)).isEmpty, "invalid plan preserves stage evidence")
        print("PASS: checksum-valid malformed node plan is blocked")
    }

    static func changedOwnerNonce() throws {
        let fixture = try fixture("changed-owner-nonce")
        defer {
            cleanFixture(fixture)
        }
        let marker = try crash(fixture, phase: "checkpoint-durable")
        guard let stage = try stages(fixture).first else {
            throw failure("stage not found")
        }
        try SendToPersistentIO.save(
            SendToStageOwner(version: 1, taskID: marker.taskID, nonce: "different-owner"),
            at: stage.appendingPathComponent("owner.json"))
        let resumed = try invoke(fixture, action: "resume")
        try expect(resumed.error != nil || !resumed.failures.isEmpty, "changed owner nonce blocks resume")
        let discarded = try invoke(fixture, action: "discard")
        try expect(
            discarded.error != nil || !discarded.failures.isEmpty, "changed owner nonce blocks destructive discard")
        try expect(fileManager.fileExists(atPath: stage.path), "foreign-owner stage is retained")
        print("PASS: foreign stage nonce is never adopted or deleted")
    }

    static func discardLeavesLegacyStage() throws {
        let fixture = try fixture("legacy-stage-preservation")
        defer {
            cleanFixture(fixture)
        }
        _ = try crash(fixture, phase: "checkpoint-durable")
        let legacy = fixture.destination.appendingPathComponent(".JobsSendTo-" + UUID().uuidString)
        try fileManager.createDirectory(at: legacy, withIntermediateDirectories: false)
        let sentinel = legacy.appendingPathComponent("legacy-data")
        let bytes = Data("old unjournaled task".utf8)
        try bytes.write(to: sentinel)
        let discarded = try invoke(fixture, action: "discard")
        try expect(
            discarded.error == nil && discarded.failures.isEmpty,
            "explicit discard can remove its proven incomplete task")
        try expect(try Data(contentsOf: sentinel) == bytes, "discard does not adopt or delete an old unjournaled stage")
        try expect(
            fileManager.fileExists(atPath: fixture.configuration.sources[0].path), "discard preserves the source")
        print("PASS: explicit discard leaves legacy unjournaled data alone")
    }

    static func concurrentWorker() throws {
        let fixture = try fixture("concurrent-lock")
        defer {
            cleanFixture(fixture)
        }
        let process = try stoppedWorker(fixture, phase: "midchunk")
        defer {
            terminate(process)
        }
        let report = try invoke(fixture, action: "resume")
        try expect(
            report.error != nil || !report.failures.isEmpty || report.tasks.contains(where: \.isBusy),
            "a second worker cannot acquire the live task lock")
        terminate(process)
        let resumed = try invoke(fixture, action: "resume")
        try assertCompleted(fixture, resumed)
        print("PASS: live lock excludes concurrency and SIGKILL releases it")
    }

    static func assertCompleted(_ fixture: Fixture, _ report: Report) throws {
        try expect(
            report.error == nil && report.failures.isEmpty && !report.cancelled,
            "resume succeeds: \(report.error ?? "") \(report.failures)")
        for (relative, expected) in fixture.expected {
            let actual = try Data(contentsOf: fixture.destination.appendingPathComponent(relative))
            try expect(
                SHA256.hash(data: actual) == SHA256.hash(data: expected), "resumed content hash matches \(relative)")
        }
        try expect(
            try Data(contentsOf: fixture.destination.appendingPathComponent("unrelated.txt"))
                == Data("unrelated destination data".utf8), "unrelated destination data remains unchanged")
        let names = try fileManager.contentsOfDirectory(atPath: fixture.destination.path)
        try expect(!names.contains(where: { $0.contains(" (2)") }), "recovery does not create duplicate publications")
    }

    static func crash(_ fixture: Fixture, phase: String, node: Int? = nil) throws -> Marker {
        let process = try stoppedWorker(fixture, phase: phase, node: node)
        defer {
            terminate(process)
        }
        let marker = try load(Marker.self, fixture.markerURL)
        terminate(process)
        try expect(
            process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGKILL,
            "worker is killed independently at \(phase)")
        return marker
    }

    static func stoppedWorker(_ fixture: Fixture, phase: String, node: Int? = nil) throws -> Process {
        var configuration = fixture.configuration
        configuration.stopPhase = phase
        configuration.stopNode = node
        try save(configuration, fixture.configURL)
        let process = try launch(fixture, action: "run")
        let deadline = Date().addingTimeInterval(30)
        while process.isRunning && !fileManager.fileExists(atPath: fixture.markerURL.path) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard fileManager.fileExists(atPath: fixture.markerURL.path) else {
            terminate(process)
            let report =
                (try? String(contentsOf: fixture.root.appendingPathComponent("report-run.json"), encoding: .utf8))
                ?? "no worker report"
            throw failure("worker did not reach \(phase); " + log(fixture, action: "run") + report)
        }
        return process
    }

    static func invoke(_ fixture: Fixture, action: String) throws -> Report {
        let process = try launch(fixture, action: action)
        defer {
            terminate(process)
        }
        let deadline = Date().addingTimeInterval(40)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard !process.isRunning else {
            throw failure("worker timeout " + action)
        }
        let reportURL = fixture.root.appendingPathComponent("report-" + action + ".json")
        guard process.terminationStatus == 0, fileManager.fileExists(atPath: reportURL.path) else {
            throw failure("worker failed " + action + ": " + log(fixture, action: action))
        }
        return try load(Report.self, reportURL)
    }

    static func launch(_ fixture: Fixture, action: String) throws -> Process {
        let report = fixture.root.appendingPathComponent("report-" + action + ".json")
        if fileManager.fileExists(atPath: report.path) {
            try fileManager.removeItem(at: report)
        }
        let eventURL = fixture.root.appendingPathComponent("events-" + action + ".jsonl")
        try Data().write(to: eventURL)
        let output = fixture.root.appendingPathComponent("worker-" + action + ".log")
        try Data().write(to: output)
        let handle = try FileHandle(forWritingTo: output)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        process.arguments = ["--worker", fixture.root.path, action]
        process.currentDirectoryURL = fixture.root
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        try handle.close()
        return process
    }

    static func terminate(_ process: Process) {
        if process.isRunning {
            _ = kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
    }

    static func stages(_ fixture: Fixture) throws -> [URL] {
        return try fileManager.contentsOfDirectory(at: fixture.destination, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".JobsSendTo-") }
    }

    static func recursiveFiles(_ root: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }
    }

    static func stagedDataFile(_ fixture: Fixture, minimum: Int = block) throws -> URL? {
        for stage in try stages(fixture) {
            for file in try recursiveFiles(stage) {
                let attributes = try fileManager.attributesOfItem(atPath: file.path)
                if attributes[.type] as? FileAttributeType == .typeRegular,
                    file.pathComponents.contains(where: { $0.hasPrefix("payload-") }),
                    (attributes[.size] as? NSNumber)?.intValue ?? 0 >= minimum
                {
                    return file
                }
            }
        }
        return nil
    }

    static func taskManifest(_ fixture: Fixture) throws -> URL {
        let files = try recursiveFiles(fixture.store).filter { $0.lastPathComponent == "task.json" }
        guard let first = files.first else {
            throw failure("task.json not found")
        }
        return first
    }

    static func events(_ fixture: Fixture, action: String) throws -> [Marker] {
        let data = try Data(contentsOf: fixture.root.appendingPathComponent("events-" + action + ".jsonl"))
        return try data.split(separator: 10).map { try JSONDecoder().decode(Marker.self, from: Data($0)) }
    }

    static func log(_ fixture: Fixture, action: String) -> String {
        return
            (try? String(contentsOf: fixture.root.appendingPathComponent("worker-" + action + ".log"), encoding: .utf8))
            ?? "no log"
    }

    static func failure(_ text: String) -> NSError {
        return NSError(domain: "SendToResumeCrashTests", code: 2, userInfo: [NSLocalizedDescriptionKey: text])
    }

    static func save<T: Encodable>(_ value: T, _ url: URL) throws {
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    static func load<T: Decodable>(_ type: T.Type, _ url: URL) throws -> T {
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    static func worker(root: URL, action: String) throws {
        let configuration = try load(Configuration.self, root.appendingPathComponent("config.json"))
        let destinationURL = root.appendingPathComponent("destination")
        var taskID = (try? load(UUID.self, root.appendingPathComponent("task-id.json")))
        var cancelled = false
        let eventURL = root.appendingPathComponent("events-" + action + ".jsonl")
        let eventOutput = try FileHandle(forWritingTo: eventURL)
        defer {
            try? eventOutput.close()
        }
        let options = SendToPersistentOptions(
            storeRoot: root.appendingPathComponent("journal"),
            volumeProvider: {
                let value = try SendToFilesystem.attributes(destinationURL.path)
                return [
                    SendToVolume(
                        url: destinationURL, name: "isolated test destination",
                        identity: SendToFilesystem.identity(value), isNetwork: false)
                ]
            },
            hook: { event in
                guard let id = taskID else {
                    return
                }
                let marker = Marker(
                    taskID: id, phase: event.phase.rawValue, nodeIndex: event.nodeIndex, bytes: event.bytes)
                do {
                    var data = try JSONEncoder().encode(marker)
                    data.append(10)
                    try eventOutput.write(contentsOf: data)
                    if action == "cancel", event.phase == .midchunk {
                        cancelled = true
                    }
                    if action == "run", configuration.stopPhase == event.phase.rawValue,
                        configuration.stopNode == nil || configuration.stopNode == event.nodeIndex
                    {
                        try save(marker, root.appendingPathComponent("crash-marker.json"))
                        _ = raise(SIGSTOP)
                    }
                } catch {
                    fputs("crash hook failed: \(error)\n", stderr)
                    exit(96)
                }
            })
        let engine = SendToPersistentEngine(options: options)
        var result = SendToResult()
        var errorText: String?
        do {
            if action == "run" || action == "cancel" {
                let sources = try SendToCore.snapshotSources(configuration.sources)
                let destination = try options.volumeProvider()[0]
                taskID = try engine.create(sources: sources, destination: destination)
                try save(taskID!, root.appendingPathComponent("task-id.json"))
            }
            if action == "run" || action == "resume" || action == "cancel" {
                guard let taskID else {
                    throw failure("missing task ID")
                }
                result = engine.resume(taskID: taskID, cancel: { cancelled }, progress: { _ in })
            } else if action == "discard" {
                guard let taskID else {
                    throw failure("missing task ID")
                }
                try engine.discard(taskID: taskID)
            }
        } catch {
            errorText = error.localizedDescription
        }
        let tasks: [SendToTaskSummary]
        do {
            tasks = try engine.pendingTasks()
        } catch {
            errorText = (errorText ?? "") + "; list: " + error.localizedDescription
            tasks = []
        }
        let report = Report(
            successes: result.successes, failures: result.failures.map { $0.code + ": " + $0.message },
            cancelled: result.cancelled, tasks: tasks, error: errorText)
        try save(report, root.appendingPathComponent("report-" + action + ".json"))
    }
}
