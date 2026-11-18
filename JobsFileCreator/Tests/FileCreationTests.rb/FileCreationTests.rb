# frozen_string_literal: true
# 编译真实业务与生产宿主入口；UI、应用循环及系统退出由硬边界替身承接。
# JOBS_TERMINAL_STYLE_GUARD_V1_BEGIN
if $PROGRAM_NAME == __FILE__
  # 直接运行时由 fork 父进程保护配色；子进程继续原文件，不重放 Ruby 参数和预载模块。
  def jobs_terminal_style_bootstrap_v1
    return unless $PROGRAM_NAME == __FILE__
    plain = lambda do
      ENV.update('PLAIN_OUTPUT' => '1', 'NO_COLOR' => '1', 'FORCE_COLOR' => '0',
                 'CLICOLOR' => '0', 'ANSI_COLORS_DISABLED' => '1', 'npm_config_color' => 'false')
    end
    notify = lambda do |message|
      encoding = $stderr.external_encoding || Encoding::UTF_8
      $stderr.write((message + "\n").encode(encoding, invalid: :replace, undef: :replace))
    end
    return unless $stdin.tty? && $stdout.tty?
    return if ENV.key?('NO_COLOR') || ENV['PLAIN_OUTPUT'] == '1' ||
              ENV['IS_SOURCETREE_RUNTIME'] == '1' ||
              ENV.keys.any? { |key| key.match?(/\A(?:SOURCETREE|SOURCE_TREE)/i) }
    return if ['', 'dumb'].include?(ENV.fetch('TERM', ''))
    if File::ALT_SEPARATOR == '\\' || !Process.respond_to?(:fork) ||
       Thread.list.length > 1 || ENV['TMUX'] || ENV['STY']
      plain.call
      return
    end
    tty_name = IO.popen(['tty'], err: File::NULL, &:read).strip
    groups = IO.popen(['ps', '-o', 'pgid=', '-o', 'tpgid=', '-p', Process.pid.to_s], err: File::NULL, &:read).split
    unless tty_name.match?(%r{\A/dev/[A-Za-z0-9_./-]+\z}) && groups.length == 2 &&
           groups.all? { |group| group.match?(/\A\d+\z/) } && groups[0].to_i > 0 && groups[0] == groups[1]
      plain.call
      return
    end
    owner = ENV['JOBS_TERMINAL_STYLE_OWNER']
    if ENV['JOBS_TERMINAL_STYLE_TTY'] == tty_name && owner && owner.match?(/\A\d+\z/)
      begin
        Process.kill(0, owner.to_i)
        return
      rescue Errno::ESRCH, Errno::EPERM
      end
    end
    require 'io/console'
    require 'tmpdir'
    if Thread.list.length > 1
      plain.call
      return
    end
    tty = File.open('/dev/tty', 'r+')
    tty.binmode
    tty.sync = true
    keys = ['10', '11', '12'] + (0..15).map { |index| "4;#{index}" }
    palette = %w[000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee
                 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff]
    targets = { '10' => 'ffffff', '11' => '000000', '12' => 'ffffff' }
    palette.each_with_index { |color, index| targets["4;#{index}"] = color }
    query = lambda do |key|
      tty.write("\e]#{key};?\a")
      bytes = ''.b
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.3
      loop do
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return nil if remaining <= 0 || !IO.select([tty], nil, nil, remaining)
        piece = tty.read_nonblock(256, exception: false)
        next if piece == :wait_readable
        return nil unless piece && !piece.empty?
        bytes << piece
        return nil if bytes.bytesize > 256 || !bytes.start_with?("\e".b)
        break if bytes.end_with?("\a".b) || bytes.end_with?("\e\\".b)
      end
      match = bytes.match(/\A\e\]#{Regexp.escape(key)};rgb:([0-9a-fA-F]{1,4})\/([0-9a-fA-F]{1,4})\/([0-9a-fA-F]{1,4})(?:\a|\e\\)\z/n)
      return nil unless match
      components = match.captures.map { |hex| (hex.to_i(16) * 65535.0 / (16**hex.length - 1)).round }
      { raw: bytes, rgb: components }
    rescue IOError, SystemCallError
      nil
    end
    snapshot = lambda do
      values = {}
      tty.raw(min: 0, time: 0, intr: true) do
        keys.each do |key|
          value = query.call(key)
          return nil unless value
          values[key] = value
        end
      end
      values
    rescue IOError, SystemCallError, ArgumentError
      nil
    end
    original = snapshot.call
    unless original
      notify.call('终端不支持完整配色保存，或启动时收到其它输入；保留原配色并使用纯文本。')
      tty.close
      plain.call
      return
    end
    directory = Dir.mktmpdir('jobs-terminal-style-')
    recovery = File.join(directory, 'restore.sh')
    original_bytes = keys.map { |key| original.fetch(key).fetch(:raw) }.join
    recovery_source = "#!/bin/sh\n" \
      "[ -t 0 ] && [ \"$(tty)\" = '#{tty_name}' ] || { printf '请在原终端运行恢复入口。\\n' >&2; exit 1; }\n" \
      "printf '本操作会覆盖此终端当前配色。确认恢复脚本启动前的配色，请输入 YES：' >&2\n" \
      "IFS= read -r jobs_restore_choice\n[ \"$jobs_restore_choice\" = YES ] || exit 1\n" \
      "printf '%s\\033[0m' '#{original_bytes}' > /dev/tty\n"
    File.open(recovery, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.binmode
      file.write(recovery_source.b)
    end
    notify.call("本次终端临时使用黑底白字；强退后恢复入口：sh \"#{recovery}\"")
    changed = false
    applied = nil
    # 比较仍生效的本轮颜色，只恢复未被用户另行修改的项。
    cleanup = lambda do
      current = applied && snapshot.call
      unless current
        notify.call("终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh \"#{recovery}\"")
        return false
      end
      conflicts = []
      restore_bytes = ''.b
      keys.each do |key|
        if current.fetch(key).fetch(:rgb) == applied.fetch(key).fetch(:rgb)
          restore_bytes << original.fetch(key).fetch(:raw)
        else
          conflicts << key
        end
      end
      tty.write(restore_bytes + "\e[0m".b)
      if conflicts.empty?
        File.unlink(recovery)
        Dir.rmdir(directory)
        true
      else
        notify.call("检测到运行期间的配色变更，已保留这些项：#{conflicts.join(' ')}")
        notify.call("确认要覆盖后续改色时才使用恢复入口：sh \"#{recovery}\"")
        false
      end
    rescue IOError, SystemCallError
      notify.call("终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh \"#{recovery}\"")
      false
    end
    child_pid = nil
    guardian = false
    interrupted = nil
    previous_signals = {}
    %w[INT TERM HUP].each do |name|
      previous_signals[name] = Signal.trap(name) do
        interrupted = name
        if child_pid && name != 'INT'
          begin
            Process.kill(name, child_pid)
          rescue Errno::ESRCH
          end
        end
      end
    end
    begin
      changed = true
      tty.write(targets.map { |key, color| "\e]#{key};##{color}\a" }.join + "\e[0m")
      applied = snapshot.call
      unless applied
        notify.call('无法核实本次临时配色，已停止启动业务。')
        raise SystemExit, 1
      end
      desired = targets.all? do |key, hex|
        rgb = hex.scan(/../).map { |component| component.to_i(16) * 257 }
        applied.fetch(key).fetch(:rgb).zip(rgb).all? { |actual, expected| (actual - expected).abs <= 255 }
      end
      unless desired
        notify.call('终端未接受本次配色，恢复后使用纯文本。')
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      if interrupted
        raise SystemExit, 128 + Signal.list.fetch(interrupted)
      end
      if Thread.list.length > 1
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      $stdout.flush
      $stderr.flush
      begin
        child_pid = Process.fork
      rescue NotImplementedError, SystemCallError
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      unless child_pid
        changed = false
        ENV['JOBS_TERMINAL_STYLE_TTY'] = tty_name
        ENV['JOBS_TERMINAL_STYLE_OWNER'] = Process.ppid.to_s
        raise SystemExit, 128 + Signal.list.fetch(interrupted) if interrupted
        return
      end
      guardian = true
      result = nil
      loop do
        begin
          _, result = Process.wait2(child_pid)
          break
        rescue Interrupt, Errno::EINTR
        end
      end
      status_code = result.exitstatus || 128 + result.termsig
      %w[INT TERM HUP].each { |name| Signal.trap(name, 'IGNORE') }
      restored = cleanup.call
      changed = false
      status_code = 1 if !restored && status_code.zero?
      tty.close
      Process.exit!(status_code)
    ensure
      if changed
        %w[INT TERM HUP].each { |name| Signal.trap(name, 'IGNORE') }
        cleanup.call
      end
      previous_signals.each { |name, handler| Signal.trap(name, handler) } unless guardian
      tty.close unless tty.closed?
    end
  rescue IOError, SystemCallError, LoadError => error
    if guardian
      notify.call("终端保护监督进程异常：#{error.message}")
      Process.exit!(1)
    end
    raise SystemExit, 1 if changed
    notify.call("终端保护不可用，使用纯文本：#{error.message}")
    plain.call
  end
  jobs_terminal_style_bootstrap_v1

end
# JOBS_TERMINAL_STYLE_GUARD_V1_END

require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'json'

class FileCreationTests < Minitest::Test
  ROOT = File.expand_path('..', File.dirname(__dir__))
  CONTEXT = File.join(ROOT, 'Shared/FileCreationContext/FileCreationContext.swift')
  REQUEST = File.join(ROOT, 'Shared/FileCreationRequest/FileCreationRequest.swift')

  def test_filesystem_transport_and_dialog_controller_use_only_temporary_fixtures
    paths = [CONTEXT, REQUEST,
             File.join(ROOT, 'JobsFileCreator/FileCreationService/FileCreationService.swift'),
             File.join(ROOT, 'JobsFileCreator/FileCreationController/FileCreationController.swift'),
             File.join(File.dirname(__dir__), 'FileCreationBehaviorTests.swift')]
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
