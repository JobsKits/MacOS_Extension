//
//  DiskSpaceSummary.swift
//  JobsDiskSpaceInfoShared
//
//  Created by Jobs on 2026年11月15日，星期日.
//

import AppKit
import Darwin
import DiskArbitration
import IOKit
import IOKit.storage

enum DiskSpaceSummary {

    struct Sample {
        let device: String
        let mount: String
        let fileSystem: String
        let flags: UInt32
        var capacity: UInt64
        var free: UInt64
        var isVirtualStorage = false

        var includesStorage: Bool {
            let systemVolume = mount == "/" || mount == "/System/Volumes/Data"
            return !isVirtualStorage && flags & UInt32(MNT_LOCAL) != 0
                && device.range(of: #"^/dev/disk[0-9]+(?:s[0-9]+)*$"#, options: .regularExpression) != nil
                && capacity > 0
                && (systemVolume || flags & UInt32(MNT_RDONLY | MNT_DONTBROWSE) == 0)
        }

        var storageKey: String {
            // APFS 的系统、数据卷及启动快照共享容器，不能累加同一份空间。
            if fileSystem == "apfs",
               let range = device.range(of: #"^/dev/disk[0-9]+"#, options: .regularExpression) {
                return "apfs:" + device[range]
            }
            return device
        }
    }

    struct Totals {
        let capacity: UInt64
        let free: UInt64

        var percentage: Double {
            guard capacity > 0 else {
                return 0
            }
            return Double(free) / Double(capacity) * 100
        }
    }

    static func totals(from samples: [Sample]) -> Totals? {
        var pools: [String: Sample] = [:]
        for sample in samples where sample.includesStorage {
            if let previous = pools[sample.storageKey] {
                // 同一容量池只采用一个完整样本，不能把旧根卷较大的余量拼给新 Data 卷。
                if sample.capacity > previous.capacity ||
                    (sample.capacity == previous.capacity && sample.mount == "/System/Volumes/Data") {
                    pools[sample.storageKey] = sample
                }
            } else {
                pools[sample.storageKey] = sample
            }
        }
        guard !pools.isEmpty else {
            return nil
        }
        var capacity: UInt64 = 0
        var free: UInt64 = 0
        for pool in pools.values {
            let nextCapacity = capacity.addingReportingOverflow(pool.capacity)
            let nextFree = free.addingReportingOverflow(min(pool.free, pool.capacity))
            guard !nextCapacity.overflow, !nextFree.overflow else {
                return nil
            }
            capacity = nextCapacity.partialValue
            free = nextFree.partialValue
        }
        return Totals(capacity: capacity, free: free)
    }

