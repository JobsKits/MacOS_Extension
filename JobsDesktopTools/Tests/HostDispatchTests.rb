# frozen_string_literal: true
# 编译真实宿主，用动作替身承接回调，不打开终端、不改偏好或模拟器。
require 'minitest/autorun'
require 'tmpdir'
require 'open3'

class DesktopHostDispatchTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  def test_two_url_callbacks_dispatch_each_enabled_action_only_once
    Dir.mktmpdir('jobs-desktop-host-tests-') do |directory|
      files = %w[Shared/DesktopMenuAction/DesktopMenuAction.swift Shared/DesktopMenuRequest/DesktopMenuRequest.swift JobsDesktopTools/AppDelegate.swift]
      source = files.map { |filename| File.read(File.join(ROOT, filename)) }.join("\n")
      main = File.join(directory, 'main.swift')
      binary = File.join(directory, 'host-tests')
      File.write(main, source + "\n" + fixture)
      output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', main, '-o', binary)
      assert status.success?, output
      output, status = Open3.capture2e(binary)
      assert status.success?, output
      assert_includes output, 'PASS: 12 desktop host assertions'
    end
  end

  private

  def fixture
    <<~'SWIFT'
      enum DesktopMenuConfiguration {
          static var enabled = Set(DesktopMenuAction.allCases)
          static func enabledFeatures() -> Set<DesktopMenuAction> { return enabled }
      }
      enum DesktopAlert {
          static var count = 0
          static func show(_ message: String) { count += 1 }
      }
      enum Operations {
          static var actions: [DesktopMenuAction] = []
          static var fails = false
      }
      struct DesktopActionExecutor {
          func perform(_ request: DesktopMenuRequest) throws {
              Operations.actions.append(request.action)
              if Operations.fails { throw NSError(domain: "Fixture", code: 1) }
          }
      }
      var checks = 0
      func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
          checks += 1
          if !condition() { fatalError(message) }
      }
      func waitForCallbacks() {
          let until = Date().addingTimeInterval(0.1)
          while Date() < until { _ = RunLoop.current.run(mode: .default, before: until) }
      }
      func deliverAppleEvent(_ url: URL, to delegate: AppDelegate) {
          let event = NSAppleEventDescriptor(eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL), targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
          event.setParam(NSAppleEventDescriptor(string: url.absoluteString), forKeyword: keyDirectObject)
          _ = delegate.perform(NSSelectorFromString("handleOpenURL:withReplyEvent:"), with: event, with: NSAppleEventDescriptor.null())
      }
      let delegate = AppDelegate()
      for action in DesktopMenuAction.allCases {
          let url = DesktopMenuRequest(action: action, showsHiddenFiles: action == .hiddenFiles ? true : nil).url!
          delegate.application(NSApplication.shared, open: [url])
          deliverAppleEvent(url, to: delegate)
          delegate.application(NSApplication.shared, open: [url])
          waitForCallbacks()
          expect(Operations.actions.filter { $0 == action }.count == 1, "two URL delivery callbacks dispatch each action once")
      }
      expect(DesktopAlert.count == 0, "successful actions show no alert")
      DesktopMenuConfiguration.enabled = []
      delegate.application(NSApplication.shared, open: [DesktopMenuRequest(action: .createIOS).url!])
      waitForCallbacks()
      expect(Operations.actions.count == 6, "disabled feature does not reach executor")
      expect(DesktopAlert.count == 1, "disabled feature reports failure")
      delegate.application(NSApplication.shared, open: [URL(string: "jobsdesktoptools://perform/unknown?cmd=anything")!])
      expect(Operations.actions.count == 6, "invalid request is not dispatched")
      DesktopMenuConfiguration.enabled = [.hiddenFiles]
      Operations.fails = true
      delegate.application(NSApplication.shared, open: [DesktopMenuRequest(action: .hiddenFiles, showsHiddenFiles: false).url!])
      waitForCallbacks()
      expect(Operations.actions.last == .hiddenFiles, "separate explicit desired state remains usable")
      expect(DesktopAlert.count == 3, "invalid request and executor failure both surface")
      print("PASS: \(checks) desktop host assertions")
    SWIFT
  end
end
