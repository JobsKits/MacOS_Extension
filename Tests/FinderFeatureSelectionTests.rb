# frozen_string_literal: true
# Jobs：在临时进程里检查真实 AppKit 分组按钮和布局，不运行安装器或注册扩展。

require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class FinderFeatureSelectionTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_real_group_buttons_global_controls_and_short_screen_layout
    source = File.read(File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift'))
    source = source.sub(/let selectionController = FeatureSelectionController\(\)\nprint\(selectionController.runModal\(\)\)\nexit\(0\)/, '')
    harness = <<~'SWIFT'
      func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
          guard condition() else {
              fatalError(message)
          }
      }

      extension FeatureSelectionController {
          func verifySelection() {
              buildWindow(screenSize: NSSize(width: 1440, height: 900))
              let all = FeatureOption.all.map { $0.identifier }
              let grouped = FeatureGroup.all.flatMap { $0.identifiers }
              expect(FeatureOption.flutter.count == 19 && all.count == 52, "Flutter exposes all 19 leaf actions alongside the Git rollback action")
              expect(!all.contains("flutter-tools") && all.contains("flutter-package-ios") && all.contains("flutter-package-ohos"), "parent menus are not counted as actions")
              expect(all.count >= 29 && FeatureOption.ios.count >= 9, "existing functions plus requested iOS scripts")
              expect(Set(all).count == all.count, "unique function identifiers")
              expect(Set(grouped) == Set(all) && grouped.count == all.count, "every function in exactly one group")
              expect(checkedIdentifiers() == all, "all functions selected by default in stable output order")
              expect(selectAllButton?.isEnabled == false && clearButton?.isEnabled == true, "initial global buttons")
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
              expect(FeatureOption.all.allSatisfy { !$0.title.contains("鸿蒙") }, "visible platform names use English")
              expect(FeatureOption.flutter.first { $0.identifier == "flutter-run" }?.title == "从终端运行 Flutter 项目", "Flutter run names the terminal")
              expect(FeatureOption.flutter.first { $0.identifier == "flutter-clean-build-artifacts" }?.title == "清理当前 Flutter 项目构建产物", "Flutter cleanup names its scope")
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
              expect(checkedIdentifiers().count == 33, "Flutter clear changes all leaf actions only")
              checkboxes.first { $0.option.identifier == "flutter-package-android" }!.button.performClick(nil)
              expect(flutter.summary.stringValue == "已选 1 / 19", "one Flutter submenu can be installed")
              print("group controls and function identifiers passed")
          }

          func verifyLayout(_ screen: NSSize) {
              buildWindow(screenSize: screen)
              let content = window!.contentView!
              content.layoutSubtreeIfNeeded()
              expect(window!.frame.width <= screen.width, "window fits screen width \(screen): \(window!.frame)")
              expect(window!.frame.height <= screen.height, "window fits screen height \(screen): \(window!.frame)")
              for checkbox in checkboxes {
                  let rect = checkbox.button.convert(checkbox.button.bounds, to: content)
                  expect(rect.width > 0 && rect.height > 0, "checkbox has size: \(checkbox.option.identifier), rect \(rect), parent \(checkbox.button.superview!.frame), content \(content.frame)")
                  let scroll = content.subviews.compactMap { $0 as? NSScrollView }.first
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
                      let scroll = content.subviews.compactMap { $0 as? NSScrollView }.first
                      expect(scroll != nil || content.bounds.contains(rect), "group controls fit content or scroll document")
                  }
              }
              let rect = installButton!.convert(installButton!.bounds, to: content)
              expect(content.bounds.contains(rect), "install visible")
              if let scroll = content.subviews.compactMap({ $0 as? NSScrollView }).first {
                  expect(content.bounds.contains(scroll.frame), "scroll viewport fits content")
                  expect(scroll.hasVerticalScroller && scroll.documentView!.frame.height > scroll.contentView.bounds.height, "overflow remains reachable")
                  scroll.contentView.scroll(to: .zero)
                  let bottom = checkboxes.last!.button
                  bottom.scrollToVisible(bottom.bounds)
                  expect(scroll.documentView!.visibleRect.contains(bottom.convert(bottom.bounds, to: scroll.documentView)), "last checkbox reachable by scrolling")
              }
              print("layout \(Int(screen.width))x\(Int(screen.height)): \(Int(window!.frame.width))x\(Int(window!.frame.height)) passed")
          }
      }

      let application = NSApplication.shared
      application.setActivationPolicy(.prohibited)
      application.finishLaunching()
      FeatureSelectionController().verifySelection()
      for size in [NSSize(width: 1440, height: 900), NSSize(width: 1280, height: 720), NSSize(width: 1280, height: 600), NSSize(width: 1024, height: 768)] {
          FeatureSelectionController().verifyLayout(size)
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
      assert_equal 4, output.scan(/^layout .* passed$/).count, output
    end
  end
end
