//
//  GitProxyRequest.swift
//  JobsGitProxyShared
//
//  Created by Jobs on 2026年10月22日，星期四.
//

import Foundation

/// 请求只表达固定动作；外部 URL 无法指定脚本、命令或文件路径。
enum GitProxyRequest {
    static let scheme = "jobsgitproxyconfigurator"
    static let canonicalURL = URL(string: "jobsgitproxyconfigurator://git/configure")!

    static func isConfigureRequest(_ requestURL: URL) -> Bool {
        guard let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.scheme == scheme
            && components.percentEncodedHost == "git"
            && components.percentEncodedPath == "/configure"
            && components.user == nil
            && components.password == nil
            && components.port == nil
            && components.query == nil
            && components.fragment == nil
            && requestURL.absoluteString == canonicalURL.absoluteString
    }
}
