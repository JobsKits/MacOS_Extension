//
//  IOSProjectValidator.swift
//  JobsIOSToolsShared
//
//  Created by Jobs on 2026年10月23日，星期五.
//

import Darwin
import Foundation

struct IOSProjectValidator {
    private let manager = FileManager.default

    func supports(_ action: IOSToolsAction, at url: URL) -> Bool {
        return isIOSProject(at: url) && (action != .podBuildCheck || hasDirectPodspec(at: url))
    }

    func isIOSProject(at url: URL) -> Bool {
        guard url.isFileURL, !FinderDesktopMenuPolicy.isDesktopContainer(url),
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isPackage != true, values.isSymbolicLink != true,
              let children = try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey]) else {
            return false
        }
        return children.contains { child in
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if ["xcodeproj", "xcworkspace"].contains(child.pathExtension) {
                return values?.isDirectory == true
            }
            return values?.isRegularFile == true && (["Podfile", "Package.swift"].contains(child.lastPathComponent) || child.pathExtension == "podspec")
        }
    }

    func hasDirectPodspec(at url: URL) -> Bool {
        guard let children = try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return false
        }
        return children.contains { $0.pathExtension == "podspec" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }
}

enum FinderDesktopMenuPolicy {
    static func isDesktopContainer(_ url: URL) -> Bool {
        guard let home = realHomeDirectory else {
            return true
        }
        return url.standardizedFileURL.resolvingSymlinksInPath().path == home.appendingPathComponent("Desktop").standardizedFileURL.resolvingSymlinksInPath().path
    }

    static var realHomeDirectory: URL? {
        var size = max(16_384, Int(sysconf(_SC_GETPW_R_SIZE_MAX)))
        while size <= 1_048_576 {
            var account = passwd()
            var result: UnsafeMutablePointer<passwd>?
            var buffer = [CChar](repeating: 0, count: size)
            let lookup = buffer.withUnsafeMutableBufferPointer { storage -> (Int32, String?) in
                let status = getpwuid_r(getuid(), &account, storage.baseAddress, storage.count, &result)
                guard status == 0, let home = result?.pointee.pw_dir else {
                    return (status, nil)
                }
                return (status, String(cString: home))
            }
            if lookup.0 == 0 {
                guard let home = lookup.1, home.hasPrefix("/") else {
                    return nil
                }
                return URL(fileURLWithPath: home, isDirectory: true)
            }
            guard lookup.0 == ERANGE else {
                return nil
            }
            size *= 2
        }
        return nil
    }
}

enum IOSFeatureConfiguration {
    static var configurationFileURL: URL? {
        return FinderDesktopMenuPolicy.realHomeDirectory?.appendingPathComponent("Library/Application Support/JobsIOSTools/EnabledFeatures.txt")
    }

    static func enabledFeatures(bundle: Bundle = .main) -> Set<IOSToolsAction> {
        if let url = configurationFileURL, FileManager.default.fileExists(atPath: url.path) {
            // 已有配置不可读时保守关闭，不把权限异常解释为全部启用。
            return parse((try? String(contentsOf: url, encoding: .utf8)) ?? "")
        }
        if let url = bundle.resourceURL?.appendingPathComponent("EnabledFeatures.txt"),
           let value = try? String(contentsOf: url, encoding: .utf8) {
            return parse(value)
        }
        return Set(IOSToolsAction.allCases)
    }

    static func parse(_ value: String) -> Set<IOSToolsAction> {
        return Set(value.components(separatedBy: CharacterSet(charactersIn: ",\n\r")).compactMap {
            IOSToolsAction(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines))
        })
    }
}
