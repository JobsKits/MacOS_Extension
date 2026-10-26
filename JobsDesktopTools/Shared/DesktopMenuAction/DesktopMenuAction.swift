//
//  DesktopMenuAction.swift
//  JobsDesktopToolsShared
//
//  Created by Jobs on 2026年10月26日，星期一.
//

import Foundation

/// 声明顺序就是桌面顺序；过滤未启用的叶子不会重新排列剩余项。
enum DesktopMenuAction: String, CaseIterable {
    case createIOS = "ios-simulator-create"
    case createAndroid = "android-simulator-create"
    case createHarmony = "harmony-simulator-create"
    case repairAndroid = "android-simulator-repair"
    case repairHarmony = "harmony-simulator-repair"
    case hiddenFiles = "hidden-files-toggle"

    var title: String {
        switch self {
        /// 使用 iOS 模拟器新建动作。
        case .createIOS:
            return "🍎 新建 iOS 模拟器"
        /// 使用 Android 模拟器新建动作。
        case .createAndroid:
            return "📱 新建 Android 模拟器"
        /// 使用 Harmony 模拟器新建动作。
        case .createHarmony:
            return "🌈 新建 Harmony 模拟器"
        /// 检测和修复现有 Android 模拟器。
        case .repairAndroid:
            return "🩺 Android 模拟器检测与修复"
        /// 检测和修复现有 Harmony 模拟器。
        case .repairHarmony:
            return "🧰 Harmony 模拟器检测与修复"
        /// 显示或隐藏当前用户的隐藏文件。
        case .hiddenFiles:
            return "👁️ 显示文件"
        }
    }

    static func visible(enabled: Set<DesktopMenuAction>, isDesktop: Bool, allowsHiddenFiles: Bool) -> [DesktopMenuAction] {
        return allCases.filter { action in
            return enabled.contains(action) && (action == .hiddenFiles ? allowsHiddenFiles : isDesktop)
        }
    }
}
