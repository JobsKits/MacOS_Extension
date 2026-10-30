# frozen_string_literal: true
# Jobs：真实 WKWebView + PTY + fzf，全部业务均为临时脚本，不安装或下载 SDK。
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'json'

class SetupWindowTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  def test_real_embedded_terminal_fzf_input_resize_events_and_complete_private_log
    source = File.read(File.join(ROOT, 'Scripts/Tools/SetupProjectWindow.swift')).split('if CommandLine.arguments.count == 5').first
    fzf = ['/opt/homebrew/bin/fzf', '/usr/local/bin/fzf'].find { |path| File.executable?(path) }
    refute_nil fzf, 'native fzf is required for the embedded terminal interaction test'
    Dir.mktmpdir('jobs-setup-window-test-') do |directory|
      directory = File.realpath(directory)
      tools = File.join(directory, 'Tools')
      FileUtils.mkdir_p(tools)
      FileUtils.cp_r(File.join(ROOT, 'Scripts/Tools/SetupGUIAssets'), tools)
      FileUtils.cp(File.join(ROOT, 'Scripts/Tools/SetupVersion.json'), tools)
      File.write(File.join(tools, 'SetupFlutterProject.zsh'), <<~ZSH)
        #!/bin/zsh
        [[ -t 0 && -t 1 ]] || exit 91
        print -r -- '{"id":"flutter","title":"Flutter SDK","state":"running","message":"请选择","version":"Flutter 3.47.8 · Dart 3.13.7"}' >> "$JOBS_FLUTTER_SETUP_EVENTS"
        print -r -- '{"id":"platforms.android.sdk","parent":"platforms.android","title":"Android SDK","state":"attention","message":"fixture","version":"API 36 · Build-tools 36.0.0"}' >> "$JOBS_FLUTTER_SETUP_EVENTS"
        print -r -- FZF_READY
        selected="$(print -l first second | #{fzf} --height=8 --layout=reverse --no-sort --prompt='SDK > ')" || exit 92
        print -r -- "SELECTION:$selected"
        print -r -- INPUT_READY
        IFS= read -r answer || exit 93
        print -r -- "LITERAL:$answer"
        stty size
        print -r -- '{"id":"flutter","title":"Flutter SDK","state":"succeeded"}' >> "$JOBS_FLUTTER_SETUP_EVENTS"
        print -r -- 'RAW_COMPLETE_最后一行'
      ZSH
      harness = <<~'SWIFT'
        extension SetupProjectWindow {
            func verifyEmbeddedTerminal() throws {
                applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
                var sentChoice = false
                var sentLiteral = false
                var choiceReadyAt: Date?
                var originalRows = 0
                var draggedRows = 0
                let deadline = Date().addingTimeInterval(25)
                while Date() < deadline && !finished {
                    _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                    let text = String(decoding: (try? Data(contentsOf: session.appendingPathComponent("terminal.raw.log"))) ?? Data(), as: UTF8.self)
                    if text.contains("FZF_READY"), choiceReadyAt == nil { choiceReadyAt = Date() }
                    if let ready = choiceReadyAt, Date().timeIntervalSince(ready) > 0.5, !sentChoice {
                        sentChoice = true
                        // Directly use an encoded JSON value to preserve raw key bytes through JS.
                        let data = try JSONSerialization.data(withJSONObject: ["type": "input", "data": "\u{1b}[B\r"])
                        let json = String(decoding: data, as: UTF8.self)
                        web.evaluateJavaScript("window.webkit.messageHandlers.pty.postMessage(\(json))", completionHandler: nil)
                    }
                    if text.contains("INPUT_READY"), !sentLiteral {
                        sentLiteral = true
                        var before = winsize()
                        _ = ioctl(master, TIOCGWINSZ, &before)
                        originalRows = Int(before.ws_row)
                        let divider = split.subviews[0].frame.height
                        split.setPosition(divider + 80, ofDividerAt: 0)
                        let resizeDeadline = Date().addingTimeInterval(3)
                        while Date() < resizeDeadline {
                            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                            var after = winsize()
                            _ = ioctl(master, TIOCGWINSZ, &after)
                            draggedRows = Int(after.ws_row)
                            if draggedRows > 0 && draggedRows != originalRows { break }
                        }
                        guard !split.isVertical, split.dividerThickness >= 14, draggedRows > 0, draggedRows < originalRows else { fatalError("Dragging the actual vertical split did not resize xterm and PTY rows") }
                        resize(cols: 131, rows: 37)
                        let data = try JSONSerialization.data(withJSONObject: ["type": "input", "data": "literal '$ touch NEVER\r"])
                        let json = String(decoding: data, as: UTF8.self)
                        web.evaluateJavaScript("window.webkit.messageHandlers.pty.postMessage(\(json))", completionHandler: nil)
                    }
                }
                for _ in 0..<5 { _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
                let log = session.appendingPathComponent("terminal.raw.log")
                let text = String(decoding: try Data(contentsOf: log), as: UTF8.self)
                guard finished, text.contains("SELECTION:second"), text.contains("LITERAL:literal '$ touch NEVER"), text.contains("RAW_COMPLETE_最后一行"), text.contains("37 131") else { fatalError("PTY/fzf/input/resize failure:\n\(text)") }
                guard states["flutter"] == "succeeded", states["platforms.android.sdk"] == "attention", labels["platforms.android.sdk"]?.stringValue.contains("需用户处理") == true else { fatalError("Milestone state events were lost") }
                let connectorFields = columns["flutter"]?.superview?.subviews.compactMap { $0 as? NSTextField }.filter { $0.stringValue == ">>>>>" } ?? []
                let milestoneScroll = split.subviews.compactMap { $0 as? NSScrollView }.first!
                guard connectorFields.count == 5, connectorFields.allSatisfy({ $0.frame.width >= 48 }),
                      milestoneScroll.documentView!.frame.width <= milestoneScroll.contentView.bounds.width + 0.5 else { fatalError("ASCII milestone connectors or 6-column viewport overflow") }
                print("PASS: five visible monospace >>>>> connectors between six milestone columns")
                print("PASS: real NSSplitView divider drag changes xterm and PTY rows from \(originalRows) to \(draggedRows)")
                guard window.title.contains("v1.1.0"), window.title.contains("2026.10.29.2"), versionLabels["flutter"]?.stringValue.contains("3.47.8") == true,
                      versionLabels["platforms.android.sdk"]?.stringValue.contains("36.0.0") == true, versionLabels["flutter"]?.isHidden == false,
                      versionLabels["platforms.android.sdk"]?.maximumNumberOfLines == 2 else { fatalError("Actual tool/SDK/component versions must be visible, including after a later state event omits version") }
                print("PASS: tool build, SDK/Dart and Android component versions are visible with 2-line limits")
                let attrs = try FileManager.default.attributesOfItem(atPath: log.path)
                guard (attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600 else { fatalError("Raw log must be private") }
                guard text.contains("\u{1b}[") else { fatalError("Raw log must retain ANSI output") }
                print("PASS: real WKWebView + PTY, fzf, raw literal keys, resize, nested milestone events, private complete ANSI log")
                window.delegate = nil
                window.close()
                reader?.cancel()
                if master >= 0 { Darwin.close(master); master = -1 }
                try rawLog.close()
                try FileManager.default.removeItem(at: session)
            }
        }
        extension SetupProjectWindow {
            func verifyCancellationFallback() throws {
                try "#!/bin/zsh\ntrap '' INT\nprint -r -- IGNORING_INTERRUPT_READY\n/bin/sleep 60\n".write(to: tools.appendingPathComponent("SetupFlutterProject.zsh"), atomically: true, encoding: .utf8)
                applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
                var cancelled = false
                let deadline = Date().addingTimeInterval(14)
                while Date() < deadline && !finished {
                    _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                    let text = String(decoding: (try? Data(contentsOf: session.appendingPathComponent("terminal.raw.log"))) ?? Data(), as: UTF8.self)
                    if text.contains("IGNORING_INTERRUPT_READY"), !cancelled { cancelled = true; cancelTask() }
                }
                guard cancelled, finished, kill(child, 0) != 0 else { fatalError("Cancellation did not stop and reap the owned PTY child") }
                print("PASS: Ctrl+C ignored branch bounded TERM stops only the owned PTY process group")
                window.delegate = nil
                window.close()
                reader?.cancel()
                if master >= 0 { Darwin.close(master); master = -1 }
                try rawLog.close()
                try FileManager.default.removeItem(at: session)
            }
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let test = try SetupProjectWindow(project: CommandLine.arguments[1], tools: URL(fileURLWithPath: CommandLine.arguments[2]))
        try test.verifyEmbeddedTerminal()
        let cancelTest = try SetupProjectWindow(project: CommandLine.arguments[1], tools: URL(fileURLWithPath: CommandLine.arguments[2]))
        try cancelTest.verifyCancellationFallback()
      SWIFT
      # Only the encoded key path is used; avoid a redundant synthetic key sequence.
      main = File.join(directory, 'main.swift')
      File.write(main, source + harness)
      binary = File.join(directory, 'window-tests')
      out, err, status = Open3.capture3('/usr/bin/xcrun', 'swiftc', main, '-o', binary)
      assert status.success?, out + err
      out, err, status = Open3.capture3(binary, directory, tools)
      assert status.success?, out + err
      assert_includes out, 'PASS: real WKWebView + PTY'
      assert_includes out, 'PASS: Ctrl+C ignored branch'
      assert_includes out, 'PASS: tool build, SDK/Dart'
      assert_includes out, 'PASS: five visible monospace'
      assert_includes out, 'PASS: real NSSplitView'
      refute File.exist?(File.join(directory, 'NEVER'))
    end
  end
end
