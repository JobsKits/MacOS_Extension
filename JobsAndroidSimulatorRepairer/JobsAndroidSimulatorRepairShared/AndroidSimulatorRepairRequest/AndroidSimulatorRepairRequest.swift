//
//  AndroidSimulatorRepairRequest.swift
//  JobsAndroidSimulatorRepairShared
//
//  Created by Jobs on 2026年10月23日，星期五.
//

import Foundation

/// 请求只表达固定动作；外部 URL 无法指定脚本、命令或文件路径。
enum AndroidSimulatorRepairRequest {
    static let scheme = "jobsandroidsimulatorrepairer"
    static let canonicalURL = URL(string: "jobsandroidsimulatorrepairer://simulator/repair")!

    static func isRepairRequest(_ requestURL: URL) -> Bool {
        guard let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.scheme == scheme
            && components.percentEncodedHost == "simulator"
            && components.percentEncodedPath == "/repair"
            && components.user == nil
            && components.password == nil
            && components.port == nil
            && components.query == nil
            && components.fragment == nil
            && requestURL.absoluteString == canonicalURL.absoluteString
    }
}