    static func readTotals() -> Totals? {
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            return nil
        }
        return readSnapshot(mounted: mountedSamples, refresh: { candidate in
            guard let virtual = virtualStorage(for: candidate, session: session) else {
                return nil
            }
            if virtual {
                var excluded = candidate
                excluded.isVirtualStorage = true
                return excluded
            }
            var info = statfs()
            guard candidate.mount.withCString({ statfs($0, &info) }) == 0 else {
                return nil
            }
            return sample(from: info)
        }, volumeCapacity: { candidate in
            // 系统“可用”包含可清除缓存，原始 f_bavail 会少算这一部分。
            let url = URL(fileURLWithPath: candidate.mount, isDirectory: true)
            guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                                 .volumeAvailableCapacityForImportantUsageKey]),
                  let total = values.volumeTotalCapacity,
                  let available = values.volumeAvailableCapacityForImportantUsage else {
                return nil
            }
            return (Int64(total), available)
        })
    }

    static func readSnapshot(mounted: () -> [Sample]?, refresh: (Sample) -> Sample?,
                             volumeCapacity: (Sample) -> (total: Int64, available: Int64)?) -> Totals? {
        guard let candidates = mounted() else {
            return nil
        }
        var samples: [Sample] = []
        for candidate in candidates where candidate.includesStorage {
            guard var fresh = refresh(candidate),
                  fresh.device == candidate.device,
                  fresh.mount == candidate.mount,
                  fresh.fileSystem == candidate.fileSystem else {
                return nil
            }
            if fresh.isVirtualStorage {
                continue
            }
            guard fresh.includesStorage,
                  let capacity = volumeCapacity(fresh), capacity.total > 0, capacity.available >= 0 else {
                return nil
            }
            fresh.capacity = UInt64(capacity.total)
            fresh.free = UInt64(capacity.available)
            samples.append(fresh)
        }
        return totals(from: samples)
    }

    static func virtualStorage(deviceProtocol: String, location: String?) -> Bool? {
        guard !deviceProtocol.isEmpty, deviceProtocol.caseInsensitiveCompare("Unknown") != .orderedSame else {
            return nil
        }
        guard deviceProtocol == kIOPropertyPhysicalInterconnectTypeVirtual else {
            return false
        }
        guard let location else {
            return nil
        }
        return location == kIOPropertyInterconnectFileKey || location == kIOPropertyInterconnectRAMKey
    }

    private static func virtualStorage(for candidate: Sample, session: DASession) -> Bool? {
        guard let disk = candidate.device.withCString({ DADiskCreateFromBSDName(kCFAllocatorDefault, session, $0) }),
              let description = DADiskCopyDescription(disk) as? [String: Any],
              let deviceProtocol = description[kDADiskDescriptionDeviceProtocolKey as String] as? String else {
            return nil
        }
        if deviceProtocol != kIOPropertyPhysicalInterconnectTypeVirtual {
            return virtualStorage(deviceProtocol: deviceProtocol, location: nil)
        }
        let media = DADiskCopyIOMedia(disk)
        guard media != 0 else {
            return nil
        }
        defer { IOObjectRelease(media) }
        let properties = IORegistryEntrySearchCFProperty(
            media, kIOServicePlane, kIOPropertyProtocolCharacteristicsKey as CFString,
            kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        ) as? [String: Any]
        return virtualStorage(deviceProtocol: deviceProtocol,
                              location: properties?[kIOPropertyPhysicalInterconnectLocationKey] as? String)
    }

    private static func mountedSamples() -> [Sample]? {
        // 先读挂载快照，只对本地磁盘刷新统计，避免等待网络文件系统。
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else {
            return nil
        }
        var mounts: [statfs] = .init(repeating: statfs(), count: Int(count) + 8)
        let actualCount = mounts.withUnsafeMutableBufferPointer { buffer in
            return getfsstat(buffer.baseAddress,
                             Int32(buffer.count * MemoryLayout<statfs>.stride),
                             MNT_NOWAIT)
        }
        guard actualCount > 0, actualCount < mounts.count else {
            return nil
        }
        return mounts.prefix(Int(actualCount)).map { sample(from: $0) }
    }

    private static func sample(from value: statfs) -> Sample {
        var info = value
        let device = withUnsafeBytes(of: &info.f_mntfromname) { bytes in
            return String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        let mount = withUnsafeBytes(of: &info.f_mntonname) { bytes in
            return String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        let fileSystem = withUnsafeBytes(of: &info.f_fstypename) { bytes in
            return String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        let capacity = info.f_blocks.multipliedReportingOverflow(by: UInt64(info.f_bsize))
        let free = info.f_bavail.multipliedReportingOverflow(by: UInt64(info.f_bsize))
        return Sample(device: device,
                      mount: mount,
                      fileSystem: fileSystem,
                      flags: info.f_flags,
                      capacity: capacity.overflow ? 0 : capacity.partialValue,
                      free: free.overflow ? 0 : free.partialValue)
    }

    static func menuTitle(totals: Totals? = readTotals(),
                          language: String = Locale.preferredLanguages.first ?? "en") -> String {
        let text = labels(language: language)
        guard let totals, totals.capacity > 0 else {
            return "💽 " + text.unavailable
        }
        let percent = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), totals.percentage)
        return "💽 \(text.remaining)：\(formatBytes(totals.free)) / \(formatBytes(totals.capacity))（\(percent)%）"
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB", "EB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        return String(format: "%.2f %@", locale: Locale(identifier: "en_US_POSIX"), value, units[index])
    }

    private static func labels(language: String) -> (remaining: String, unavailable: String) {
        let code = language.lowercased().replacingOccurrences(of: "_", with: "-")
        if code.hasPrefix("zh") {
            let traditional = code.contains("hant") || code.hasSuffix("-tw") || code.hasSuffix("-hk") || code.hasSuffix("-mo")
            return traditional ? ("磁碟剩餘", "磁碟空間無法讀取") : ("磁盘剩余", "磁盘空间无法读取")
        }
        switch code.split(separator: "-").first {
        case "bo":
            return ("ཌིས་ཀིའི་ལྷག་མ", "ཌིས་ཀིའི་བར་སྟོང་ཀློག་མི་ཐུབ།")
        case "ja":
            return ("ディスク空き容量", "ディスク容量を取得できません")
        case "fr":
            return ("Espace disque libre", "Espace disque indisponible")
        case "es":
            return ("Espacio libre en disco", "Espacio en disco no disponible")
        case "de":
            return ("Freier Speicherplatz", "Speicherplatz nicht verfügbar")
        case "ru":
            return ("Свободно на дисках", "Данные о дисках недоступны")
        case "ko":
            return ("디스크 여유 공간", "디스크 공간을 확인할 수 없습니다")
        default:
            return ("Disk space remaining", "Disk space unavailable")
        }
    }

    static func makeMenu(action: Selector?, target: AnyObject?,
                         read: () -> Totals? = { readTotals() }) -> NSMenu {
        return NSMenu.makeDiskSpaceMenu(title: menuTitle(totals: read()), action: action, target: target)
    }
}

private extension NSMenu {

    static func makeDiskSpaceMenu(title: String, action: Selector?, target: AnyObject?) -> NSMenu {
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem.makeDiskSpaceItem(title: title, action: action, target: target))
        return menu
    }
}

private extension NSMenuItem {

    static func makeDiskSpaceItem(title: String, action: Selector?, target: AnyObject?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.isEnabled = true
        item.target = target
        return item
    }
}
