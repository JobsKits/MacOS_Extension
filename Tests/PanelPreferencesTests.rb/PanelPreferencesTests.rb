# frozen_string_literal: true
# Jobs：在独立 UserDefaults suite 和原生 AppKit 窗口中验证主题、语言及活动状态保留。
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class PanelPreferencesTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def test_preferences_translation_theme_and_existing_control_state
    source = File.read(File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift'))
    source = source.sub(%r{// MARK: - Entry point.*?// MARK: - Feature catalog}m, '')
    harness = <<~'SWIFT'
      func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
          guard condition() else {
              fatalError(message)
          }
      }
      extension FeatureSelectionController {
          func verifyInstallControlRow() {
              managerPath = "/dev/null"
              buildWindow(screenSize: NSSize(width: 1440, height: 900))
              let location = installLocationButton!
              let cleanup = cleanupBuildProductsButton!
              let cleanNow = cleanupNowButton!
              let header = headerView!
              for language in ["zh-Hans", "zh-Hant", "en"] {
                  preferences.language = language
                  applyPanelPreferences()
                  expect(abs(location.frame.midY - cleanup.frame.midY) < 0.5 && abs(location.frame.midY - cleanNow.frame.midY) < 0.5, "deployment and cleanup controls share one vertically centered row")
                  expect(abs(cleanup.frame.minX - location.frame.maxX - 16) < 0.5, "location and automatic cleanup have a 16 point gap")
                  expect(abs(cleanNow.frame.minX - cleanup.frame.maxX - 16) < 0.5, "automatic and manual cleanup have a 16 point gap")
                  for control in [location, cleanup, cleanNow] {
                      expect(header.bounds.contains(control.frame), "complete deployment row stays within the header")
                      expect(control.frame.width + 0.5 >= control.fittingSize.width, "complete deployment titles fit in every language")
                      expect(!control.frame.intersects(installLocationLabel!.frame) && !control.frame.intersects(summaryLabel!.frame), "path and selection summary remain on separate rows below")
                  }
                  expect(window!.contentMinSize.width >= cleanNow.frame.maxX + 52, "minimum width reserves the complete row without wrapping")
                  verifyToolbarGeometry(wrapped: false)
              }
              appManagementBlocked = true
              refreshCleanupBuildProductsOption()
              let privacy = privacySettingsButton!
              expect(!privacy.isHidden, "privacy authorization action remains available when blocked")
              expect(abs(privacy.frame.midY - actionControl!.frame.midY) < 0.5, "privacy authorization shares the separate install / uninstall action row")
              expect(!privacy.frame.intersects(actionControl!.frame), "privacy authorization does not overlap the action switch")
              for control in [location, cleanup, cleanNow] {
                  expect(!privacy.frame.intersects(control.frame), "privacy authorization never overlaps the deployment and cleanup row")
              }
              actionControl!.selectedSegment = 1
              actionChanged()
              expect(cleanup.isHidden && !cleanNow.isHidden, "uninstall retains independent cleanup and hides automatic cleanup")
              expect(abs(cleanNow.frame.minX - location.frame.maxX - 16) < 0.5 && abs(cleanNow.frame.midY - location.frame.midY) < 0.5, "uninstall compacts independent cleanup into the same row")
              location.state = .off
              installLocationChanged()
              expect(cleanup.isHidden && cleanNow.isHidden, "build-directory route keeps both cleanup controls hidden")
              location.state = .on
              installLocationChanged()
              actionControl!.selectedSegment = 0
              actionChanged()
              expect(!cleanup.isHidden && !cleanNow.isHidden && abs(cleanNow.frame.minX - cleanup.frame.maxX - 16) < 0.5, "returning to Applications install restores the original single row")
              preferences.language = "zh-Hans"
          }

          func verifyToolbarGeometry(wrapped: Bool) {
              let header = headerView!
              let toolbar = preferencesToolbar!
              let title = headerTitleLabel!
              expect(header.bounds.contains(toolbar.frame), "toolbar remains inside the header")
              expect(abs(toolbar.frame.maxX - header.bounds.maxX) < 0.5, "preferences align with the content's right edge")
              expect(abs(header.frame.maxX - window!.contentView!.bounds.maxX + 26) < 0.5, "toolbar shares the panel's right content inset")
              expect(abs(header.frame.maxY - window!.contentView!.bounds.maxY + headerTopInset) < 0.5, "header stays anchored at the top while resizing")
              expect(!toolbar.frame.intersects(title.frame), "preferences never cover the title")
              expect(!toolbar.frame.intersects(actionControl!.frame), "preferences never cover install / uninstall controls")
              if wrapped {
                  expect(toolbar.frame.maxY + 7.5 <= title.frame.minY, "narrow windows place a right-aligned toolbar below the title")
                  expect(header.bounds.height == headerBaseHeight + toolbar.frame.height + 8, "narrow fallback adds exactly one toolbar row")
              } else {
                  expect(abs(toolbar.frame.midY - title.frame.midY) < 0.5, "toolbar shares the title's top row")
                  expect(header.bounds.height == headerBaseHeight, "wide windows do not add a preferences row")
              }
              let controls = toolbar.subviews.compactMap { $0 as? NSControl }
              for (index, control) in controls.enumerated() {
                  expect(toolbar.bounds.contains(control.frame), "each preference control stays in its toolbar")
                  expect(control.font?.pointSize == 12, "preference labels and menus share the same font size")
                  for other in controls.dropFirst(index + 1) {
                      expect(!control.frame.intersects(other.frame), "preference labels and menus never overlap")
                  }
              }
              expect(themeControl!.frame.height == 24 && languageControl!.frame.height == 24, "both native dropdowns share a compact height")
              expect(themeControl!.frame.width == languageControl!.frame.width, "both native dropdowns share a balanced width")
          }

          func verifyPreferences(directory: URL) throws {
              buildWindow(screenSize: NSSize(width: 1440, height: 1000))
              installMenu(application: NSApplication.shared)
              applyPanelPreferences()
              verifyToolbarGeometry(wrapped: false)
              let originalContentSize = window!.contentView!.bounds.size
              let originalMinimumSize = window!.contentMinSize
              window!.setContentSize(NSSize(width: originalContentSize.width + 240, height: originalContentSize.height + 80))
              verifyToolbarGeometry(wrapped: false)
              // 隔离窗口临时放宽最小宽度，只验证标题/偏好栏的窄窗回退，不改变产品默认约束。
              window!.contentMinSize = NSSize(width: preferencesToolbar!.frame.width + 52, height: originalMinimumSize.height)
              let narrowWidth = headerTitleFrame.width + 24 + preferencesToolbar!.frame.width - 20 + 52
              window!.setContentSize(NSSize(width: narrowWidth, height: originalContentSize.height + 80))
              verifyToolbarGeometry(wrapped: true)
              window!.contentMinSize = originalMinimumSize
              window!.setContentSize(originalContentSize)
              verifyToolbarGeometry(wrapped: false)
              let originalWindow = window!
              let first = checkboxes.first { $0.option.identifier == "path_copier" }!.button
              first.performClick(nil)
              let originalButton = first
              logTextView!.string = "原始日志 / 中文路径 / raw backend output\n"
              let originalLog = logTextView!.string
              featureStates["path_copier"] = "failed"
              logURL = directory.appendingPathComponent("原始日志 中文.log")
              lastExitStatus = 3
              executionLabel!.stringValue = "任务失败：成功 0，失败 1；退出码 3；进度 100.0%；安装总用时 00:00:12"
              refreshExecutionState()
              let failure = statusLabels["path_copier"]!
              for language in ["en", "zh-Hant", "zh-Hans", "en"] {
                  languageControl!.selectItem(at: ManagerPanelPreferences.languages.firstIndex(of: language)!)
                  languageChanged()
                  verifyToolbarGeometry(wrapped: false)
                  expect(window === originalWindow && first === originalButton, "same live window and selection controls")
                  expect(first.state == .on && checkedIdentifiers() == ["path_copier"], "language changes preserve selection")
                  expect(logTextView!.string == originalLog && lastExitStatus == 3, "language changes preserve raw log and task result")
                  expect(first.title == preferences.text("复制绝对路径"), "feature catalog changes language")
                  expect(failure.stringValue == preferences.text("失败，见日志"), "failure status changes language")
                  expect(failure.toolTip!.contains("原始日志 中文.log"), "tooltip retains original path")
                  expect(failure.attributedStringValue.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int == 1, "localized error remains an underlined link")
                  expect(executionLabel!.stringValue == preferences.text("任务失败：成功 0，失败 1；退出码 3；进度 100.0%；安装总用时 00:00:12"), "completed summary changes language")
                  expect(NSApplication.shared.mainMenu!.items[1].title == preferences.text("编辑"), "edit menu changes language")
                  expect(languageControl!.itemTitles.contains("简体中文") && languageControl!.itemTitles.contains("繁體中文"), "language names remain readable endonyms")
                  for group in groupControls {
                      expect(group.select.title == preferences.text("全选"), "group selection title changes language")
                  }
              }
              for theme in ManagerPanelPreferences.themes {
                  themeControl!.selectItem(at: ManagerPanelPreferences.themes.firstIndex(of: theme)!)
                  themeChanged()
                  let expected: NSAppearance.Name? = theme == "dark" ? .darkAqua : (theme == "light" ? .aqua : nil)
                  expect(window!.appearance?.name == expected, "each theme applies native window appearance")
                  expect(logTextView!.string == originalLog && first.state == .on, "theme changes preserve raw log and selection")
                  expect(logTextView!.textColor == .textColor && logTextView!.backgroundColor == .textBackgroundColor, "existing log uses semantic text and background colors")
              }
              var systemLanguage = "zh-TW"
              preferences.systemLanguages = { [systemLanguage] }
              languageControl!.selectItem(at: 0)
              languageChanged()
              expect(first.title == "複製絕對路徑", "system mode initially resolves traditional Chinese")
              systemLanguage = "en-GB"
              NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
              expect(first.title == "Copy absolute path", "system language notification refreshes existing controls")
              languageControl!.selectItem(at: 1)
              languageChanged()
              systemLanguage = "zh-TW"
              NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
              expect(first.title == "复制绝对路径", "explicit language remains fixed after system changes")
              for (language, theme, name) in [("en", "light", "english-day"), ("zh-Hant", "dark", "traditional-night")] where ProcessInfo.processInfo.environment["JOBS_PANEL_PREVIEW_DIR"] != nil {
                  preferences.language = language
                  preferences.theme = theme
                  applyPanelPreferences()
                  if let bitmap = originalWindow.contentView!.bitmapImageRepForCachingDisplay(in: originalWindow.contentView!.bounds) {
                      originalWindow.contentView!.cacheDisplay(in: originalWindow.contentView!.bounds, to: bitmap)
                      try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
                  }
              }
              // 模拟活动任务，只切换外观和语言，不启动安装器。
              worker = Process()
              activeWorkerAction = "install"
              featureStates["path_copier"] = "running"
              refreshSelectionState()
              preferences.language = "en"
              preferences.theme = "dark"
              applyPanelPreferences()
              expect(isRunning && activeWorkerAction == "install" && featureStates["path_copier"] == "running", "active task survives preference changes")
              expect(themeControl!.isEnabled && languageControl!.isEnabled && first.isEnabled == false, "preferences remain usable while task selection is locked")
              worker = nil
              activeWorkerAction = nil
              print("Native panel preferences and live-state preservation passed")
          }
      }
      let application = NSApplication.shared
      application.setActivationPolicy(.prohibited)
      application.finishLaunching()
      let domain = "com.jobs.tests.panel-preferences.\(UUID().uuidString)"
      let defaults = UserDefaults(suiteName: domain)!
      defer {
          defaults.removePersistentDomain(forName: domain)
      }
      let preferences = ManagerPanelPreferences(defaults: defaults, systemLanguages: { ["zh-CN"] })
      expect(preferences.theme == "system" && preferences.language == "system", "new users follow system")
      for (identifier, expected) in [("zh-TW", "zh-Hant"), ("zh-HK", "zh-Hant"), ("zh-MO", "zh-Hant"), ("zh-Hant-US", "zh-Hant"), ("zh-Hans-HK", "zh-Hans"), ("zh-SG", "zh-Hans"), ("zh_CN", "zh-Hans"), ("fr-FR", "en"), ("en-US", "en")] {
          expect(ManagerPanelPreferences.resolveLanguage(identifier) == expected, "system UI language resolution: \(identifier)")
      }
      preferences.language = "en"
      preferences.theme = "dark"
      let reloaded = ManagerPanelPreferences(defaults: UserDefaults(suiteName: domain)!)
      expect(reloaded.language == "en" && reloaded.theme == "dark", "preferences survive a new settings instance")
      defaults.set("unknown", forKey: "theme")
      defaults.set("unknown", forKey: "language")
      expect(preferences.language == "system" && preferences.theme == "system", "invalid persisted values fall back safely")
      for title in FeatureOption.all.map({ $0.title }) + FeatureGroup.all.map({ $0.title }) {
          let english = preferences.text(title, language: "en")
          expect(!english.unicodeScalars.contains(where: { (0x3400...0x9FFF).contains($0.value) }), "complete English catalog coverage: \(title) => \(english)")
      }
      preferences.language = "zh-Hans"
      try FeatureSelectionController(scope: ["path_copier", "git-pull", "flutter-project-setup"], preferences: preferences).verifyPreferences(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
      FeatureSelectionController(scope: ["path_copier"], installLocation: "applications", preferences: preferences).verifyInstallControlRow()
    SWIFT
    Dir.mktmpdir('jobs-panel-preferences-') do |directory|
      swift = File.join(directory, 'main.swift')
      executable = File.join(directory, 'panel-tests')
      File.write(swift, source + harness)
      output, status = Open3.capture2e('xcrun', 'swiftc', swift, '-o', executable)
      assert status.success?, output
      artifacts = ENV['JOBS_PANEL_PREVIEW_DIR'] || directory
      Dir.mkdir(artifacts) unless Dir.exist?(artifacts)
      output, status = Open3.capture2e(executable, artifacts)
      assert status.success?, output
      assert_includes output, 'Native panel preferences and live-state preservation passed'
    end
  end

  def test_all_standalone_panels_and_manager_snapshots_match_the_current_source
    source = File.binread(File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift'))
    panels = Dir[File.join(ROOT, '*/Scripts/ManagementPanel.swift')]
    snapshots = Dir[File.join(ROOT, '{,*/}Scripts/【MacOS】联合App管理.zsh/Resources/PanelSource.txt')]
    assert_equal 10, panels.length
    assert_equal 32, snapshots.length
    (panels + snapshots).each do |path|
      assert_equal source, File.binread(path), path
    end
  end
end
