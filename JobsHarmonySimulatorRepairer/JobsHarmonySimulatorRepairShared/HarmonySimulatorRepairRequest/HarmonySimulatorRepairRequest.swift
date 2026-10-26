//
//  HarmonySimulatorRepairRequest.swift
//  JobsHarmonySimulatorRepairShared
//
//  Created by Jobs on 2026年10月24日，星期六.
//

import Foundation

/// 请求只表达固定动作；外部 URL 无法指定脚本、命令或文件路径。
enum HarmonySimulatorRepairRequest {
    static let scheme = "jobsharmonysimulatorrepairer"
    static let canonicalURL = URL(string: "jobsharmonysimulatorrepairer://simulator/repair")!

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
