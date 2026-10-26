//
//  HiddenFilesMenuContext.swift
//  JobsHiddenFilesShared
//
//  Created by Jobs on 2026年10月23日，星期五.
//

import Foundation

/// 全局可见性开关允许桌面和目录背景；Finder 的 items / toolbar / sidebar 回调一律不加入。
enum HiddenFilesMenuContext {
    static func allowsMenu(isContainer: Bool, targetedURL: URL?) -> Bool {
        guard isContainer else {
            return false
        }
        // 桌面背景可能没有 target；动作无需读写目标目录，不能因此丢失入口。
        guard let targetedURL else {
            return true
        }
        guard targetedURL.isFileURL, targetedURL.path.hasPrefix("/"),
              targetedURL.host == nil || targetedURL.host == "" || targetedURL.host == "localhost" else {
            return false
        }
        if let values = try? targetedURL.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) {
            if values.isDirectory == false || values.isPackage == true {
                return false
            }
        }
        // 目录元数据受权限或沙盒限制时仍可显示，因为切换的是用户 Finder 偏好。
        return true
    }
}
