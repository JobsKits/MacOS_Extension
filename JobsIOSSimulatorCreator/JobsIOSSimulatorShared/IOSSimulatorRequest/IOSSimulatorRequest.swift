//
//  IOSSimulatorRequest.swift
//  JobsIOSSimulatorShared
//
//  Created by Jobs on 2026年10月20日，星期二.
//

import Foundation

/// 请求只表达固定动作；外部 URL 无法指定脚本、命令或文件路径。
enum IOSSimulatorRequest {
    static let scheme = "jobsiossimulatorcreator"
    static let canonicalURL = URL(string: "jobsiossimulatorcreator://simulator/create")!

    static func isCreateRequest(_ requestURL: URL) -> Bool {
        guard let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.scheme == scheme
            && components.percentEncodedHost == "simulator"
            && components.percentEncodedPath == "/create"
            && components.user == nil
            && components.password == nil
            && components.port == nil
            && components.query == nil
            && components.fragment == nil
            && requestURL.absoluteString == canonicalURL.absoluteString
    }
}
