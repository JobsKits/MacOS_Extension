//
//  HiddenFilesToggleService.swift
//  JobsHiddenFilesToggler
//
//  Created by Jobs on 2026年10月23日，星期五.
//

import Foundation
import CoreFoundation

/// 执行顺序固定为实时读取、规范化、反转写回、刷新；测试可注入全部系统边界。
struct HiddenFilesToggleService {
    var read: () throws -> Any?
    var write: (Bool) throws -> Void
    var refresh: () throws -> Void

    @discardableResult
    func toggle() throws -> Bool {
        let target = try !Self.booleanValue(read())
        try write(target)
        do {
            try refresh()
        } catch {
            let visibility = target ? "显示" : "隐藏"
            throw NSError(
                domain: "JobsHiddenFilesToggler",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Finder 偏好已写入为‘\(visibility)隐藏文件’，但刷新失败：\(error.localizedDescription)\n请手动重新启动 Finder。再次点击会反转当前偏好。"]
            )
        }
        return target
    }

    static func booleanValue(_ value: Any?) throws -> Bool {
        guard let value else {
            return false
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue
            }
            if number == NSNumber(value: 0) {
                return false
            }
            if number == NSNumber(value: 1) {
                return true
            }
        } else if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                break
            }
        }
        throw NSError(
            domain: "JobsHiddenFilesToggler",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "AppleShowAllFiles 不是可识别的布尔值，已停止，未覆盖现有偏好。"]
        )
    }
}
