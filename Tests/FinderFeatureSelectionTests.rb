# frozen_string_literal: true
# Jobs：在临时进程里检查真实 AppKit 分组按钮和布局，不运行安装器或注册扩展。

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
              expect(FeatureOption.flutter.count == 47 && all.count == 86, "all leaf actions include file creation, viewer, merge and split")
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
              expect(general.group.identifiers.contains("command-shortcut-create"), "command launcher belongs to file and general tools")
              expect(FeatureOption.independent.filter { $0.identifier == "command-shortcut-create" }.map { $0.title } == ["创建脚本快捷入口"], "command launcher is one independent action")
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
              expect(checkedIdentifiers().count == all.count - FeatureOption.flutter.count, "Flutter clear changes all leaf actions only")
              checkboxes.first { $0.option.identifier == "flutter-package-android" }!.button.performClick(nil)
              expect(flutter.summary.stringValue == "已选 1 / 47", "one Flutter submenu can be installed")
              print("group controls and function identifiers passed")
          }

          func verifyManagement() {
              buildWindow(screenSize: NSSize(width: 1280, height: 720))
              expect(formattedOutcome() == "__CANCELLED__", "no plan before explicit confirmation")
              selectAllButton?.performClick(nil)
              let selectedBeforeSwitch = checkedIdentifiers()
              actionControl?.selectedSegment = 1
              actionChanged()
              expect(managementAction == "uninstall" && checkedIdentifiers() == selectedBeforeSwitch, "switching to uninstall preserves every selected feature")
              expect(installButton?.title == "卸载" && installButton?.isEnabled == true, "uninstall action uses the retained explicit selection")
              expect(groupControls.allSatisfy { $0.summary.stringValue == "已选 \($0.group.options.count) / \($0.group.options.count)" }, "mode switch preserves group counts")
              clearAllClicked()
              checkboxes.first { $0.option.identifier == "git-pull" }!.button.performClick(nil)
              installClicked()
              expect(formattedOutcome() == "uninstall|git-pull", "single uninstall returns the exact leaf and action")
              actionControl?.selectedSegment = 0
              actionChanged()
              expect(checkedIdentifiers() == ["git-pull"] && installButton?.title == "安装 / 更新", "switching back preserves the selected feature")
              clearAllClicked()
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
