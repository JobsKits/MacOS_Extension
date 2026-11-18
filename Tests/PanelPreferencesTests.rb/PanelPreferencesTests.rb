# frozen_string_literal: true
# Jobs：在独立 UserDefaults suite 和原生 AppKit 窗口中验证主题、语言及活动状态保留。
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
      final class IsolatedGroupDraggingInfo: NSObject, NSDraggingInfo {
          var draggingDestinationWindow: NSWindow?
          var draggingSourceOperationMask: NSDragOperation = .move
          var draggingLocation = NSPoint.zero
          var draggedImageLocation = NSPoint.zero
          var draggedImage: NSImage? = nil
          let draggingPasteboard = NSPasteboard.withUniqueName()
          var draggingSource: Any?
          var draggingSequenceNumber = 1
          var draggingFormation: NSDraggingFormation = .none
          var animatesToDestination = false
          var numberOfValidItemsForDrop = 1
          var springLoadingHighlight: NSSpringLoadingHighlight = .none
          func slideDraggedImage(to screenPoint: NSPoint) {}
          override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { return nil }
          func resetSpringLoading() {}
          func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
      }
      extension FeatureSelectionController {
          func writePreview(name: String, dark: Bool = false) {
              guard let directory = ProcessInfo.processInfo.environment["JOBS_PANEL_PREVIEW_DIR"],
                    let view = window?.contentView,
                    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                  return
              }
              view.cacheDisplay(in: view.bounds, to: bitmap)
              let image = NSImage(size: view.bounds.size)
              image.lockFocus()
              (dark ? NSColor.black : NSColor.white).setFill()
              NSRect(origin: .zero, size: view.bounds.size).fill()
              let foreground = NSImage(size: view.bounds.size)
              foreground.addRepresentation(bitmap)
              foreground.draw(in: NSRect(origin: .zero, size: view.bounds.size), from: .zero, operation: .sourceOver, fraction: 1)
              image.unlockFocus()
              if let data = image.tiffRepresentation, let rendered = NSBitmapImageRep(data: data) {
                  try! rendered.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
              }
          }

          func verifyLocalizedBounds(_ control: NSControl, context: String) {
              let font = control.font ?? NSFont.systemFont(ofSize: 13)
              let text = (control as? NSButton)?.title ?? control.stringValue
              let titleWidth = control is NSButton ? (control.cell?.titleRect(forBounds: control.bounds).width ?? control.frame.width) : control.frame.width - 4
              let bounds = (text as NSString).boundingRect(with: NSSize(width: titleWidth, height: .greatestFiniteMagnitude),
                  options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
              expect(control.frame.height + 0.5 >= ceil(bounds.height), "\(context) retains complete localized glyph height: \(text), frame \(control.frame), titleWidth \(titleWidth), needed \(bounds)")
              if let parent = control.superview {
                  expect(parent.bounds.insetBy(dx: -0.5, dy: -0.5).contains(control.frame), "\(context) stays within its parent: \(control.frame), bounds \(parent.bounds)")
              }
          }

          func verifyInternationalLayout() {
              managerPath = "/dev/null"
              installLocation = "applications"
              for size in [NSSize(width: 1440, height: 900), NSSize(width: 1024, height: 768), NSSize(width: 800, height: 600)] {
                  buildWindow(screenSize: size)
                  print("international layout \(Int(size.width)): \(window!.frame.size)")
                  let headerControls = headerView!.subviews.compactMap { $0 as? NSControl }.map { "\($0.stringValue): \($0.frame)" }
                  let groups = featureScrollView!.documentView!.subviews.compactMap { $0 as? NSBox }.map { "\($0.title): \($0.frame), content \($0.contentView!.bounds)" }
                  expect(window!.frame.width <= size.width && window!.frame.height <= size.height, "complete manager fits \(size) with every language reserved: \(window!.frame), header \(headerControls), list \(featureScrollView!.frame), groups \(groups), execution \(executionLabel!.frame)")
                  let originalWindow = window!
                  let document = featureScrollView!.documentView!
                  var columnLeading: [CGFloat: CGFloat] = [:]
                  for box in document.subviews.compactMap({ $0 as? NSBox }) {
                      for label in statusLabels.values where label.superview === box.contentView {
                          let x = label.convert(label.bounds, to: document).minX
                          if let expected = columnLeading[box.frame.minX] {
                              expect(abs(x - expected) < 0.5, "status text aligns across all groups in the same visual column")
                          } else {
                              columnLeading[box.frame.minX] = x
                          }
                      }
                  }
                  for language in ManagerPanelPreferences.languages where language != "system" {
                      preferences.language = language
                      applyPanelPreferences()
                      expect(window === originalWindow, "internationalization updates existing controls")
                      let availableContent = NSWindow.contentRect(forFrameRect: NSRect(origin: .zero, size: size), styleMask: window!.styleMask)
                      expect(window!.frame.width <= size.width && window!.frame.height <= size.height, "each localized window fits the display after layout")
                      expect(window!.contentMinSize.width <= availableContent.width && window!.contentMinSize.height <= availableContent.height, "minimum size preserves the display budget including the title bar")
                      for item in checkboxes {
                          verifyLocalizedBounds(item.button, context: "\(language) feature")
                      }
                      for controls in groupControls {
                          verifyLocalizedBounds(controls.summary, context: "\(language) group count")
                      }
                      for state in ["idle", "selected", "waiting", "running", "succeeded", "failed", "not-installed", "skipped"] {
                          featureStates = Dictionary(uniqueKeysWithValues: checkboxes.map { ($0.option.identifier, state) })
                          refreshSelectionState()
                          applyPanelPreferences()
                          for label in statusLabels.values {
                              verifyLocalizedBounds(label, context: "\(language) \(state) status")
                          }
                      }
                      verifyLocalizedBounds(installLocationButton!, context: "\(language) deployment location")
                      if !cleanupBuildProductsButton!.isHidden {
                          verifyLocalizedBounds(cleanupBuildProductsButton!, context: "\(language) automatic cleanup")
                      }
                      let footerControls = buttonRow!.subviews.compactMap { $0 as? NSControl }.filter { !$0.isHidden }
                      for (index, control) in footerControls.enumerated() {
                          verifyLocalizedBounds(control, context: "\(language) footer action")
                          expect(abs(control.frame.midY - buttonRow!.bounds.midY) < 0.5, "footer controls remain vertically centered")
                          for other in footerControls.dropFirst(index + 1) {
                              expect(!control.frame.intersects(other.frame), "localized footer actions never overlap")
                          }
                      }
                      verifyLocalizedBounds(summaryLabel!, context: "\(language) selection summary")
                      verifyLocalizedBounds(installLocationLabel!, context: "\(language) deployment description")
                      if size.width == 1440 && ["bo", "de"].contains(language) {
                          let states = ["succeeded", "running", "waiting", "failed"]
                          featureStates = Dictionary(uniqueKeysWithValues: checkboxes.enumerated().map { ($0.element.option.identifier, states[$0.offset % states.count]) })
                          preferences.theme = language == "de" ? "dark" : "light"
                          refreshSelectionState()
                          applyPanelPreferences()
                          writePreview(name: language == "de" ? "german-dark-full" : "tibetan-light-full", dark: language == "de")
                      }
                  }
              }
              preferences.language = "zh-Hans"
          }

          func verifyStatusColumns() {
              buildWindow(screenSize: NSSize(width: 1280, height: 800))
              let originalLeading = statusLabels.mapValues { $0.frame.minX }
              for language in ManagerPanelPreferences.languages where language != "system" {
                  preferences.language = language
                  for theme in ["light", "dark", "system"] {
                      preferences.theme = theme
                      for state in ["idle", "selected", "waiting", "running", "succeeded", "failed", "not-installed", "skipped"] {
                          featureStates = Dictionary(uniqueKeysWithValues: checkboxes.map { ($0.option.identifier, state) })
                          lastWorkerAction = "install"
                          refreshSelectionState()
                          applyPanelPreferences()
                          for checkbox in checkboxes {
                              let identifier = checkbox.option.identifier
                              let label = statusLabels[identifier]!
                              let icon = statusIcons[identifier]!
                              let activity = activityIndicators[identifier]!
                              expect(icon.frame == activity.frame, "status icon and spinner occupy the same fixed column")
                              expect(abs(icon.frame.midY - checkbox.button.frame.midY) < 0.5, "status icon is vertically centered on its row")
                              expect(label.frame.minX == originalLeading[identifier], "every status keeps its original text leading")
                              expect(abs(label.frame.minX - icon.frame.maxX - 8) < 0.5, "all status icons use the same text gap")
                              expect(!label.stringValue.contains("✅"), "success glyph never changes the text column")
                              expect(icon.isHidden == (state == "running"), "only the spinner is displayed during active work")
                              if state == "succeeded" {
                                  expect(icon.image != nil && icon.contentTintColor == .systemGreen && label.textColor == .systemGreen, "success has a separate green icon and green text in each theme")
                              }
                          }
                      }
                  }
                  let expectedTitle = preferences.text("自定义Finder右键菜单", language: language)
                  expect(headerTitleLabel!.stringValue == expectedTitle, "panel title has complete Simplified, Traditional and English mappings")
                  if language == "bo" {
                      expect(headerTitleLabel!.font?.familyName == "Kailasa" || headerTitleLabel!.font?.familyName == "Kokonor", "Tibetan uses an installed font with Tibetan glyph coverage")
                  }
              }
              preferences.language = "zh-Hans"
              preferences.theme = "light"
              featureStates = ["path_copier": "succeeded", "file-create": "running", "file-hash": "waiting"]
              lastWorkerAction = "install"
              refreshSelectionState()
              applyPanelPreferences()
              writePreview(name: "simplified-light-status-columns")
              preferences.theme = "system"
              print("Native fixed status columns and title mappings passed")
          }

          func verifyPinnedGroupActions() {
              let scroll = featureScrollView!
              let document = featureDocument!
              let ios = featureBoxes["ios"]!
              let controls = groupControls.first { $0.group.identifier == "ios" }!
              let expectedPlan = FeatureOption.all.map { $0.identifier }
              selectAllClicked()
              let title = ios.convert(ios.titleRect, to: document)
              scroll.contentView.scroll(to: NSPoint(x: 0, y: title.midY - scroll.contentSize.height))
              scroll.reflectScrolledClipView(scroll.contentView)
              guard let header = document.pinnedHeaders.first(where: { !$0.isHidden && $0.sourceBox === ios }) else {
                  fatalError("the original group actions remain reachable after their title scrolls out")
              }
              for button in [controls.select, controls.clear] {
                  let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: header.superview)
                  expect(header.hitTest(point) === button, "pinned toolbar preserves native button hit testing instead of starting a card drag")
              }
              controls.clear.performClick(nil)
              let iosIdentifiers = Set(controls.group.identifiers)
              expect(checkedIdentifiers() == expectedPlan.filter { !iosIdentifiers.contains($0) }, "clearing the pinned group affects only that group's feature identifiers")
              controls.select.performClick(nil)
              expect(checkedIdentifiers() == expectedPlan, "selecting the pinned group restores only its own cleared features")
              clearAllClicked()
              scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.maxY - scroll.contentSize.height)))
              scroll.reflectScrolledClipView(scroll.contentView)
              expect(ios.groupToolbar?.superview === ios.contentView && ios.groupToolbar?.frame == ios.groupToolbarFrame, "returning to the top restores the original group toolbar parent and frame")
          }

          func verifyPinnedGroupHeaders() {
              let scroll = featureScrollView!
              let document = featureDocument!
              let split = logSplitView!
              let originalUpperHeight = split.arrangedSubviews[0].frame.height
              let originalLanguage = preferences.language
              let originalTheme = preferences.theme
              let originalSelections = checkedIdentifiers()
              let originalLog = logTextView!.string
              let originalWorker = worker
              let originalStates = featureStates
              let originalToolbars = featureBoxes.mapValues { $0.groupToolbar! }
              let originalToolbarFrames = featureBoxes.mapValues { $0.groupToolbarFrame }
              defer {
                  preferences.language = originalLanguage
                  preferences.theme = originalTheme
                  applyPanelPreferences()
                  split.setPosition(originalUpperHeight, ofDividerAt: 0)
                  scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.maxY - scroll.contentSize.height)))
                  scroll.reflectScrolledClipView(scroll.contentView)
              }
              func scrollToTop(_ top: CGFloat) {
                  scroll.contentView.scroll(to: NSPoint(x: 0, y: top - scroll.contentSize.height))
                  scroll.reflectScrolledClipView(scroll.contentView)
              }
              func visibleHeader(for box: ManagerFeatureBox) -> ManagerFeaturePinnedHeader? {
                  return document.pinnedHeaders.first { !$0.isHidden && $0.sourceBox === box }
              }
              scrollToTop(document.bounds.maxY)
              expect(document.pinnedHeaders.allSatisfy { $0.isHidden }, "complete native titles at the top do not gain duplicate pinned titles")
              preferences.theme = "light"
              applyPanelPreferences()
              let ios = featureBoxes["ios"]!
              let iosTitle = ios.convert(ios.titleRect, to: document)
              scrollToTop(iosTitle.midY)
              guard let iosHeader = visibleHeader(for: ios) else {
                  fatalError("a half-clipped group title gains its complete pinned title through clip bounds notifications")
              }
              expect(iosHeader.titleField.stringValue == ios.title, "pinned title names the partially clipped group")
              expect(abs(iosHeader.frame.maxY - document.visibleRect.maxY) < 0.5, "pinned title follows the actual viewport top")
              expect(document.visibleRect.insetBy(dx: -0.5, dy: -0.5).contains(iosHeader.frame), "a pinned title stays inside its visual column and viewport")
              for box in [ios, featureBoxes["flutter"]!] {
                  let toolbar = box.groupToolbar!
                  let header = visibleHeader(for: box)!
                  let controls = groupControls.first { $0.group.identifier == box.groupIdentifier }!
                  expect(toolbar === originalToolbars[box.groupIdentifier] && toolbar.superview === header, "pinning moves the actual group toolbar without copying its controls")
                  expect(header.bounds.contains(toolbar.frame) && !toolbar.frame.intersects(header.titleField.frame), "the complete original toolbar fits below the pinned title")
                  for button in [controls.select, controls.clear] {
                      expect(header.bounds.contains(button.convert(button.bounds, to: header)) && !button.isEnabled, "pinned group buttons remain complete and disabled during the active worker")
                      expect(button.target === self && button.identifier?.rawValue == box.groupIdentifier, "pinned group buttons preserve their target and stable group identifier")
                  }
                  expect(controls.select.action == #selector(selectGroupClicked(_:)) && controls.clear.action == #selector(clearGroupClicked(_:)), "pinning preserves the original group selection actions")
                  expect(header.bounds.contains(controls.summary.convert(controls.summary.bounds, to: header)), "the complete dynamic selection count remains inside the pinned toolbar")
              }
              let flutter = featureBoxes["flutter"]!
              guard let flutterHeader = visibleHeader(for: flutter) else {
                  fatalError("the tall right column retains its own independent Flutter context")
              }
              expect(flutterHeader.frame.minX >= flutter.frame.minX && flutterHeader.frame.maxX <= flutter.frame.maxX + 0.5, "right-column pinned title stays inside the Flutter card width")
              expect(!iosHeader.frame.intersects(flutterHeader.frame), "the two visible column titles never overlap")
              writePreview(name: "simplified-light-pinned-group-titles")
              // 小视口让相邻分组边界也能通过真实滚动到达，覆盖标题推出过程。
              split.setPosition(minimumUpperPaneHeight, ofDividerAt: 0)
              scrollToTop(ios.frame.midY)
              expect(visibleHeader(for: ios) === iosHeader, "scrolling within a card reuses its pinned header")
              for language in ManagerPanelPreferences.languages where language != "system" {
                  preferences.language = language
                  for theme in ["light", "dark", "system"] {
                      preferences.theme = theme
                      applyPanelPreferences()
                      expect(visibleHeader(for: ios)?.titleField.stringValue == ios.title, "visible pinned title follows each language and theme without stale text")
                      verifyLocalizedBounds(iosHeader.titleField, context: "\(language) pinned group title")
                      let toolbar = ios.groupToolbar!
                      expect(iosHeader.bounds.contains(toolbar.frame), "localized group actions and counts remain inside the pinned header")
                      for controls in groupControls where controls.group.identifier == "ios" {
                          verifyLocalizedBounds(controls.summary, context: "\(language) pinned group count")
                      }
                      expect(checkedIdentifiers() == originalSelections && logTextView!.string == originalLog && worker === originalWorker && featureStates == originalStates, "scrolling and pinned-title localization preserve the live task, selection and log")
                      if language == "bo" && theme == "dark" {
                          writePreview(name: "tibetan-dark-pinned-group-titles", dark: true)
                      }
                  }
              }
              scrollToTop(ios.frame.minY + 6)
              guard let pushedHeader = visibleHeader(for: ios) else {
                  fatalError("the outgoing group retains its context until its bottom reaches the viewport top")
              }
              expect(pushedHeader.frame.minY >= ios.frame.minY - 0.5 && pushedHeader.frame.maxY > document.visibleRect.maxY, "the outgoing pinned title is pushed off at its own card boundary")
              let simulators = featureBoxes["simulators"]!
              let nextTitle = simulators.convert(simulators.titleRect, to: document)
              scrollToTop(simulators.frame.maxY + 1)
              expect(visibleHeader(for: ios) == nil && visibleHeader(for: simulators) == nil, "the next complete native title is not covered by the outgoing pinned title")
              scrollToTop(nextTitle.midY)
              expect(visibleHeader(for: ios) == nil && visibleHeader(for: simulators)?.titleField.stringValue == simulators.title, "crossing the next title switches context to that group")
              expect(ios.groupToolbar?.superview === ios.contentView && ios.groupToolbar?.frame == originalToolbarFrames["ios"], "switching pinned groups restores the preceding toolbar's original parent and frame")
              scrollToTop(document.bounds.maxY)
              for (identifier, box) in featureBoxes {
                  expect(box.groupToolbar === originalToolbars[identifier] && box.groupToolbar?.superview === box.contentView && box.groupToolbar?.frame == originalToolbarFrames[identifier], "returning to native titles restores every original toolbar without replacement")
              }
              expect(checkboxes.allSatisfy { !$0.button.isEnabled }, "scrolling never unlocks feature selection while a worker runs")
              print("Native clipped-title pinning, column boundaries and localized live-state preservation passed")
          }

          func verifyGroupReordering() {
              let stored = preferences.defaults.object(forKey: "featureGroupColumns.v1")
              defer {
                  if let stored { preferences.defaults.set(stored, forKey: "featureGroupColumns.v1") }
                  else { preferences.defaults.removeObject(forKey: "featureGroupColumns.v1") }
              }
              preferences.defaults.removeObject(forKey: "featureGroupColumns.v1")
              preferences.language = "zh-Hans"
              buildWindow(screenSize: NSSize(width: 1440, height: 900))
              expect(displayedGroupColumns == [["ide", "git", "general", "ios", "simulators"], ["flutter"]], "new full panel keeps Flutter alone on the right")
              let document = featureDocument!
              let originalBoxes = featureBoxes
              let originalButtons = checkboxes.map { $0.button }
              verifyPinnedGroupActions()
              selectAllClicked()
              let expectedPlan = FeatureOption.all.map { $0.identifier }
              logTextView!.string = "unchanged worker output\n"
              worker = Process()
              activeWorkerAction = "install"
              runningIdentifiers = expectedPlan
              featureStates["path_copier"] = "running"
              refreshSelectionState()
              let currentWorker = worker
              verifyPinnedGroupHeaders()
              let drag = IsolatedGroupDraggingInfo()
              drag.draggingSource = featureBoxes["git"]!
              drag.draggingDestinationWindow = window
              drag.draggingPasteboard.setString("git", forType: ManagerFeatureBox.pasteboardType)
              drag.draggingLocation = document.convert(NSPoint(x: groupColumnFrames[1].midX, y: document.bounds.maxY - 1), to: nil)
              expect(document.draggingEntered(drag) == .move && document.prepareForDragOperation(drag), "native destination accepts the current card title drag")
              expect(document.performDragOperation(drag), "native destination handles the drop while a worker runs")
              document.concludeDragOperation(drag)
              expect(preferences.featureGroupColumns[1] == ["git", "flutter"], "native drop inserts before the tall Flutter card")
              expect(worker === currentWorker && runningIdentifiers == expectedPlan && featureStates["path_copier"] == "running", "dragging preserves the live worker, execution order and state")
              expect(checkboxes.map { $0.button } == originalButtons && checkedIdentifiers() == expectedPlan && logTextView!.string == "unchanged worker output\n", "dragging reuses selected controls and raw logs")
              expect(!checkboxes[0].button.isEnabled, "dragging never unlocks task selection")
              drag.draggingSource = NSView()
              expect(document.draggingEntered(drag).isEmpty && !document.performDragOperation(drag), "foreign dragging sources are rejected")
              drag.draggingSource = originalBoxes["git"]!
              drag.draggingPasteboard.setString("flutter", forType: ManagerFeatureBox.pasteboardType)
              expect(document.draggingUpdated(drag).isEmpty, "mismatched card identifiers are rejected")
              for key in FeatureGroup.all.map({ $0.identifier }) {
                  for column in 0...1 {
                      expect(moveFeatureGroup(key, toColumn: column, before: preferences.featureGroupColumns[column].first(where: { $0 != key })), "every group can move into either column")
                      expect(document.frame.width <= featureScrollView!.contentSize.width + 1, "every cross-column move stays within the horizontal viewport")
                      expect(featureBoxes[key] === originalBoxes[key], "cross-column movement keeps the original card")
                  }
              }
              for language in ["de", "bo", "en", "zh-Hans"] {
                  preferences.language = language
                  applyPanelPreferences()
                  expect(checkedIdentifiers() == expectedPlan && worker === currentWorker, "reordered active cards survive language switching")
              }
              worker = nil
              activeWorkerAction = nil
              let saved = preferences.featureGroupColumns
              expect(ManagerPanelPreferences(defaults: preferences.defaults).featureGroupColumns == saved, "card placement survives a new preferences instance")
              let scoped = FeatureSelectionController(scope: ["path_copier"], preferences: preferences)
              scoped.buildWindow(screenSize: NSSize(width: 1440, height: 900))
              expect(scoped.displayedGroupColumns.count == 1 && preferences.featureGroupColumns == saved, "single-group panels have no empty right column and never reset global placement")
              buildWindow(screenSize: NSSize(width: 800, height: 600))
              expect(displayedGroupColumns.count == 1 && preferences.featureGroupColumns == saved, "narrow fallback preserves stored two-column placement")
              preferences.featureGroupColumns = [["unknown", "git", "git"], ["flutter", "git"]]
              expect(preferences.featureGroupColumns == [["git", "ide", "general", "ios", "simulators"], ["flutter"]], "invalid and duplicate saved ids are removed and missing groups restored")
              preferences.featureGroupColumns = [FeatureGroup.all.map { $0.identifier }, []]
              buildWindow(screenSize: NSSize(width: 1440, height: 900))
              expect(displayedGroupColumns[1].isEmpty && groupColumnFrames.count == 2, "a persisted empty column remains a usable drop destination")
              expect(moveFeatureGroup("flutter", toColumn: 1, before: nil) && displayedGroupColumns[1] == ["flutter"], "an empty column accepts cards after reopening")
              expect(!moveFeatureGroup("unknown", toColumn: 0, before: nil), "unknown groups cannot modify saved placement")
              preferences.featureGroupColumns = ManagerPanelPreferences.defaultFeatureGroupColumns
              managerPath = "/dev/null"
              installLocation = "applications"
              buildWindow(screenSize: NSSize(width: 1440, height: 900))
              selectAllClicked()
              preferences.theme = "dark"
              featureStates = ["path_copier": "running", "git-pull": "succeeded", "flutter-project-setup": "waiting"]
              refreshSelectionState()
              applyPanelPreferences()
              writePreview(name: "simplified-dark-full", dark: true)
              print("Native card drag callbacks, cross-column persistence and active worker preservation passed")
          }

          func verifyInstallControlRow() {
              managerPath = "/dev/null"
              buildWindow(screenSize: NSSize(width: 1440, height: 900))
              let location = installLocationButton!
              let cleanup = cleanupBuildProductsButton!
              let cleanNow = cleanupNowButton!
              let header = headerView!
              cleanup.performClick(nil)
              expect(cleanup.state == .on && cleanupBuildProducts, "the isolated Applications layout fixture accepts an explicit cleanup choice")
              cleanup.performClick(nil)
              expect(cleanup.state == .off && !cleanupBuildProducts, "the user can cancel post-install cleanup")
              for language in ManagerPanelPreferences.languages where language != "system" {
                  preferences.language = language
                  refreshSelectionState()
                  applyPanelPreferences()
                  expect(cleanup.state == .off && !cleanupBuildProducts, "language changes and selection refresh preserve manual cleanup cancellation")
                  expect(abs(location.frame.midY - cleanup.frame.midY) < 0.5, "deployment checkboxes share one vertically centered row")
                  expect(abs(cleanup.frame.minX - location.frame.maxX - 16) < 0.5, "automatic cleanup follows the actual localized title with a 16 point gap")
                  for control in [location, cleanup] {
                      expect(header.bounds.contains(control.frame), "complete deployment row stays within the header")
                      verifyLocalizedBounds(control, context: "\(language) deployment checkbox")
                      expect(!control.frame.intersects(installLocationLabel!.frame) && !control.frame.intersects(summaryLabel!.frame), "path and selection summary remain on separate rows below")
                  }
                  expect(cleanNow.superview === installButton!.superview && cleanNow.superview !== header, "independent cleanup belongs to the bottom action row")
                  expect(abs(cleanNow.frame.minX - installButton!.frame.maxX - 10) < 0.5, "independent cleanup directly follows the main action")
                  verifyLocalizedBounds(cleanNow, context: "\(language) independent cleanup")
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
              cleanup.performClick(nil)
              expect(cleanup.state == .on && cleanupBuildProducts, "cleanup can be selected again before switching operations")
              actionControl!.selectedSegment = 1
              actionChanged()
              expect(cleanup.isHidden && cleanup.state == .on && cleanupBuildProducts && !cleanNow.isHidden, "uninstall retains independent cleanup and the automatic cleanup preference")
              expect(abs(cleanNow.frame.minX - installButton!.frame.maxX - 10) < 0.5, "uninstall also places independent cleanup to the right of its main action")
              location.state = .off
              installLocationChanged()
              expect(cleanup.isHidden && !cleanNow.isHidden && !cleanNow.isEnabled, "build-directory route keeps independent cleanup visible with its execution guard")
              location.state = .on
              installLocationChanged()
              actionControl!.selectedSegment = 0
              actionChanged()
              expect(!cleanup.isHidden && cleanup.state == .off && !cleanupBuildProducts && !cleanNow.isHidden && abs(cleanNow.frame.minX - installButton!.frame.maxX - 10) < 0.5, "returning to Applications install keeps the independent action without restoring cancelled automatic cleanup")
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
                  expect(control.font?.pointSize == (preferences.resolvedLanguage == "bo" ? 13 : 12), "preference labels and menus share the same script-appropriate font size")
                  for other in controls.dropFirst(index + 1) {
                      expect(!control.frame.intersects(other.frame), "preference labels and menus never overlap")
                  }
              }
              expect(themeControl!.frame.height == 28 && languageControl!.frame.height == 28, "both native dropdowns reserve complete Tibetan glyph height")
              expect((100...132).contains(themeControl!.frame.width) && (100...132).contains(languageControl!.frame.width), "dropdowns use compact widths for their current labels")
              expect(themeControl!.alignment == .center && languageControl!.alignment == .center, "dropdown display text is centered")
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
              for language in ManagerPanelPreferences.languages.filter({ $0 != "system" }) + ["en"] {
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
                  let darkLog = window!.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                  let logColors = ManagerLogPalette(dark: darkLog)
                  expect(logTextView!.textColor == logColors.foreground(.normal) &&
                         logTextView!.backgroundColor == logColors.background,
                         "existing log uses the complete palette for the selected theme")
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
              for language in ManagerPanelPreferences.languages where language != "system" {
                  preferences.language = language
                  preferences.theme = "dark"
                  applyPanelPreferences()
                  expect(isRunning && activeWorkerAction == "install" && featureStates["path_copier"] == "running", "active task survives every supported language")
                  expect(themeControl!.isEnabled && languageControl!.isEnabled && first.isEnabled == false, "preferences remain usable while task selection is locked")
              }
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
      for (identifier, expected) in [("zh-TW", "zh-Hant"), ("zh-HK", "zh-Hant"), ("zh-MO", "zh-Hant"), ("zh-Hant-US", "zh-Hant"), ("zh-Hans-HK", "zh-Hans"), ("zh-SG", "zh-Hans"), ("zh_CN", "zh-Hans"), ("fr-FR", "fr"), ("bo-CN", "bo"), ("ja-JP", "ja"), ("es-ES", "es"), ("de-DE", "de"), ("ru-RU", "ru"), ("ko-KR", "ko"), ("en-US", "en")] {
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
      extension ManagerPanelPreferences {
          func verifyCompleteCatalog() {
              let supported = Set(["zh-Hans", "zh-Hant", "bo", "en", "ja", "fr", "es", "de", "ru", "ko"])
              expect(Set(Self.languages.filter { $0 != "system" }) == supported && Self.languageNames.count == Self.languages.count, "ten complete languages plus system have readable names")
              let pattern = try! NSRegularExpression(pattern: #"\{\d+\}"#)
              func tokens(_ text: String) -> [String] {
                  return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range) }.sorted()
              }
              for language in ["bo", "ja", "fr", "es", "de", "ru", "ko"] {
                  for entry in Self.translations {
                      guard let translated = Self.additionalTranslations[language]?[entry.english], !translated.isEmpty else {
                          fatalError("missing full GUI translation: \(language) / \(entry.english)")
                      }
                      expect(tokens(translated) == tokens(entry.english), "translation preserves every dynamic token")
                      expect(text(entry.source, language: language) == translated, "current GUI uses its selected language catalog")
                  }
              }
          }
      }
      preferences.verifyCompleteCatalog()
      preferences.language = "zh-Hans"
      FeatureSelectionController(preferences: preferences).verifyGroupReordering()
      FeatureSelectionController(preferences: preferences).verifyInternationalLayout()
      try FeatureSelectionController(scope: ["path_copier", "git-pull", "flutter-project-setup"], preferences: preferences).verifyPreferences(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
      FeatureSelectionController(scope: ["path_copier"], installLocation: "applications", preferences: preferences).verifyInstallControlRow()
      FeatureSelectionController(scope: ["path_copier", "file-create", "file-hash"], preferences: preferences).verifyStatusColumns()
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
    assert_equal 14, panels.length
    assert_equal 36, snapshots.length
    (panels + snapshots).each do |path|
      assert_equal source, File.binread(path), path
    end
  end

  def test_embedded_catalog_matches_the_portable_shared_catalog
    require 'json'
    source = File.read(File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift'))
    embedded = source.match(/private static let additionalTranslationsJSON = #"""\n(.*?)\n    """#/m)
    refute_nil embedded
    catalog = JSON.parse(File.read(File.join(ROOT, 'Scripts/ManagerPanelTranslations.json')))
    assert_equal %w[bo de es fr ja ko ru], catalog.keys.sort
    assert_equal catalog, JSON.parse(embedded[1])
    tokens = ->(value) { value.scan(/\{\d+\}/).sort }
    catalog.each do |language, entries|
      assert_equal 362, entries.length, "complete shared catalog: #{language}"
      entries.each do |english, translated|
        refute_empty translated, "nonempty translation: #{language} / #{english}"
        assert_equal tokens.call(english), tokens.call(translated), "preserved tokens: #{language} / #{english}"
      end
    end
  end
end
