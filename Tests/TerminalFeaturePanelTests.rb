# frozen_string_literal: true
# 编译真实宿主面板；隔离系统登记，只检查勾选与布局，不保存用户配置。
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class TerminalFeaturePanelTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_every_terminal_action_can_be_selected_without_losing_legacy_choices
    source = File.read(File.join(ROOT, 'JobsTerminalOpener/JobsTerminalOpener/MainViewController.swift'))
    raise '未找到待隔离的自动登记调用' unless source.sub!(
      "        reloadFeatureSelection()\n        enableFinderExtension()",
      "        reloadFeatureSelection()\n        // 隔离测试不登记扩展。"
    )
    harness = <<~'SWIFT'
      func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
          if !condition() {
              fatalError(message)
          }
      }
      extension MainViewController {
          func verifyPanel(size: NSSize) {
              view.setFrameSize(size)
              buildInterface()
              layoutInterface()
              view.layoutSubtreeIfNeeded()
              let actions = featureCheckboxes.map { $0.feature }
              expect(Set(actions) == Set(FinderMenuFeature.allCases), "every saved action has a checkbox")
              expect(actions.count == Set(actions).count, "one checkbox per action")
              setAllFeaturesEnabled(true)
              expect(selectedFeatures() == Set(FinderMenuFeature.allCases), "select all retains new and legacy actions")
              setAllFeaturesEnabled(false)
              expect(selectedFeatures().isEmpty, "clear removes every action")
              let viewer = featureCheckboxes.first { $0.feature == .fileContent }!
              viewer.checkbox.state = .on
              expect(selectedFeatures() == [.fileContent], "single viewer selection does not enable siblings")
              let rect = viewer.checkbox.convert(viewer.checkbox.bounds, to: scrollDocumentView)
              expect(rect.width >= viewer.checkbox.fittingSize.width - 1, "viewer label fits")
              expect(scrollDocumentView.bounds.contains(rect), "viewer remains in the scrollable document")
              print("panel \(Int(size.width))x\(Int(size.height)) passed")
          }
      }
      let application = NSApplication.shared
      application.setActivationPolicy(.prohibited)
      application.finishLaunching()
      for size in [NSSize(width: 820, height: 580), NSSize(width: 720, height: 460)] {
          MainViewController().verifyPanel(size: size)
      }
    SWIFT
    Dir.mktmpdir('jobs-terminal-panel-') do |directory|
      path = File.join(directory, 'main.swift')
      binary = File.join(directory, 'panel-check')
      File.write(path, source + "\n" + harness)
      output, status = Open3.capture2e(
        '/usr/bin/xcrun', 'swiftc',
        File.join(ROOT, 'JobsTerminalOpener/JobsTerminalShared/FinderMenuFeatureConfiguration.swift'),
        path, '-o', binary
      )
      assert status.success?, output
      output, status = Open3.capture2e(binary)
      assert status.success?, output
      assert_equal 2, output.scan(/^panel .* passed$/).count, output
    end
  end
end
