//
//  FileHashTarget.swift
//  JobsFileHasherShared
//
//  Created by Jobs on 2026年11月6日，星期五.
//

import Foundation
import Darwin

enum FileHashTarget {

    // 使用 lstat 排除目录、链接与设备；菜单和实际打开前共用同一边界。
    static func regularFile(_ url: URL) -> URL? {
        guard url.isFileURL,
              url.path.hasPrefix("/"),
              !url.path.contains("\0") else {
            return nil
        }
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            return nil
        }
        return url.standardizedFileURL
    }

    static func singleSelection(_ urls: [URL]?) -> URL? {
        guard let urls,
              urls.count == 1 else {
            return nil
        }
        return regularFile(urls[0])
    }
}
