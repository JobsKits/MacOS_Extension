//
//  SendToCore.swift
//  JobsSendToCore
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import Darwin
import DiskArbitration

enum SendToCore {

    // Filesystem and network-volume queries belong on a worker queue, never Finder's menu callback.
    static func volumes() throws -> [SendToVolume] {
        return try volumes(requireWriteAccess: true)
    }

    static func volumes(requireWriteAccess: Bool) throws -> [SendToVolume] {
        let keys: Set<URLResourceKey> = [.volumeIsLocalKey, .volumeIsReadOnlyKey, .volumeNameKey]
        guard let mounts = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: []) else {
            throw SendToCoreError.rejected("无法读取已挂载卷清单。")
        }
        let session = DASessionCreate(kCFAllocatorDefault)
        var result: [SendToVolume] = []
        var identities = Set<SendToIdentity>()
        for mount in mounts {
            do {
                let values = try mount.resourceValues(forKeys: keys)
                var internalDevice: Bool?
                var protocolName: String?
                var deviceModel: String?
                if values.volumeIsLocal == true, let session,
                   let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, mount as CFURL),
                   let description = DADiskCopyDescription(disk) as? [String: Any] {
                    internalDevice = description[kDADiskDescriptionDeviceInternalKey as String] as? Bool
                    protocolName = description[kDADiskDescriptionDeviceProtocolKey as String] as? String
                    deviceModel = description[kDADiskDescriptionDeviceModelKey as String] as? String
                }
                guard SendToVolumePolicy.accepts(isLocal: values.volumeIsLocal,
                                                readOnly: values.volumeIsReadOnly,
                                                writable: requireWriteAccess && FileManager.default.isWritableFile(atPath: mount.path),
                                                internalDevice: internalDevice,
                                                protocolName: protocolName,
                                                deviceModel: deviceModel,
                                                requireWriteAccess: requireWriteAccess) else {
                    continue
                }
                let url = try SendToFilesystem.realURL(mount)
                let attributes = try SendToFilesystem.attributes(url.path)
                guard SendToFilesystem.kind(attributes) == .directory else {
                    continue
                }
                let identity = SendToFilesystem.identity(attributes)
                guard identities.insert(identity).inserted else {
                    continue
                }
                result.append(SendToVolume(url: url,
                                           name: values.volumeName ?? url.lastPathComponent,
                                           identity: identity,
                                           isNetwork: values.volumeIsLocal == false))
            } catch {
                // A mount that disappears during sampling is omitted from this snapshot.
                continue
            }
        }
        return result.sorted {
            if $0.name == $1.name {
                return $0.url.path < $1.url.path
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func snapshotSources(_ urls: [URL]) throws -> [SendToSource] {
        guard !urls.isEmpty, urls.count <= 128 else {
            throw SendToCoreError.rejected("请选择 1 至 128 个普通文件或文件夹。")
        }
        var result: [SendToSource] = []
        var seen = Set<String>()
        for url in urls {
            guard url.isFileURL else {
                throw SendToCoreError.rejected("只接受本地文件路径。")
            }
            let before = try SendToFilesystem.attributes(url.path)
            guard let kind = SendToFilesystem.kind(before) else {
                throw SendToCoreError.rejected("所选链接或特殊设备不参与发送：\(url.path)")
            }
            let resolved = try SendToFilesystem.realURL(url)
            let value = try SendToFilesystem.attributes(resolved.path)
            let identity = SendToFilesystem.identity(value)
            guard identity == SendToFilesystem.identity(before), seen.insert(resolved.path).inserted else {
                throw SendToCoreError.rejected("源对象发生变化或重复选择：\(url.path)")
            }
            result.append(SendToSource(url: resolved, identity: identity, kind: kind))
        }
        return result
    }

    // Read-only preflight still performs I/O and must only be used off the main thread.
    static func canCopy(sources: [SendToSource], destination: SendToVolume) -> Bool {
        do {
            guard !sources.isEmpty, sources.count <= 128 else {
                return false
            }
            let fd = try SendToFilesystem.openDirectory(destination.url.path)
            defer {
                close(fd)
            }
            try SendToFilesystem.validateDestination(destination, fd: fd)
            for source in sources {
                try SendToFilesystem.validate(source)
            }
            try SendToFilesystem.assertOutsideSources(sources, destination: destination, fd: fd)
            return true
        } catch {
            return false
        }
    }

    // The synchronous worker is called from the host's background queue; callbacks are not AppKit calls.
    static func copy(sources: [SendToSource], destination: SendToVolume,
                     cancel: @escaping () -> Bool,
                     progress: @escaping (SendToProgress) -> Void) -> SendToResult {
        do {
            let engine = SendToPersistentEngine(options: SendToPersistentOptions(storeRoot: try SendToPersistentIO.defaultStore()))
            let id = try engine.create(sources: sources, destination: destination, cancel: cancel, progress: progress)
            return engine.resume(taskID: id, cancel: cancel, progress: progress)
        } catch SendToCoreError.cancelled {
            var result = SendToResult()
            result.cancelled = true
            return result
        } catch {
            var result = SendToResult()
            result.failures.append(SendToFailure(source: nil, code: "create", message: error.localizedDescription))
            return result
        }
    }

    static func pendingTasks() throws -> [SendToTaskSummary] {
        return try SendToPersistentEngine(options: SendToPersistentOptions(storeRoot: SendToPersistentIO.defaultStore())).pendingTasks()
    }

    static func matchingTasks(sources: [SendToSource], destination: SendToVolume? = nil,
                               cancel: () -> Bool = { false }) throws -> [SendToTaskMatch] {
        return try SendToPersistentEngine(options: SendToPersistentOptions(storeRoot: SendToPersistentIO.defaultStore()))
            .matchingTasks(sources: sources, destination: destination, cancel: cancel)
    }

    static func selectedDirectory(root: SendToVolume, folder: URL, expectedInode: UInt64? = nil) throws -> SendToVolume {
        guard let current = try volumes().first(where: {
            $0.url == root.volumeURL && $0.identity == root.volumeIdentity
        }) else {
            throw SendToCoreError.rejected("原设备已卸载或卷身份变化，请重新扫描。")
        }
        return try SendToFilesystem.selectedDirectory(root: current, folder: folder, expectedInode: expectedInode)
    }

    static func destinationProof(taskID: UUID) throws -> SendToVolumeProof {
        return try SendToPersistentEngine(options: SendToPersistentOptions(storeRoot: SendToPersistentIO.defaultStore()))
            .destinationProof(taskID: taskID)
    }

    static func resolvedDestination(taskID: UUID) throws -> SendToVolume {
        return try SendToPersistentEngine(options: SendToPersistentOptions(storeRoot: SendToPersistentIO.defaultStore()))
            .resolvedDestination(taskID: taskID)
    }

    static func resume(taskID: UUID, cancel: @escaping () -> Bool,
                       progress: @escaping (SendToProgress) -> Void) -> SendToResult {
        do {
            return SendToPersistentEngine(options: SendToPersistentOptions(storeRoot: try SendToPersistentIO.defaultStore()))
                .resume(taskID: taskID, cancel: cancel, progress: progress)
        } catch {
            var result = SendToResult()
            result.taskID = taskID
            result.resumeAvailable = true
            result.failures.append(SendToFailure(source: nil, code: "journal", message: error.localizedDescription))
            return result
        }
    }

    static func discard(taskID: UUID) throws {
        try SendToPersistentEngine(options: SendToPersistentOptions(storeRoot: SendToPersistentIO.defaultStore())).discard(taskID: taskID)
    }
}
