//
//  PermanentDeleteService.swift
//  JobsPermanentDeleter
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import Darwin

enum PermanentDeleteService {

    struct Failure: LocalizedError {
        let cause: String
        let remainingPath: String?

        var errorDescription: String? {
            return cause + (remainingPath.map { "\n" + PermanentDeleteDiagnostics.remaining + ": " + $0 } ?? "")
        }
    }

    // Open every directory component without following links, binding traversal to the chosen parent.
    static func openDirectory(_ path: String) throws -> Int32 {
        var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw error()
        }
        do {
            for component in path.split(separator: "/") {
                let next = openat(descriptor, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else {
                    throw error()
                }
                close(descriptor)
                descriptor = next
            }
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    // Claim the selected root before deletion, then verify its identity inside a private same-volume stage.
    static func apply(_ item: PermanentDeleteContext.Item) throws {
        guard let current = PermanentDeleteContext.snapshot(item.url),
              current.path == item.path, current.device == item.device, current.inode == item.inode,
              current.kind == item.kind, current.parentDevice == item.parentDevice,
              current.parentInode == item.parentInode else {
            throw POSIXError(.ESTALE)
        }
        let parentURL = item.url.deletingLastPathComponent()
        let parent = try openDirectory(parentURL.path)
        defer {
            close(parent)
        }
        var parentInfo = stat()
        var before = stat()
        guard fstat(parent, &parentInfo) == 0,
              parentInfo.st_dev == item.parentDevice, parentInfo.st_ino == item.parentInode,
              fstatat(parent, item.url.lastPathComponent, &before, AT_SYMLINK_NOFOLLOW) == 0,
              PermanentDeleteContext.matches(before, item: item) else {
            throw POSIXError(.ESTALE)
        }
        let stageName = ".jobs-permanent-delete-" + UUID().uuidString
        guard mkdirat(parent, stageName, mode_t(0o700)) == 0 else {
            throw error()
        }
        let stage = openat(parent, stageName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard stage >= 0 else {
            _ = unlinkat(parent, stageName, AT_REMOVEDIR)
            throw error()
        }
        defer {
            close(stage)
        }
        let stagePath = parentURL.appendingPathComponent(stageName).appendingPathComponent("target").path
        guard renameatx_np(parent, item.url.lastPathComponent, stage, "target", UInt32(RENAME_EXCL)) == 0 else {
            let failure = error()
            _ = unlinkat(parent, stageName, AT_REMOVEDIR)
            throw failure
        }
        do {
            var claimed = stat()
            guard fstatat(stage, "target", &claimed, AT_SYMLINK_NOFOLLOW) == 0,
                  PermanentDeleteContext.matches(claimed, item: item) else {
                throw POSIXError(.ESTALE)
            }
            try remove(parent: stage, name: "target", expected: claimed, device: item.device)
            guard unlinkat(parent, stageName, AT_REMOVEDIR) == 0 else {
                throw error()
            }
        } catch {
            var remainder = stat()
            if fstatat(stage, "target", &remainder, AT_SYMLINK_NOFOLLOW) == 0 {
                // Never overwrite a concurrently created original name; report retained data precisely.
                if renameatx_np(stage, "target", parent, item.url.lastPathComponent, UInt32(RENAME_EXCL)) == 0 {
                    _ = unlinkat(parent, stageName, AT_REMOVEDIR)
                    throw Failure(cause: error.localizedDescription + "\n" + PermanentDeleteDiagnostics.partial, remainingPath: item.path)
                }
                throw Failure(cause: error.localizedDescription + "\n" + PermanentDeleteDiagnostics.partial, remainingPath: stagePath)
            }
            if unlinkat(parent, stageName, AT_REMOVEDIR) != 0 {
                throw Failure(cause: error.localizedDescription, remainingPath: parentURL.appendingPathComponent(stageName).path)
            }
            throw error
        }
    }

    // Descend via directory handles, never traverse links or mounted filesystems, and verify each unlink.
    private static func remove(parent: Int32, name: String, expected: stat, device: Int32) throws {
        var current = stat()
        guard fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
              sameIdentity(current, expected), current.st_dev == device else {
            throw POSIXError(.ESTALE)
        }
        if current.st_mode & UInt16(S_IFMT) == UInt16(S_IFDIR) {
            let descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else {
                throw error()
            }
            var opened = stat()
            guard fstat(descriptor, &opened) == 0, sameIdentity(opened, expected),
                  let directory = fdopendir(descriptor) else {
                close(descriptor)
                throw POSIXError(.ESTALE)
            }
            defer {
                closedir(directory)
            }
            errno = 0
            while let entry = readdir(directory) {
                let child = withUnsafePointer(to: entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if child == "." || child == ".." {
                    continue
                }
                var childInfo = stat()
                guard fstatat(descriptor, child, &childInfo, AT_SYMLINK_NOFOLLOW) == 0 else {
                    throw error()
                }
                try remove(parent: descriptor, name: child, expected: childInfo, device: device)
                errno = 0
            }
            guard errno == 0 else {
                throw error()
            }
            var final = stat()
            guard fstatat(parent, name, &final, AT_SYMLINK_NOFOLLOW) == 0, sameIdentity(final, expected) else {
                throw POSIXError(.ESTALE)
            }
            guard unlinkat(parent, name, AT_REMOVEDIR) == 0 else {
                throw error()
            }
        } else {
            let kind = current.st_mode & UInt16(S_IFMT)
            guard kind == UInt16(S_IFREG) || kind == UInt16(S_IFLNK) else {
                throw POSIXError(.ENOTSUP)
            }
            guard unlinkat(parent, name, 0) == 0 else {
                throw error()
            }
        }
    }

    // Keep low-level diagnostics intact while the surrounding UI supplies translated context.
    private static func error() -> POSIXError {
        return POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    private static func sameIdentity(_ left: stat, _ right: stat) -> Bool {
        return left.st_dev == right.st_dev && left.st_ino == right.st_ino &&
            left.st_mode & UInt16(S_IFMT) == right.st_mode & UInt16(S_IFMT)
    }
}

// Foundation-only tests provide these strings; the host binds them to the selected UI language.
enum PermanentDeleteDiagnostics {
    static var remaining = "Remaining path"
    static var partial = "Deletion may be partial. Remaining items were retained; no deleted contents can be restored by this tool."
}
