# frozen_string_literal: true
# Jobs：真实 AppKit 控件连接隔离 worker，验证两种部署位置；不调用任何安装器或系统登记。
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class DeploymentLocationPanelTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def test_real_checkbox_layout_worker_arguments_and_target_state_isolation
    source = File.read(File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift'))
    source = source.sub(%r{// MARK: - Entry point.*?// MARK: - Feature catalog}m, '')
    harness = <<~'SWIFT'
      func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
          guard condition() else {
              fatalError(message)
          }
      }
      func pump(until condition: () -> Bool) {
          let deadline = Date().addingTimeInterval(5)
          while !condition(), Date() < deadline {
              RunLoop.current.run(until: Date().addingTimeInterval(0.01))
          }
          expect(condition(), "isolated worker finishes")
      }
      extension FeatureSelectionController {
          func verifyLocationControls(screen: NSSize) {
              buildWindow(screenSize: screen)
              let button = installLocationButton!
              let label = installLocationLabel!
              expect(button.title == "使用「应用程序」中的联合 App 安装 / 卸载", "checkbox states both operations")
              expect(button.state == .off && installLocation == "build", "build directory remains the default")
              expect(label.stringValue.contains("构建目录"), "default destination is visible")
              expect(cleanupBuildProductsButton!.isHidden && cleanupBuildProductsButton!.state == .off && !cleanupBuildProducts, "build route hides and clears cleanup")
              expect(installButton!.isEnabled == false && checkedIdentifiers().isEmpty, "choosing a destination never selects functions")
              let header = button.superview!
              let controls = header.subviews.compactMap { $0 as? NSControl }.filter { !$0.isHidden }
              for control in controls {
                  expect(header.bounds.insetBy(dx: -0.5, dy: -0.5).contains(control.frame), "header control stays within its parent")
                  expect(control.frame.width + 0.5 >= control.fittingSize.width, "header text fits its width")
                  expect(control.frame.height + 0.5 >= control.fittingSize.height, "header text fits its height")
              }
              for (index, control) in controls.enumerated() {
                  for other in controls.dropFirst(index + 1) {
                      expect(!control.frame.intersects(other.frame), "header rows never overlap")
                  }
              }
              expect(window!.contentView!.bounds.contains(header.frame), "header remains visible")
              expect(window!.contentView!.frame.height <= screen.height + 1, "short screens keep a bounded window")
              button.performClick(nil)
              expect(installLocation == "applications" && label.stringValue.contains("/Applications"), "checkbox switches to Applications")
              expect(label.stringValue.contains("Jobs自定义右键菜单.app") && label.stringValue.contains("/Applications/Jobs自定义右键菜单.app"), "Applications route names the single combined App and exact location")
              let cleanup = cleanupBuildProductsButton!
              expect(!cleanup.isHidden && cleanup.state == .off && cleanup.isEnabled && !cleanupBuildProducts, "Applications install reveals an opt-in cleanup checkbox")
              expect(cleanup.title == "安装成功后清除此轮构建产物", "cleanup title describes successful installation and this build only")
              let cleanupNow = cleanupNowButton!
              expect(abs(button.frame.midY - cleanup.frame.midY) < 0.5 && abs(button.frame.midY - cleanupNow.frame.midY) < 0.5, "deployment location, automatic cleanup and manual cleanup share one centered horizontal row")
              expect(abs(cleanup.frame.minX - button.frame.maxX - 16) < 0.5 && abs(cleanupNow.frame.minX - cleanup.frame.maxX - 16) < 0.5, "deployment row uses consistent explicit gaps")
              expect(cleanupNow.frame.minX > cleanup.frame.maxX && header.bounds.contains(cleanup.frame) && header.bounds.contains(cleanupNow.frame), "cleanup checkbox and independent action remain together within the header")
              expect(cleanupNow.title == "🧹 清除构建产物" && !cleanupNow.isHidden && !cleanupNow.isEnabled, "Applications exposes independent cleanup but requires selected functions")
              expect(cleanupNow.layer?.backgroundColor == NSColor.systemRed.cgColor && cleanupNow.contentTintColor == .white, "independent cleanup uses a red background and white content")
              expect(cleanupNow.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .white, "cleanup button title is white")
              expect(cleanup.frame.width + 0.5 >= cleanup.fittingSize.width, "cleanup title fits on short screens")
              let visibleControls = header.subviews.compactMap { $0 as? NSControl }.filter { !$0.isHidden }
              for (index, control) in visibleControls.enumerated() {
                  for other in visibleControls.dropFirst(index + 1) {
                      expect(!control.frame.intersects(other.frame), "Applications cleanup controls never overlap visible header rows")
                  }
              }
              cleanup.performClick(nil)
              expect(cleanupBuildProducts, "cleanup requires an explicit click")
              expect(installButton!.isEnabled == false && checkedIdentifiers().isEmpty, "destination alone cannot execute a task")
              expect(label.frame.width + 0.5 >= label.fittingSize.width, "Applications hint fits without relayout")
              button.performClick(nil)
              expect(installLocation == "build", "unchecking restores the existing directory route")
              expect(cleanup.isHidden && cleanup.state == .off && !cleanupBuildProducts && cleanupNowButton!.isHidden, "returning to build clears automatic cleanup and hides independent cleanup")
          }
          func verifyExplicitApplicationsMode() {
              buildWindow(screenSize: NSSize(width: 1280, height: 720))
              expect(installLocationButton!.state == .on && installLocation == "applications", "explicit manager mode initializes the control")
              expect(!cleanupBuildProductsButton!.isHidden && cleanupBuildProductsButton!.state == .off, "explicit Applications route still defaults cleanup off")
              cleanupBuildProductsButton!.performClick(nil)
              expect(cleanupBuildProducts, "cleanup can be explicitly selected")
              actionControl!.selectedSegment = 1
              actionChanged()
              expect(cleanupBuildProductsButton!.isHidden && cleanupBuildProductsButton!.state == .off && !cleanupBuildProducts && !cleanupNowButton!.isHidden, "uninstall hides automatic cleanup but retains independent cleanup")
              actionControl!.selectedSegment = 0
              actionChanged()
              expect(!cleanupBuildProductsButton!.isHidden && cleanupBuildProductsButton!.state == .off && !cleanupBuildProducts, "switching back to install never restores a previous cleanup request")
          }
          func verifyLegacyMode() {
              buildWindow(screenSize: NSSize(width: 1280, height: 720))
              expect(installLocationButton == nil && installLocationLabel == nil && cleanupBuildProductsButton == nil, "legacy selection-only mode retains the old plan protocol and has no cleanup action")
              cancelClicked()
              expect(formattedOutcome() == "__CANCELLED__", "cancelling remains a plan with no operation")
          }
          func verifyEmptySelection() {
              buildWindow(screenSize: NSSize(width: 1280, height: 720))
              installLocationButton!.performClick(nil)
              installClicked()
              expect(!isRunning && lastExitStatus == nil, "Applications with no selected functions never starts a worker")
          }
          func verifyIndependentCleanupAndCooperativeStop(path: String) throws {
              buildWindow(screenSize: NSSize(width: 1280, height: 720))
              installLocationButton!.performClick(nil)
              checkboxes.first { $0.option.identifier == "path_copier" }!.button.performClick(nil)
              installationTiming.elapsed = 12
              uninstallationTiming.elapsed = 34
              cleanupBuildProductsButton!.performClick(nil)
              expect(cleanupNowButton!.isEnabled, "selected functions enable independent cleanup")
              setenv("JOBS_TEST_WORKER_MODE", "cleanup", 1)
              cleanupNowButton!.performClick(nil)
              expect(isRunning && activeWorkerAction == "cleanup" && !cleanupNowButton!.isEnabled && !installButton!.isEnabled, "cleanup runs independently and locks execution controls")
              pump { !isRunning }
              expect(lastExitStatus == 0 && statusLabels["path_copier"]!.stringValue == "已清理", "cleanup has its own completion state")
              expect(installationTiming.elapsed == 12 && uninstallationTiming.elapsed == 34 && cleanupTiming.elapsed > 0, "cleanup preserves both installation and uninstallation clocks")
              expect(executionLabel!.stringValue.contains("清理总用时") && installButton!.title == "安装 / 更新", "cleanup completion restores the original tab action")
              let capture = URL(fileURLWithPath: ProcessInfo.processInfo.environment["JOBS_TEST_ARGUMENTS"]!)
              var arguments = try Data(contentsOf: capture).split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
              expect(arguments == ["--non-interactive", "--action", "cleanup", "--features", "path_copier", "--install-location", "applications"], "independent cleanup sends no install or post-install cleanup request")
              try? FileManager.default.removeItem(at: logURL!.deletingLastPathComponent())
              actionControl!.selectedSegment = 1
              actionChanged()
              checkboxes.first { $0.option.identifier == "path_copier" }!.button.performClick(nil)
              expect(cleanupNowButton!.isEnabled && !cleanupNowButton!.isHidden && cleanupBuildProductsButton!.isHidden, "uninstall tab retains independent cleanup without the automatic cleanup checkbox")
              cleanupNowButton!.performClick(nil)
              pump { !isRunning }
              expect(lastExitStatus == 0 && installButton!.title == "卸载" && installationTiming.elapsed == 12 && uninstallationTiming.elapsed == 34, "cleanup from uninstall restores that tab without overwriting either clock")
              try? FileManager.default.removeItem(at: logURL!.deletingLastPathComponent())
              actionControl!.selectedSegment = 0
              actionChanged()
              clearAllClicked()
              setenv("JOBS_TEST_WORKER_MODE", "stop", 1)
              selectAllClicked()
              installClicked()
              pump { featureStates["path_copier"] == "running" }
              expect(installButton!.title == "停止安装" && installButton!.isEnabled, "active installation exposes a working stop button")
              let request = stopRequestURL!
              expect(!FileManager.default.fileExists(atPath: request.path), "a fresh job starts without a stop request")
              installButton!.performClick(nil)
              expect(stopRequested && isRunning && !installButton!.isEnabled, "stop writes a request and keeps the current process running")
              expect(executionLabel!.stringValue.contains("正在完成当前功能，随后停止"), "cooperative stop explains the current unit must finish")
              let requestAttributes = try FileManager.default.attributesOfItem(atPath: request.path)
              let sessionAttributes = try FileManager.default.attributesOfItem(atPath: request.deletingLastPathComponent().path)
              expect((requestAttributes[.posixPermissions] as! NSNumber).intValue & 0o777 == 0o600, "stop request is private")
              expect((sessionAttributes[.posixPermissions] as! NSNumber).intValue & 0o777 == 0o700, "stop request belongs to a private session directory")
              let modification = requestAttributes[.modificationDate] as! Date
              installClicked()
              let repeatedAttributes = try FileManager.default.attributesOfItem(atPath: request.path)
              expect(repeatedAttributes[.modificationDate] as? Date == modification, "repeated stop cannot rewrite the request")
              pump { !isRunning }
              expect(workerReportedStopped && lastExitStatus == 0 && featureStates["path_copier"] == "succeeded" && featureStates["file-create"] == "skipped", "worker acknowledgement preserves current success and marks later work unexecuted")
              expect(logTextView!.string.contains("current unit completed safely"), "the current worker was allowed to finish without termination")
              expect(!logTextView!.string.contains("JOBS_MANAGER_STOPPED"), "stop control protocol stays out of visible logs")
              expect(progressIndicator!.doubleValue == 1 && progressIndicator!.maxValue == 2, "skipped work does not count as settled work")
              expect(executionLabel!.stringValue.hasPrefix("已停止") && executionLabel!.stringValue.contains("失败 0") && executionLabel!.stringValue.contains("未执行 1") && executionLabel!.stringValue.contains("50.0%"), "stopped work is distinguished from failure and never fabricates full progress")
              expect(statusLabels["file-create"]!.stringValue == "未执行" && installButton!.title == "安装 / 更新" && installButton!.isEnabled && closeButton!.isEnabled, "finished stop restores normal reusable controls")
              arguments = try Data(contentsOf: capture).split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
              expect(arguments.contains("--stop-request-file") && arguments.contains(request.path), "the worker receives its own stop path")
              try? FileManager.default.removeItem(at: logURL!.deletingLastPathComponent())
              setenv("JOBS_TEST_WORKER_MODE", "stop-failure", 1)
              installClicked()
              pump { featureStates["path_copier"] == "running" }
              installButton!.performClick(nil)
              pump { !isRunning }
              expect(lastExitStatus == 29 && !workerReportedStopped && featureStates.values.allSatisfy { $0 == "failed" }, "a crash without STOPPED acknowledgement is not mislabeled as cooperative cancellation")
              expect(executionLabel!.stringValue.hasPrefix("任务失败"), "abnormal exit remains a failure despite a pending stop request")
              try? FileManager.default.removeItem(at: logURL!.deletingLastPathComponent())
              setenv("JOBS_TEST_WORKER_MODE", "blocked", 1)
              setenv("JOBS_FINDER_RESPONSIBLE_APP", "/fixture/Jobs右键菜单管理面板.app", 1)
              installClicked()
              pump { !isRunning }
              expect(lastExitStatus == 77 && appManagementBlocked, "App Management denial is a distinct blocked outcome")
              expect(executionLabel!.stringValue.hasPrefix("需要App管理授权") && featureStates["file-create"] == "skipped", "authorization denial does not turn later work into completed or failed work")
              expect(privacySettingsButton!.isEnabled && !privacySettingsButton!.isHidden && privacySettingsButton!.title == "打开隐私与安全性设置", "blocked completion exposes an explicit settings button")
              expect(logTextView!.string.contains("/fixture/Jobs右键菜单管理面板.app") && !logTextView!.string.contains("JOBS_MANAGER_BLOCKED"), "logs identify the stable responsible app without leaking the control protocol")
              let controls = privacySettingsButton!.superview!.subviews.compactMap { $0 as? NSControl }.filter { !$0.isHidden }
              for (index, control) in controls.enumerated() {
                  expect(control.superview!.bounds.insetBy(dx: -0.5, dy: -0.5).contains(control.frame), "blocked header controls remain in bounds")
                  for other in controls.dropFirst(index + 1) {
                      expect(!control.frame.intersects(other.frame), "settings action does not overlap cleanup or header controls")
                  }
              }
              var openedSettings = false
              privacySettingsOpener = { openedSettings = true }
              expect(!openedSettings, "authorization settings never open automatically")
              privacySettingsButton!.performClick(nil)
              expect(openedSettings, "the settings button invokes only the explicit user action")
              try? FileManager.default.removeItem(at: logURL!.deletingLastPathComponent())
              unsetenv("JOBS_FINDER_RESPONSIBLE_APP")
              unsetenv("JOBS_TEST_WORKER_MODE")
          }
          func verifyWorkerRoute(path: String, location: String, operation: String, cleanup: Bool) throws {
              actionControl!.selectedSegment = operation == "uninstall" ? 1 : 0
              actionChanged()
              installLocationButton!.state = location == "applications" ? .on : .off
              installLocationChanged()
              let expectedCleanup = operation == "install" && location == "applications" && cleanup
              cleanupBuildProductsButton!.state = cleanup ? .on : .off
              cleanupBuildProductsChanged()
              expect(cleanupBuildProducts == expectedCleanup, "only an Applications installation accepts cleanup")
              checkboxes.first { $0.option.identifier == "path_copier" }!.button.performClick(nil)
              installClicked()
              expect(isRunning && !installLocationButton!.isEnabled, "worker locks the selected destination")
              expect(!cleanupBuildProductsButton!.isEnabled, "worker locks cleanup selection")
              cleanupBuildProductsButton!.performClick(nil)
              expect(cleanupBuildProducts == expectedCleanup, "disabled cleanup cannot change the current job")
              cleanupBuildProductsButton!.state = expectedCleanup ? .off : .on
              cleanupBuildProductsChanged()
              expect(cleanupBuildProducts == expectedCleanup && cleanupBuildProductsButton!.state == (expectedCleanup ? .on : .off), "active work rejects programmatic cleanup changes")
              installLocationButton!.performClick(nil)
              expect(installLocation == location, "disabled checkbox cannot change the current target")
              installLocationButton!.state = location == "applications" ? .off : .on
              installLocationChanged()
              expect(installLocation == location && installLocationButton!.state == (location == "applications" ? .on : .off), "programmatic changes cannot retarget active work")
              pump { !isRunning }
              expect(lastExitStatus == 0 && featureStates["path_copier"] == "succeeded", "isolated operation completes")
              expect(installLocationButton!.isEnabled, "destination unlocks when the worker exits")
              let capture = URL(fileURLWithPath: ProcessInfo.processInfo.environment["JOBS_TEST_ARGUMENTS"]!)
              let arguments = try Data(contentsOf: capture).split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
              var expectedArguments = ["--non-interactive", "--action", operation, "--features", "path_copier", "--install-location", location]
              if expectedCleanup {
                  expectedArguments.append("--cleanup-build-products")
              }
              var normalizedArguments = arguments
              if operation == "install" {
                  let index = normalizedArguments.firstIndex(of: "--stop-request-file")!
                  let stopPath = normalizedArguments[index + 1]
                  expect(URL(fileURLWithPath: stopPath).deletingLastPathComponent() == logURL!.deletingLastPathComponent(), "install stop request belongs to the same private log session")
                  expect(!FileManager.default.fileExists(atPath: stopPath), "stop request is initially absent")
                  normalizedArguments.removeSubrange(index...(index + 1))
              }
              expect(normalizedArguments == expectedArguments, "cleanup flag appears only for an explicitly selected Applications install")
              expect(logTextView!.string.contains("安装成功后清除此轮构建产物：已勾选。") == expectedCleanup, "cleanup request is recorded only for the eligible job")
              expect(logTextView!.string.contains(location == "applications" ? "/Applications" : "构建目录"), "session log records its selected target")
              let installedDuration = installationTiming.elapsed
              let uninstalledDuration = uninstallationTiming.elapsed
              installLocationButton!.performClick(nil)
              expect(featureStates.isEmpty && runningIdentifiers.isEmpty && lastExitStatus == nil, "switching destination clears results from the former target")
              expect(!cleanupBuildProducts && cleanupBuildProductsButton!.state == .off, "destination changes discard the old job's cleanup request")
              expect(progressIndicator!.doubleValue == 0 && statusLabels["path_copier"]!.stringValue == "已选择", "the new target never inherits a successful install or uninstall status")
              expect(checkedIdentifiers() == ["path_copier"], "target change preserves the user's function selection")
              expect(installationTiming.elapsed == installedDuration && uninstallationTiming.elapsed == uninstalledDuration, "destination change preserves the independent operation histories")
              clearAllClicked()
              try? FileManager.default.removeItem(at: logURL!)
          }
      }
      let application = NSApplication.shared
      application.setActivationPolicy(.prohibited)
      application.finishLaunching()
      let fixture = CommandLine.arguments[1]
      let arguments = ["--manager", fixture, "--scope", "path_copier"]
      for invalid in ["other", "", "APPLICATIONS"] {
          do {
              _ = try FeatureSelectionController.parseArguments(arguments + ["--install-location", invalid])
              fatalError("invalid install location accepted")
          } catch {}
      }
      do {
          _ = try FeatureSelectionController.parseArguments(arguments + ["--install-location"])
          fatalError("missing install location accepted")
      } catch {}
      for theme in [NSAppearance.Name.aqua, .darkAqua] {
          application.appearance = NSAppearance(named: theme)
          for screen in [NSSize(width: 1920, height: 1080), NSSize(width: 1366, height: 768), NSSize(width: 800, height: 600)] {
              try FeatureSelectionController.parseArguments(arguments).verifyLocationControls(screen: screen)
              try FeatureSelectionController.parseArguments(["--manager", fixture]).verifyLocationControls(screen: screen)
          }
      }
      try FeatureSelectionController.parseArguments(arguments + ["--install-location", "applications"]).verifyExplicitApplicationsMode()
      try FeatureSelectionController.parseArguments([]).verifyLegacyMode()
      let controller = try FeatureSelectionController.parseArguments(arguments)
      controller.verifyEmptySelection()
      for operation in ["install", "uninstall"] {
          for location in ["build", "applications"] {
              for cleanup in [false, true] {
                  try controller.verifyWorkerRoute(path: fixture, location: location, operation: operation, cleanup: cleanup)
              }
          }
      }
      try FeatureSelectionController.parseArguments(["--manager", fixture, "--scope", "path_copier,file-create"]).verifyIndependentCleanupAndCooperativeStop(path: fixture)
      print("Deployment location checkbox, layout and isolated worker routes passed")
    SWIFT
    Dir.mktmpdir('jobs-deployment-panel-') do |directory|
      fixture = File.join(directory, 'worker 中文.zsh')
      capture = File.join(directory, 'arguments')
      File.write(fixture, <<~'ZSH')
        printf '%s\0' "$@" > "$JOBS_TEST_ARGUMENTS"
        if [[ "${JOBS_TEST_WORKER_MODE:-}" == cleanup ]]; then
          (( $# == 7 )) && [[ "$3" == cleanup && "$5" == path_copier && "$7" == applications && "$JOBS_FINDER_CLEANUP_BUILD_PRODUCTS" == 0 ]] || exit 87
          /bin/sleep 0.1
          print 'JOBS_MANAGER_EVENT\tpath_copier\tsucceeded\t清理完成'
          exit 0
        fi
        if [[ "${JOBS_TEST_WORKER_MODE:-}" == blocked ]]; then
          print 'JOBS_MANAGER_EVENT\tpath_copier\trunning\t正在安装'
          print 'JOBS_MANAGER_BLOCKED\tapp-management\t77'
          print 'JOBS_MANAGER_EVENT\tpath_copier\tfailed\t需要App管理授权'
          print 'JOBS_MANAGER_EVENT\tfile-create\tskipped\t等待授权后重新执行'
          exit 77
        fi
        if [[ "${JOBS_TEST_WORKER_MODE:-}" == stop-failure ]]; then
          print 'JOBS_MANAGER_EVENT\tpath_copier\trunning\t正在执行当前功能'
          /bin/sleep 0.15
          print 'abnormal worker exit' >&2
          exit 29
        fi
        if [[ "${JOBS_TEST_WORKER_MODE:-}" == stop ]]; then
          stop_file=""
          for (( i=1; i<=$#; i++ )); do
            [[ "${@[i]}" != --stop-request-file ]] || stop_file="${@[i+1]}"
          done
          [[ "$3" == install && "$5" == path_copier,file-create && -n "$stop_file" && ! -e "$stop_file" ]] || exit 88
          print 'JOBS_MANAGER_EVENT\tpath_copier\trunning\t正在执行当前功能'
          /bin/sleep 0.35
          print 'current unit completed safely'
          print 'JOBS_MANAGER_EVENT\tpath_copier\tsucceeded\t当前功能完成'
          [[ -f "$stop_file" ]] || exit 89
          print 'JOBS_MANAGER_EVENT\tfile-create\tskipped\t后续功能未执行'
          print 'JOBS_MANAGER_STOPPED\t用户请求停止'
          exit 0
        fi
        [[ "$1" == --non-interactive && "$2" == --action && "$4" == --features && "$5" == path_copier && "$6" == --install-location ]] || exit 81
        [[ "$3" == install || "$3" == uninstall ]] || exit 82
        [[ "$7" == build || "$7" == applications ]] || exit 83
        operation="$3"
        shift 7
        expected_cleanup=0
        has_stop=0
        while (( $# )); do
          case "$1" in
            --stop-request-file)
              (( $# >= 2 )) && [[ "$operation" == install && ! -e "$2" ]] || exit 84
              has_stop=1
              shift
              ;;
            --cleanup-build-products) expected_cleanup=1 ;;
            *) exit 84 ;;
          esac
          shift
        done
        [[ "$operation" != install || "$has_stop" == 1 ]] || exit 86
        [[ "${JOBS_FINDER_CLEANUP_BUILD_PRODUCTS:-}" == "$expected_cleanup" ]] || exit 85
        /bin/sleep 0.15
        print 'JOBS_MANAGER_EVENT\tpath_copier\tsucceeded\t完成隔离任务'
      ZSH
      path = File.join(directory, 'main.swift')
      binary = File.join(directory, 'panel-check')
      File.write(path, source + "\n" + harness)
      output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', path, '-o', binary)
      assert status.success?, output
      output, status = Open3.capture2e({ 'JOBS_TEST_ARGUMENTS' => capture, 'JOBS_FINDER_CLEANUP_BUILD_PRODUCTS' => '1' }, binary, fixture)
      assert status.success?, output
      assert_includes output, 'Deployment location checkbox, layout and isolated worker routes passed'
    end
  end
end
