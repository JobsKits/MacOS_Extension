# frozen_string_literal: true
# Jobs：在临时进程里检查真实 AppKit 分组按钮和布局，不运行安装器或注册扩展。

require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class FinderFeatureSelectionTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_real_group_buttons_global_controls_and_short_screen_layout
    source = File.read(ENV.fetch('JOBS_FINDER_PANEL_TEST_SOURCE', File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift')))
    source = source.sub(%r{// MARK: - Entry point.*?// MARK: - Feature catalog}m, '')
    harness = <<~'SWIFT'
      func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
          guard condition() else {
              fatalError(message)
          }
      }

      extension FeatureSelectionController {
          func verifyTextBounds(_ field: NSTextField, context: String) {
              let fitting = field.fittingSize
              expect(field.frame.width + 0.5 >= fitting.width, "\(context) text width \(field.stringValue): frame \(field.frame.width), needed \(fitting.width)")
              expect(field.frame.height + 0.5 >= fitting.height, "\(context) text height \(field.stringValue)")
              if let parent = field.superview {
                  expect(parent.bounds.insetBy(dx: -0.5, dy: -0.5).contains(field.frame), "\(context) remains inside its parent")
              }
          }

          func verifyGroupCountBounds(context: String) {
              for controls in groupControls {
                  verifyTextBounds(controls.summary, context: "\(context) / \(controls.group.identifier)")
                  expect(controls.summary.frame.minX >= controls.clear.frame.maxX, "\(context) count does not overlap group buttons")
              }
              verifyTextBounds(summaryLabel!, context: "\(context) / global selection")
          }

          func verifyLogToolbarBounds(context: String) {
              let scroll = logTextView!.enclosingScrollView!
              let panel = scroll.superview!
              let title = panel.subviews.compactMap { $0 as? NSTextField }.first!
              let buttons = panel.subviews.compactMap { $0 as? NSButton }.sorted { $0.frame.minX < $1.frame.minX }
              expect(buttons.count == 3, "\(context) log toolbar retains all controls")
              verifyTextBounds(title, context: "\(context) / log title")
              expect(title.frame.maxX <= buttons.first!.frame.minX, "\(context) log title does not overlap toolbar buttons")
              for (index, button) in buttons.enumerated() {
                  expect(panel.bounds.insetBy(dx: -0.5, dy: -0.5).contains(button.frame), "\(context) log button remains inside toolbar: \(button.title)")
                  expect(button.frame.width + 0.5 >= button.fittingSize.width, "\(context) log button title fits: \(button.title)")
                  expect(button.frame.minY >= scroll.frame.maxY, "\(context) log button does not overlap text viewport")
                  if index > 0 {
                      expect(buttons[index - 1].frame.maxX <= button.frame.minX, "\(context) adjacent log buttons do not overlap")
                  }
              }
          }

          func verifyEverySelectionCount(context: String) {
              clearAllClicked()
              for controls in groupControls {
                  let identifiers = Set(controls.group.identifiers)
                  let options = checkboxes.filter { identifiers.contains($0.option.identifier) }
                  for count in 0...options.count {
                      for (index, option) in options.enumerated() {
                          option.button.state = index < count ? .on : .off
                      }
                      refreshSelectionState()
                      expect(controls.summary.stringValue == "已选 \(count) / \(options.count)", "\(context) group count is exact")
                      verifyGroupCountBounds(context: "\(context) count \(count)")
                  }
              }
              expect(checkedIdentifiers().count == checkboxes.count, "\(context) reaches full selection")
              verifyGroupCountBounds(context: "\(context) full selection")
          }

          func verifyExecutionTextBounds(context: String) {
              selectAllClicked()
              runningIdentifiers = checkedIdentifiers()
              // 未运行的 Process 只模拟面板忙状态，不启动脚本或触碰扩展。
              worker = Process()
              let total = runningIdentifiers.count
              let milestones = Set([0, 1, 9, 10, max(0, total - 1), total].filter { $0 <= total }).sorted()
              for operation in ["install", "uninstall"] {
                  managementAction = operation
                  executionTiming.elapsed = 35_999_999
                  for completed in milestones {
                      featureStates = Dictionary(uniqueKeysWithValues: runningIdentifiers.enumerated().map { index, identifier in
                          (identifier, index < completed ? "succeeded" : (index == completed ? "running" : "waiting"))
                      })
                      refreshSelectionState()
                      verifyGroupCountBounds(context: "\(context) / \(operation) running")
                      verifyTextBounds(executionLabel!, context: "\(context) / \(operation) \(completed)/\(total)")
                      for label in statusLabels.values {
                          verifyTextBounds(label, context: "\(context) / feature status")
                      }
                  }
              }
              featureStates = Dictionary(uniqueKeysWithValues: runningIdentifiers.map { ($0, "succeeded") })
              finishWorker(exitStatus: 0)
              verifyTextBounds(executionLabel!, context: "\(context) / success result")
              if let first = runningIdentifiers.first {
                  featureStates[first] = "failed"
              }
              finishWorker(exitStatus: 7)
              verifyTextBounds(executionLabel!, context: "\(context) / failure result")
          }

          func verifySelection() {
              buildWindow(screenSize: NSSize(width: 1440, height: 900))
              let all = FeatureOption.all.map { $0.identifier }
              let grouped = FeatureGroup.all.flatMap { $0.identifiers }
              expect(FeatureOption.flutter.count == 45 && all.count == 82, "all leaf actions include file creation, viewer, merge and split")
              expect(!all.contains("git-sourcetree"), "retired Sourcetree entry is absent from management choices")
              let privateActions = ["flutter-export-private-dependencies", "flutter-import-private-dependencies"]
              expect(privateActions.allSatisfy { action in all.filter { $0 == action }.count == 1 }, "private export and import each occur exactly once")
              expect(FeatureOption.flutter.first { $0.identifier == privateActions[0] }?.title == "🔐 提取Flutter项目工程私库依赖", "private export title identifies its restricted dependency scope")
              expect(FeatureOption.flutter.first { $0.identifier == privateActions[1] }?.title == "📥 导入Flutter项目工程私库依赖", "private import remains distinct from public dependency import")
              expect(FeatureGroup.all.count == 6, "right-click regrouping keeps the six management groups")
              expect(!all.contains("flutter-tools") && all.contains("flutter-package-ios") && all.contains("flutter-package-ohos"), "parent menus are not counted as actions")
              expect(all.count >= 29 && FeatureOption.ios.count >= 9, "existing functions plus requested iOS scripts")
              expect(Set(all).count == all.count, "unique function identifiers")
              expect(Set(grouped) == Set(all) && grouped.count == all.count, "every function in exactly one group")
              let general = groupControls.first { $0.group.identifier == "general" }!
              expect(general.group.identifiers.contains("file-create"), "file creation belongs to file and general tools")
              expect(FeatureOption.independent.filter { $0.identifier == "file-create" }.map { $0.title } == ["新建文件"], "file creation remains an independent action exactly once")
              expect(checkedIdentifiers().isEmpty, "management starts with no implicit selection")
              expect(selectAllButton?.isEnabled == true && clearButton?.isEnabled == false && installButton?.isEnabled == false, "initial empty selection disables execution")
              selectAllButton?.performClick(nil)
              expect(checkedIdentifiers() == all, "global select retains stable output order")
              verifyGroupCountBounds(context: "all selected before clearing")
              for controls in groupControls {
                  let groupIDs = Set(controls.group.identifiers)
                  controls.clear.performClick(nil)
                  expect(checkedIdentifiers() == all.filter { !groupIDs.contains($0) }, "clear only the selected group")
                  expect(controls.clear.isEnabled == false && controls.select.isEnabled, "empty group controls")
                  expect(controls.summary.stringValue == "已选 0 / \(groupIDs.count)", "group count after clearing")
                  controls.select.performClick(nil)
                  expect(checkedIdentifiers() == all, "restore only the selected group")
              }
              clearButton?.performClick(nil)
              expect(checkedIdentifiers().isEmpty && installButton?.isEnabled == false, "global clear disables install")
              installClicked()
              if case .selected = outcome {
                  fatalError("empty selection must not install even through Return handler")
              }
              let ios = groupControls.first { $0.group.identifier == "ios" }!
              expect(Array(ios.group.identifiers.prefix(2)) == ["pod_install", "ios-pod-update"], "Pod Install and Pod Update are adjacent")
              expect(ios.group.options[0].title == "Pod Install" && ios.group.options[1].title == "Pod Update", "Pod titles use initial capitals")
              expect(ios.group.identifiers.contains("ios-clean-build-artifacts"), "iOS cleanup belongs to the iOS group")
              expect(!all.contains("ios-clean-cache"), "overlapping iOS cleanup is not a second option")
              expect(FeatureOption.all.filter { $0.identifier != "flutter-package-ohos" }.allSatisfy { !$0.title.contains("鸿蒙") }, "other platform names retain their existing names")
              expect(FeatureOption.all.first { $0.identifier == "flutter-package-ohos" }?.title == "打包鸿蒙（HAP + APP）", "Harmony packaging states both outputs")
              expect(FeatureOption.flutter.first { $0.identifier == "flutter-run" }?.title == "从终端运行 Flutter 项目", "Flutter run names the terminal")
              expect(FeatureOption.flutter.first { $0.identifier == "flutter-clean-build-artifacts" }?.title == "清理当前 Flutter 项目构建产物", "Flutter cleanup names its scope")
              expect(FeatureOption.flutter.first { $0.identifier == "flutter-native-dependencies" }?.title == "准备原生库与构建依赖（组合操作）", "native preparation is labeled as a combined operation")
              expect(FeatureOption.flutter.first { $0.identifier == "flutter-gradle-download" }?.title == "下载Gradled分发与构建插件", "resource label keeps the requested spelling")
              expect(FeatureOption.flutter.first { $0.identifier == "flutter-sdk-version" }?.title == "查看当前Flutter项目工程的SDK版本", "SDK inspection label matches its menu")
              let git = groupControls.first { $0.group.identifier == "git" }!
              expect(git.group.identifiers == ["git-pull", "git-rollback", "git_remote", "git_remote_copier", "git-proxy-configure", "git_empty_commit_push"], "all six Git actions remain individually selectable")
              ios.select.performClick(nil)
              expect(checkedIdentifiers() == all.filter { ios.group.identifiers.contains($0) }, "select one group from global empty")
              expect(checkedIdentifiers().count == ios.group.identifiers.count && installButton?.isEnabled == true, "iOS group includes pod install, IPA signing and ten scripts")
              checkboxes.first { $0.option.identifier == "ios-pod-build-check" }!.button.performClick(nil)
              expect(ios.summary.stringValue == "已选 \(ios.group.identifiers.count - 1) / \(ios.group.identifiers.count)" && ios.select.isEnabled, "individual checkbox updates group")
              selectAllButton?.performClick(nil)
              expect(checkedIdentifiers() == all, "global select restores all groups")
              let flutter = groupControls.first { $0.group.identifier == "flutter" }!
              flutter.clear.performClick(nil)
              expect(checkedIdentifiers().count == 37, "Flutter clear changes all leaf actions only")
              checkboxes.first { $0.option.identifier == "flutter-package-android" }!.button.performClick(nil)
              expect(flutter.summary.stringValue == "已选 1 / 45", "one Flutter submenu can be installed")
              print("group controls and function identifiers passed")
          }

          func verifyManagement() {
              buildWindow(screenSize: NSSize(width: 1280, height: 720))
              expect(formattedOutcome() == "__CANCELLED__", "no plan before explicit confirmation")
              selectAllButton?.performClick(nil)
              actionControl?.selectedSegment = 1
              actionChanged()
              expect(managementAction == "uninstall" && checkedIdentifiers().isEmpty, "switching to uninstall clears the selected install plan")
              expect(installButton?.title == "卸载" && installButton?.isEnabled == false, "uninstall action requires a fresh choice")
              expect(groupControls.allSatisfy { $0.summary.stringValue.hasPrefix("已选 0 /") }, "mode switch clears all groups")
              checkboxes.first { $0.option.identifier == "git-pull" }!.button.performClick(nil)
              installClicked()
              expect(formattedOutcome() == "uninstall|git-pull", "single uninstall returns the exact leaf and action")
              actionControl?.selectedSegment = 0
              actionChanged()
              expect(checkedIdentifiers().isEmpty && installButton?.title == "安装 / 更新", "switching back also clears the plan")
              checkboxes.first { $0.option.identifier == "path_copier" }!.button.performClick(nil)
              installClicked()
              expect(formattedOutcome() == "install|path_copier", "install returns action and exact selection")
              cancelClicked()
              expect(formattedOutcome() == "__CANCELLED__", "cancel discards the complete plan")
              _ = windowShouldClose(window!)
              expect(formattedOutcome() == "__CANCELLED__", "window close discards the complete plan")
              print("management actions and cancellation passed")
          }

          func verifyScope() {
              buildWindow(screenSize: NSSize(width: 1024, height: 768))
              verifyLogToolbarBounds(context: "scope \(scopeIdentifiers.count)")
              let all = FeatureOption.all.map { $0.identifier }
              let expected = all.filter { scopeIdentifiers.contains($0) }
              expect(checkboxes.map { $0.option.identifier }.sorted() == expected.sorted(), "only scoped options are rendered")
              expect(checkedIdentifiers().isEmpty, "scoped management also starts empty")
              expect(installButton!.frame.width >= installButton!.fittingSize.width - 1, "uninstall button title fits")
              actionControl?.selectedSegment = 0
              actionChanged()
              expect(installButton!.frame.width >= installButton!.fittingSize.width - 1, "install title fits after switching from initial uninstall")
              actionControl?.selectedSegment = 1
              actionChanged()
              selectAllClicked()
              expect(checkedIdentifiers() == expected, "global select cannot escape the scope")
              for controls in groupControls {
                  expect(Set(controls.group.identifiers).isSubset(of: scopeIdentifiers), "group controls use the visible scope")
                  controls.clear.performClick(nil)
                  expect(!checkedIdentifiers().contains { controls.group.identifiers.contains($0) }, "group clear affects the scoped group")
                  controls.select.performClick(nil)
                  expect(checkedIdentifiers() == expected, "group select cannot enable hidden siblings")
              }
              installClicked()
              expect(formattedOutcome() == "uninstall|\(expected.joined(separator: ","))", "scoped output captures the chosen operation")
              verifyEverySelectionCount(context: "scope \(scopeIdentifiers.count)")
              verifyExecutionTextBounds(context: "scope \(scopeIdentifiers.count)")
              verifyLogToolbarBounds(context: "scope \(scopeIdentifiers.count) after execution")
              print("scope \(scopeIdentifiers.count) passed")
          }

          func verifyLayout(_ screen: NSSize, appearance: NSAppearance.Name) {
              NSApplication.shared.appearance = NSAppearance(named: appearance)
              buildWindow(screenSize: screen)
              let content = window!.contentView!
              content.layoutSubtreeIfNeeded()
              verifyLogToolbarBounds(context: "\(appearance.rawValue) \(screen)")
              expect(window!.frame.width <= screen.width, "window fits screen width \(screen): \(window!.frame)")
              expect(window!.frame.height <= screen.height, "window fits screen height \(screen): \(window!.frame)")
              for checkbox in checkboxes {
                  let rect = checkbox.button.convert(checkbox.button.bounds, to: content)
                  expect(rect.width > 0 && rect.height > 0, "checkbox has size: \(checkbox.option.identifier), rect \(rect), parent \(checkbox.button.superview!.frame), content \(content.frame)")
                  let scroll = featureScrollView
                  if let scroll, let document = scroll.documentView {
                      expect(document.bounds.contains(checkbox.button.convert(checkbox.button.bounds, to: document)), "every option fits scroll document")
                  } else {
                      expect(content.bounds.contains(rect), "checkbox visible in content: \(checkbox.option.identifier)")
                  }
                  expect(rect.width >= checkbox.button.fittingSize.width - 1, "checkbox label is not clipped")
              }
              for controls in groupControls {
                  for button in [controls.select, controls.clear] {
                      let rect = button.convert(button.bounds, to: content)
                      let scroll = featureScrollView
                      expect(scroll != nil || content.bounds.contains(rect), "group controls fit content or scroll document")
                  }
              }
              let rect = installButton!.convert(installButton!.bounds, to: content)
              expect(content.bounds.contains(rect), "install visible")
              if let scroll = featureScrollView {
                  expect(content.bounds.contains(scroll.convert(scroll.bounds, to: content)), "scroll viewport fits content")
                  expect(scroll.hasVerticalScroller, "options remain scrollable when the log grows")
                  scroll.contentView.scroll(to: .zero)
                  let bottom = checkboxes.last!.button
                  bottom.scrollToVisible(bottom.bounds)
                  expect(scroll.documentView!.visibleRect.contains(bottom.convert(bottom.bounds, to: scroll.documentView)), "last checkbox reachable by scrolling")
              }
              let context = "\(appearance.rawValue) \(Int(screen.width))x\(Int(screen.height))"
              verifyEverySelectionCount(context: context)
              verifyExecutionTextBounds(context: context)
              verifyLogResize(context: context)
              print("layout \(context): \(Int(window!.frame.width))x\(Int(window!.frame.height)) passed")
          }

          func verifyLogResize(context: String) {
              let split = logSplitView!
              let log = logTextView!
              let upper = split.arrangedSubviews[0]
              let lower = split.arrangedSubviews[1]
              let content = window!.contentView!
              expect(window!.styleMask.contains(.resizable), "\(context) window can be resized")
              let initialHeight = lower.frame.height
              let originalSelections = checkedIdentifiers()
              log.string = "第一行日志\n第二行中文日志\n"
              let fullLog = log.string
              split.setPosition(minimumUpperPaneHeight, ofDividerAt: 0)
              expect(lower.frame.height > initialHeight, "\(context) dragging up enlarges the log")
              expect(upper.frame.height >= minimumUpperPaneHeight - 1, "\(context) upper controls stay usable")
              verifyLogToolbarBounds(context: "\(context) expanded log")
              let last = checkboxes.last!.button
              last.scrollToVisible(last.bounds)
              let document = featureScrollView!.documentView!
              expect(document.visibleRect.contains(last.convert(last.bounds, to: document)), "\(context) last option reachable after dragging")
              split.setPosition(split.bounds.height, ofDividerAt: 0)
              expect(lower.frame.height >= 111, "\(context) dragging down preserves the log toolbar and viewport")
              verifyLogToolbarBounds(context: "\(context) smallest log")
              expect(checkedIdentifiers() == originalSelections && log.string == fullLog, "\(context) dragging preserves selection and log content")
              let savedSize = content.frame.size
              window!.setContentSize(NSSize(width: savedSize.width + 80, height: savedSize.height + 100))
              content.layoutSubtreeIfNeeded()
              expect(split.bounds.width > savedSize.width - 52 && split.bounds.height > upper.frame.height, "\(context) split follows the window")
              expect(content.bounds.contains(installButton!.convert(installButton!.bounds, to: content)), "\(context) install stays visible after resizing")
              verifyLogToolbarBounds(context: "\(context) resized window")
              split.setPosition(minimumUpperPaneHeight, ofDividerAt: 0)
              window!.setContentSize(window!.contentMinSize)
              content.layoutSubtreeIfNeeded()
              expect(upper.frame.height >= minimumUpperPaneHeight - 1 && lower.frame.height >= 111, "\(context) shrinking a large log preserves both minimum heights")
              expect(content.bounds.contains(installButton!.convert(installButton!.bounds, to: content)), "\(context) install stays visible at minimum window size")
              verifyLogToolbarBounds(context: "\(context) minimum window after large log")
              window!.setContentSize(savedSize)
              content.layoutSubtreeIfNeeded()
              let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
              let menu = log.menu(for: event)!
              let items = menu.items.filter { $0.action == #selector(NSText.selectAll(_:)) }
              expect(items.count == 1 && items[0].title == "全选", "\(context) right-click offers one Select All")
              expect(items[0].target === log, "\(context) right-click action targets the log itself")
              _ = NSApplication.shared.sendAction(items[0].action!, to: items[0].target, from: items[0])
              expect(log.selectedRange() == NSRange(location: 0, length: (fullLog as NSString).length), "\(context) Select All selects the complete Chinese log")
              log.string = ""
              log.selectAll(nil)
              expect(log.selectedRange().length == 0 && !log.isEditable, "\(context) empty read-only log handles Select All")
          }
      }

      let application = NSApplication.shared
      application.setActivationPolicy(.prohibited)
      application.finishLaunching()
      FeatureSelectionController().verifySelection()
      FeatureSelectionController().verifyManagement()
      try FeatureSelectionController.parseArguments(["--action", "uninstall", "--scope", "git-pull"]).verifyScope()
      try FeatureSelectionController.parseArguments(["--scope", "git-pull,path_copier,flutter-run", "--action", "uninstall"]).verifyScope()
      try FeatureSelectionController.parseArguments(["--scope", "git-pull,run-authorize"]).verifyScope()
      try FeatureSelectionController.parseArguments(["--scope", "file-create", "--action", "uninstall"]).verifyScope()
      for arguments in [["--action", "delete"], ["--scope", ""], ["--scope", "git-pull,"], ["--scope", "unknown"], ["--action"], ["--unknown", "x"]] {
          do {
              _ = try FeatureSelectionController.parseArguments(arguments)
              fatalError("invalid arguments were accepted: \(arguments)")
          } catch {
              expect((error as NSError).code == 2, "invalid argument reports explicit failure")
          }
      }
      let sizes = [NSSize(width: 1440, height: 900), NSSize(width: 1280, height: 720), NSSize(width: 1280, height: 600), NSSize(width: 1024, height: 768), NSSize(width: 2560, height: 1440), NSSize(width: 900, height: 620)]
      for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
          for size in sizes {
              FeatureSelectionController().verifyLayout(size, appearance: appearance)
          }
      }
    SWIFT
    Dir.mktmpdir('jobs-finder-selection-') do |dir|
      path = File.join(dir, 'main.swift')
      binary = File.join(dir, 'selection-check')
      File.write(path, source + "\n" + harness)
      output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', path, '-o', binary)
      assert status.success?, output
      output, status = Open3.capture2e(binary)
      assert status.success?, output
      assert_includes output, 'group controls and function identifiers passed'
      assert_includes output, 'management actions and cancellation passed'
      assert_equal 4, output.scan(/^scope .* passed$/).count, output
      assert_equal 12, output.scan(/^layout .* passed$/).count, output
    end
  end
end
