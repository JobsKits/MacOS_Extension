//
//  FlutterToolsRequest.swift
//  JobsFlutterToolsShared
//
//  Created by Jobs on 2026年10月22日，星期四.
//

import Foundation

enum FlutterToolsAction: String, CaseIterable {
    case run
    case pubGet = "pub-get"
    case extract
    case sdkVersion = "sdk-version"
    case sdkManage = "sdk-manage"
    case harmonySdkManage = "ohos-sdk-manage"
    case javaManage = "java-manage"
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
        case .run:
            return "运行Flutter项目"
        case .pubGet:
            return "拉取Flutter第三方依赖"
        case .extract:
            return "提取Flutter第三方依赖"
        case .sdkVersion:
            return "查看当前Flutter项目的SDK版本"
        case .sdkManage:
            return "安装/切换Flutter SDK版本"
        case .harmonySdkManage:
            return "安装/切换 Flutter@OpenHarmony SDK"
        case .javaManage:
            return "安装/切换Java环境"
        case .package:
            return "Flutter打包"
        case .packageIOS:
            return "iOS"
        case .packageAndroid:
            return "Android"
        case .packageHarmony:
            return "鸿蒙"
        case .codegen:
            return "Flutter自动化生产代码"
        case .nativeDoctor:
            return "原生Flutter项目体检"
        case .harmonyDoctor:
            return "鸿蒙Flutter环境体检"
        case .cleanBuildArtifacts:
            return "清理当前项目构建产物"
        case .maintenance:
            return "依赖与缓存维护"
        case .repairNamespace:
            return "修复 Flutter 插件 namespace"
        case .repairAndroid:
            return "修复 Android SDK / platforms 缺失"
        case .repairImports:
            return "修复 Flutter 项目中文路径"
        case .repairPackageImports:
            return "修复 Dart 相对 import 为 package 引用"
        }
    }

    static let development: [Self] = [.run, .pubGet, .extract, .sdkVersion, .sdkManage, .harmonySdkManage, .javaManage, .package, .codegen]
    static let packaging: [Self] = [.packageIOS, .packageAndroid, .packageHarmony]
    static let doctors: [Self] = [.nativeDoctor, .harmonyDoctor]
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
