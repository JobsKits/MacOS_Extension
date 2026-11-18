//
//  DiskSpaceSummaryTests.swift
//  JobsDiskSpaceInfoTests
//
//  Created by Jobs on 2026年11月15日，星期日.
//

import AppKit
import Darwin

@main
enum DiskSpaceSummaryTests {

    static func main() {
        typealias Sample = DiskSpaceSummary.Sample
        let local = UInt32(MNT_LOCAL)
        let system = Sample(device: "/dev/disk3s1s1", mount: "/", fileSystem: "apfs",
                            flags: local | UInt32(MNT_RDONLY), capacity: 1000, free: 400)
        let data = Sample(device: "/dev/disk3s5", mount: "/System/Volumes/Data", fileSystem: "apfs",
                          flags: local | UInt32(MNT_DONTBROWSE), capacity: 1000, free: 400)
        let limited = Sample(device: "/dev/disk3s8", mount: "/Volumes/Quota", fileSystem: "apfs",
                             flags: local, capacity: 100, free: 25)
        let external = Sample(device: "/dev/disk4s1", mount: "/Volumes/External", fileSystem: "exfat",
                              flags: local, capacity: 2000, free: 1000)
        let alias = Sample(device: "/dev/disk4s1", mount: "/Volumes/Alias", fileSystem: "exfat",
                           flags: local, capacity: 2000, free: 1000)
        let network = Sample(device: "server:/share", mount: "/Volumes/Network", fileSystem: "nfs",
                             flags: 0, capacity: 9000, free: 9000)
        let image = Sample(device: "/dev/disk5s1", mount: "/Volumes/Installer", fileSystem: "apfs",
                           flags: local | UInt32(MNT_RDONLY), capacity: 9000, free: 9000)
        let hidden = Sample(device: "/dev/disk1s1", mount: "/System/Volumes/Preboot", fileSystem: "apfs",
                            flags: local | UInt32(MNT_DONTBROWSE), capacity: 9000, free: 9000)
        let total = DiskSpaceSummary.totals(from: [system, data, limited, external, alias, network, image, hidden])!
        precondition(total.capacity == 3000 && total.free == 1400, "容量池和挂载别名必须去重")
        precondition(DiskSpaceSummary.totals(from: []) == nil)
        precondition(DiskSpaceSummary.totals(from: [network, image, hidden]) == nil)
        let full = Sample(device: "/dev/disk4s1", mount: "/Volumes/Full", fileSystem: "exfat",
                          flags: local, capacity: 1000, free: 0)
        precondition(DiskSpaceSummary.totals(from: [full])!.percentage == 0)
        let invalid = Sample(device: "/dev/disk4s1", mount: "/Volumes/Invalid", fileSystem: "exfat",
                             flags: local, capacity: 1000, free: 2000)
        precondition(DiskSpaceSummary.totals(from: [invalid])!.free == 1000)
        let huge = Sample(device: "/dev/disk8s1", mount: "/Volumes/Huge", fileSystem: "exfat",
                          flags: local, capacity: UInt64.max, free: 0)
        precondition(DiskSpaceSummary.totals(from: [huge, external]) == nil)
        let writableImage = Sample(device: "/dev/disk21s1", mount: "/Volumes/Cache", fileSystem: "apfs",
                                   flags: local, capacity: 32_000, free: 24_000, isVirtualStorage: true)
        precondition(DiskSpaceSummary.totals(from: [system, data, writableImage])!.capacity == 1000,
                     "可写文件镜像不能再次增加整机容量")
        precondition(DiskSpaceSummary.virtualStorage(deviceProtocol: "Apple Fabric", location: "Internal") == false)
        precondition(DiskSpaceSummary.virtualStorage(deviceProtocol: "USB", location: "External") == false)
        precondition(DiskSpaceSummary.virtualStorage(deviceProtocol: "Virtual Interface", location: "Internal") == false,
                     "不能把真实后端的虚拟控制器等同文件镜像")
        precondition(DiskSpaceSummary.virtualStorage(deviceProtocol: "Virtual Interface", location: "File") == true)
        precondition(DiskSpaceSummary.virtualStorage(deviceProtocol: "Virtual Interface", location: "RAM") == true)
        precondition(DiskSpaceSummary.virtualStorage(deviceProtocol: "Virtual Interface", location: nil) == nil)
        precondition(DiskSpaceSummary.virtualStorage(deviceProtocol: "", location: nil) == nil)
        precondition(DiskSpaceSummary.virtualStorage(deviceProtocol: "Unknown", location: "Internal") == nil)
        let oldRoot = Sample(device: system.device, mount: "/", fileSystem: "apfs", flags: system.flags,
                             capacity: 1000, free: 900)
        for samples in [[oldRoot, data], [data, oldRoot]] {
            precondition(DiskSpaceSummary.totals(from: samples)!.free == 400,
                         "Data与根卷不能取最大旧余量")
        }
        var enumerations = 0
        var refreshes = 0
        func snapshot(_ free: UInt64?) -> DiskSpaceSummary.Totals? {
            return DiskSpaceSummary.readSnapshot(mounted: {
                enumerations += 1
                return [data]
            }, refresh: { candidate in
                refreshes += 1
                guard let free else { return nil }
                return Sample(device: candidate.device, mount: candidate.mount, fileSystem: candidate.fileSystem,
                              flags: candidate.flags, capacity: candidate.capacity, free: free)
            }, volumeCapacity: { candidate in
                return free.map { (Int64(candidate.capacity), Int64($0)) }
            })
        }
        precondition(snapshot(350)?.free == 350)
        precondition(snapshot(120)?.free == 120)
        precondition(snapshot(nil) == nil, "读取失败不能回退第一次或上次成功值")
        precondition(snapshot(0)?.free == 0)
        precondition(enumerations == 4 && refreshes == 4)
        precondition(DiskSpaceSummary.readSnapshot(mounted: { [data] }, refresh: { _ in external },
                                                  volumeCapacity: { _ in (2000, 1000) }) == nil,
                     "挂载身份变化不能展示混合快照")
        var availableQueries = 0
        func systemSnapshot(_ available: Int64?) -> DiskSpaceSummary.Totals? {
            return DiskSpaceSummary.readSnapshot(mounted: { [oldRoot, data, writableImage] }, refresh: { $0 },
                                                  volumeCapacity: { sample in
                availableQueries += 1
                precondition(!sample.isVirtualStorage, "磁盘镜像不能触发可用空间查询")
                return (sample.mount == "/" ? 950 : available).map { (1000, $0) }
            })
        }
        precondition(systemSnapshot(492)?.free == 492, "可用空间必须包含系统可清除部分，且优先Data完整样本")
        precondition(systemSnapshot(450)?.free == 450, "系统可用空间必须逐次重新读取")
        precondition(systemSnapshot(nil) == nil, "接口缺值不能回退原始空闲或旧可用量")
        precondition(systemSnapshot(-1) == nil, "负数不可解释为巨大的无符号可用量")
        precondition(systemSnapshot(0)?.free == 0, "真实零可用量仍是有效读数")
        precondition(systemSnapshot(2000)?.free == 1000, "可用量不得超过当前容量")
        precondition(availableQueries == 12)
        precondition(DiskSpaceSummary.readSnapshot(mounted: { [data] }, refresh: { $0 },
                                                  volumeCapacity: { _ in (2000, 1500) })?.capacity == 2000,
                     "总量和可用量必须采用同一次系统查询的完整结果")
        for total in [Int64(0), -1] {
            precondition(DiskSpaceSummary.readSnapshot(mounted: { [data] }, refresh: { $0 },
                                                      volumeCapacity: { _ in (total, 100) }) == nil)
        }
        let value = DiskSpaceSummary.Totals(capacity: 1_000_000_000_000, free: 250_000_000_000)
        let title = DiskSpaceSummary.menuTitle(totals: value, language: "zh-Hans")
        precondition(title == "💽 磁盘剩余：250.00 GB / 1.00 TB（25.00%）")
        let languages = ["zh-Hans", "zh-Hant", "bo", "en", "ja", "fr", "es", "de", "ru", "ko"]
        for language in languages {
            precondition(DiskSpaceSummary.menuTitle(totals: value, language: language).contains("25.00%"))
            precondition(!DiskSpaceSummary.menuTitle(totals: nil, language: language).contains("%"))
        }
        precondition(DiskSpaceSummary.menuTitle(totals: value, language: "zh-TW").contains("磁碟剩餘"))
        precondition(DiskSpaceSummary.menuTitle(totals: .init(capacity: 3, free: 1), language: "en").contains("33.33%"))
        let target = NSObject()
        let action = NSSelectorFromString("cleanup:")
        let menu = DiskSpaceSummary.makeMenu(action: action, target: target)
        precondition(!menu.autoenablesItems && menu.items.count == 1)
        let item = menu.items[0]
        precondition(item.isEnabled && item.action == action && item.target === target && item.keyEquivalent.isEmpty)
        var queries = 0
        for remaining in [UInt64(300), 100, 0] {
            let freshMenu = DiskSpaceSummary.makeMenu(action: action, target: target, read: {
                queries += 1
                return .init(capacity: 1000, free: remaining)
            })
            precondition(freshMenu.items[0].title == DiskSpaceSummary.menuTitle(
                totals: .init(capacity: 1000, free: remaining)))
        }
        let failedMenu = DiskSpaceSummary.makeMenu(action: action, target: target, read: {
            queries += 1
            return nil
        })
        precondition(queries == 4 && !failedMenu.items[0].title.contains("%") && failedMenu.items[0].isEnabled)
        guard let live = DiskSpaceSummary.readTotals() else {
            fatalError("本机磁盘读取失败")
        }
        precondition(live.capacity > 0 && live.free <= live.capacity)
        print("PASS: 系统可用空间完整样本／异常与零值、汇总去重、镜像排除、Data优先、逐次读取／失败恢复、十语言菜单")
        print("LIVE: " + DiskSpaceSummary.menuTitle(totals: live, language: "zh-Hans"))
        print("BYTES: free=\(live.free) capacity=\(live.capacity)")
    }
}
