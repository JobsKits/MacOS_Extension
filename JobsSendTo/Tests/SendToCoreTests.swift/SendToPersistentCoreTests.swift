//
//  SendToPersistentCoreTests.swift
//  JobsSendToCoreTests
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import Darwin

@main
enum SendToPersistentCoreTests {
    static var assertions = 0
    static let manager = FileManager.default

    static func check(_ value: Bool, _ message: String) {
        assertions += 1
        precondition(value, message)
    }

    static func mkdir(_ url: URL) throws {
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func volume(_ url: URL) throws -> SendToVolume {
        return SendToVolume(url: try SendToFilesystem.realURL(url), name: "Isolated device",
                            identity: try SendToFilesystem.identity(SendToFilesystem.attributes(url.path)), isNetwork: false)
    }

    static func engine(root: URL, destination: URL,
                       hook: @escaping (SendToResumeEvent) -> Void = {
                           _ in
                       }) -> SendToPersistentEngine {
        var options = SendToPersistentOptions(storeRoot: root)
        options.volumeProvider = {
            [try volume(destination)]
        }
        options.proofProvider = { url in
            let normal = try SendToPersistentIO.proof(url)
            if try SendToFilesystem.realURL(url) == SendToFilesystem.realURL(destination) {
                return SendToVolumeProof(rootURL: destination, uuid: "isolated-" + destination.lastPathComponent,
                                          fsid: normal.fsid, networkEndpoint: nil, fsType: normal.fsType,
                                          rootIno: try SendToFilesystem.attributes(destination.path).st_ino)
            }
            return normal
        }
        options.hook = hook
        return SendToPersistentEngine(options: options)
    }

    static func writeLarge(_ url: URL, blocks: Int = 5) throws {
        let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        precondition(fd >= 0)
        defer {
            close(fd)
        }
        for index in 0..<blocks {
            try SendToPersistentIO.writeBlock(fd: fd,
                                               data: Data(repeating: UInt8(index + 1), count: SendToPersistentIO.blockSize),
                                               offset: Int64(index * SendToPersistentIO.blockSize), midpoint: {
                                                   _ in
                                               })
        }
    }

    static func subdirectoryTests(_ base: URL) throws {
        let root = base.appendingPathComponent("folder-device")
        let target = root.appendingPathComponent("JobsMacStorage/nested folder")
        let source = base.appendingPathComponent("folder-source.bin")
        let store = base.appendingPathComponent("folder-store")
        try mkdir(target)
        try writeLarge(source, blocks: 2)
        let rootVolume = try volume(root)
        let selected = try SendToFilesystem.selectedDirectory(root: rootVolume, folder: target.standardizedFileURL)
        check(selected.rootURL == rootVolume.url && selected.volumeIdentity == rootVolume.identity,
              "selected subdirectory retains its separate volume anchor")
        let legacy = try JSONDecoder().decode(SendToVolume.self, from: JSONEncoder().encode(rootVolume))
        check(legacy.rootURL == nil && legacy.rootIdentity == nil, "legacy four-field volume records decode as root tasks")
        do {
            _ = try SendToFilesystem.selectedDirectory(root: rootVolume, folder: base)
            preconditionFailure("arbitrary local directory must not become a device")
        } catch { assertions += 1 }
        let link = root.appendingPathComponent("linked-folder")
        try manager.createSymbolicLink(at: link, withDestinationURL: target)
        do {
            _ = try SendToFilesystem.selectedDirectory(root: rootVolume, folder: link)
            preconditionFailure("directory symlink must not become a target")
        } catch { assertions += 1 }
        check(!SendToCore.canCopy(sources: try SendToCore.snapshotSources([root]), destination: selected),
              "selected subdirectory still rejects a containing source folder")
        try Data("existing-user-copy".utf8).write(to: target.appendingPathComponent(source.lastPathComponent))
        var pause = false
        let worker = engine(root: store, destination: root, hook: {
            if $0.phase == .checkpointDurable { pause = true }
        })
        let sources = try SendToCore.snapshotSources([source])
        let id = try worker.create(sources: sources, destination: selected)
        let stopped = worker.resume(taskID: id, cancel: { pause }, progress: { _ in })
        check(stopped.cancelled && stopped.resumeAvailable, "subdirectory transfer pauses with a durable checkpoint")
        let stage = target.appendingPathComponent(".JobsSendTo-" + id.uuidString)
        check(manager.fileExists(atPath: stage.path) && !manager.fileExists(atPath: root.appendingPathComponent(stage.lastPathComponent).path),
              "private checkpoint data stays in the chosen subdirectory")
        let matches = try worker.matchingTasks(sources: sources, destination: selected)
        check(matches.count == 1 && matches[0].summary.id == id && matches[0].canResume,
              "repeat same source and anchored folder discovers original resumable task")
        check(try worker.matchingTasks(sources: sources, destination: rootVolume).isEmpty,
              "a root destination cannot match an old subdirectory task")
        let resumed = engine(root: store, destination: root).resume(taskID: id, cancel: { false }, progress: { _ in })
        check(resumed.failures.isEmpty && resumed.successes.count == 1 && resumed.successes[0].deletingLastPathComponent().path == target.path,
              "fresh engine resumes and publishes inside original target folder")
        check(try Data(contentsOf: target.appendingPathComponent(source.lastPathComponent)) == Data("existing-user-copy".utf8),
              "subdirectory resume preserves existing same-name user copy")
        check(!manager.fileExists(atPath: root.appendingPathComponent(source.lastPathComponent).path),
              "resumed subdirectory task never falls back to volume root")

        let changedSource = base.appendingPathComponent("changed-folder-source")
        try Data("old".utf8).write(to: changedSource)
        let changedSnapshots = try SendToCore.snapshotSources([changedSource])
        let changedID = try worker.create(sources: changedSnapshots, destination: selected)
        try Data("new-content".utf8).write(to: changedSource)
        let changedMatches = try worker.matchingTasks(sources: SendToCore.snapshotSources([changedSource]), destination: selected)
        check(changedMatches.count == 1 && !changedMatches[0].canResume && changedMatches[0].reason != nil,
              "same logical source edited since checkpoint is shown with a blocked-continue reason")
        try worker.discard(taskID: changedID)
        check(try worker.pendingTasks().allSatisfy { $0.id != changedID }, "safe restart can discard only selected old task before creating another")

        let replacementID = try worker.create(sources: sources, destination: selected)
        let moved = root.appendingPathComponent("saved-target")
        try manager.moveItem(at: target, to: moved)
        try mkdir(target)
        let replaced = worker.resume(taskID: replacementID, cancel: { false }, progress: { _ in })
        check(!replaced.failures.isEmpty && replaced.successes.isEmpty,
              "same subdirectory path with a different inode cannot take over an old task")
        try manager.removeItem(at: target)
        try manager.createSymbolicLink(at: target, withDestinationURL: moved)
        let linked = worker.resume(taskID: replacementID, cancel: { false }, progress: { _ in })
        check(!linked.failures.isEmpty && linked.successes.isEmpty, "replaced target path cannot resume through a symlink")

        let network = base.appendingPathComponent("network-fixture")
        try mkdir(network)
        var visible = true
        var mounted = true
        var options = SendToPersistentOptions(storeRoot: base.appendingPathComponent("network-fixture-store"))
        let networkRoot = try volume(network)
        let networkVolume = SendToVolume(url: networkRoot.url, name: "network", identity: networkRoot.identity, isNetwork: true)
        options.volumeProvider = { visible ? [networkVolume] : [] }
        options.mountedVolumeProvider = { mounted ? [network] : [] }
        options.proofProvider = { url in
            let normal = try SendToPersistentIO.proof(url)
            return SendToVolumeProof(rootURL: network, uuid: "network-fixture-proof", fsid: normal.fsid,
                                      networkEndpoint: nil, fsType: normal.fsType, rootIno: networkRoot.identity.ino)
        }
        let networkWorker = SendToPersistentEngine(options: options)
        let networkID = try networkWorker.create(sources: sources, destination: networkVolume)
        visible = false
        let permissions = networkWorker.resume(taskID: networkID, cancel: { false }, progress: { _ in })
        check(permissions.failures.first?.systemCode == nil, "mounted but excluded or unwritable share is not misclassified as a disconnection")
        let deniedMatch = try networkWorker.matchingTasks(sources: sources)
        check(deniedMatch.count == 1 && !deniedMatch[0].canResume && !deniedMatch[0].canRestart,
              "source-only discovery retains inaccessible tasks with disabled unsafe actions")
        mounted = false
        let offlineMatch = try networkWorker.matchingTasks(sources: sources)
        check(offlineMatch.count == 1 && offlineMatch[0].summary.id == networkID && offlineMatch[0].canResume && offlineMatch[0].canRestart,
              "without a mounted target, exact sources discover old task and allow explicit continue or deferred restart intent")
        let offline = networkWorker.resume(taskID: networkID, cancel: { false }, progress: { _ in })
        check(offline.failures.first?.systemCode == ENOTCONN, "only proven absent original network mount gets a reconnectable network errno")

        var liveRoot = base.appendingPathComponent("remount-old")
        let movedRoot = base.appendingPathComponent("remount-new")
        let relative = "JobsMacStorage/inner"
        try mkdir(liveRoot.appendingPathComponent(relative))
        let remountID = try SendToFilesystem.attributes(liveRoot.path).st_ino
        var remountOptions = SendToPersistentOptions(storeRoot: base.appendingPathComponent("remount-store"))
        remountOptions.volumeProvider = { [try volume(liveRoot)] }
        remountOptions.mountedVolumeProvider = { [liveRoot] }
        remountOptions.proofProvider = { url in
            let actual = try SendToPersistentIO.proof(url)
            if url.path == liveRoot.path || url.path.hasPrefix(liveRoot.path + "/") {
                return SendToVolumeProof(rootURL: liveRoot, uuid: "stable-remount-fixture", fsid: actual.fsid,
                                          networkEndpoint: nil, fsType: actual.fsType, rootIno: remountID)
            }
            return actual
        }
        var remountPause = false
        remountOptions.hook = { if $0.phase == .checkpointDurable { remountPause = true } }
        let remountWorker = SendToPersistentEngine(options: remountOptions)
        let remountTarget = try SendToFilesystem.selectedDirectory(root: volume(liveRoot), folder: liveRoot.appendingPathComponent(relative))
        let remountTask = try remountWorker.create(sources: sources, destination: remountTarget)
        _ = remountWorker.resume(taskID: remountTask, cancel: { remountPause }, progress: { _ in })
        try manager.moveItem(at: liveRoot, to: movedRoot)
        liveRoot = movedRoot
        let remounted = SendToPersistentEngine(options: remountOptions).resume(taskID: remountTask, cancel: { false }, progress: { _ in })
        check(remounted.failures.isEmpty && remounted.successes.first?.deletingLastPathComponent().path == liveRoot.appendingPathComponent(relative).path,
              "stable volume at a new mount path resumes the original relative target directory")
        let incompleteAnchor = SendToVolume(url: remountTarget.url, name: "broken", identity: remountTarget.identity,
                                            isNetwork: false, rootURL: remountTarget.rootURL)
        check(!SendToCore.canCopy(sources: sources, destination: incompleteAnchor), "an unpaired volume-root anchor never enables copying")
    }

    static func main() throws {
        let base = manager.temporaryDirectory.appendingPathComponent("JobsSendToPersistent-" + UUID().uuidString)
        try mkdir(base)
        defer {
            try? manager.removeItem(at: base)
        }
        let source = base.appendingPathComponent("source")
        let destination = base.appendingPathComponent("device")
        try mkdir(source)
        try mkdir(destination)
        let ordinary = source.appendingPathComponent("file.txt")
        try Data("source-original".utf8).write(to: ordinary)
        try Data("existing-target".utf8).write(to: destination.appendingPathComponent("file.txt"))
        let store = base.appendingPathComponent("store")
        var worker = engine(root: store, destination: destination)
        var phases: [String] = []
        let task = try worker.create(sources: SendToCore.snapshotSources([ordinary]), destination: volume(destination), progress: {
            phases.append($0.phase ?? "")
        })
        var result = worker.resume(taskID: task, cancel: {
            false
        }, progress: {
            _ in
        })
        check(result.successes.first?.lastPathComponent == "file (2).txt", "persistent engine preserves same-name target")
        check(result.failures.isEmpty && !result.resumeAvailable, "persistent transfer completes")
        check(phases.contains("preparing"), "prehash preparation emits honest phase")
        check(try String(contentsOf: ordinary, encoding: .utf8) == "source-original", "source untouched")
        check(try String(contentsOf: destination.appendingPathComponent("file.txt"), encoding: .utf8) == "existing-target", "existing target untouched")
        let completedNames = try manager.contentsOfDirectory(atPath: worker.directory(task).path)
        check(Set(completedNames) == ["task.json", "receipt.json", "lock"], "completed hash ledgers compact to small receipt and stable lock")
        check(try worker.pendingTasks().isEmpty, "completed receipt excluded from pending list")
        result = worker.resume(taskID: task, cancel: {
            false
        }, progress: {
            _ in
        })
        check(result.successes.count == 1 && !result.resumeAvailable, "completed receipt replay does not re-copy")
        check(!manager.fileExists(atPath: destination.appendingPathComponent("file (3).txt").path), "no extra numbered copy on receipt replay")

        let tree = source.appendingPathComponent("tree")
        try mkdir(tree)
        try Data("nested".utf8).write(to: tree.appendingPathComponent("item"))
        let outside = base.appendingPathComponent("outside")
        try Data("outside-preserved".utf8).write(to: outside)
        try manager.createSymbolicLink(at: tree.appendingPathComponent("link"), withDestinationURL: outside)
        try mkdir(destination.appendingPathComponent("tree"))
        worker = engine(root: store, destination: destination)
        let treeTask = try worker.create(sources: SendToCore.snapshotSources([tree]), destination: volume(destination))
        result = worker.resume(taskID: treeTask, cancel: {
            false
        }, progress: {
            _ in
        })
        check(result.successes.first?.lastPathComponent == "tree (2)", "persistent directory never merges existing directory")
        check(try manager.destinationOfSymbolicLink(atPath: destination.appendingPathComponent("tree (2)/link").path) == outside.path, "persistent symlink copies link text only")
        check(try String(contentsOf: outside, encoding: .utf8) == "outside-preserved", "persistent symlink target untouched")

        let large = source.appendingPathComponent("large.bin")
        try writeLarge(large)
        var pause = false
        var offsets: [Int64] = []
        worker = engine(root: store, destination: destination, hook: {
            if $0.phase == .checkpointDurable, let bytes = $0.bytes {
                offsets.append(bytes)
                if bytes == Int64(2 * SendToPersistentIO.blockSize) {
                    pause = true
                }
            }
        })
        let largeTask = try worker.create(sources: SendToCore.snapshotSources([large]), destination: volume(destination))
        result = worker.resume(taskID: largeTask, cancel: {
            pause
        }, progress: {
            _ in
        })
        check(result.cancelled && result.resumeAvailable && result.taskID == largeTask, "pause preserves durable task identity")
        let stage = destination.appendingPathComponent(".JobsSendTo-" + largeTask.uuidString)
        let payload = stage.appendingPathComponent("payload-0")
        check(try SendToFilesystem.attributes(payload.path).st_size == Int64(2 * SendToPersistentIO.blockSize), "paused committed blocks stay in persistent device stage")
        check(try worker.pendingTasks().contains {
            $0.id == largeTask && $0.state == "paused"
        }, "paused task survives engine instance")
        let fd = Darwin.open(payload.path, O_RDWR | O_NOFOLLOW)
        precondition(fd >= 0)
        try SendToPersistentIO.writeBlock(fd: fd, data: Data([0xff]), offset: Int64(SendToPersistentIO.blockSize), midpoint: {
            _ in
        })
        precondition(ftruncate(fd, off_t(30 * 1024 * 1024)) == 0)
        close(fd)
        var resumedOffsets: [Int64] = []
        worker = engine(root: store, destination: destination, hook: {
            if $0.phase == .checkpointDurable, let bytes = $0.bytes {
                resumedOffsets.append(bytes)
            }
        })
        result = worker.resume(taskID: largeTask, cancel: {
            false
        }, progress: {
            _ in
        })
        check(result.failures.isEmpty && result.successes.count == 1, "resume revalidates and repairs corrupted committed suffix")
        check(resumedOffsets.first == Int64(2 * SendToPersistentIO.blockSize), "resume keeps first valid block and rewinds to corrupted block")
        check(try Data(contentsOf: large) == Data(contentsOf: destination.appendingPathComponent("large.bin")), "resumed final data matches complete source baseline")
        check(!manager.fileExists(atPath: stage.path), "completed persistent stage removed after durable receipt")

        let cancelled = source.appendingPathComponent("cancelled.bin")
        try writeLarge(cancelled, blocks: 2)
        pause = false
        worker = engine(root: store, destination: destination, hook: {
            if $0.phase == .midchunk, ($0.bytes ?? 0) > 0 {
                pause = true
            }
        })
        let cancelledTask = try worker.create(sources: SendToCore.snapshotSources([cancelled]), destination: volume(destination))
        result = worker.resume(taskID: cancelledTask, cancel: {
            pause
        }, progress: {
            _ in
        })
        let cancelledStage = destination.appendingPathComponent(".JobsSendTo-" + cancelledTask.uuidString)
        check(result.cancelled && result.resumeAvailable && manager.fileExists(atPath: cancelledStage.path), "midblock cancellation retains recoverable partial data")
        check(!manager.fileExists(atPath: destination.appendingPathComponent("cancelled.bin").path), "midblock partial never published")
        let lockBefore = try SendToFilesystem.attributes(worker.directory(cancelledTask).appendingPathComponent("lock").path).st_ino
        try Data("unknown-user-data".utf8).write(to: cancelledStage.appendingPathComponent("sentinel"))
        do {
            try worker.discard(taskID: cancelledTask); preconditionFailure("unknown stage content must block discard")
        } catch {
            assertions += 1
        }
        check(try String(contentsOf: cancelledStage.appendingPathComponent("sentinel"), encoding: .utf8) == "unknown-user-data", "discard preserves unknown stage entries")
        try manager.removeItem(at: cancelledStage.appendingPathComponent("sentinel"))
        try worker.discard(taskID: cancelledTask)
        check(!manager.fileExists(atPath: cancelledStage.path), "explicit discard removes only validated private stage")
        check(try SendToFilesystem.attributes(worker.directory(cancelledTask).appendingPathComponent("lock").path).st_ino == lockBefore, "discard keeps same lock inode to prevent split-lock race")
        check(Set(try manager.contentsOfDirectory(atPath: worker.directory(cancelledTask).path)) == ["task.json", "lock"], "discard leaves only small disabled tombstone")
        result = worker.resume(taskID: cancelledTask, cancel: {
            false
        }, progress: {
            _ in
        })
        check(result.successes.isEmpty && !result.failures.isEmpty, "discarded task cannot restart transmission")

        let edited = source.appendingPathComponent("edited.bin")
        try writeLarge(edited, blocks: 2)
        pause = false
        worker = engine(root: store, destination: destination, hook: { if $0.phase == .checkpointDurable {
            pause = true
        } })
        let editedTask = try worker.create(sources: SendToCore.snapshotSources([edited]), destination: volume(destination))
        _ = worker.resume(taskID: editedTask, cancel: {
            pause
        }, progress: {
            _ in
        })
        let editFD = Darwin.open(edited.path, O_WRONLY)
        precondition(editFD >= 0)
        try SendToPersistentIO.writeBlock(fd: editFD, data: Data([123]), offset: 0, midpoint: {
            _ in
        })
        close(editFD)
        result = worker.resume(taskID: editedTask, cancel: {
            false
        }, progress: {
            _ in
        })
        check(result.successes.isEmpty && result.failures.first?.code == "resume-blocked", "source edits during pause block mixed-version resume")
        check(manager.fileExists(atPath: destination.appendingPathComponent(".JobsSendTo-" + editedTask.uuidString).path), "blocked task keeps old stage for review/discard")

        let corruptJournal = worker.directory(editedTask).appendingPathComponent("task.json")
        try Data("damaged".utf8).write(to: corruptJournal)
        check(try worker.pendingTasks().contains {
            $0.id == editedTask && $0.state == "blocked" && $0.detail != nil
        }, "corrupt journal is a blocked row instead of disappearing")
        result = worker.resume(taskID: editedTask, cancel: {
            false
        }, progress: {
            _ in
        })
        check(result.successes.isEmpty && result.resumeAvailable, "corrupt journal never resumes blindly")
        check(manager.fileExists(atPath: destination.appendingPathComponent(".JobsSendTo-" + editedTask.uuidString).path), "corrupt journal leaves target data intact")
        let external = base.appendingPathComponent("external-user-directory")
        try mkdir(external)
        try Data("external-user-file".utf8).write(to: external.appendingPathComponent("keep"))
        let linkedID = UUID()
        try manager.createSymbolicLink(at: worker.directory(linkedID), withDestinationURL: external)
        check(try worker.pendingTasks().contains {
            $0.id == linkedID && $0.state == "blocked"
        }, "symlink task UUID is visible as blocked")
        result = worker.resume(taskID: linkedID, cancel: {
            false
        }, progress: {
            _ in
        })
        check(result.successes.isEmpty && !result.failures.isEmpty, "symlink task UUID never follows external directory")
        do {
            try worker.discard(taskID: linkedID); preconditionFailure("symlink task UUID must not be discarded")
        } catch {
            assertions += 1
        }
        check(try manager.contentsOfDirectory(atPath: external.path) == ["keep"], "list/resume/discard never create external lock or delete external user data")
        try subdirectoryTests(base)
        print("PASS: SendToPersistentCoreTests (\(assertions) production-engine assertions)")
    }
}
