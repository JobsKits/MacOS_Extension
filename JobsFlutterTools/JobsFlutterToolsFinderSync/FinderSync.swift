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
    private let diagnosticLock = NSLock()
    private let diagnosticURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("JobsFlutterToolsFinderMenu-\(getpid()).jsonl")

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
        writeDiagnostic(["event": "initialized", "observedRoot": "/"])
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else {
            recordMenuDiagnostic(menuKind, reason: "unsupported-kind")
            return nil
        }
        guard let projectURL = candidateURL(for: menuKind) else {
            recordMenuDiagnostic(menuKind, reason: "no-candidate")
            return nil
        }
        guard validator.isFlutterProject(at: projectURL) else {
            recordMenuDiagnostic(menuKind, candidate: projectURL, valid: false, reason: "non-flutter")
            return nil
        }
        let enabled = FlutterFeatureConfiguration.enabledFeatures()
        let configuredCount = enabled.count
        guard !enabled.isEmpty else {
            recordMenuDiagnostic(menuKind, candidate: projectURL, valid: true, enabled: configuredCount,
                                 available: 0, reason: "no-enabled-actions")
            return nil
        }
        let menu = NSMenu(title: "")
        let development = NSMenu(title: "🦋 Flutter开发相关辅助工具")
        for action in [FlutterToolsAction.projectSetup, .run] {
            if enabled.contains(action) {
                development.addItem(makeItem(action, menuKind))
            }
        }
        addGroup(title: "📥 拉取Flutter项目工程相关依赖",
                 actions: FlutterToolsAction.dependencyFetch,
                 enabled: enabled,
                 kind: menuKind,
                 to: development)
        addGroup(title: "🧩 提取Flutter项目工程依赖",
                 actions: FlutterToolsAction.dependencyExports,
                 enabled: enabled,
                 kind: menuKind,
                 to: development)
        addGroup(title: "📤 导入Flutter项目工程依赖",
                 actions: FlutterToolsAction.dependencyImports,
                 enabled: enabled,
                 kind: menuKind,
                 to: development)
        addGroup(title: "🔀 安装/切换Flutter运行环境",
                 actions: FlutterToolsAction.environments,
                 enabled: enabled,
                 kind: menuKind,
                 to: development)
        addGroup(title: "🧱 Flutter 资源与构建依赖",
                 actions: FlutterToolsAction.resources,
                 enabled: enabled,
                 kind: menuKind,
                 to: development)
        addGroup(title: FlutterToolsAction.package.title,
                 actions: FlutterToolsAction.packaging,
                 enabled: enabled,
                 kind: menuKind,
                 to: development)
        if enabled.contains(.codegen) {
            development.addItem(makeItem(.codegen, menuKind))
        }
        addGroup(title: "🏥 Flutter项目体检",
                 actions: FlutterToolsAction.doctors,
                 enabled: enabled,
                 kind: menuKind,
                 to: development)
        addGroup(title: "🔧 Flutter项目修复",
                 actions: FlutterToolsAction.repairs,
                 enabled: enabled,
                 kind: menuKind,
                 to: development)
        addGroup(title: "🧹 Flutter清理维护工具",
                 actions: FlutterToolsAction.cleaning,
                 enabled: enabled,
                 kind: menuKind,
                 to: development)
        let parent = NSMenuItem(title: development.title, action: nil, keyEquivalent: "")
        parent.submenu = development
        menu.addItem(parent)
        recordMenuDiagnostic(menuKind, candidate: projectURL, valid: true, enabled: configuredCount,
                             available: enabled.count, returned: leafCount(in: menu), reason: "returned")
        return menu
    }

    /// 现场只记录菜单判定和数量；每个进程最多保留 128 KiB，不读取或回显 SDK 配置。
    private func recordMenuDiagnostic(_ kind: FIMenuKind, candidate: URL? = nil, valid: Bool? = nil,
                                      enabled: Int = -1, available: Int = -1, returned: Int = 0, reason: String) {
        writeDiagnostic([
            "event": "menu", "kind": kind.rawValue,
            "candidate": candidate.map { String($0.path.prefix(4096)) } ?? "",
            "validator": valid.map { $0 as Any } ?? NSNull(),
            "enabledCount": enabled, "availableCount": available,
            "returnedLeafCount": returned, "reason": reason
        ])
    }

    private func leafCount(in menu: NSMenu) -> Int {
        menu.items.reduce(0) { count, item in
            count + (item.submenu.map { leafCount(in: $0) } ?? (item.action == nil ? 0 : 1))
        }
    }

    private func writeDiagnostic(_ fields: [String: Any]) {
        var record = fields
        record["time"] = Date().timeIntervalSince1970
        record["pid"] = getpid()
        guard var data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else {
            return
        }
        data.append(0x0A)
        diagnosticLock.lock()
        defer {
            diagnosticLock.unlock()
        }
        let descriptor = diagnosticURL.path.withCString {
            open($0, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            return
        }
        defer {
            close(descriptor)
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == getuid(), info.st_nlink == 1,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            return
        }
        if info.st_size + off_t(data.count) > 131_072 && ftruncate(descriptor, 0) != 0 {
            return
        }
        data.withUnsafeBytes { storage in
            guard let address = storage.baseAddress else {
                return
            }
            var offset = 0
            while offset < storage.count {
                let written = write(descriptor, address.advanced(by: offset), storage.count - offset)
                if written < 0 && errno == EINTR {
                    continue
                }
                guard written > 0 else {
                    return
                }
                offset += written
            }
        }
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
        case .projectSetup:
            selector = selected ? #selector(projectSetupSelected(_:)) : #selector(projectSetupContainer(_:))
        case .gradleDownload:
            selector = selected ? #selector(gradleDownloadSelected(_:)) : #selector(gradleDownloadContainer(_:))
        case .run:
            selector = selected ? #selector(runSelected(_:)) : #selector(runContainer(_:))
        case .pubGet:
            selector = selected ? #selector(pubGetSelected(_:)) : #selector(pubGetContainer(_:))
        case .androidDependencies:
            selector = selected ? #selector(androidDependenciesSelected(_:)) : #selector(androidDependenciesContainer(_:))
        case .podsDependencies:
            selector = selected ? #selector(podsDependenciesSelected(_:)) : #selector(podsDependenciesContainer(_:))
        case .spmDependencies:
            selector = selected ? #selector(spmDependenciesSelected(_:)) : #selector(spmDependenciesContainer(_:))
        case .ohosDependencies:
            selector = selected ? #selector(ohosDependenciesSelected(_:)) : #selector(ohosDependenciesContainer(_:))
        case .nativeDependencies:
            selector = selected ? #selector(nativeDependenciesSelected(_:)) : #selector(nativeDependenciesContainer(_:))
        case .flutterPrecache:
            selector = selected ? #selector(flutterPrecacheSelected(_:)) : #selector(flutterPrecacheContainer(_:))
        case .webDependencies:
            selector = selected ? #selector(webDependenciesSelected(_:)) : #selector(webDependenciesContainer(_:))
        case .exportPrivateDependencies:
            selector = selected ? #selector(exportPrivateDependenciesSelected(_:)) : #selector(exportPrivateDependenciesContainer(_:))
        case .importPrivateDependencies:
            selector = selected ? #selector(importPrivateDependenciesSelected(_:)) : #selector(importPrivateDependenciesContainer(_:))
        case .extract:
            selector = selected ? #selector(extractSelected(_:)) : #selector(extractContainer(_:))
        case .importDependencies:
            selector = selected ? #selector(importDependenciesSelected(_:)) : #selector(importDependenciesContainer(_:))
        case .exportGradleDependencies:
            selector = selected ? #selector(exportGradleDependenciesSelected(_:)) : #selector(exportGradleDependenciesContainer(_:))
        case .importGradleDependencies:
            selector = selected ? #selector(importGradleDependenciesSelected(_:)) : #selector(importGradleDependenciesContainer(_:))
        case .exportPodsDependencies:
            selector = selected ? #selector(exportPodsDependenciesSelected(_:)) : #selector(exportPodsDependenciesContainer(_:))
        case .importPodsDependencies:
            selector = selected ? #selector(importPodsDependenciesSelected(_:)) : #selector(importPodsDependenciesContainer(_:))
        case .exportSpmDependencies:
            selector = selected ? #selector(exportSpmDependenciesSelected(_:)) : #selector(exportSpmDependenciesContainer(_:))
        case .importSpmDependencies:
            selector = selected ? #selector(importSpmDependenciesSelected(_:)) : #selector(importSpmDependenciesContainer(_:))
        case .exportOhosDependencies:
            selector = selected ? #selector(exportOhosDependenciesSelected(_:)) : #selector(exportOhosDependenciesContainer(_:))
        case .importOhosDependencies:
            selector = selected ? #selector(importOhosDependenciesSelected(_:)) : #selector(importOhosDependenciesContainer(_:))
        case .exportNativeDependencies:
            selector = selected ? #selector(exportNativeDependenciesSelected(_:)) : #selector(exportNativeDependenciesContainer(_:))
        case .importNativeDependencies:
            selector = selected ? #selector(importNativeDependenciesSelected(_:)) : #selector(importNativeDependenciesContainer(_:))
        case .exportPrecacheDependencies:
            selector = selected ? #selector(exportPrecacheDependenciesSelected(_:)) : #selector(exportPrecacheDependenciesContainer(_:))
        case .importPrecacheDependencies:
            selector = selected ? #selector(importPrecacheDependenciesSelected(_:)) : #selector(importPrecacheDependenciesContainer(_:))
        case .exportWebDependencies:
            selector = selected ? #selector(exportWebDependenciesSelected(_:)) : #selector(exportWebDependenciesContainer(_:))
        case .importWebDependencies:
            selector = selected ? #selector(importWebDependenciesSelected(_:)) : #selector(importWebDependenciesContainer(_:))
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

    @objc private func projectSetupSelected(_ sender: NSMenuItem) {
        perform(.projectSetup, for: .contextualMenuForItems)
    }

    @objc private func projectSetupContainer(_ sender: NSMenuItem) {
        perform(.projectSetup, for: .contextualMenuForContainer)
    }

    @objc private func gradleDownloadSelected(_ sender: NSMenuItem) {
        perform(.gradleDownload, for: .contextualMenuForItems)
    }

    @objc private func gradleDownloadContainer(_ sender: NSMenuItem) {
        perform(.gradleDownload, for: .contextualMenuForContainer)
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

    @objc private func androidDependenciesSelected(_ sender: NSMenuItem) {
        perform(.androidDependencies, for: .contextualMenuForItems)
    }

    @objc private func androidDependenciesContainer(_ sender: NSMenuItem) {
        perform(.androidDependencies, for: .contextualMenuForContainer)
    }

    @objc private func podsDependenciesSelected(_ sender: NSMenuItem) {
        perform(.podsDependencies, for: .contextualMenuForItems)
    }

    @objc private func podsDependenciesContainer(_ sender: NSMenuItem) {
        perform(.podsDependencies, for: .contextualMenuForContainer)
    }

    @objc private func spmDependenciesSelected(_ sender: NSMenuItem) {
        perform(.spmDependencies, for: .contextualMenuForItems)
    }

    @objc private func spmDependenciesContainer(_ sender: NSMenuItem) {
        perform(.spmDependencies, for: .contextualMenuForContainer)
    }

    @objc private func ohosDependenciesSelected(_ sender: NSMenuItem) {
        perform(.ohosDependencies, for: .contextualMenuForItems)
    }

    @objc private func ohosDependenciesContainer(_ sender: NSMenuItem) {
        perform(.ohosDependencies, for: .contextualMenuForContainer)
    }

    @objc private func nativeDependenciesSelected(_ sender: NSMenuItem) {
        perform(.nativeDependencies, for: .contextualMenuForItems)
    }

    @objc private func nativeDependenciesContainer(_ sender: NSMenuItem) {
        perform(.nativeDependencies, for: .contextualMenuForContainer)
    }

    @objc private func flutterPrecacheSelected(_ sender: NSMenuItem) {
        perform(.flutterPrecache, for: .contextualMenuForItems)
    }

    @objc private func flutterPrecacheContainer(_ sender: NSMenuItem) {
        perform(.flutterPrecache, for: .contextualMenuForContainer)
    }

    @objc private func webDependenciesSelected(_ sender: NSMenuItem) {
        perform(.webDependencies, for: .contextualMenuForItems)
    }

    @objc private func webDependenciesContainer(_ sender: NSMenuItem) {
        perform(.webDependencies, for: .contextualMenuForContainer)
    }

    @objc private func exportPrivateDependenciesSelected(_ sender: NSMenuItem) {
        perform(.exportPrivateDependencies, for: .contextualMenuForItems)
    }

    @objc private func exportPrivateDependenciesContainer(_ sender: NSMenuItem) {
        perform(.exportPrivateDependencies, for: .contextualMenuForContainer)
    }

    @objc private func importPrivateDependenciesSelected(_ sender: NSMenuItem) {
        perform(.importPrivateDependencies, for: .contextualMenuForItems)
    }

    @objc private func importPrivateDependenciesContainer(_ sender: NSMenuItem) {
        perform(.importPrivateDependencies, for: .contextualMenuForContainer)
    }

    @objc private func extractSelected(_ sender: NSMenuItem) {
        perform(.extract, for: .contextualMenuForItems)
    }

    @objc private func extractContainer(_ sender: NSMenuItem) {
        perform(.extract, for: .contextualMenuForContainer)
    }

    @objc private func importDependenciesSelected(_ sender: NSMenuItem) {
        perform(.importDependencies, for: .contextualMenuForItems)
    }

    @objc private func importDependenciesContainer(_ sender: NSMenuItem) {
        perform(.importDependencies, for: .contextualMenuForContainer)
    }

    @objc private func exportGradleDependenciesSelected(_ sender: NSMenuItem) {
        perform(.exportGradleDependencies, for: .contextualMenuForItems)
    }

    @objc private func exportGradleDependenciesContainer(_ sender: NSMenuItem) {
        perform(.exportGradleDependencies, for: .contextualMenuForContainer)
    }

    @objc private func importGradleDependenciesSelected(_ sender: NSMenuItem) {
        perform(.importGradleDependencies, for: .contextualMenuForItems)
    }

    @objc private func importGradleDependenciesContainer(_ sender: NSMenuItem) {
        perform(.importGradleDependencies, for: .contextualMenuForContainer)
    }

    @objc private func exportPodsDependenciesSelected(_ sender: NSMenuItem) {
        perform(.exportPodsDependencies, for: .contextualMenuForItems)
    }

    @objc private func exportPodsDependenciesContainer(_ sender: NSMenuItem) {
        perform(.exportPodsDependencies, for: .contextualMenuForContainer)
    }

    @objc private func importPodsDependenciesSelected(_ sender: NSMenuItem) {
        perform(.importPodsDependencies, for: .contextualMenuForItems)
    }

    @objc private func importPodsDependenciesContainer(_ sender: NSMenuItem) {
        perform(.importPodsDependencies, for: .contextualMenuForContainer)
    }

    @objc private func exportSpmDependenciesSelected(_ sender: NSMenuItem) {
        perform(.exportSpmDependencies, for: .contextualMenuForItems)
    }

    @objc private func exportSpmDependenciesContainer(_ sender: NSMenuItem) {
        perform(.exportSpmDependencies, for: .contextualMenuForContainer)
    }

    @objc private func importSpmDependenciesSelected(_ sender: NSMenuItem) {
        perform(.importSpmDependencies, for: .contextualMenuForItems)
    }

    @objc private func importSpmDependenciesContainer(_ sender: NSMenuItem) {
        perform(.importSpmDependencies, for: .contextualMenuForContainer)
    }

    @objc private func exportOhosDependenciesSelected(_ sender: NSMenuItem) {
        perform(.exportOhosDependencies, for: .contextualMenuForItems)
    }

    @objc private func exportOhosDependenciesContainer(_ sender: NSMenuItem) {
        perform(.exportOhosDependencies, for: .contextualMenuForContainer)
    }

    @objc private func importOhosDependenciesSelected(_ sender: NSMenuItem) {
        perform(.importOhosDependencies, for: .contextualMenuForItems)
    }

    @objc private func importOhosDependenciesContainer(_ sender: NSMenuItem) {
        perform(.importOhosDependencies, for: .contextualMenuForContainer)
    }

    @objc private func exportNativeDependenciesSelected(_ sender: NSMenuItem) {
        perform(.exportNativeDependencies, for: .contextualMenuForItems)
    }

    @objc private func exportNativeDependenciesContainer(_ sender: NSMenuItem) {
        perform(.exportNativeDependencies, for: .contextualMenuForContainer)
    }

    @objc private func importNativeDependenciesSelected(_ sender: NSMenuItem) {
        perform(.importNativeDependencies, for: .contextualMenuForItems)
    }

    @objc private func importNativeDependenciesContainer(_ sender: NSMenuItem) {
        perform(.importNativeDependencies, for: .contextualMenuForContainer)
    }

    @objc private func exportPrecacheDependenciesSelected(_ sender: NSMenuItem) {
        perform(.exportPrecacheDependencies, for: .contextualMenuForItems)
    }

    @objc private func exportPrecacheDependenciesContainer(_ sender: NSMenuItem) {
        perform(.exportPrecacheDependencies, for: .contextualMenuForContainer)
    }

    @objc private func importPrecacheDependenciesSelected(_ sender: NSMenuItem) {
        perform(.importPrecacheDependencies, for: .contextualMenuForItems)
    }

    @objc private func importPrecacheDependenciesContainer(_ sender: NSMenuItem) {
        perform(.importPrecacheDependencies, for: .contextualMenuForContainer)
    }

    @objc private func exportWebDependenciesSelected(_ sender: NSMenuItem) {
        perform(.exportWebDependencies, for: .contextualMenuForItems)
    }

    @objc private func exportWebDependenciesContainer(_ sender: NSMenuItem) {
        perform(.exportWebDependencies, for: .contextualMenuForContainer)
    }

    @objc private func importWebDependenciesSelected(_ sender: NSMenuItem) {
        perform(.importWebDependencies, for: .contextualMenuForItems)
    }

    @objc private func importWebDependenciesContainer(_ sender: NSMenuItem) {
        perform(.importWebDependencies, for: .contextualMenuForContainer)
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
        guard action != .packageHarmony || validator.isHarmonyFlutterProject(at: projectURL) else {
            showFailure("鸿蒙打包需要当前 Flutter 工程包含普通 ohos 目录、ohos/build-profile.json5 和 ohos/oh-package.json5，请先完成鸿蒙适配。")
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
