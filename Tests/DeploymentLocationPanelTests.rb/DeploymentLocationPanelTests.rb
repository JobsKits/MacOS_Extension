# frozen_string_literal: true
# Jobs：真实 AppKit 控件连接隔离 worker，验证两种部署位置；不调用任何安装器或系统登记。
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
          func verifyDefaultManagementSelections() {
              buildWindow(screenSize: NSSize(width: 1280, height: 720))
              let location = installLocationButton!
              let cleanup = cleanupBuildProductsButton!
              expect(location.state == .on && installLocation == "applications", "a manager without an explicit location initially selects Applications")
              expect(!cleanup.isHidden && cleanup.isEnabled && cleanup.state == .on && cleanupBuildProducts, "a new Applications installation initially selects post-install cleanup")
              expect(checkedIdentifiers().isEmpty && !installButton!.isEnabled, "default destination and cleanup never select features or enable empty execution")
              installClicked()
              expect(!isRunning && lastExitStatus == nil, "default checked options cannot execute an empty feature plan")
              cleanup.performClick(nil)
              refreshSelectionState()
              applyPanelPreferences()
              expect(cleanup.state == .off && !cleanupBuildProducts, "refreshing the default manager preserves manual cleanup cancellation")
              cleanup.performClick(nil)
              location.performClick(nil)
              expect(installLocation == "build" && cleanup.isHidden && cleanup.state == .off && !cleanupBuildProducts, "switching the default manager to build cancels cleanup")
              location.performClick(nil)
              expect(installLocation == "applications" && !cleanup.isHidden && cleanup.state == .off && !cleanupBuildProducts, "returning to Applications does not reapply the initial cleanup default")
          }

          func verifyCleanupFlagOverride(location: String, enabled: Bool) {
              expect(installLocation == location && cleanupBuildProducts == enabled, "explicit cleanup flags resolve before the first manager window")
              buildWindow(screenSize: NSSize(width: 1280, height: 720))
              expect(installLocationButton!.state == (location == "applications" ? .on : .off), "the initial location control reflects the parsed route")
              expect(cleanupBuildProductsButton!.state == (enabled ? .on : .off) && cleanupBuildProducts == enabled, "the initial cleanup control reflects the final enable or disable flag")
              expect(checkedIdentifiers().isEmpty && !installButton!.isEnabled && !isRunning, "cleanup flag overrides never select features or execute work")
          }

          func verifyCleanupSelectionRoundTrip(enabled: Bool) throws {
              buildWindow(screenSize: NSSize(width: 1280, height: 720))
              let cleanup = cleanupBuildProductsButton!
              expect(cleanupBuildProducts == enabled, "the initial cleanup preference survives either starting action")
              for _ in 0..<3 {
                  actionControl!.selectedSegment = 1
                  actionChanged()
                  expect(cleanup.isHidden && !cleanup.isEnabled && cleanupBuildProducts == enabled, "uninstall hides and locks cleanup without discarding the install preference")
                  cleanup.state = enabled ? .off : .on
                  cleanupBuildProductsChanged()
                  expect(cleanupBuildProducts == enabled && cleanup.state == (enabled ? .on : .off), "hidden cleanup changes cannot replace the retained preference")
                  refreshSelectionState()
                  applyPanelPreferences()
                  actionControl!.selectedSegment = 0
                  actionChanged()
                  expect(installLocationButton!.state == .on && !cleanup.isHidden && cleanup.isEnabled && cleanup.state == (enabled ? .on : .off), "returning to install restores both deployment controls and the user's cleanup choice")
              }
              checkboxes.first { $0.option.identifier == "path_copier" }!.button.performClick(nil)
              actionControl!.selectedSegment = 1
              actionChanged()
              installClicked()
              pump { !isRunning }
              expect(lastExitStatus == 0 && cleanupBuildProducts == enabled, "uninstall completes without consuming the retained install preference")
              let capture = URL(fileURLWithPath: ProcessInfo.processInfo.environment["JOBS_TEST_ARGUMENTS"]!)
              let arguments = try Data(contentsOf: capture).split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
              expect(arguments == ["--non-interactive", "--action", "uninstall", "--features", "path_copier", "--install-location", "applications"], "uninstall never requests cleanup even when the retained install preference is selected")
              actionControl!.selectedSegment = 0
              actionChanged()
              expect(cleanup.state == (enabled ? .on : .off) && cleanupBuildProducts == enabled, "returning after actual uninstall work preserves the cleanup preference")
              try? FileManager.default.removeItem(at: logURL!.deletingLastPathComponent())
          }

          func verifyLocationControls(screen: NSSize) {
              buildWindow(screenSize: screen)
              let button = installLocationButton!
              let label = installLocationLabel!
              expect(button.title == "使用「应用程序」中的联合 App 安装 / 卸载", "checkbox states both operations")
              expect(button.state == .off && installLocation == "build", "an explicit build location remains respected")
              expect(label.stringValue.contains("构建目录"), "the explicit build destination is visible")
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
              expect(window!.contentView!.frame.height <= screen.height + 1, "short screens keep a bounded window: \(screen), content \(window!.contentView!.frame), header \(header.frame), execution \(executionLabel!.frame), scope \(scopeIdentifiers.count)")
              button.performClick(nil)
              expect(installLocation == "applications" && label.stringValue.contains("/Applications"), "checkbox switches to Applications")
              expect(label.stringValue.contains("Jobs自定义右键菜单.app") && label.stringValue.contains("/Applications/Jobs自定义右键菜单.app"), "Applications route names the single combined App and exact location")
              let cleanup = cleanupBuildProductsButton!
              expect(!cleanup.isHidden && cleanup.state == .off && cleanup.isEnabled && !cleanupBuildProducts, "Applications install reveals an opt-in cleanup checkbox")
              expect(cleanup.title == "安装成功后清除此轮构建产物", "cleanup title describes successful installation and this build only")
              let cleanupNow = cleanupNowButton!
              expect(abs(button.frame.midY - cleanup.frame.midY) < 0.5, "deployment checkboxes share one centered horizontal row")
              expect(abs(cleanup.frame.minX - button.frame.maxX - 16) < 0.5, "automatic cleanup follows the current title with a compact gap")
              expect(header.bounds.contains(cleanup.frame) && cleanupNow.superview === installButton!.superview && cleanupNow.superview !== header && abs(cleanupNow.frame.minX - installButton!.frame.maxX - 10) < 0.5, "independent cleanup follows the main action in the bottom row")
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
              expect(cleanup.isHidden && cleanup.state == .off && !cleanupBuildProducts && !cleanupNowButton!.isHidden && !cleanupNowButton!.isEnabled, "returning to build clears automatic cleanup and keeps the independent action visible but disabled")
          }
          func verifyExplicitApplicationsMode() {
              buildWindow(screenSize: NSSize(width: 1280, height: 720))
              expect(installLocationButton!.state == .on && installLocation == "applications", "explicit manager mode initializes the control")
              expect(!cleanupBuildProductsButton!.isHidden && cleanupBuildProductsButton!.state == .on && cleanupBuildProducts, "explicit Applications installation initially selects cleanup")
              cleanupBuildProductsButton!.performClick(nil)
              refreshSelectionState()
              applyPanelPreferences()
              expect(cleanupBuildProductsButton!.state == .off && !cleanupBuildProducts, "refreshing preserves explicit cleanup cancellation")
              cleanupBuildProductsButton!.performClick(nil)
              expect(cleanupBuildProducts, "cleanup can be explicitly selected")
              actionControl!.selectedSegment = 1
              actionChanged()
              expect(cleanupBuildProductsButton!.isHidden && cleanupBuildProductsButton!.state == .on && cleanupBuildProducts && !cleanupNowButton!.isHidden, "uninstall hides automatic cleanup while retaining its install preference and independent cleanup")
              actionControl!.selectedSegment = 0
              actionChanged()
              expect(!cleanupBuildProductsButton!.isHidden && cleanupBuildProductsButton!.state == .on && cleanupBuildProducts, "switching back to install restores the selected cleanup preference")
          }
          func verifyLegacyMode() {
              buildWindow(screenSize: NSSize(width: 1280, height: 720))
              expect(installLocation == "build" && !cleanupBuildProducts, "legacy selection-only mode preserves its build location without cleanup")
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
              expect(checkedIdentifiers() == ["path_copier"], "uninstall tab preserves the selected cleanup target")
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
              expect(executionLabel!.stringValue.hasPrefix("需要权限检查") && featureStates["file-create"] == "skipped", "permission denial does not turn later work into completed or failed work")
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
      try FeatureSelectionController.parseArguments(arguments).verifyDefaultManagementSelections()
      try FeatureSelectionController.parseArguments(["--manager", fixture]).verifyDefaultManagementSelections()
      for initialAction in ["install", "uninstall"] {
          try FeatureSelectionController.parseArguments(arguments + ["--action", initialAction]).verifyCleanupSelectionRoundTrip(enabled: true)
          try FeatureSelectionController.parseArguments(arguments + ["--action", initialAction, "--no-cleanup-build-products"]).verifyCleanupSelectionRoundTrip(enabled: false)
      }
      try FeatureSelectionController.parseArguments(arguments + ["--no-cleanup-build-products"]).verifyCleanupFlagOverride(location: "applications", enabled: false)
      try FeatureSelectionController.parseArguments(arguments + ["--install-location", "applications", "--no-cleanup-build-products"]).verifyCleanupFlagOverride(location: "applications", enabled: false)
      try FeatureSelectionController.parseArguments(arguments + ["--no-cleanup-build-products", "--cleanup-build-products"]).verifyCleanupFlagOverride(location: "applications", enabled: true)
      try FeatureSelectionController.parseArguments(arguments + ["--cleanup-build-products", "--no-cleanup-build-products"]).verifyCleanupFlagOverride(location: "applications", enabled: false)
      try FeatureSelectionController.parseArguments(arguments + ["--install-location", "build", "--cleanup-build-products"]).verifyCleanupFlagOverride(location: "build", enabled: false)
      for theme in [NSAppearance.Name.aqua, .darkAqua] {
          application.appearance = NSAppearance(named: theme)
          for screen in [NSSize(width: 1920, height: 1080), NSSize(width: 1366, height: 768), NSSize(width: 800, height: 600)] {
              try FeatureSelectionController.parseArguments(arguments + ["--install-location", "build"]).verifyLocationControls(screen: screen)
              try FeatureSelectionController.parseArguments(["--manager", fixture, "--install-location", "build"]).verifyLocationControls(screen: screen)
          }
      }
      try FeatureSelectionController.parseArguments(arguments + ["--install-location", "applications"]).verifyExplicitApplicationsMode()
      try FeatureSelectionController.parseArguments([]).verifyLegacyMode()
      let controller = try FeatureSelectionController.parseArguments(arguments + ["--install-location", "build"])
      controller.verifyEmptySelection()
      for operation in ["install", "uninstall"] {
          for location in ["build", "applications"] {
              for cleanup in [false, true] {
                  try controller.verifyWorkerRoute(path: fixture, location: location, operation: operation, cleanup: cleanup)
              }
          }
      }
      try FeatureSelectionController.parseArguments(["--manager", fixture, "--scope", "path_copier,file-create", "--install-location", "build"]).verifyIndependentCleanupAndCooperativeStop(path: fixture)
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
