//
//  SendToCoreTests.swift
//  JobsSendToCoreTests
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import Darwin

@main
enum SendToCoreTests {
    private static var checks = 0
    private static let manager = FileManager.default

    private static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        precondition(condition, message)
    }

    private static func folder(_ url: URL) throws {
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func write(_ text: String, _ url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    private static func volume(_ url: URL) throws -> SendToVolume {
        return SendToVolume(url: try SendToFilesystem.realURL(url), name: "隔离目标",
                            identity: try SendToFilesystem.identity(SendToFilesystem.attributes(url.path)), isNetwork: false)
    }

    // Only mounted-volume membership is injected; descriptor, identity, copy and cleanup paths are production code.
    private static func run(_ sources: [URL], _ destination: URL,
                            cancel: @escaping () -> Bool = { false },
                            progress: @escaping (SendToProgress) -> Void = { _ in },
                            dataCheckpoint: @escaping (Int64) -> Void = { _ in }) throws -> SendToResult {
        return SendToCopySession(sources: try SendToCore.snapshotSources(sources), destination: try volume(destination),
                                  validateMount: {}, cancel: cancel, progress: progress, dataCheckpoint: dataCheckpoint).run()
    }

    private static func entries(_ directory: URL) throws -> [String] {
        return try manager.contentsOfDirectory(atPath: directory.path).sorted()
    }

    static func main() throws {
        let root = manager.temporaryDirectory.appendingPathComponent("JobsSendToCore-中文 !&% ' $()-" + UUID().uuidString)
        try folder(root)
        defer {
            try? manager.removeItem(at: root)
        }
        let input = root.appendingPathComponent("输入")
        let output = root.appendingPathComponent("输出")
        try folder(input)
        try folder(output)
        let source = input.appendingPathComponent("资料.txt")
        try write("original", source)
        let target = output.appendingPathComponent("资料.txt")
        try write("existing", target)
        var result = try run([source], output)
        expect(result.successes.map(\.lastPathComponent) == ["资料 (2).txt"], "same-name file keeps both")
        expect(result.failures.isEmpty && !result.cancelled, "regular copy succeeds")
        expect(try String(contentsOf: target, encoding: .utf8) == "existing", "existing target never overwritten")
        expect(try String(contentsOf: source, encoding: .utf8) == "original", "source stays unchanged")
        expect(try String(contentsOf: output.appendingPathComponent("资料 (2).txt"), encoding: .utf8) == "original", "copied data matches")
        result = try run([source], output)
        expect(result.successes.first?.lastPathComponent == "资料 (3).txt", "numbered collisions repeat safely")
        let marker: [UInt8] = [11, 22, 33, 44]
        expect(marker.withUnsafeBytes { setxattr(source.path, "com.jobs.sendto.fixture", $0.baseAddress, $0.count, 0, 0) } == 0, "metadata fixture created on temporary source")
        precondition(chmod(source.path, 0o640) == 0)
        result = try run([source], output)
        let metadataCopy = result.successes[0]
        var copiedMarker = [UInt8](repeating: 0, count: 4)
        let markerCount = copiedMarker.withUnsafeMutableBytes { getxattr(metadataCopy.path, "com.jobs.sendto.fixture", $0.baseAddress, $0.count, 0, 0) }
        expect(markerCount == 4 && copiedMarker == marker, "copyfile preserves extended attributes")
        expect(try SendToFilesystem.attributes(metadataCopy.path).st_mode & 0o777 == 0o640, "copyfile preserves source permission bits")
        let hardLink = input.appendingPathComponent("another-hardlink.txt")
        precondition(link(source.path, hardLink.path) == 0)
        result = try run([source, hardLink], output)
        expect(result.successes.count == 2 && result.failures.isEmpty, "distinct ordinary-file hardlink names are both copied without following symlinks")

        let tree = input.appendingPathComponent("folder.command")
        try folder(tree.appendingPathComponent("内层"))
        try write("nested", tree.appendingPathComponent("内层/item"))
        let outside = root.appendingPathComponent("outside")
        try folder(outside)
        try write("outside-preserved", outside.appendingPathComponent("keep"))
        try manager.createSymbolicLink(at: tree.appendingPathComponent("外链"), withDestinationURL: outside)
        let existingTree = output.appendingPathComponent("folder.command")
        try folder(existingTree)
        try write("existing-directory", existingTree.appendingPathComponent("keep"))
        result = try run([tree], output)
        expect(result.successes.first?.lastPathComponent == "folder (2).command", "directory conflict never merges")
        expect(result.failures.isEmpty, "directory data and metadata copy succeeds")
        let copiedTree = output.appendingPathComponent("folder (2).command")
        expect(try String(contentsOf: copiedTree.appendingPathComponent("内层/item"), encoding: .utf8) == "nested", "nested contents copied")
        expect(try manager.destinationOfSymbolicLink(atPath: copiedTree.appendingPathComponent("外链").path) == outside.path, "interior symlink stays a link")
        expect(try entries(existingTree) == ["keep"], "preexisting directory untouched")
        expect(try String(contentsOf: outside.appendingPathComponent("keep"), encoding: .utf8) == "outside-preserved", "external link target is untouched")
        let sourceLink = input.appendingPathComponent("selected-link")
        try manager.createSymbolicLink(at: sourceLink, withDestinationURL: source)
        do {
            _ = try SendToCore.snapshotSources([sourceLink])
            preconditionFailure("selected symlink must be rejected")
        } catch {
            checks += 1
        }

        let inside = tree.appendingPathComponent("目的内部")
        try folder(inside)
        result = try run([tree], inside)
        expect(result.successes.isEmpty && result.failures.count == 1, "destination inside source rejected")
        expect(try entries(inside).isEmpty, "containment failure creates no stage")
        result = try run([tree], tree)
        expect(result.successes.isEmpty && result.failures.count == 1, "destination equals source rejected")
        let destinationAlias = root.appendingPathComponent("destination-alias")
        try manager.createSymbolicLink(at: destinationAlias, withDestinationURL: inside)
        let aliasVolume = SendToVolume(url: destinationAlias, name: "alias", identity: try volume(inside).identity, isNetwork: false)
        expect(!SendToCore.canCopy(sources: try SendToCore.snapshotSources([tree]), destination: aliasVolume), "destination symlink cannot bypass containment")
        let sourceFD = try SendToFilesystem.openDirectory(tree.path)
        let first = try SendToFilesystem.names(fd: sourceFD)
        let second = try SendToFilesystem.names(fd: sourceFD)
        close(sourceFD)
        expect(first == second && !first.isEmpty, "enumerating a directory does not consume the caller's descriptor offset")

        let beforeCancel = try entries(output)
        result = try run([source], output, cancel: { true })
        expect(result.cancelled && result.successes.isEmpty, "pre-start cancellation is separate from failure")
        expect(try entries(output) == beforeCancel, "pre-start cancellation writes nothing")
        let secondSource = input.appendingPathComponent("second.txt")
        try write("second", secondSource)
        var cancelAfterFirst = false
        result = try run([source, secondSource], output, cancel: { cancelAfterFirst }, progress: {
            if $0.completed == 1 {
                cancelAfterFirst = true
            }
        })
        expect(result.cancelled && result.successes.count == 1, "cancellation keeps previously published success")
        expect(!manager.fileExists(atPath: output.appendingPathComponent("second.txt").path), "later item not copied after cancel")

        // Cancel after copyfile reports actual copied data, not merely before/after a top-level file.
        let large = input.appendingPathComponent("large.bin")
        let file = Darwin.open(large.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        precondition(file >= 0)
        let block = [UInt8](repeating: 0x5a, count: 128 * 1024)
        for _ in 0..<128 {
            precondition(block.withUnsafeBytes { Darwin.write(file, $0.baseAddress, $0.count) } == block.count)
        }
        close(file)
        var inFlightCancel = false
        var actualCopied: Int64 = 0
        result = try run([large], output, cancel: { inFlightCancel }, dataCheckpoint: {
            if $0 > 0 {
                actualCopied = $0
                inFlightCancel = true
            }
        })
        expect(actualCopied > 0 && actualCopied < 16 * 1024 * 1024, "large-file cancellation occurs between real data blocks")
        expect(result.cancelled && result.successes.isEmpty && result.failures.isEmpty, "in-flight cancellation stops before publication")
        expect(!manager.fileExists(atPath: output.appendingPathComponent("large.bin").path), "partial large file never published")
        expect(try entries(output).allSatisfy { !$0.hasPrefix(".JobsSendTo-") }, "cancelled private stage is removed")
        expect(try SendToFilesystem.attributes(large.path).st_size == 16 * 1024 * 1024, "large source remains intact")
        for code in [ENOSPC, EIO, ENOTSUP, EPERM] {
            var errorProgressCalls = 0
            let context = SendToCopyContext(cancelled: { false }, progress: { errorProgressCalls += 1 }, dataCheckpoint: { _ in })
            errno = code
            let response = SendToCopyContext.callback(COPYFILE_COPY_DATA, COPYFILE_ERR, nil, nil, nil,
                                                       Unmanaged.passUnretained(context).toOpaque())
            expect(response == COPYFILE_QUIT && context.firstFailure == code, "copyfile errors quit immediately and preserve original system error")
            expect(errorProgressCalls == 0 && !context.userCancelled, "disk-full/I/O/unsupported metadata errors are not retries or user cancellation")
        }
        let cancelledContext = SendToCopyContext(cancelled: { true }, progress: {}, dataCheckpoint: { _ in })
        let cancelledPointer = Unmanaged.passUnretained(cancelledContext).toOpaque()
        expect(SendToCopyContext.callback(COPYFILE_COPY_DATA, COPYFILE_PROGRESS, nil, nil, nil, cancelledPointer) == COPYFILE_QUIT, "user cancel requests copyfile quit")
        errno = ECANCELED
        _ = SendToCopyContext.callback(COPYFILE_COPY_DATA, COPYFILE_ERR, nil, nil, nil, cancelledPointer)
        expect(cancelledContext.userCancelled && cancelledContext.firstFailure == nil, "copyfile cancellation error does not become a fake disk failure")

        let staleSource = input.appendingPathComponent("stale")
        try write("old", staleSource)
        let oldSnapshot = try SendToCore.snapshotSources([staleSource])
        try manager.moveItem(at: staleSource, to: input.appendingPathComponent("stale-preserved"))
        try write("replacement", staleSource)
        result = SendToCopySession(sources: oldSnapshot, destination: try volume(output), validateMount: {}, cancel: { false }, progress: { _ in }).run()
        expect(result.successes.isEmpty && !result.failures.isEmpty, "replaced source snapshot rejected")
        expect(!manager.fileExists(atPath: output.appendingPathComponent("stale").path), "source replacement not copied")

        let switched = root.appendingPathComponent("switched")
        try folder(switched)
        let held = root.appendingPathComponent("held-original-destination")
        var switchedOnce = false
        result = try run([source], switched, progress: { event in
            if !switchedOnce, event.completed == 0 {
                switchedOnce = true
                try! manager.moveItem(at: switched, to: held)
                try! folder(switched)
                try! write("new-destination-preserved", switched.appendingPathComponent("keep"))
            }
        })
        expect(result.successes.isEmpty && !result.failures.isEmpty, "destination replacement fails before publication")
        expect(try entries(switched) == ["keep"], "replacement destination untouched")
        expect(try entries(held).isEmpty, "own stage cleaned through original directory handle only")

        let publishedSwitch = root.appendingPathComponent("published-switch")
        let publishedHeld = root.appendingPathComponent("published-held")
        try folder(publishedSwitch)
        result = SendToCopySession(sources: try SendToCore.snapshotSources([source]), destination: try volume(publishedSwitch),
                                   validateMount: {}, cancel: { false }, progress: { _ in }, publicationCheckpoint: { _ in
                                       try! manager.moveItem(at: publishedSwitch, to: publishedHeld)
                                       try! folder(publishedSwitch)
                                       try! write("replacement-after-publication", publishedSwitch.appendingPathComponent("keep"))
                                   }).run()
        expect(result.successes.count == 1 && result.failures.first?.code == "post-publication", "post-publication mount/path loss preserves success and reports uncertainty separately")
        expect(try String(contentsOf: publishedHeld.appendingPathComponent("资料.txt"), encoding: .utf8) == "original", "published copy is retained after target replacement")
        expect(try entries(publishedSwitch) == ["keep"], "post-publication cleanup never touches replacement destination")

        let stageSwitch = root.appendingPathComponent("stage-switch")
        let heldStage = root.appendingPathComponent("held-private-stage")
        try folder(stageSwitch)
        var changedStage = false
        var replacementStage: URL?
        result = try run([source], stageSwitch, progress: { event in
            if !changedStage, event.completed == 0,
               let name = try! entries(stageSwitch).first(where: { $0.hasPrefix(".JobsSendTo-") }) {
                changedStage = true
                let stage = stageSwitch.appendingPathComponent(name)
                replacementStage = stage
                try! manager.moveItem(at: stage, to: heldStage)
                try! folder(stage)
                try! write("unrelated-replacement", stage.appendingPathComponent("keep"))
            }
        })
        expect(result.successes.isEmpty && result.failures.contains { $0.code == "cleanup" }, "staging identity replacement refuses cleanup")
        expect(try String(contentsOf: replacementStage!.appendingPathComponent("keep"), encoding: .utf8) == "unrelated-replacement", "unknown replacement staging object remains untouched")
        expect(manager.fileExists(atPath: heldStage.appendingPathComponent("payload").path), "moved private partial copy is retained rather than searching/deleting arbitrary paths")

        let sourceSwitch = input.appendingPathComponent("source-switch")
        let sourceHeld = input.appendingPathComponent("source-held")
        try write("selected-source", sourceSwitch)
        var changedSource = false
        result = try run([sourceSwitch], output, progress: { event in
            if !changedSource, event.completed == 0 {
                changedSource = true
                try! manager.moveItem(at: sourceSwitch, to: sourceHeld)
                try! manager.createSymbolicLink(at: sourceSwitch, withDestinationURL: outside.appendingPathComponent("keep"))
            }
        })
        expect(result.successes.isEmpty && !result.failures.isEmpty, "source switched to external symlink during copy is not published")
        expect(try String(contentsOf: sourceHeld, encoding: .utf8) == "selected-source", "original selected source retained")
        expect(try String(contentsOf: outside.appendingPathComponent("keep"), encoding: .utf8) == "outside-preserved", "source switch never follows or mutates external link target")

        let pipeTree = input.appendingPathComponent("pipe-tree")
        try folder(pipeTree)
        precondition(mkfifo(pipeTree.appendingPathComponent("pipe").path, 0o600) == 0)
        result = try run([pipeTree, secondSource], output)
        expect(result.failures.count == 1 && result.successes.count == 1, "unsupported item reports failure and later item still succeeds")
        expect(!manager.fileExists(atPath: output.appendingPathComponent("pipe-tree").path), "failed directory is not partially published")
        expect(try entries(output).allSatisfy { !$0.hasPrefix(".JobsSendTo-") }, "failed private stage removed")
        expect(try SendToFilesystem.attributes(pipeTree.appendingPathComponent("pipe").path).st_mode & S_IFMT == S_IFIFO, "source special node untouched")

        expect(SendToVolumePolicy.accepts(isLocal: false, readOnly: false, writable: true, internalDevice: nil, protocolName: nil, deviceModel: nil), "mounted SMB/AFP network volume accepted")
        expect(SendToVolumePolicy.accepts(isLocal: true, readOnly: false, writable: true, internalDevice: false, protocolName: "USB", deviceModel: "External"), "physical USB volume accepted")
        expect(!SendToVolumePolicy.accepts(isLocal: true, readOnly: false, writable: true, internalDevice: false, protocolName: "Disk Image", deviceModel: "Apple Disk Image"), "NAS-backed local disk image excluded")
        expect(!SendToVolumePolicy.accepts(isLocal: true, readOnly: false, writable: true, internalDevice: true, protocolName: "PCI-Express", deviceModel: "SSD"), "internal disk excluded")
        expect(!SendToVolumePolicy.accepts(isLocal: false, readOnly: true, writable: true, internalDevice: nil, protocolName: nil, deviceModel: nil), "read-only network mount excluded")
        expect(!SendToVolumePolicy.accepts(isLocal: false, readOnly: false, writable: false, internalDevice: nil, protocolName: nil, deviceModel: nil), "nonwritable network mount excluded")
        expect(SendToVolumePolicy.accepts(isLocal: false, readOnly: false, writable: false, internalDevice: nil, protocolName: nil, deviceModel: nil, requireWriteAccess: false), "read-only Finder sandbox may preview a mounted network volume")
        expect(SendToVolumePolicy.accepts(isLocal: true, readOnly: false, writable: false, internalDevice: false, protocolName: "USB", deviceModel: "External", requireWriteAccess: false), "read-only Finder sandbox may preview physical USB media")
        expect(!SendToVolumePolicy.accepts(isLocal: false, readOnly: true, writable: false, internalDevice: nil, protocolName: nil, deviceModel: nil, requireWriteAccess: false), "preview still excludes truly read-only mounted volumes")
        expect(!SendToVolumePolicy.accepts(isLocal: true, readOnly: false, writable: false, internalDevice: false, protocolName: "Disk Image", deviceModel: "Apple Disk Image", requireWriteAccess: false), "preview never turns a local disk image into external media")
        expect(!SendToVolumePolicy.accepts(isLocal: true, readOnly: false, writable: false, internalDevice: true, protocolName: "PCI-Express", deviceModel: "SSD", requireWriteAccess: false), "preview still excludes internal media")
        expect(!SendToVolumePolicy.accepts(isLocal: nil, readOnly: false, writable: false, internalDevice: nil, protocolName: nil, deviceModel: nil, requireWriteAccess: false), "preview still requires volume classification evidence")
        expect(!SendToVolumePolicy.accepts(isLocal: true, readOnly: false, writable: true, internalDevice: false, protocolName: nil, deviceModel: nil), "unknown local hardware excluded conservatively")
        let liveVolumes = try SendToCore.volumes()
        expect(Set(liveVolumes.map(\.identity)).count == liveVolumes.count, "real public mounted-volume query yields unique identities")
        expect(liveVolumes.allSatisfy { $0.url.isFileURL }, "live candidates are mounted file URLs")
        result = SendToCore.copy(sources: try SendToCore.snapshotSources([source]), destination: try volume(output), cancel: { false }, progress: { _ in })
        expect(result.successes.isEmpty && result.failures.first?.code == "create", "production API rejects arbitrary internal test folder as device")
        let longName = String(repeating: "藏", count: 80) + ".txt"
        expect(SendToCopySession.availableName(longName, number: 22).utf8.count <= Int(NAME_MAX), "conflict suffix keeps filesystem component byte limit")
        print("PASS: SendToCoreTests (\(checks) assertions); actual in-flight cancellation after \(actualCopied) bytes; \(liveVolumes.count) live mounted candidates sampled read-only (network \(liveVolumes.filter(\.isNetwork).count), local \(liveVolumes.filter { !$0.isNetwork }.count))")
    }
}
