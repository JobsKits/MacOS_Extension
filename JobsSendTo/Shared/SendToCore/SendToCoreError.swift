//
//  SendToCoreError.swift
//  JobsSendToCore
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import Darwin

enum SendToCoreError: LocalizedError {
    case rejected(String)
    case system(String, String, Int32)
    case cancelled

    var errorDescription: String? {
        switch self {
        /// 参数或对象身份不满足复制边界。
        case .rejected(let reason):
            return reason
        /// 保留真实系统错误与路径供诊断。
        case .system(let operation, let path, let code):
            return "\(operation)：\(path)（\(code)：\(String(cString: strerror(code)))）"
        /// 取消与普通失败分别汇总。
        case .cancelled:
            return "已取消复制；已完成项目保留。"
        }
    }
}
