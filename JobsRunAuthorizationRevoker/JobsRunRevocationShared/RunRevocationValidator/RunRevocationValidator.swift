//
//  RunRevocationValidator.swift
//  JobsRunRevocationShared
//
//  Created by Jobs on 2026年10月24日，星期六.
//

import Foundation

/// 菜单和宿主共用单文件边界，不将目录、工程包或符号链接当成可授权文件。
struct RunRevocationValidator {
    func isRegularFile(at url: URL) -> Bool {
        guard url.isFileURL,
              !url.path.utf8.contains(0),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.standardizedFileURL.path),
              let type = attributes[.type] as? FileAttributeType else {
            return false
        }
        return type == .typeRegular
    }

    func selectedFile(from urls: [URL]?) -> URL? {
        guard let urls, urls.count == 1,
              let url = urls.first,
              isRegularFile(at: url) else {
            return nil
        }
        return url.standardizedFileURL
    }
}
