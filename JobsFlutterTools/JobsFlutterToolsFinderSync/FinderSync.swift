//
//  FinderSync.swift
//  JobsFlutterToolsFinderSync
//
//  Created by Jobs on 2026年10月22日，星期四.
//

import AppKit
import FinderSync
import Darwin

final class FinderSync: FIFinderSync {
    private let validator = FlutterProjectValidator()

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer,
              let projectURL = candidateURL(for: menuKind),
              validator.isFlutterProject(at: projectURL) else {
            return nil
        }
        let enabled = FlutterFeatureConfiguration.enabledFeatures()
        guard !enabled.isEmpty else {
            return nil
        }
        let menu = NSMenu(title: "")
        let development = NSMenu(title: "Flutter开发相关辅助工具")
        for action in FlutterToolsAction.development {
            if action == .package {
                addGroup(title: action.title, actions: FlutterToolsAction.packaging, enabled: enabled, kind: menuKind, to: development)
            } else if enabled.contains(action) {
                development.addItem(makeItem(action, menuKind))
            }
        }
        addGroup(title: "Flutter项目体检", actions: FlutterToolsAction.doctors, enabled: enabled, kind: menuKind, to: development)
        addGroup(title: "Flutter项目修复", actions: FlutterToolsAction.repairs, enabled: enabled, kind: menuKind, to: development)
        addGroup(title: "Flutter清理维护工具", actions: FlutterToolsAction.cleaning, enabled: enabled, kind: menuKind, to: development)
        let parent = NSMenuItem(title: development.title, action: nil, keyEquivalent: "")
        parent.submenu = development
        menu.addItem(parent)
        return menu
    }

    private func addGroup(title: String, actions: [FlutterToolsAction], enabled: Set<FlutterToolsAction>, kind: FIMenuKind, to parent: NSMenu) {
        let actions = actions.filter { enabled.contains($0) }
        guard !actions.isEmpty else {
            return
        }
        let submenu = NSMenu(title: title)
        for action in actions {
            submenu.addItem(makeItem(action, kind))
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        parent.addItem(item)
    }

    private func makeItem(_ action: FlutterToolsAction, _ kind: FIMenuKind) -> NSMenuItem {
        let selected = kind == .contextualMenuForItems
        let selector: Selector
        switch action {
        case .cleanBuildArtifacts:
            selector = selected ? #selector(cleanBuildArtifactsSelected(_:)) : #selector(cleanBuildArtifactsContainer(_:))
        case .maintenance:
            selector = selected ? #selector(maintenanceSelected(_:)) : #selector(maintenanceContainer(_:))
        case .repairNamespace:
            selector = selected ? #selector(repairNamespaceSelected(_:)) : #selector(repairNamespaceContainer(_:))
        case .run:
            selector = selected ? #selector(runSelected(_:)) : #selector(runContainer(_:))
        case .pubGet:
            selector = selected ? #selector(pubGetSelected(_:)) : #selector(pubGetContainer(_:))
        case .extract:
            selector = selected ? #selector(extractSelected(_:)) : #selector(extractContainer(_:))
        case .sdkVersion:
            selector = selected ? #selector(sdkVersionSelected(_:)) : #selector(sdkVersionContainer(_:))
        case .sdkManage:
            selector = selected ? #selector(sdkManageSelected(_:)) : #selector(sdkManageContainer(_:))
        case .harmonySdkManage:
            selector = selected ? #selector(harmonySdkManageSelected(_:)) : #selector(harmonySdkManageContainer(_:))
        case .javaManage:
            selector = selected ? #selector(javaManageSelected(_:)) : #selector(javaManageContainer(_:))
        case .package:
            selector = selected ? #selector(packageSelected(_:)) : #selector(packageContainer(_:))
        case .packageIOS:
            selector = selected ? #selector(packageIOSSelected(_:)) : #selector(packageIOSContainer(_:))
        case .packageAndroid:
            selector = selected ? #selector(packageAndroidSelected(_:)) : #selector(packageAndroidContainer(_:))
        case .packageHarmony:
            selector = selected ? #selector(packageHarmonySelected(_:)) : #selector(packageHarmonyContainer(_:))
        case .codegen:
            selector = selected ? #selector(codegenSelected(_:)) : #selector(codegenContainer(_:))
        case .nativeDoctor:
            selector = selected ? #selector(nativeDoctorSelected(_:)) : #selector(nativeDoctorContainer(_:))
        case .harmonyDoctor:
            selector = selected ? #selector(harmonyDoctorSelected(_:)) : #selector(harmonyDoctorContainer(_:))
        case .repairAndroid:
            selector = selected ? #selector(repairAndroidSelected(_:)) : #selector(repairAndroidContainer(_:))
        case .repairImports:
            selector = selected ? #selector(repairImportsSelected(_:)) : #selector(repairImportsContainer(_:))
        case .repairPackageImports:
            selector = selected ? #selector(repairPackageImportsSelected(_:)) : #selector(repairPackageImportsContainer(_:))
        }
        let item = NSMenuItem(title: action.title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private func candidateURL(for menuKind: FIMenuKind) -> URL? {
        let controller = FIFinderSyncController.default()
        if menuKind == .contextualMenuForItems {
            guard let items = controller.selectedItemURLs(), items.count == 1 else {
                return nil
            }
            return items.first
        }
        guard let targetURL = controller.targetedURL(), targetURL.isFileURL,
              !FinderDesktopMenuPolicy.isDesktopContainer(targetURL) else {
            return nil
        }
        return targetURL
    }

    @objc private func cleanBuildArtifactsSelected(_ sender: NSMenuItem) {
        perform(.cleanBuildArtifacts, for: .contextualMenuForItems)
    }

    @objc private func cleanBuildArtifactsContainer(_ sender: NSMenuItem) {
        perform(.cleanBuildArtifacts, for: .contextualMenuForContainer)
    }

    @objc private func maintenanceSelected(_ sender: NSMenuItem) {
        perform(.maintenance, for: .contextualMenuForItems)
    }

    @objc private func maintenanceContainer(_ sender: NSMenuItem) {
        perform(.maintenance, for: .contextualMenuForContainer)
    }

    @objc private func repairNamespaceSelected(_ sender: NSMenuItem) {
        perform(.repairNamespace, for: .contextualMenuForItems)
    }

    @objc private func repairNamespaceContainer(_ sender: NSMenuItem) {
        perform(.repairNamespace, for: .contextualMenuForContainer)
    }

    @objc private func runSelected(_ sender: NSMenuItem) {
        perform(.run, for: .contextualMenuForItems)
    }

    @objc private func runContainer(_ sender: NSMenuItem) {
        perform(.run, for: .contextualMenuForContainer)
    }

    @objc private func pubGetSelected(_ sender: NSMenuItem) {
        perform(.pubGet, for: .contextualMenuForItems)
    }

    @objc private func pubGetContainer(_ sender: NSMenuItem) {
        perform(.pubGet, for: .contextualMenuForContainer)
    }

    @objc private func extractSelected(_ sender: NSMenuItem) {
        perform(.extract, for: .contextualMenuForItems)
    }

    @objc private func extractContainer(_ sender: NSMenuItem) {
        perform(.extract, for: .contextualMenuForContainer)
    }

    @objc private func sdkVersionSelected(_ sender: NSMenuItem) {
        perform(.sdkVersion, for: .contextualMenuForItems)
    }

    @objc private func sdkVersionContainer(_ sender: NSMenuItem) {
        perform(.sdkVersion, for: .contextualMenuForContainer)
    }

    @objc private func sdkManageSelected(_ sender: NSMenuItem) {
        perform(.sdkManage, for: .contextualMenuForItems)
    }

    @objc private func sdkManageContainer(_ sender: NSMenuItem) {
        perform(.sdkManage, for: .contextualMenuForContainer)
    }

    @objc private func harmonySdkManageSelected(_ sender: NSMenuItem) {
        perform(.harmonySdkManage, for: .contextualMenuForItems)
    }

    @objc private func harmonySdkManageContainer(_ sender: NSMenuItem) {
        perform(.harmonySdkManage, for: .contextualMenuForContainer)
    }

    @objc private func javaManageSelected(_ sender: NSMenuItem) {
        perform(.javaManage, for: .contextualMenuForItems)
    }

    @objc private func javaManageContainer(_ sender: NSMenuItem) {
        perform(.javaManage, for: .contextualMenuForContainer)
    }

    @objc private func packageSelected(_ sender: NSMenuItem) {
        perform(.package, for: .contextualMenuForItems)
    }

    @objc private func packageContainer(_ sender: NSMenuItem) {
        perform(.package, for: .contextualMenuForContainer)
    }

    @objc private func packageIOSSelected(_ sender: NSMenuItem) {
        perform(.packageIOS, for: .contextualMenuForItems)
    }

    @objc private func packageIOSContainer(_ sender: NSMenuItem) {
        perform(.packageIOS, for: .contextualMenuForContainer)
    }

    @objc private func packageAndroidSelected(_ sender: NSMenuItem) {
        perform(.packageAndroid, for: .contextualMenuForItems)
    }

    @objc private func packageAndroidContainer(_ sender: NSMenuItem) {
        perform(.packageAndroid, for: .contextualMenuForContainer)
    }

    @objc private func packageHarmonySelected(_ sender: NSMenuItem) {
        perform(.packageHarmony, for: .contextualMenuForItems)
    }

    @objc private func packageHarmonyContainer(_ sender: NSMenuItem) {
        perform(.packageHarmony, for: .contextualMenuForContainer)
    }

    @objc private func codegenSelected(_ sender: NSMenuItem) {
        perform(.codegen, for: .contextualMenuForItems)
    }

    @objc private func codegenContainer(_ sender: NSMenuItem) {
        perform(.codegen, for: .contextualMenuForContainer)
    }

    @objc private func nativeDoctorSelected(_ sender: NSMenuItem) {
        perform(.nativeDoctor, for: .contextualMenuForItems)
    }

    @objc private func nativeDoctorContainer(_ sender: NSMenuItem) {
        perform(.nativeDoctor, for: .contextualMenuForContainer)
    }

    @objc private func harmonyDoctorSelected(_ sender: NSMenuItem) {
        perform(.harmonyDoctor, for: .contextualMenuForItems)
    }

    @objc private func harmonyDoctorContainer(_ sender: NSMenuItem) {
        perform(.harmonyDoctor, for: .contextualMenuForContainer)
    }

    @objc private func repairAndroidSelected(_ sender: NSMenuItem) {
        perform(.repairAndroid, for: .contextualMenuForItems)
    }

    @objc private func repairAndroidContainer(_ sender: NSMenuItem) {
        perform(.repairAndroid, for: .contextualMenuForContainer)
    }

    @objc private func repairImportsSelected(_ sender: NSMenuItem) {
        perform(.repairImports, for: .contextualMenuForItems)
    }

    @objc private func repairImportsContainer(_ sender: NSMenuItem) {
        perform(.repairImports, for: .contextualMenuForContainer)
    }

    @objc private func repairPackageImportsSelected(_ sender: NSMenuItem) {
        perform(.repairPackageImports, for: .contextualMenuForItems)
    }

    @objc private func repairPackageImportsContainer(_ sender: NSMenuItem) {
        perform(.repairPackageImports, for: .contextualMenuForContainer)
    }

    private func perform(_ action: FlutterToolsAction, for menuKind: FIMenuKind) {
        // Finder 转发菜单动作时不依赖 representedObject，重新查询本次菜单上下文。
        guard FlutterFeatureConfiguration.permits(action, enabled: FlutterFeatureConfiguration.enabledFeatures()),
              let projectURL = candidateURL(for: menuKind),
              validator.isFlutterProject(at: projectURL) else {
            showFailure("当前菜单上下文已失效，或文件夹不再是可识别的 Flutter 项目，请关闭菜单后重新右键。")
            return
        }
        guard let requestURL = FlutterToolsRequest.url(for: projectURL, action: action) else {
            showFailure("无法创建 Flutter 开发辅助工具请求，请重新选择项目。")
            return
        }
        NSLog("JobsFlutterToolsFinderSync: 请求宿主处理 %@", projectURL.path)
        if !NSWorkspace.shared.open(requestURL) {
            showFailure("无法打开宿主，请先运行 JobsFlutterTools.app；仍失败时重新安装此扩展。")
        }
    }

    private func showFailure(_ message: String) {
        NSLog("JobsFlutterToolsFinderSync: %@", message)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Flutter 开发辅助工具未启动"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

// 独立工程各自携带同一策略；只屏蔽真实桌面容器，不影响选中的项目或同名目录。
private enum FinderDesktopMenuPolicy {
    static var desktopURLs: [URL] {
        var directories = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)
        // 沙盒中的 Foundation Home 可能重定向，使用用户目录服务识别真实桌面。
        if let home = userHomeDirectoryURL() {
            directories.append(home.appendingPathComponent("Desktop", isDirectory: true))
        }
        return directories
    }

    static func isDesktopContainer(_ url: URL, desktopURLs: [URL] = Self.desktopURLs) -> Bool {
        guard url.isFileURL else {
            return false
        }
        let candidatePath = url.standardizedFileURL.resolvingSymlinksInPath().path
        return desktopURLs.contains { desktopURL in
            desktopURL.isFileURL
                && desktopURL.standardizedFileURL.resolvingSymlinksInPath().path == candidatePath
        }
    }

    private static func userHomeDirectoryURL() -> URL? {
        var bufferSize = max(16_384, Int(sysconf(_SC_GETPW_R_SIZE_MAX)))
        while bufferSize <= 1_048_576 {
            var account = passwd()
            var result: UnsafeMutablePointer<passwd>?
            var buffer = [CChar](repeating: 0, count: bufferSize)
            let lookup = buffer.withUnsafeMutableBufferPointer { storage -> (status: Int32, home: String?) in
                let status = getpwuid_r(getuid(), &account, storage.baseAddress, storage.count, &result)
                guard status == 0, let home = result?.pointee.pw_dir else {
                    return (status, nil)
                }
                return (status, String(cString: home))
            }
            if lookup.status == 0 {
                guard let home = lookup.home, home.hasPrefix("/") else {
                    return nil
                }
                return URL(fileURLWithPath: home, isDirectory: true)
            }
            guard lookup.status == ERANGE else {
                return nil
            }
            bufferSize *= 2
        }
        return nil
    }

}
