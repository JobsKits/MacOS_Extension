# frozen_string_literal: true
# 编译真实业务与生产宿主入口；UI、应用循环及系统退出由硬边界替身承接。
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'json'

class FileCreationTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  CONTEXT = File.join(ROOT, 'Shared/FileCreationContext/FileCreationContext.swift')
  REQUEST = File.join(ROOT, 'Shared/FileCreationRequest/FileCreationRequest.swift')

  def test_filesystem_transport_and_dialog_controller_use_only_temporary_fixtures
    paths = [CONTEXT, REQUEST,
             File.join(ROOT, 'JobsFileCreator/FileCreationService/FileCreationService.swift'),
             File.join(ROOT, 'JobsFileCreator/FileCreationController/FileCreationController.swift'),
             File.join(__dir__, 'FileCreationBehaviorTests.swift')]
    output = compile_and_run(paths)
    assert_match(/PASS: \d+ file creation behavior assertions/, output)
  end

  def test_actual_production_entry_retains_delegate_and_dispatches_each_click_once
    delegate = File.read(File.join(ROOT, 'JobsFileCreator/AppDelegate.swift'))
    refute_match(/^\s*@main\b/, delegate)
    delegate = delegate.gsub('NSAppleEventManager.shared()', 'TestAppleEventManager.shared()')
    delegate = delegate.gsub('NSApp.terminate(nil)', 'TestApplication.shared.terminate(nil)')
    entry = File.read(File.join(ROOT, 'JobsFileCreator/main.swift'))
    assert_includes entry, 'NSApplication.shared.byDelegate(appDelegate)'
    entry = entry.gsub('NSApplication.shared', 'TestApplication.shared').gsub('NSApplicationMain(', 'TestApplicationMain(')
    source = HOST_BOUNDARIES + "\n" + delegate + "\n" + entry + <<~'SWIFT'
      expect(TestApplication.mainCalls == 1, "production entry enters app main once")
      expect(TestApplication.shared.delegate != nil, "production entry continues to strongly retain the weak delegate")
      print("PASS: \(hostAssertions) production bootstrap and single-dispatch assertions")
    SWIFT
    Dir.mktmpdir('jobs-file-create-host-') do |directory|
      path = File.join(directory, 'main.swift')
      File.write(path, source)
      output = compile_and_run([CONTEXT, REQUEST, path], directory)
      assert_match(/PASS: \d+ production bootstrap and single-dispatch assertions/, output)
    end
  end

  def test_project_embeds_one_extension_and_main_belongs_only_to_the_host
    output, result = Open3.capture2e('/usr/bin/plutil', '-convert', 'json', '-o', '-', File.join(ROOT, 'JobsFileCreator.xcodeproj/project.pbxproj'))
    assert result.success?, output
    objects = JSON.parse(output).fetch('objects')
    main_ref = objects.select { |_, value| value['isa'] == 'PBXFileReference' && File.basename(value['path'].to_s) == 'main.swift' }
    assert_equal 1, main_ref.length
    source_targets = objects.values.map do |target|
      next unless target['isa'] == 'PBXNativeTarget'
      contains_main = target['buildPhases'].any? do |phase_id|
        phase = objects.fetch(phase_id)
        phase['isa'] == 'PBXSourcesBuildPhase' && phase['files'].any? { |build| objects.fetch(build)['fileRef'] == main_ref.keys.first }
      end
      target['name'] if contains_main
    end.compact
    assert_equal ['JobsFileCreator'], source_targets
    extensions = objects.values.select { |object| object['isa'] == 'PBXNativeTarget' && object['productType'] == 'com.apple.product-type.app-extension' }
    assert_equal ['JobsFileCreatorFinderSync'], extensions.map { |target| target['name'] }
    phases = objects.values.select { |object| object['isa'] == 'PBXCopyFilesBuildPhase' && object['dstSubfolderSpec'].to_s == '13' }
    assert_equal 1, phases.length
    assert_equal 1, phases.first['files'].length
  end

  def test_actual_editing_menu_routes_shortcuts_to_the_text_responder
    Dir.mktmpdir('jobs-file-create-edit-menu-') do |directory|
      path = File.join(directory, 'main.swift')
      File.write(path, <<~'SWIFT')
        import AppKit
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.finishLaunching()
        FileCreatorInterface.installEditingMenu()
        let edit = application.mainMenu!.items[1].submenu!
        let expected: [(Selector, String)] = [
            (#selector(NSText.cut(_:)), "x"),
            (#selector(NSText.copy(_:)), "c"),
            (#selector(NSText.paste(_:)), "v"),
            (#selector(NSText.selectAll(_:)), "a")
        ]
        for value in expected {
            let matches = edit.items.filter { $0.action == value.0 }
            precondition(matches.count == 1, "Each text editing action appears once")
            let item = matches[0]
            precondition(item.keyEquivalent == value.1)
            precondition(item.target == nil, "Edit actions must follow the text responder")
            precondition(item.keyEquivalentModifierMask == .command)
        }
        let icon = FileCreatorInterface.fileIcon
        precondition(icon.isValid && icon.size.width > 0 && icon.size.height > 0, "File dialog uses a real system file icon")
        let alert = NSAlert.make()
        let defaultIcon = alert.icon?.tiffRepresentation
        alert.byIcon(icon)
        precondition(alert.icon === icon, "File icon is assigned to the actual alert")
        precondition(alert.icon?.tiffRepresentation != defaultIcon, "Generic file icon replaces the application placeholder")
        print("PASS: native text editing shortcuts")
      SWIFT
      output = compile_and_run([File.join(ROOT, 'Shared/FileCreatorFactories/FileCreatorFactories.swift'),
                                File.join(ROOT, 'JobsFileCreator/FileCreatorInterface/FileCreatorInterface.swift'), path], directory)
      assert_includes output, 'PASS: native text editing shortcuts'
    end
  end

  private

  def compile_and_run(paths, directory = nil)
    unless directory
      return Dir.mktmpdir('jobs-file-create-tests-') { |temp| compile_and_run(paths, temp) }
    end
    binary = File.join(directory, 'test')
    output, result = Open3.capture2e('/usr/bin/xcrun', 'swiftc', *paths, '-o', binary)
    assert result.success?, output
    output, result = Open3.capture2e(binary)
    assert result.success?, output
    output
  end

  HOST_BOUNDARIES = <<~'SWIFT'
    import AppKit

    var hostAssertions = 0
    func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        hostAssertions += 1
        if !value() {
            fatalError(message)
        }
    }

    final class TestApplication {
        static let shared = TestApplication()
        static var mainCalls = 0
        weak var delegate: NSApplicationDelegate?
        var terminations = 0

        @discardableResult
        func byDelegate(_ value: NSApplicationDelegate) -> Self {
            delegate = value
            return self
        }

        func terminate(_ sender: Any?) {
            expect(Thread.isMainThread, "idle exit uses the main thread")
            terminations += 1
        }
    }

    final class TestAppleEventManager {
        static let instance = TestAppleEventManager()
        weak var handler: AnyObject?
        var selector: Selector?
        static func shared() -> TestAppleEventManager {
            return instance
        }

        func setEventHandler(_ object: Any, andSelector selector: Selector,
                             forEventClass eventClass: AEEventClass, andEventID eventID: AEEventID) {
            expect(eventClass == AEEventClass(kInternetEventClass) && eventID == AEEventID(kAEGetURL), "cold-start Get URL handler is registered")
            handler = object as AnyObject
            self.selector = selector
        }
    }

    enum FileCreatorInterface {
        static var failures = 0
        static var menuInstallations = 0
        static func installEditingMenu() {
            menuInstallations += 1
        }
        static func showFailure(_ message: String) {
            expect(!message.isEmpty, "invalid request has a visible reason")
            failures += 1
        }
    }

    struct FileCreationController {
        static var directories: [URL] = []
        func run(in directory: URL) {
            Self.directories.append(directory)
        }
    }

    func TestApplicationMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32 {
        TestApplication.mainCalls += 1
        expect(argc > 0 && argv[0] != nil, "real command line reaches production entry")
        expect(TestApplication.shared.delegate is AppDelegate, "production delegate is attached before application main")
        autoreleasepool {
            TestApplication.shared.delegate?.applicationWillFinishLaunching?(Notification(name: NSApplication.willFinishLaunchingNotification))
        }
        expect(TestApplication.shared.delegate != nil, "entry strongly owns the weak delegate")
        expect(FileCreatorInterface.menuInstallations == 1, "production lifecycle prepares filename editing shortcuts")
        expect(TestAppleEventManager.instance.handler === TestApplication.shared.delegate, "lifecycle registers the attached delegate")
        let delegate = TestApplication.shared.delegate as! AppDelegate
        let root = FileManager.default.temporaryDirectory
        let first = FileCreationRequest(directoryURL: root)!.url!
        delegate.application(NSApplication.shared, open: [first, first])
        expect(FileCreationController.directories.isEmpty, "cold-start URL waits for launch completion")
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        expect(FileCreationController.directories == [root.standardizedFileURL], "duplicate system callback shows one prompt")
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kInternetEventClass),
                                          eventID: AEEventID(kAEGetURL),
                                          targetDescriptor: nil,
                                          returnID: AEReturnID(kAutoGenerateReturnID),
                                          transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: first.absoluteString), forKeyword: keyDirectObject)
        _ = delegate.perform(TestAppleEventManager.instance.selector!, with: event, with: NSAppleEventDescriptor.null())
        expect(FileCreationController.directories.count == 1, "AppleEvent duplicate also shares click deduplication")
        delegate.application(NSApplication.shared, open: [FileCreationRequest(directoryURL: root)!.url!])
        expect(FileCreationController.directories.count == 2, "new click remains actionable after a completed dialog")
        delegate.application(NSApplication.shared, open: [URL(string: "jobsfilecreator://wrong")!])
        expect(FileCreatorInterface.failures == 1 && FileCreationController.directories.count == 2, "invalid URL cannot create a file")
        expect(TestApplication.shared.terminations == 0, "idle exit waits until URL dispatch completes")
        let deadline = Date().addingTimeInterval(2)
        while TestApplication.shared.terminations == 0 && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        expect(TestApplication.shared.terminations == 1, "idle generations produce one final exit")
        expect(TestApplication.shared.delegate != nil && TestAppleEventManager.instance.handler != nil, "entry retains delegate throughout the complete event loop")
        return 0
    }
  SWIFT
end
