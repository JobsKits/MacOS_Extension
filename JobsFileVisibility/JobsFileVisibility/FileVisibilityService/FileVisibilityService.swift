//
//  FileVisibilityService.swift
//  JobsFileVisibility
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import Darwin

enum FileVisibilityService {

    // Bind the mutation to an open object, so a replaced path or final symlink cannot redirect it.
    static func apply(_ item: FileVisibilityContext.Item, hidden: Bool) throws {
        let descriptor = open(item.path, O_EVTONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer {
            close(descriptor)
        }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              FileVisibilityContext.matches(before, item: item) else {
            throw POSIXError(.ESTALE)
        }
        let mask = UInt32(UF_HIDDEN)
        let desired = hidden ? before.st_flags | mask : before.st_flags & ~mask
        if desired != before.st_flags {
            guard fchflags(descriptor, desired) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
        var after = stat()
        var currentPath = stat()
        guard fstat(descriptor, &after) == 0,
              lstat(item.path, &currentPath) == 0,
              FileVisibilityContext.matches(currentPath, item: item),
              after.st_flags & mask == desired & mask,
              after.st_flags & ~mask == before.st_flags & ~mask else {
            throw POSIXError(.ESTALE)
        }
    }
}
