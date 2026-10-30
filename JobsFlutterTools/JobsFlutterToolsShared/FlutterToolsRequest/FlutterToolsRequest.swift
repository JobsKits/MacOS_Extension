//
//  FlutterToolsRequest.swift
//  JobsFlutterToolsShared
//
//  Created by Jobs on 2026年10月22日，星期四.
//

import Foundation

enum FlutterToolsAction: String, CaseIterable {
    case projectSetup = "project-setup"
    case run
    case pubGet = "pub-get"
    case androidDependencies = "android-dependencies"
    case podsDependencies = "pods-dependencies"
    case spmDependencies = "spm-dependencies"
    case ohosDependencies = "ohos-dependencies"
    case nativeDependencies = "native-dependencies"
    case flutterPrecache = "flutter-precache"
    case webDependencies = "web-dependencies"
    case extract
    case exportPrivateDependencies = "export-private-dependencies"
    case importPrivateDependencies = "import-private-dependencies"
    case importDependencies = "import-dependencies"
    case exportGradleDependencies = "export-gradle-dependencies"
    case importGradleDependencies = "import-gradle-dependencies"
    case exportPodsDependencies = "export-pods-dependencies"
    case importPodsDependencies = "import-pods-dependencies"
    case exportSpmDependencies = "export-spm-dependencies"
    case importSpmDependencies = "import-spm-dependencies"
    case exportOhosDependencies = "export-ohos-dependencies"
    case importOhosDependencies = "import-ohos-dependencies"
    case exportNativeDependencies = "export-native-dependencies"
    case importNativeDependencies = "import-native-dependencies"
    case exportPrecacheDependencies = "export-precache-dependencies"
    case importPrecacheDependencies = "import-precache-dependencies"
    case exportWebDependencies = "export-web-dependencies"
    case importWebDependencies = "import-web-dependencies"
    case sdkVersion = "sdk-version"
    case sdkManage = "sdk-manage"
    case harmonySdkManage = "ohos-sdk-manage"
    case javaManage = "java-manage"
    case gradleDownload = "gradle-download"
    case package
    case codegen
    case packageIOS = "package-ios"
    case packageAndroid = "package-android"
    case packageHarmony = "package-ohos"
    case nativeDoctor = "native-doctor"
    case harmonyDoctor = "harmony-doctor"
    case cleanBuildArtifacts = "clean-build-artifacts"
    case maintenance
    case repairNamespace = "repair-namespace"
    case repairAndroid = "repair-android"
    case repairImports = "repair-imports"
    case repairPackageImports = "repair-package-imports"

    var title: String {
        switch self {
        case .projectSetup:
            return "🚀 一键配置 Flutter 项目"
        case .run:
            return "▶️ 从终端运行 Flutter 项目"
        case .pubGet:
            return "📥 拉取 Flutter Pub 依赖"
        case .androidDependencies:
            return "🤖 拉取 Android 原生依赖"
        case .podsDependencies:
            return "🥥 拉取 CocoaPods 依赖"
        case .spmDependencies:
            return "🧬 拉取 Swift Package 依赖"
        case .ohosDependencies:
            return "🕊️ 拉取 OpenHarmony 依赖"
        case .nativeDependencies:
            return "🧱 准备原生库与构建依赖（组合操作）"
        case .flutterPrecache:
            return "🗃️ 下载Flutter平台资源"
        case .webDependencies:
            return "🌐 拉取 Web 工程依赖"
        case .exportPrivateDependencies:
            return "🔐 提取Flutter项目工程私库依赖"
        case .importPrivateDependencies:
            return "📥 导入Flutter项目工程私库依赖"
        case .extract:
            return "🧩 提取 Flutter Pub 依赖"
        case .importDependencies:
            return "📤 导入 Flutter Pub 依赖"
        case .exportGradleDependencies:
            return "🧩 提取 Gradle 分发与依赖缓存"
        case .importGradleDependencies:
            return "📤 导入 Gradle 分发与依赖缓存"
        case .exportPodsDependencies:
            return "🧩 提取 CocoaPods 依赖"
        case .importPodsDependencies:
            return "📤 导入 CocoaPods 依赖"
        case .exportSpmDependencies:
            return "🧩 提取 Swift Package 依赖"
        case .importSpmDependencies:
            return "📤 导入 Swift Package 依赖"
        case .exportOhosDependencies:
            return "🧩 提取 OpenHarmony 依赖"
        case .importOhosDependencies:
            return "📤 导入 OpenHarmony 依赖"
        case .exportNativeDependencies:
            return "🧩 提取 原生构建缓存"
        case .importNativeDependencies:
            return "📤 导入 原生构建缓存"
        case .exportPrecacheDependencies:
            return "🧩 提取 Flutter 平台资源"
        case .importPrecacheDependencies:
            return "📤 导入 Flutter 平台资源"
        case .exportWebDependencies:
            return "🧩 提取 Web 依赖"
        case .importWebDependencies:
            return "📤 导入 Web 依赖"
        case .sdkVersion:
            return "🔎 查看当前Flutter项目工程的SDK版本"
        case .sdkManage:
            return "🔀 安装/切换Flutter SDK"
        case .harmonySdkManage:
            return "🕊️ 安装/切换Flutter@OpenHarmony SDK"
        case .javaManage:
            return "☕ 安装/切换Java SDK"
        case .gradleDownload:
            return "📚 下载Gradled分发与构建插件"
        case .package:
            return "📦 Flutter打包"
        case .packageIOS:
            return "🍏 iOS"
        case .packageAndroid:
            return "🤖 Android"
        case .packageHarmony:
            return "📦 打包鸿蒙（HAP + APP）"
        case .codegen:
            return "⚙️ Flutter自动化生产代码"
        case .nativeDoctor:
            return "🧑‍⚕️ 原生Flutter项目体检"
        case .harmonyDoctor:
            return "💓 OpenHarmony Flutter 环境体检"
        case .cleanBuildArtifacts:
            return "🗑️ 清理当前 Flutter 项目构建产物"
        case .maintenance:
            return "♻️ 依赖与缓存维护"
        case .repairNamespace:
            return "🏷️ 修复 Flutter 插件 namespace"
        case .repairAndroid:
            return "🩹 修复 Android SDK / platforms 缺失"
        case .repairImports:
            return "🈶 修复 Flutter 项目中文路径"
        case .repairPackageImports:
            return "🔤 修复 Dart 相对 import 为 package 引用"
        }
    }

