//
//  DesktopActionExecutor.swift
//  JobsDesktopTools
//
//  Created by Jobs on 2026年10月26日，星期一.
//

import Foundation

/// 聚合宿主使用自己的脚本资源，不需要旧功能宿主或原工程目录。
struct DesktopActionExecutor {
    func perform(_ request: DesktopMenuRequest) throws {
        switch request.action {
        /// 使用 iOS 模拟器新建动作。
        case .createIOS:
            try IOSSimulatorTerminalLauncher().launch()
        /// 使用 Android 模拟器新建动作。
        case .createAndroid:
            try AndroidSimulatorTerminalLauncher().launch()
        /// 使用 Harmony 模拟器新建动作。
        case .createHarmony:
            try HarmonySimulatorTerminalLauncher().launch()
        /// 检测和修复现有 Android 模拟器。
        case .repairAndroid:
            try AndroidSimulatorRepairTerminalLauncher().launch()
        /// 检测和修复现有 Harmony 模拟器。
        case .repairHarmony:
            try HarmonySimulatorRepairTerminalLauncher().launch()
        /// 显示或隐藏当前用户的隐藏文件。
        case .hiddenFiles:
            guard let target = request.showsHiddenFiles else {
                return
            }
            let preferences = FinderHiddenFilesPreferences()
            let current = try HiddenFilesToggleService.booleanValue(preferences.read())
            if current != target {
                try preferences.write(target)
                do {
                    try FinderRefresher().refresh()
                } catch {
                    let state = target ? "显示" : "隐藏"
                    throw NSError.make(domain: "JobsDesktopTools", message: "Finder 偏好已写入为‘\(state)隐藏文件’，但刷新失败：\(error.localizedDescription)\n请手动重新启动 Finder。")
                }
            }
        }
    }
}
