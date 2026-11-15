//
//  CommandShortcutContext.swift
//  JobsCommandShortcutCreator
//
//  Created by Jobs on 2026年11月13日，星期五.
//

import Foundation

enum CommandShortcutContext {

    static func directory(isContainer: Bool,
                          targetedURL: URL?) -> URL? {
        guard isContainer,
              let url = targetedURL,
              url.isFileURL,
              url.query == nil,
              url.fragment == nil,
              url.host == nil || url.host == "" || url.host == "localhost",
              url.path.hasPrefix("/"),
              !url.path.contains("\0"),
              url.pathExtension == "command",
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeDirectory,
              script(in: url) != nil else {
            return nil
        }
        return url.standardizedFileURL
    }

    static func script(in directory: URL) -> URL? {
        let script = directory.appendingPathComponent(directory.lastPathComponent,
                                                       isDirectory: false)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: script.path),
              attributes[.type] as? FileAttributeType == .typeRegular else {
            return nil
        }
        return script
    }
}
