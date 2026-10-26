//
//  DesktopMenuRequest.swift
//  JobsDesktopToolsShared
//
//  Created by Jobs on 2026年10月26日，星期一.
//

import Foundation

/// 固定白名单 URL 只表达动作，不能携带路径、命令或任意资源名。
struct DesktopMenuRequest {
    let action: DesktopMenuAction
    let showsHiddenFiles: Bool?

    init(action: DesktopMenuAction, showsHiddenFiles: Bool? = nil) {
        self.action = action
        self.showsHiddenFiles = showsHiddenFiles
    }

    var url: URL? {
        if action == .hiddenFiles {
            guard let showsHiddenFiles else {
                return nil
            }
            return URL(string: "jobsdesktoptools://perform/\(action.rawValue)?show=\(showsHiddenFiles ? "1" : "0")")
        }
        guard showsHiddenFiles == nil else {
            return nil
        }
        return URL(string: "jobsdesktoptools://perform/\(action.rawValue)")
    }

    init?(url: URL) {
        for candidate in DesktopMenuAction.allCases {
            let states: [Bool?] = candidate == .hiddenFiles ? [true, false] : [nil]
            for state in states {
                let request = DesktopMenuRequest(action: candidate, showsHiddenFiles: state)
                if request.url?.absoluteString == url.absoluteString {
                    self = request
                    return
                }
            }
        }
        return nil
    }
}
