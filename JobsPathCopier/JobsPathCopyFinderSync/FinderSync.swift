//
//  FinderSync.swift
//  JobsPathCopyFinderSync
//
//  Created by Jobs on 2026年6月28日，星期日.
//

import AppKit
import CoreFoundation
import FinderSync
import UserNotifications

final class FinderSync: FIFinderSync {
    private let clipboardWriter = PathClipboardWriter()
    private let containingAppBundleIdentifier = "com.jobs.JobsPathCopier"
    private let logURL: URL = {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let directoryURL = baseURL.appendingPathComponent("JobsPathCopyFinderSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("FinderSync.log")
    }()

    override init() {
        super.init()
        configureObservedDirectories()
        writeLog("FinderSync init pid=\(ProcessInfo.processInfo.processIdentifier), bundlePath=\(Bundle.main.bundlePath)")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let urls = candidateURLs()
        writeLog("menu kind=\(menuKind.rawValue), candidates=\(urls.map(\.path).joined(separator: " | "))")
        guard menuKind == .contextualMenuForItems, urls.count == 1 else { return nil }

        let menu = NSMenu(title: "")
        let copyItem = NSMenuItem(title: "复制绝对路径", action: #selector(copyAbsolutePath(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.isEnabled = true
        menu.addItem(copyItem)
        return menu
    }
}

private extension FinderSync {
    func configureObservedDirectories() {
        let directoryURLs: Set<URL> = [URL(fileURLWithPath: "/", isDirectory: true)]
        FIFinderSyncController.default().directoryURLs = directoryURLs
        writeLog("observed=\(directoryURLs.map(\.path).sorted().joined(separator: " | "))")
    }

    @objc func copyAbsolutePath(_ sender: Any?) {
        let urls = candidateURLs()
        var messages: [String] = []
        writeLog("action candidates=\(urls.map(\.path).joined(separator: " | "))")

        for url in urls {
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let path = try clipboardWriter.copyAbsolutePath(from: url)
                writeLog("copied \(path)")
                showSuccessPrompt(path: path)
                return
            } catch {
                writeLog("failed \(url.path): \(error.localizedDescription)")
                messages.append(error.localizedDescription)
            }
        }

        showFailureAlert(messages: messages)
    }

    func candidateURLs() -> [URL] {
        let controller = FIFinderSyncController.default()
        guard let selectedURLs = controller.selectedItemURLs(),
              selectedURLs.count == 1,
              let selectedURL = selectedURLs.first,
              selectedURL.isFileURL else { return [] };return [selectedURL.standardizedFileURL]
    }

    func showFailureAlert(messages: [String]) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "复制绝对路径失败"
        alert.informativeText = messages.isEmpty ? "请选择一个文件或文件夹后再试。" : messages.joined(separator: "\n")
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    func showSuccessPrompt(path: String) {
        let runningApps = runningContainingApps()
        writeLog("success prompt begin path=\(path), containingAppCount=\(runningApps.count), containingApps=\(runningAppDescription(runningApps))")
        showSuccessDialogByOsascript(path: path)
    }

    func runningContainingApps() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: containingAppBundleIdentifier)
    }

    func runningAppDescription(_ apps: [NSRunningApplication]) -> String {
        guard !apps.isEmpty else { return "[]" }
        let descriptions = apps.map { app in
            "pid=\(app.processIdentifier), localizedName=\(app.localizedName ?? ""), bundleURL=\(app.bundleURL?.path ?? ""), executableURL=\(app.executableURL?.path ?? "")"
        };return descriptions.joined(separator: " | ")
    }

    func showSuccessDialogByOsascript(path: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.runCommand(
                executablePath: "/usr/bin/osascript",
                arguments: [
                    "-l",
                    "JavaScript",
                    "-e",
                    self?.successHUDJavaScript() ?? "",
                    "复制绝对路径成功",
                    "已写入剪贴板",
                    "1.0"
                ]
            )
            self?.writeLog("osascript success HUD didSucceed=\(result?.didSucceed == true), status=\(result?.terminationStatus ?? -1), output=\(result?.output ?? "")")
            guard result?.didSucceed != true else { return }
            self?.showSuccessNoticeByCoreFoundation(path: path)
        }
    }

    func successHUDJavaScript() -> String {
        """
        function run(argv) {
            ObjC.import('Cocoa')

            const titleText = argv[0] || '复制绝对路径成功'
            const detailText = argv[1] || '已写入剪贴板'
            const duration = Math.max(0.8, Math.min(1.5, parseFloat(argv[2] || '1.0')))
            const maxAlpha = 0.98
            const fadeInDuration = 0.16
            const fadeOutDuration = 0.22
            const holdDuration = Math.max(0.2, duration - fadeInDuration - fadeOutDuration)
            const app = $.NSApplication.sharedApplication
            app.setActivationPolicy($.NSApplicationActivationPolicyAccessory)

            const width = 410
            const height = 124
            const iconSize = 88
            const leftPadding = 24
            const textLeft = 138
            const iconCenterX = leftPadding + iconSize / 2
            const iconCenterY = height / 2
            const screenFrame = $.NSScreen.mainScreen.visibleFrame
            const x = screenFrame.origin.x + (screenFrame.size.width - width) / 2
            const y = screenFrame.origin.y + (screenFrame.size.height - height) / 2
            const window = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(
                $.NSMakeRect(x, y, width, height),
                0,
                $.NSBackingStoreBuffered,
                false
            )
            window.setOpaque(false)
            window.setBackgroundColor($.NSColor.clearColor)
            window.setLevel($.NSStatusWindowLevel)
            window.setIgnoresMouseEvents(true)
            window.setHasShadow(true)
            window.setCollectionBehavior(
                $.NSWindowCollectionBehaviorCanJoinAllSpaces |
                $.NSWindowCollectionBehaviorTransient |
                $.NSWindowCollectionBehaviorFullScreenAuxiliary
            )

            const effect = $.NSVisualEffectView.alloc.initWithFrame($.NSMakeRect(0, 0, width, height))
            effect.setMaterial($.NSVisualEffectMaterialHUDWindow)
            effect.setBlendingMode($.NSVisualEffectBlendingModeBehindWindow)
            effect.setState($.NSVisualEffectStateActive)
            effect.setAppearance($.NSAppearance.appearanceNamed($.NSAppearanceNameVibrantDark))
            effect.setWantsLayer(true)
            effect.layer.setCornerRadius(12)
            effect.layer.setMasksToBounds(true)
            window.contentView.addSubview(effect)

            const darkBase = $.NSBox.alloc.initWithFrame($.NSMakeRect(0, 0, width, height))
            darkBase.setBoxType($.NSBoxCustom)
            darkBase.setBorderType($.NSNoBorder)
            darkBase.setCornerRadius(12)
            darkBase.setFillColor($.NSColor.colorWithCalibratedWhiteAlpha(0.04, 0.78))
            effect.addSubview(darkBase)

            function centeredRect(size) {
                return $.NSMakeRect(iconCenterX - size / 2, iconCenterY - size / 2, size, size)
            }

            function circleView(size, alpha) {
                const circle = $.NSBox.alloc.initWithFrame(centeredRect(size))
                circle.setBoxType($.NSBoxCustom)
                circle.setBorderType($.NSNoBorder)
                circle.setCornerRadius(size / 2)
                circle.setFillColor($.NSColor.systemGreenColor)
                circle.setAlphaValue(alpha)
                return circle
            }

            function iconGroupView(size) {
                const group = $.NSView.alloc.initWithFrame(centeredRect(size))
                group.setWantsLayer(true)
                group.layer.setAnchorPoint($.CGPointMake(0.5, 0.5))

                const circle = $.NSBox.alloc.initWithFrame($.NSMakeRect(0, 0, size, size))
                circle.setBoxType($.NSBoxCustom)
                circle.setBorderType($.NSNoBorder)
                circle.setCornerRadius(size / 2)
                circle.setFillColor($.NSColor.systemGreenColor)
                group.addSubview(circle)

                const checkSize = size * 0.72
                const checkView = $.NSImageView.alloc.initWithFrame($.NSMakeRect((size - checkSize) / 2, (size - checkSize) / 2, checkSize, checkSize))
                checkView.setImage($.NSImage.imageWithSystemSymbolNameAccessibilityDescription('checkmark', 'success'))
                checkView.setContentTintColor($.NSColor.whiteColor)
                checkView.setSymbolConfiguration($.NSImageSymbolConfiguration.configurationWithPointSizeWeight(size * 0.62, $.NSFontWeightBold))
                group.addSubview(checkView)
                return group
            }

            const pulseOuter = circleView(70, 0.24)
            const pulseInner = circleView(58, 0.32)
            effect.addSubview(pulseOuter)
            effect.addSubview(pulseInner)

            const burstDots = []
            for (let index = 0; index < 8; index++) {
                const dot = circleView(8, 0)
                burstDots.push(dot)
                effect.addSubview(dot)
            }

            const iconView = iconGroupView(iconSize)
            iconView.setAlphaValue(0)
            effect.addSubview(iconView)

            const title = $.NSTextField.labelWithString(titleText)
            title.setFrame($.NSMakeRect(textLeft, 62, 250, 34))
            title.setFont($.NSFont.systemFontOfSizeWeight(26, $.NSFontWeightBold))
            title.setTextColor($.NSColor.colorWithCalibratedWhiteAlpha(1, 0.98))
            effect.addSubview(title)

            const detail = $.NSTextField.labelWithString(detailText)
            detail.setFrame($.NSMakeRect(textLeft, 34, 250, 24))
            detail.setFont($.NSFont.systemFontOfSizeWeight(16, $.NSFontWeightMedium))
            detail.setTextColor($.NSColor.colorWithCalibratedWhiteAlpha(1, 0.9))
            effect.addSubview(detail)

            window.setAlphaValue(0)
            window.makeKeyAndOrderFront(null)
            app.activateIgnoringOtherApps(true)
            const animationStart = Date.now()

            function clamp(value, min, max) {
                return Math.max(min, Math.min(max, value))
            }

            function smoothStep(value) {
                return value * value * (3 - 2 * value)
            }

            function updateIconBurst() {
                const elapsed = (Date.now() - animationStart) / 1000
                const popProgress = clamp(elapsed / 0.34, 0, 1)
                const pulseProgress = clamp(elapsed / 0.46, 0, 1)
                const popEase = Math.sin(popProgress * Math.PI)
                const settleEase = smoothStep(clamp((elapsed - 0.16) / 0.28, 0, 1))
                const iconScale = popProgress < 1 ? 0.52 + 0.72 * popEase + 0.48 * popProgress : 1
                const settledScale = iconScale + (1 - iconScale) * settleEase
                const currentIconSize = iconSize * settledScale
                iconView.layer.setAffineTransform($.CGAffineTransformMakeScale(currentIconSize / iconSize, currentIconSize / iconSize))
                iconView.setAlphaValue(clamp(elapsed / 0.12, 0, 1))

                const outerSize = 66 + pulseProgress * 82
                const innerSize = 54 + pulseProgress * 48
                pulseOuter.setFrame(centeredRect(outerSize))
                pulseInner.setFrame(centeredRect(innerSize))
                pulseOuter.setCornerRadius(outerSize / 2)
                pulseInner.setCornerRadius(innerSize / 2)
                pulseOuter.setAlphaValue(Math.max(0, 0.34 * (1 - pulseProgress)))
                pulseInner.setAlphaValue(Math.max(0, 0.26 * (1 - pulseProgress)))

                for (let index = 0; index < burstDots.length; index++) {
                    const angle = (Math.PI * 2 * index) / burstDots.length
                    const dotProgress = clamp((elapsed - 0.05) / 0.34, 0, 1)
                    const distance = 30 + 34 * smoothStep(dotProgress)
                    const dotSize = 7 - 2 * dotProgress
                    const dotX = iconCenterX + Math.cos(angle) * distance - dotSize / 2
                    const dotY = iconCenterY + Math.sin(angle) * distance - dotSize / 2
                    burstDots[index].setFrame($.NSMakeRect(dotX, dotY, dotSize, dotSize))
                    burstDots[index].setCornerRadius(dotSize / 2)
                    burstDots[index].setAlphaValue(Math.max(0, 0.88 * (1 - dotProgress)))
                }
            }

            function pumpEvents(seconds) {
                const end = Date.now() + seconds * 1000
                while (Date.now() < end) {
                    updateIconBurst()
                    const event = app.nextEventMatchingMaskUntilDateInModeDequeue(
                        $.NSEventMaskAny,
                        $.NSDate.dateWithTimeIntervalSinceNow(0.016),
                        $.NSDefaultRunLoopMode,
                        true
                    )
                    if (event) {
                        app.sendEvent(event)
                    }
                }
            }

            function animateAlpha(fromAlpha, toAlpha, seconds) {
                const start = Date.now()
                const end = start + seconds * 1000
                while (Date.now() < end) {
                    const progress = Math.min(1, (Date.now() - start) / (seconds * 1000))
                    const eased = progress * progress * (3 - 2 * progress)
                    window.setAlphaValue(fromAlpha + (toAlpha - fromAlpha) * eased)
                    updateIconBurst()
                    pumpEvents(0.016)
                }
                window.setAlphaValue(toAlpha)
            }

            animateAlpha(0, maxAlpha, fadeInDuration)
            pumpEvents(holdDuration)
            animateAlpha(maxAlpha, 0, fadeOutDuration)
            const end = Date.now() + 80
            while (Date.now() < end) {
                const event = app.nextEventMatchingMaskUntilDateInModeDequeue(
                    $.NSEventMaskAny,
                    $.NSDate.dateWithTimeIntervalSinceNow(0.01),
                    $.NSDefaultRunLoopMode,
                    true
                )
                if (event) {
                    app.sendEvent(event)
                }
            }
        }
        """
    }

    func showSuccessNoticeByCoreFoundation(path: String) {
        let title = "复制绝对路径成功" as NSString
        let message = "已写入剪贴板：\n\(path)" as NSString
        let buttonTitle = "好" as NSString
        let status = CFUserNotificationDisplayNotice(
            2,
            CFOptionFlags(kCFUserNotificationNoteAlertLevel),
            nil,
            nil,
            nil,
            title,
            message,
            buttonTitle
        )
        writeLog("core foundation success notice status=\(status)")
        guard status != 0 else { return }
        deliverSuccessNotification(path: path)
    }

    func deliverSuccessNotification(path: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            self?.writeLog("notification settings authorizationStatus=\(settings.authorizationStatus.rawValue), alertSetting=\(settings.alertSetting.rawValue), soundSetting=\(settings.soundSetting.rawValue), notificationCenterSetting=\(settings.notificationCenterSetting.rawValue), lockScreenSetting=\(settings.lockScreenSetting.rawValue)")
        }
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] didAllow, error in
            self?.writeLog("notification authorization result didAllow=\(didAllow), error=\(error?.localizedDescription ?? "")")
            if let error {
                self?.writeLog("request notification authorization failed: \(error.localizedDescription)")
            }
            guard didAllow else {
                self?.writeLog("notification authorization denied")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "复制绝对路径成功"
            content.subtitle = "已写入剪贴板"
            content.body = path
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "JobsPathCopyFinderSync.copySuccess.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            self?.writeLog("deliver success notification request identifier=\(request.identifier)")
            center.add(request) { [weak self] error in
                if let error {
                    self?.writeLog("deliver success notification failed: \(error.localizedDescription)")
                    return
                }

                self?.writeLog("delivered success user notification")
            }
        }
    }

    func runCommand(executablePath: String, arguments: [String]) -> FinderCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return FinderCommandResult(didSucceed: false, terminationStatus: -1, output: error.localizedDescription)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        return FinderCommandResult(didSucceed: process.terminationStatus == 0, terminationStatus: process.terminationStatus, output: output)
    }

    func writeLog(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        NSLog("JobsPathCopyFinderSync %@", message)

        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            return
        }

        try? Data(line.utf8).write(to: logURL)
    }
}

private struct FinderCommandResult {
    let didSucceed: Bool
    let terminationStatus: Int32
    let output: String
}
