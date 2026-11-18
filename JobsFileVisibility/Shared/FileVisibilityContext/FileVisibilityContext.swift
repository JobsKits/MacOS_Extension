//
//  FileVisibilityContext.swift
//  JobsFileVisibility
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import Darwin

enum FileVisibilityContext {

    struct Item: Codable {

        let path: String
        let device: Int32
        let inode: UInt64
        let kind: UInt16

        var url: URL {
            return URL(fileURLWithPath: path)
        }
    }

    static func snapshot(_ url: URL) -> Item? {
        guard url.isFileURL,
              url.host == nil || url.host == "" || url.host == "localhost",
              url.path.hasPrefix("/"),
              url.path != "/",
              url.standardizedFileURL.path == url.path,
              !url.path.contains("\0") else {
            return nil
        }
        var value = stat()
        guard lstat(url.path, &value) == 0 else {
            return nil
        }
        let kind = value.st_mode & UInt16(S_IFMT)
        guard kind == UInt16(S_IFREG) || kind == UInt16(S_IFDIR) else {
            return nil
        }
        return Item(path: url.path,
                    device: value.st_dev,
                    inode: value.st_ino,
                    kind: kind)
    }

    static func matches(_ value: stat, item: Item) -> Bool {
        return value.st_dev == item.device && value.st_ino == item.inode &&
            value.st_mode & UInt16(S_IFMT) == item.kind
    }
}
