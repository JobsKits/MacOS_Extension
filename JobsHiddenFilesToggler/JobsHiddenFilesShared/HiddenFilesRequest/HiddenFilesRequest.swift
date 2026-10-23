//
//  HiddenFilesRequest.swift
//  JobsHiddenFilesShared
//
//  Created by Jobs on 2026年10月23日，星期五.
//

import Foundation

/// 固定请求不携带目录、脚本或命令，外部参数无法扩大操作范围。
enum HiddenFilesRequest {
    static let canonicalURL = URL(string: "jobshiddenfilestoggler://finder/toggle")!

    static func isToggleRequest(_ url: URL) -> Bool {
        return url.absoluteString == canonicalURL.absoluteString
    }
}
