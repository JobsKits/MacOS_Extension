# frozen_string_literal: true
# Jobs：真实 AppKit + Process 接假 worker；不调用任何安装或系统登记。
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

class FinderManagerPanelTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_failure_links_show_only_the_current_complete_log_in_a_new_terminal_session
    source = File.read(File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift'))
    source = source.sub(%r{// MARK: - Entry point.*?// MARK: - Feature catalog}m, '')
    source = source.sub('URL(fileURLWithPath: "/usr/bin/osascript")', 'URL(fileURLWithPath: CommandLine.arguments[2])')
    harness = <<~'SWIFT'
      func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
          guard condition() else { fatalError(message) }
      }
      func pump(until condition: () -> Bool) {
          let deadline = Date().addingTimeInterval(5)
          while !condition(), Date() < deadline {
              RunLoop.current.run(until: Date().addingTimeInterval(0.01))
          }
          expect(condition(), "log viewer callback finished")
      }
      extension FeatureSelectionController {
          func verifyLogLinks(root: URL) throws {
              buildWindow(screenSize: NSSize(width: 1280, height: 720))
              let fileManager = FileManager.default
              let capture = root.appendingPathComponent("arguments")
              let catOutput = root.appendingPathComponent("cat-output")
              let first = root.appendingPathComponent("完整日志 中文 ' $(touch injected) `touch injected` \\ \n\r\u{2028}.log")
              let contents = "完整会话开头\n" + String(repeating: "日志正文 $(touch injected)\n", count: 30_000) + "完整会话末尾\n"
              try contents.write(to: first, atomically: true, encoding: .utf8)
              logURL = first
              featureStates = ["git-pull": "failed", "path_copier": "succeeded"]
              refreshExecutionState()
              let label = statusLabels["git-pull"]!
              let click = label.gestureRecognizers.first as! NSClickGestureRecognizer
              let succeeded = statusLabels["path_copier"]!.gestureRecognizers.first as! NSClickGestureRecognizer
              expect(click.isEnabled && !succeeded.isEnabled, "only a failed row is clickable")
              expect(label.stringValue == "失败，见日志" && label.textColor == .systemRed, "existing red failure text retained")
              expect(label.toolTip?.contains(first.path) == true, "tooltip is bound to current full session log")
              expect(label.attributedStringValue.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int == 1, "failure text looks like a link")
              failedStatusClicked(click)
              pump { (try? String(contentsOf: catOutput, encoding: .utf8)) == contents }
              let arguments = try Data(contentsOf: capture).split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
              expect(arguments.count == 3 && arguments[0] == "-e", "AppleScript and command are separate argv values")
              expect(arguments[1].contains("do script (item 1 of argv)") && !arguments[1].contains("close"), "opens a new session and does not close existing sessions")
              expect(arguments[2].hasPrefix("/bin/cat -- $'"), "only cat reads the log")
              expect(!arguments[2].contains("\n") && !arguments[2].contains("\r") && !arguments[2].contains("\u{2028}"), "Terminal command is one physical line")
              expect(!fileManager.fileExists(atPath: root.appendingPathComponent("injected").path), "path and log body are never executed")
              try fileManager.removeItem(at: capture)
              label.isHidden = true
              failedStatusClicked(click)
              label.isHidden = false
              label.superview!.isHidden = true
              failedStatusClicked(click)
              label.superview!.isHidden = false
              succeeded.isEnabled = true
              failedStatusClicked(succeeded)
              expect(!fileManager.fileExists(atPath: capture.path), "hidden and non-failed labels cannot open logs")
              featureStates["git-pull"] = "running"
              refreshExecutionState()
              expect(!click.isEnabled && label.toolTip == nil, "running state removes the old failure link")
              failedStatusClicked(click)
              expect(!fileManager.fileExists(atPath: capture.path), "disabled stale click cannot reopen previous log")
              let second = root.appendingPathComponent("下一次会话.log")
              try "second-session-only".write(to: second, atomically: true, encoding: .utf8)
              logURL = second
              featureStates["git-pull"] = "failed"
              refreshExecutionState()
              expect(label.toolTip?.contains(second.path) == true, "new failure binds the new session")
              failedStatusClicked(click)
              pump { (try? String(contentsOf: catOutput, encoding: .utf8)) == "second-session-only" }
              var errors: [String] = []
              logErrorPresenter = { errors.append($0) }
              try fileManager.removeItem(at: second)
              try fileManager.removeItem(at: capture)
              failedStatusClicked(click)
              expect(errors.last?.contains(second.path) == true, "missing logs show a concrete desktop error")
              expect(!fileManager.fileExists(atPath: capture.path), "missing logs never launch Terminal")
              logURL = root
              refreshExecutionState()
              failedStatusClicked(click)
              expect(errors.last?.contains(root.path) == true, "directories are not treated as log files")
              logURL = first
              refreshExecutionState()
              setenv("JOBS_TEST_OSASCRIPT_FAILURE", "1", 1)
              failedStatusClicked(click)
              pump { errors.last?.contains("simulated Terminal failure") == true }
              unsetenv("JOBS_TEST_OSASCRIPT_FAILURE")
              featureStates.removeAll()
              refreshExecutionState()
              expect(!click.isEnabled && label.toolTip == nil, "switching or clearing state removes failure links")
              print("Failure log links and safe Terminal cat passed")
          }
      }
      let application = NSApplication.shared
      application.setActivationPolicy(.prohibited)
      application.finishLaunching()
      try FeatureSelectionController().verifyLogLinks(root: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
    SWIFT
    Dir.mktmpdir('jobs-log-link-') do |directory|
      fake = File.join(directory, 'osascript-stub')
      File.write(fake, <<~'ZSH')
        #!/bin/zsh
        [[ "${JOBS_TEST_OSASCRIPT_FAILURE:-}" != 1 ]] || { print -u2 'simulated Terminal failure'; exit 23; }
        (( $# == 3 )) && [[ "$1" == -e ]] || exit 91
        printf '%s\0' "$@" > "$JOBS_TEST_CAPTURE"
        cd "$JOBS_TEST_ROOT" || exit 92
        /bin/zsh -c "$3" > "$JOBS_TEST_CAT_OUTPUT"
      ZSH
      File.chmod(0o755, fake)
      path = File.join(directory, 'main.swift')
      binary = File.join(directory, 'log-link-check')
      File.write(path, source + "\n" + harness)
      output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', path, '-o', binary)
      assert status.success?, output
      environment = { 'JOBS_TEST_ROOT' => directory, 'JOBS_TEST_CAPTURE' => File.join(directory, 'arguments'),
                      'JOBS_TEST_CAT_OUTPUT' => File.join(directory, 'cat-output') }
      output, status = Open3.capture2e(environment, binary, directory, fake)
      assert status.success?, output
      assert_includes output, 'Failure log links and safe Terminal cat passed'
    end
  end

  def test_streaming_worker_status_failures_and_utf8
    source = File.read(File.join(ROOT, 'Scripts/SelectFinderExtensionFeatures.swift'))
    source = source.sub(%r{// MARK: - Entry point.*?// MARK: - Feature catalog}m, '')
    source = source.sub('process.executableURL = URL(fileURLWithPath: "/bin/zsh")', 'process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["JOBS_TEST_WORKER_SHELL"] ?? "/bin/zsh")')
    harness = <<~'SWIFT'
      func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
          guard condition() else {
              fatalError(message)
          }
      }
      func pump(until condition: () -> Bool) {
          let deadline = Date().addingTimeInterval(8)
          while !condition(), Date() < deadline {
              RunLoop.current.run(until: Date().addingTimeInterval(0.01))
          }
          expect(condition(), "worker completed before timeout")
      }
      extension FeatureSelectionController {
          func verifyWorker(path: String) {
              installMenu(application: NSApplication.shared)
              let menu = NSApplication.shared.mainMenu!
              expect(menu.items[1].submenu!.items[0].action == #selector(NSText.copy(_:)), "standard Copy menu routes to the responder")
              buildWindow(screenSize: NSSize(width: 1280, height: 720))
              expect(window!.level == .normal && !window!.hidesOnDeactivate, "manager is an ordinary non-floating window")
              expect(!installationTiming.hasStarted && executionLabel!.stringValue == "安装 / 更新就绪", "an untouched install shows readiness without elapsed time")
              expect(completionPercentage(completed: 12, total: 81) == "14.8%", "percentage follows completed item count")
              expect(completionPercentage(completed: 0, total: 0) == "0.0%", "empty count cannot divide by zero")
              expect(formattedElapsedTime(3661.9) == "01:01:01" && formattedElapsedTime(90061) == "25:01:01", "elapsed hours do not wrap at a day")
              managerPath = path
              checkboxes.first { $0.option.identifier == "git-pull" }!.button.performClick(nil)
              checkboxes.first { $0.option.identifier == "path_copier" }!.button.performClick(nil)
              installClicked()
              expect(isRunning, "task belongs to the panel")
              expect(executionLabel!.stringValue.contains("0.0%") && executionLabel!.stringValue.contains("安装用时 00:00:00"), "click starts progress and elapsed time at zero")
              expect(executionTimer?.isValid == true, "timer runs independently of output")
              expect(installButton!.isEnabled && installButton!.title == "停止安装" && !actionControl!.isEnabled && !closeButton!.isEnabled, "install exposes cooperative stop while other controls lock")
              expect(!windowShouldClose(window!), "closing cannot abandon an active install")
              NSApplication.shared.sendAction(menu.items[0].submenu!.items[0].action!, to: self, from: nil)
              expect(isRunning, "Cmd+Q menu cannot abandon an active install")
              expect(checkboxes.allSatisfy { !$0.button.isEnabled }, "selection cannot change during work")
              pump { featureStates["git-pull"] == "running" }
              expect(logTextView!.string.contains("实时中文日志"), "stdout displayed before process exits")
              expect(statusLabels["git-pull"]!.stringValue == "安装中…", "real running state visible")
              expect(isRunning && lastExitStatus == nil, "progress is live")
              pump { executionLabel!.stringValue.contains("安装用时 00:00:01") }
              expect(featureStates["git-pull"] == "running", "timer advances while the worker is silent")
              pump { logTextView!.string.contains("无换行进度42%") }
              expect(isRunning, "no-newline output is visible before exit")
              pump { featureStates["git-pull"] == "succeeded" }
              expect(executionLabel!.stringValue.contains("50.0%"), "completed event updates percentage")
              expect(statusLabels["git-pull"]!.stringValue == "安装成功" && statusLabels["git-pull"]!.textColor == .systemGreen, "installation success keeps green text without an embedded icon")
              expect(statusIcons["git-pull"]!.image != nil && statusIcons["git-pull"]!.contentTintColor == .systemGreen && !statusIcons["git-pull"]!.isHidden, "installation success shows a separate green icon")
              pump { featureStates["path_copier"] == "failed" }
              expect(isRunning && executionTimer?.isValid == true && executionLabel!.stringValue.contains("100.0%"), "all item results do not stop timing before the worker exits")
              pump { !isRunning }
              expect(lastExitStatus == 7, "real failure exit code retained")
              expect(featureStates["git-pull"] == "succeeded" && featureStates["path_copier"] == "failed", "partial success retained")
              expect(statusLabels["path_copier"]!.stringValue == "失败，见日志", "failure is per item")
              expect(progressIndicator!.doubleValue == 2 && progressIndicator!.maxValue == 2, "progress counts settled leaves")
              expect(executionTiming.elapsed >= 2 && executionTiming.startedAt == nil && executionTimer == nil, "exit freezes total time and releases the timer")
              expect(executionLabel!.stringValue.contains("进度 100.0%") && executionLabel!.stringValue.contains("总用时"), "partial failure still shows completed progress and final duration")
              let finalSummary = executionLabel!.stringValue
              refreshExecutionSummary()
              expect(executionLabel!.stringValue == finalSummary, "completed summary stays frozen")
              expect(logTextView!.string.contains("错误输出") && logTextView!.string.contains("最后无换行"), "stderr and EOF tail included")
              expect(!logTextView!.string.contains("JOBS_MANAGER_EVENT"), "event protocol does not leak into UI logs")
              expect(!logTextView!.string.contains("\u{1B}"), "ANSI controls removed")
              expect(logTextView!.isSelectable && !logTextView!.isEditable, "logs support text selection and copying")
              expect(installButton!.isEnabled && closeButton!.isEnabled, "finished panel can be reused or closed")
              let disk = try! String(contentsOf: logURL!, encoding: .utf8)
              expect(disk.contains("实时中文日志") && disk.contains("最后无换行"), "full log retained on disk")
              try? FileManager.default.removeItem(at: logURL!)
              let installedElapsed = installationTiming.elapsed
              actionControl!.selectedSegment = 1
              actionChanged()
              expect(!uninstallationTiming.hasStarted && executionLabel!.stringValue == "卸载就绪", "an untouched uninstall shows readiness without elapsed time")
              actionControl!.selectedSegment = 0
              actionChanged()
              expect(installationTiming.elapsed == installedElapsed && executionLabel!.stringValue.contains("安装用时 " + formattedElapsedTime(installedElapsed)), "switching back restores the independent install duration")
              actionControl!.selectedSegment = 1
              actionChanged()
              startWorker(identifiers: ["git-pull"], path: path + ".missing")
              expect(executionTiming.elapsed == 0 && executionLabel!.stringValue.contains("卸载用时 00:00:00"), "the next operation starts its own clock")
              expect(installationTiming.elapsed == installedElapsed, "starting uninstall never resets installation duration")
              pump { !isRunning }
              expect(lastExitStatus != 0 && featureStates["git-pull"] == "failed", "early exit without result cannot claim success")
              expect(executionTimer == nil && executionLabel!.stringValue.contains("总用时"), "early failure also stops timing")
              try? FileManager.default.removeItem(at: logURL!)
              startWorker(identifiers: ["git-pull"], path: path)
              pump { !isRunning }
              expect(lastExitStatus == 0 && executionLabel!.stringValue.hasPrefix("已完成"), "panel can run a successful uninstall after failure")
              expect(statusLabels["git-pull"]!.stringValue == "已卸载", "uninstall retains its own success text")
              expect(installationTiming.elapsed == installedElapsed && executionLabel!.stringValue.contains("卸载总用时"), "uninstall completion preserves installation timing")
              expect(executionTimer == nil && executionLabel!.stringValue.contains("100.0%"), "success also freezes final progress and time")
              try? FileManager.default.removeItem(at: logURL!)
              startWorker(identifiers: ["git-pull", "path_copier"], path: path, action: "uninstall")
              pump { !isRunning }
              expect(featureStates["git-pull"] == "succeeded" && featureStates["path_copier"] == "not-installed", "missing installation is a separate terminal outcome")
              expect(executionLabel!.stringValue.contains("成功 1，失败 0，无需卸载 1") && executionLabel!.stringValue.contains("100.0%"), "missing installation is processed without being counted as removed")
              let missingLabel = statusLabels["path_copier"]!
              expect(missingLabel.stringValue == "未安装，无需卸载" && missingLabel.textColor == .secondaryLabelColor, "missing installation never displays green uninstalled text")
              expect(missingLabel.gestureRecognizers.allSatisfy { !$0.isEnabled }, "missing installation is not an error log link")
              for text in preferences.variants("未安装，无需卸载") {
                  expect(missingLabel.frame.width >= (text as NSString).size(withAttributes: [.font: missingLabel.font!]).width, "all current language variants fit the status column")
              }
              expect(progressIndicator!.doubleValue == 2, "mixed removal and missing installation finish the progress bar")
              try? FileManager.default.removeItem(at: logURL!)
              startWorker(identifiers: ["path_copier"], path: path, action: "uninstall")
              pump { !isRunning }
              expect(executionLabel!.stringValue.contains("成功 0，失败 0，无需卸载 1") && featureStates["path_copier"] == "not-installed", "an entirely absent selection needs no fake removal success")
              try? FileManager.default.removeItem(at: logURL!)
              setenv("JOBS_TEST_WORKER_SHELL", path + ".missing-shell", 1)
              startWorker(identifiers: ["git-pull"], path: path)
              unsetenv("JOBS_TEST_WORKER_SHELL")
              expect(!isRunning && lastExitStatus == 2 && executionTimer == nil, "process launch error immediately freezes timing")
              expect(executionLabel!.stringValue.contains("总用时") && logTextView!.string.contains("无法启动任务"), "launch error retains the final duration and failure detail")
              expect(installationTiming.elapsed == installedElapsed, "uninstall launch failure cannot overwrite install duration")
              try? FileManager.default.removeItem(at: logURL!)
              startWorker(identifiers: ["path_copier"], path: path, action: "install")
              pump { !isRunning }
              expect(featureStates["path_copier"] == "failed", "an install cannot accept the uninstall-only missing state")
              try? FileManager.default.removeItem(at: logURL!)
              print("GUI worker streaming and completion passed")
          }
      }
      let decoder = ManagerOutputDecoder()
      let bytes = Array("实时中文\r第二行\n末尾".utf8)
      var lines: [String] = []
      for byte in bytes {
          lines += decoder.append(Data([byte]))
      }
      lines += decoder.finish()
      expect(lines == ["实时中文", "第二行", "末尾"], "UTF-8 split at every byte and CR frames decode exactly")
      let flood = ManagerOutputDecoder()
      let longLine = String(repeating: "大日志", count: 100_000)
      expect(flood.append(Data(longLine.utf8)).isEmpty, "fixture has no newline")
      let drained = flood.drainOverflow()
      expect(drained + flood.finish().joined() == longLine, "long unbroken output drains without data loss")
      let application = NSApplication.shared
      application.setActivationPolicy(.prohibited)
      application.finishLaunching()
      FeatureSelectionController().verifyWorker(path: CommandLine.arguments[1])
    SWIFT
    Dir.mktmpdir('jobs-manager-panel-') do |directory|
      fixture = File.join(directory, 'worker 中文.zsh')
      File.write(fixture, <<~'ZSH')
        if [[ "$5" == path_copier ]]; then
          print 'JOBS_MANAGER_EVENT\tpath_copier\tnot-installed\t所选位置未安装，无需卸载'
          exit 0
        fi
        if [[ "$3" == uninstall && "$5" == git-pull,path_copier ]]; then
          print 'JOBS_MANAGER_EVENT\tgit-pull\tsucceeded\t卸载完成'
          print 'JOBS_MANAGER_EVENT\tpath_copier\tnot-installed\t所选位置未安装，无需卸载'
          exit 0
        fi
        if [[ "$3" == uninstall && "$5" == git-pull ]]; then
          print 'JOBS_MANAGER_EVENT\tgit-pull\tsucceeded\t卸载完成'
          exit 0
        fi
        [[ "$1" == --non-interactive && "$2" == --action && "$3" == install && "$4" == --features && "$5" == git-pull,path_copier ]] || exit 81
        print '实时中文日志'
        print 'JOBS_MANAGER_EVENT\tgit-pull\trunning\t开始第一项'
        /bin/sleep 1.2
        printf '无换行进度42%%'
        /bin/sleep 0.25
        print ''
        print '\e[31m错误输出\e[0m' >&2
        print 'JOBS_MANAGER_EVENT\tgit-pull\tsucceeded\t第一项完成'
        print 'JOBS_MANAGER_EVENT\tpath_copier\trunning\t开始第二项'
        /bin/sleep 0.2
        print 'JOBS_MANAGER_EVENT\tpath_copier\tfailed\t第二项失败'
        printf '最后无换行'
        /bin/sleep 1.1
        exit 7
      ZSH
      path = File.join(directory, 'main.swift')
      binary = File.join(directory, 'panel-check')
      File.write(path, source + "\n" + harness)
      output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', path, '-o', binary)
      assert status.success?, output
      output, status = Open3.capture2e(binary, fixture)
      assert status.success?, output
      assert_includes output, 'GUI worker streaming and completion passed'
    end
  end
end
