//
//  DesktopMenuConfiguration.swift
//  JobsDesktopToolsShared
//
//  Created by Jobs on 2026年10月26日，星期一.
//

import Foundation
import Darwin

enum DesktopMenuConfiguration {
    static var fileURL: URL? {
        return configurationURL(realHomePath: accountHomeDirectory())
    }

    static func configurationURL(realHomePath: String?) -> URL? {
        guard let realHomePath, realHomePath.hasPrefix("/"), !realHomePath.contains("\0") else {
            return nil
        }
        return URL(fileURLWithPath: realHomePath, isDirectory: true)
            .appendingPathComponent("Library/Application Support/JobsDesktopTools/EnabledFeatures.txt")
    }

    /// Foundation 的 Home 在 Finder 沙盒内会重定向，使用真实账户路径。
    static func accountHomeDirectory() -> String? {
        var bufferSize = max(16_384, Int(sysconf(_SC_GETPW_R_SIZE_MAX)))
        while bufferSize <= 1_048_576 {
            var account = passwd()
            var result: UnsafeMutablePointer<passwd>?
            var buffer = [CChar](repeating: 0, count: bufferSize)
            let lookup = buffer.withUnsafeMutableBufferPointer { storage -> (Int32, String?) in
                let code = getpwuid_r(getuid(), &account, storage.baseAddress, storage.count, &result)
                guard code == 0, let home = result?.pointee.pw_dir else {
                    return (code, nil)
                }
                return (code, String(cString: home))
            }
            if lookup.0 == 0 {
                return lookup.1
            }
            guard lookup.0 == ERANGE else {
                return nil
            }
            bufferSize *= 2
        }
        return nil
    }

    static func enabledFeatures(at url: URL? = fileURL) -> Set<DesktopMenuAction> {
        guard let url else {
            NSLog("JobsDesktopTools configuration unavailable: account Home lookup failed uid=%u", getuid())
            return []
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                NSLog("JobsDesktopTools configuration rejected: non-regular file path=%@", url.path)
                return []
            }
            let data = try Data(contentsOf: url)
            guard data.count <= 4096, let text = String(data: data, encoding: .utf8) else {
                NSLog("JobsDesktopTools configuration rejected: invalid UTF-8 or size path=%@ bytes=%lu", url.path, data.count)
                return []
            }
            let actions = parse(text)
            if actions.isEmpty && !text.isEmpty {
                NSLog("JobsDesktopTools configuration rejected: invalid feature identifiers path=%@", url.path)
            }
            return actions
        } catch {
            NSLog("JobsDesktopTools configuration read failed path=%@ error=%@", url.path, error.localizedDescription)
            return []
        }
    }

    static func parse(_ value: String) -> Set<DesktopMenuAction> {
        guard !value.isEmpty else {
            return []
        }
        let entries = value.split(separator: ",", omittingEmptySubsequences: false)
        let actions = entries.compactMap { DesktopMenuAction(rawValue: String($0)) }
        guard actions.count == entries.count, Set(actions).count == actions.count else {
            return []
        }
        return Set(actions)
    }
}
