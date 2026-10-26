//
//  FinderHiddenFilesPreferences.swift
//  JobsHiddenFilesToggler
//
//  Created by Jobs on 2026年10月23日，星期五.
//

import Foundation
import CoreFoundation

/// 明确写当前用户、任意主机的 Finder 域，等价于原脚本的 defaults 偏好作用域。
struct FinderHiddenFilesPreferences {
    private static let applicationID = "com.apple.finder" as CFString
    private static let key = "AppleShowAllFiles" as CFString

    var synchronize: () -> Bool = {
        return CFPreferencesSynchronize(applicationID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    var copyValue: () -> Any? = {
        return CFPreferencesCopyValue(key, applicationID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    var setValue: (Bool) -> Void = { value in
        CFPreferencesSetValue(key, value as CFBoolean, applicationID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    func read() throws -> Any? {
        guard synchronize() else {
            throw failure(code: 10, message: "无法同步读取 Finder 偏好，已停止，未修改偏好。")
        }
        return copyValue()
    }

    func write(_ showsHiddenFiles: Bool) throws {
        setValue(showsHiddenFiles)
        guard synchronize() else {
            throw failure(code: 11, message: "Finder 偏好同步写入失败，结果尚未确认，未刷新 Finder。")
        }
        guard let storedValue = copyValue(),
              let confirmedValue = try? HiddenFilesToggleService.booleanValue(storedValue),
              confirmedValue == showsHiddenFiles else {
            throw failure(code: 12, message: "Finder 偏好写后校验失败，未刷新 Finder。")
        }
    }

    private func failure(code: Int, message: String) -> NSError {
        return NSError(domain: "JobsHiddenFilesToggler", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