    static let dependencyFetch: [Self] = [
        .pubGet, .androidDependencies, .podsDependencies,
        .spmDependencies, .ohosDependencies, .webDependencies
    ]
    static let dependencyExports: [Self] = [
        .extract, .exportPrivateDependencies, .exportGradleDependencies, .exportPodsDependencies,
        .exportSpmDependencies, .exportOhosDependencies, .exportNativeDependencies,
        .exportPrecacheDependencies, .exportWebDependencies
    ]
    static let dependencyImports: [Self] = [
        .importDependencies, .importPrivateDependencies, .importGradleDependencies, .importPodsDependencies,
        .importSpmDependencies, .importOhosDependencies, .importNativeDependencies,
        .importPrecacheDependencies, .importWebDependencies
    ]
    static let environments: [Self] = [.sdkManage, .harmonySdkManage, .javaManage]
    static let resources: [Self] = [.gradleDownload, .flutterPrecache, .nativeDependencies]
    static let dependencyArchives: [Self] = dependencyExports + dependencyImports
    static let dependencyPreparation: [Self] = [.androidDependencies, .podsDependencies, .spmDependencies, .ohosDependencies, .nativeDependencies, .flutterPrecache, .webDependencies]
    static let development: [Self] = [.projectSetup, .run, .codegen]
    static let packaging: [Self] = [.packageIOS, .packageAndroid, .packageHarmony]
    static let doctors: [Self] = [.sdkVersion, .nativeDoctor, .harmonyDoctor]
    static let repairs: [Self] = [.repairAndroid, .repairImports, .repairNamespace, .repairPackageImports]
    static let cleaning: [Self] = [.cleanBuildArtifacts, .maintenance]
}

enum FlutterToolsRequest {
    static let scheme = "jobsfluttertools"

    static func url(for projectURL: URL, action: FlutterToolsAction) -> URL? {
        guard projectURL.isFileURL else {
            return nil
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = action.rawValue
        components.queryItems = [URLQueryItem(name: "path", value: projectURL.standardizedFileURL.path)]
        return components.url
    }

    static func action(from requestURL: URL) -> FlutterToolsAction? {
        guard projectURL(from: requestURL) != nil, let host = requestURL.host else {
            return nil
        }
        return FlutterToolsAction(rawValue: host)
    }

    static func projectURL(from requestURL: URL) -> URL? {
        guard let c = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
              c.scheme?.lowercased() == scheme, let host = c.host, FlutterToolsAction(rawValue: host) != nil,
              c.user == nil, c.password == nil, c.port == nil, c.path.isEmpty, c.fragment == nil,
              let items = c.queryItems, items.count == 1, items[0].name == "path",
              let path = items[0].value, path.hasPrefix("/"), !path.utf8.contains(0) else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }
}
