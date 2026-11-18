//
//  FinderSync.swift
//  JobsSendToFinderSync
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit
import FinderSync

final class FinderSync: FIFinderSync {

    private let lock = NSLock.makeSendToLock()
    private var volumes: [SendToVolume] = []
    private var scanned = false
    private var scanning = false
    private var scanError: String?
    private var lastScan = Date.distantPast
    private var observers: [NSObjectProtocol] = []
    private var selectionKey = ""
    private var sources: [SendToSource] = []
    private var selectionScanning = false
    private var nextTag = 0
    private var requests: [Int: SendToRequest] = [:]
    private var reloadSelections: [Int: [URL]] = [:]
    var extensionURL: URL = Bundle.main.bundleURL
    var openHost: (URL, URL, @escaping (NSRunningApplication?, Error?) -> Void) -> Void = { request, host, completion in
        NSWorkspace.shared.byOpenURLs([request], withApplicationAt: host,
                                       configuration: NSWorkspace.OpenConfiguration.make(),
                                       completionHandler: completion)
    }

    override init() {
        super.init()
        FIFinderSyncController.default().byDirectoryURLs([URL(fileURLWithPath: "/", isDirectory: true)])
        scanVolumes()
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.scanVolumes()
            })
        }
    }

    deinit {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let selected: [URL]
        switch menuKind {
        /// Files and folders use the actual selection of this right-click.
        case .contextualMenuForItems:
            selected = FIFinderSyncController.default().selectedItemURLs() ?? []
        /// A sidebar item represents its targeted real folder.
        case .contextualMenuForSidebar:
            selected = FIFinderSyncController.default().targetedURL().map { [$0] } ?? []
        /// Background and virtual locations have no copy source.
        default:
            return nil
        }
        guard !selected.isEmpty, selected.count <= 128,
              selected.allSatisfy({ $0.isFileURL }) else {
            return nil
        }
        prepareSelection(selected)
        if lock.withSendToLock({ Date().timeIntervalSince(lastScan) > 15 }) {
            scanVolumes()
        }
        let state = lock.withSendToLock {
            return (volumes, scanned, scanning, sources, selectionScanning, scanError)
        }
        let submenu = NSMenu.make()
        if state.4 || (!state.1 && state.2) {
            submenu.byAddItem(NSMenuItem.make(title: SendToLocalization.text("scanningMenu"), enabled: false))
        } else if state.3.isEmpty {
            submenu.byAddItem(NSMenuItem.make(title: SendToLocalization.text("invalidTarget"), enabled: false))
        } else if state.5 != nil {
            submenu.byAddItem(NSMenuItem.make(title: SendToLocalization.text("scanFailed"), enabled: false))
        } else if state.0.isEmpty {
            submenu.byAddItem(NSMenuItem.make(title: SendToLocalization.text("emptyTitle"), enabled: false))
        } else {
            for volume in state.0 where safeRelationship(sources: state.3, volume: volume) {
                guard let request = SendToRequest(sources: state.3, destination: volume), let tag = reserveTag() else {
                    continue
                }
                requests[tag] = request
                submenu.byAddItem(NSMenuItem.make(title: "💾 " + volume.name + " — " + volume.url.path,
                                                    action: #selector(sendToVolume(_:)), target: self)
                    .byTag(tag))
            }
        }
        if submenu.items.isEmpty {
            submenu.byAddItem(NSMenuItem.make(title: SendToLocalization.text("noTarget"), enabled: false))
        }
        if let tag = reserveTag() {
            reloadSelections[tag] = selected
            submenu.byAddItem(NSMenuItem.make(title: SendToLocalization.text("reloadMenu"),
                                                action: #selector(reloadDestinations(_:)), target: self)
                .byTag(tag))
        }
        return NSMenu.make()
            .byAddItem(NSMenuItem.make(title: SendToLocalization.text("menu")).bySubmenu(submenu))
    }

    // Menu callbacks stay on the principal object; only immutable tagged snapshots cross the boundary.
    @objc func sendToVolume(_ sender: NSMenuItem) {
        guard let request = requests.removeValue(forKey: sender.tag) else {
            showFailure(SendToLocalization.text("expired"))
            return
        }
        open(request)
    }

    @objc func reloadDestinations(_ sender: NSMenuItem) {
        guard let selected = reloadSelections.removeValue(forKey: sender.tag) else {
            showFailure(SendToLocalization.text("expired"))
            return
        }
        scanVolumes()
        // Even a slow mounted share is queried off Finder's menu callback.
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let sources = try SendToCore.snapshotSources(selected)
                let key = selected.map(\.absoluteString).joined(separator: "\0")
                self.lock.withSendToLock {
                    guard self.selectionKey == key else {
                        return
                    }
                    self.sources = sources
                    self.selectionScanning = false
                }
                guard let request = SendToRequest(sources: sources, destination: nil) else {
                    throw NSError(domain: "JobsSendTo", code: 1)
                }
                DispatchQueue.main.async {
                    self.open(request)
                }
            } catch {
                DispatchQueue.main.async {
                    self.showFailure(error.localizedDescription)
                }
            }
        }
    }

    private func reserveTag() -> Int? {
        guard nextTag < Int.max else {
            return nil
        }
        nextTag += 1
        if requests.count + reloadSelections.count > 256 {
            let oldest = (Array(requests.keys) + Array(reloadSelections.keys)).min()!
            requests.removeValue(forKey: oldest)
            reloadSelections.removeValue(forKey: oldest)
        }
        return nextTag
    }

    private func scanVolumes() {
        let shouldScan = lock.withSendToLock {
            guard !scanning else {
                return false
            }
            scanning = true
            return true
        }
        guard shouldScan else {
            return
        }
        DispatchQueue.global(qos: .utility).async {
            // Finder's read-only sandbox cannot test the host's write access; execution rechecks it.
            let outcome = Result { try SendToCore.volumes(requireWriteAccess: false) }
            self.lock.withSendToLock {
                switch outcome {
                /// Only completed scans replace the mounted-volume snapshot.
                case .success(let current):
                    self.volumes = current
                    self.scanError = nil
                /// Distinguish failed scans from a genuinely empty mounted-device list.
                case .failure(let error):
                    self.volumes = []
                    self.scanError = error.localizedDescription
                    NSLog("JobsSendTo volume scan failed: %@", error.localizedDescription)
                }
                self.scanned = true
                self.scanning = false
                self.lastScan = Date()
            }
        }
    }

    private func prepareSelection(_ urls: [URL]) {
        let key = urls.map(\.absoluteString).joined(separator: "\0")
        let changed = lock.withSendToLock {
            guard selectionKey != key else {
                return false
            }
            selectionKey = key
            sources = []
            selectionScanning = true
            return true
        }
        guard changed else {
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let current = (try? SendToCore.snapshotSources(urls)) ?? []
            self.lock.withSendToLock {
                guard self.selectionKey == key else {
                    return
                }
                self.sources = current
                self.selectionScanning = false
            }
        }
    }

    private func safeRelationship(sources: [SendToSource], volume: SendToVolume) -> Bool {
        return sources.allSatisfy {
            let source = $0.url.standardizedFileURL.path
            let destination = volume.url.standardizedFileURL.path
            return $0.url.deletingLastPathComponent().standardizedFileURL.path != destination &&
                destination != source && !destination.hasPrefix(source + "/")
        }
    }

    private func open(_ request: SendToRequest) {
        guard let url = request.url,
              let host = SendToHost.applicationURL(forExtension: extensionURL) else {
            showFailure(SendToLocalization.text("hostMissing"))
            return
        }
        openHost(url, host) { _, error in
            guard let error else {
                return
            }
            DispatchQueue.main.async {
                self.showFailure(error.localizedDescription)
            }
        }
    }

    private func showFailure(_ message: String) {
        NSAlert.make()
            .byMessageText(SendToLocalization.text("title"))
            .byInformativeText(message)
            .byAddButton(SendToLocalization.text("ok"))
            .runModal()
    }
}
