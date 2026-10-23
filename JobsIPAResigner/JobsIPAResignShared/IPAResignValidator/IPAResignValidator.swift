//
//  IPAResignValidator.swift
//  JobsIPAResignShared
//
//  Created by Jobs on 2026年10月23日，星期五.
//

import Foundation

/// 仅接受普通 IPA 文件，菜单、URL 入口和终端派发共用同一边界。
struct IPAResignValidator {
    func isRegularFile(at url: URL) -> Bool {
        guard url.isFileURL,
              url.pathExtension.lowercased() == "ipa",
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
