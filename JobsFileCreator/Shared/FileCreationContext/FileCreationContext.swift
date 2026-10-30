//
//  FileCreationContext.swift
//  JobsFileCreatorShared
//
//  Created by Jobs on 2026年10月29日，星期四.
//

import Foundation

enum FileCreationContext {

    static func directory(isContainer: Bool,
                          targetedURL: URL?) -> URL? {
        guard isContainer,
              let url = targetedURL,
              url.isFileURL,
              url.path.hasPrefix("/"),
              !url.path.contains("\0"),
              url.query == nil,
              url.fragment == nil,
              url.host == nil || url.host == "" || url.host == "localhost",
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
              values.isDirectory == true else {
            return nil
        }
        return url.standardizedFileURL
    }
}
