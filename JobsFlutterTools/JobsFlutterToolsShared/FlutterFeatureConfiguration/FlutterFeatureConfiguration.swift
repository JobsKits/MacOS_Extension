//
//  FlutterFeatureConfiguration.swift
//  JobsFlutterToolsShared
//
//  Created by Jobs on 2026年10月24日，星期六.
//

import Foundation
import Darwin

/// 宿主与沙盒扩展共用当前用户的动作清单；每次展示及执行前重新读取。
enum FlutterFeatureConfiguration {
    static var leafActions: Set<FlutterToolsAction> {
        Set(FlutterToolsAction.allCases.filter { $0 != .package })
    }

    static func enabledFeatures(configurationURL: URL? = defaultConfigurationURL) -> Set<FlutterToolsAction> {
        guard let configurationURL else {
            return []
        }
        var info = stat()
        let result = configurationURL.path.withCString { lstat($0, &info) }
        if result != 0 {
            return errno == ENOENT ? leafActions : []
        }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_size <= 8192,
              let data = try? Data(contentsOf: configurationURL),
              data.count <= 8192,
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return []
        }
        let values = value.components(separatedBy: ",")
        var enabled: Set<FlutterToolsAction> = []
        for rawValue in values {
            guard let action = FlutterToolsAction(rawValue: rawValue), action != .package,
                  enabled.insert(action).inserted else {
                return []
            }
        }
        return enabled
    }

    static func permits(_ action: FlutterToolsAction, enabled: Set<FlutterToolsAction>) -> Bool {
        if action == .package {
            // 旧聚合 URL 仍可弹平台选择，只有全部平台启用时才允许进入。
            return Set(FlutterToolsAction.packaging).isSubset(of: enabled)
        }
        return enabled.contains(action)
    }

    private static var defaultConfigurationURL: URL? {
        var size = max(16_384, Int(sysconf(_SC_GETPW_R_SIZE_MAX)))
        while size <= 1_048_576 {
            var account = passwd()
            var result: UnsafeMutablePointer<passwd>?
            var buffer = [CChar](repeating: 0, count: size)
            let lookup = buffer.withUnsafeMutableBufferPointer { storage -> (Int32, String?) in
                let status = getpwuid_r(getuid(), &account, storage.baseAddress, storage.count, &result)
                return (status, result?.pointee.pw_dir.map { String(cString: $0) })
            }
            if lookup.0 == 0 {
                guard let home = lookup.1, home.hasPrefix("/") else {
                    return nil
                }
                return URL(fileURLWithPath: home, isDirectory: true)
                    .appendingPathComponent("Library/Application Support/JobsFinderExtensions/flutter-tools-features.conf")
            }
            guard lookup.0 == ERANGE else {
                return nil
            }
            size *= 2
        }
        return nil
    }
}
