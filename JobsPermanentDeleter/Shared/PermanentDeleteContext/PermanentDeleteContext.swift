//
//  PermanentDeleteContext.swift
//  JobsPermanentDeleter
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import Darwin

enum PermanentDeleteContext {

    struct Item: Codable {
        let path: String
        let device: Int32
        let inode: UInt64
        let kind: UInt16
        let parentDevice: Int32
        let parentInode: UInt64

        var url: URL {
            return URL(fileURLWithPath: path)
        }
    }

    // Reject broad system roots and mount roots; links are represented by their own inode.
    static func snapshot(_ url: URL) -> Item? {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
              url.path.hasPrefix("/"), !url.path.contains("\0"),
              url.standardizedFileURL.path == url.path, url.path != "/" else {
            return nil
        }
        guard let resolved = realpath(url.deletingLastPathComponent().path, nil) else {
            return nil
        }
        let parent = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
        free(resolved)
        let path = parent.appendingPathComponent(url.lastPathComponent).path
        let protected = ["/", "/System", "/Library", "/Applications", "/Users", "/Volumes", "/private", "/bin", "/sbin", "/usr", "/dev", "/etc", "/var", "/tmp", "/private/var", "/private/etc", "/private/tmp", NSHomeDirectory()]
        guard !protected.contains(path), !NSHomeDirectory().hasPrefix(path + "/"),
              !["/System/", "/bin/", "/sbin/", "/usr/", "/dev/", "/private/etc/"].contains(where: path.hasPrefix) else {
            return nil
        }
        var value = stat()
        var parentValue = stat()
        guard lstat(path, &value) == 0, lstat(parent.path, &parentValue) == 0,
              parentValue.st_mode & UInt16(S_IFMT) == UInt16(S_IFDIR),
              value.st_dev == parentValue.st_dev else {
            return nil
        }
        for critical in protected {
            var criticalInfo = stat()
            if stat(critical, &criticalInfo) == 0, value.st_dev == criticalInfo.st_dev, value.st_ino == criticalInfo.st_ino {
                return nil
            }
        }
        let kind = value.st_mode & UInt16(S_IFMT)
        guard kind == UInt16(S_IFREG) || kind == UInt16(S_IFDIR) || kind == UInt16(S_IFLNK) else {
            return nil
        }
        return Item(path: path, device: value.st_dev, inode: value.st_ino, kind: kind,
                    parentDevice: parentValue.st_dev, parentInode: parentValue.st_ino)
    }

    // Match only the object identity; contents are deliberately not treated as a frozen backup.
    static func matches(_ value: stat, item: Item) -> Bool {
        return value.st_dev == item.device && value.st_ino == item.inode &&
            value.st_mode & UInt16(S_IFMT) == item.kind
    }

    // An ancestor selection would consume the other target before its own turn.
    static func validSelection(_ items: [Item]) -> Bool {
        return !items.isEmpty && items.count <= 128 && Set(items.map(\.path)).count == items.count &&
            !items.contains { item in items.contains { other in
                item.path != other.path && item.path.hasPrefix(other.path + "/")
            } }
    }
}
