//
//  GitRemoteBrowserOpener.swift
//  JobsGitRemoteOpener
//
//  Created by Jobs on 2026年11月13日，星期五.
//

import AppKit
import Darwin

// 两个宿主共用打开流程；Finder 沙盒只负责转交文件夹请求。
struct GitRemoteBrowserOpener {
    struct Remote {
        let name: String
        let address: String
    }

    // 唯一 remote 直接打开，多个 remote 只向交互终端派发选择。
    func open(from folderURL: URL) throws {
        let remotes = try configuredRemotes(at: folderURL)
        guard !remotes.isEmpty else {
            throw failure("仓库没有配置 remote：\(folderURL.path)")
        }
        if remotes.count == 1 {
            let webURL = try GitRemoteResolver().webURL(forRemoteURLString: remotes[0].address)
            guard NSWorkspace.shared.open(webURL) else {
                throw failure("浏览器未能打开 Git 远程地址。")
            }
            return
        }
        let request = try prepareSelection(remotes: remotes)
        do {
            try dispatch(commandLine: "/bin/zsh \(shellWord(request.path))")
        } catch {
            try? FileManager.default.removeItem(at: request)
            try? FileManager.default.removeItem(at: request.deletingLastPathComponent())
            throw error
        }
    }

    // 原生 Git 解析 include、子模块与 worktree 配置，不依赖当前分支优先级。
    func configuredRemotes(at folderURL: URL) throws -> [Remote] {
        let names = try git(["remote"], at: folderURL).split(separator: "\n").map(String.init)
        return try names.map { name in
            let configured = try git(["config", "--null", "--get-all", "remote.\(name).url"], at: folderURL)
            let value = configured.split(separator: "\0", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            guard !value.isEmpty else {
                throw failure("远程 \(name) 没有有效地址。")
            }
            return Remote(name: name, address: value)
        }
    }

    // Git 只读取本地配置；错误不回显可能含认证信息的命令输出。
    private func git(_ arguments: [String], at folderURL: URL) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folderURL.path] + arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let value = String(data: data, encoding: .utf8) else {
            throw failure("无法读取当前文件夹的 Git 远程配置，请检查 Git 和仓库元数据。")
        }
        return value
    }

    // 私有载体只保存本轮候选，结束时由终端精确删除自身。
    func prepareSelection(remotes: [Remote]) throws -> URL {
        var template = Array(FileManager.default.temporaryDirectory.appendingPathComponent("JobsGitRemoteOpen-XXXXXX").path.utf8CString)
        guard let path = mkdtemp(&template) else {
            throw failure("无法创建远程地址选择的私有临时目录。")
        }
        let directory = URL(fileURLWithPath: String(cString: path), isDirectory: true)
        let scriptURL = directory.appendingPathComponent("select.zsh")
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let script = selectionScript(remotes: remotes)
            guard FileManager.default.createFile(atPath: scriptURL.path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o600]) else {
                throw failure("无法写入远程地址选择载体。")
            }
        } catch {
            try? FileManager.default.removeItem(at: scriptURL)
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        return scriptURL
    }

    // fzf 返回固定 ID 后才读取 URL；取消、空选与错误都不能取默认仓库。
    func selectionScript(remotes: [Remote]) -> String {
        let urls = remotes.map { remote in
            (try? GitRemoteResolver().webURL(forRemoteURLString: remote.address).absoluteString) ?? ""
        }
        let rows = zip(remotes.indices, remotes).map { index, remote in
            let label = urls[index].isEmpty ? "（地址类型不支持）" : urls[index]
            return shellWord("\(index + 1)\t\(remote.name)\t\(label)")
        }
        return #"""
        # shell: zsh
        # 脚本自述：选择本次右键请求要打开的 Git 远程网页；不修改仓库或 Git 配置。
        # 运行提示：方向键选择、回车打开；取消行、Esc 或 Ctrl+C 停止。
        JOBS_SELECTOR=""
        LOG_FILE=""
        # 保留业务退出码，只清理本轮私有载体。
        TRAPEXIT() {
          local result=$?
          /bin/rm -f -- "$JOBS_SELECTOR"
          /bin/rmdir -- "${JOBS_SELECTOR:h}" 2>/dev/null
          return "$result"
        }
        # 中断选择不得继续打开浏览器。
        TRAPINT() {
          exit 130
        }
        # 关闭终端时回收本轮载体。
        TRAPHUP() {
          exit 129
        }
        # 外部终止保持可识别的状态。
        TRAPTERM() {
          exit 143
        }
        # 只准备当前请求的路径与命令搜索范围。
        initialize_selection() {
          setopt NO_NOMATCH
          JOBS_SELECTOR="${${(%):-%x}:A}"
          LOG_FILE="${TMPDIR:-/tmp}/JobsGitRemoteOpen-${$}.log"
          path+=(/opt/homebrew/bin /usr/local/bin)
        }
        # 日志不包含远程 URL 中的认证数据。
        record_result() {
          print -r -- "$1" | /usr/bin/tee -a "$LOG_FILE"
        }
        # 右键已明确发起只读打开，fzf 回车即确认本轮目标。
        show_selection_intro() {
          print -r -- '打开 Git 远程地址：检测到多个 remote，请选择要打开的仓库。'
          print -r -- '仅打开选中的网页，不修改 Git 配置。↑/↓ 或 Tab 选择，回车确认；Esc / Ctrl+C 取消。'
          print -r -- "日志：$LOG_FILE"
        }
        # 检查真实 fzf 能力，不自动安装工具或退回默认远程。
        select_and_open() {
          local fzf_bin="$(command -v fzf)" help_text="" chosen="" selection_result=0 index=""
          local -a rows=(
        \#(rows.joined(separator: "\n"))
          ) urls=(\#(urls.map(shellWord).joined(separator: " ")))
          if [[ -z "$fzf_bin" ]] || ! FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE=/dev/null "$fzf_bin" --version >/dev/null 2>&1; then
            record_result '✖ fzf 缺失或损坏，请先通过 brew install fzf 安装或修复后重试。'
            return 1
          fi
          if ! help_text="$(FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE=/dev/null "$fzf_bin" --help)"; then
            record_result '✖ fzf 能力检查失败，请修复后重试。'
            return 1
          fi
          if [[ "$help_text" != *--bind* || "$help_text" != *--delimiter* || "$help_text" != *--with-nth* ]]; then
            record_result '✖ 当前 fzf 不支持所需选择选项，请更新 fzf 后重试。'
            return 1
          fi
          if [[ ! -t 0 || ! -t 1 ]]; then
            record_result '✖ 当前没有可交互终端，已停止打开。'
            return 1
          fi
          chosen="$(print -rl -- $'cancel\t取消本轮\t' "${rows[@]}" |
            FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE=/dev/null "$fzf_bin" --no-multi --no-sort --layout=reverse --border \
              --delimiter=$'\t' --with-nth=2.. --prompt='远程仓库 > ' \
              --header='↑/↓ 或 Tab 选择、回车打开；← / Esc 取消' \
              --bind='up:up,down:down,tab:down,shift-tab:up,left:abort')" || selection_result=$?
          if (( selection_result != 0 && selection_result != 1 && selection_result != 130 )); then
            record_result "✖ fzf 选择失败（退出码 $selection_result），没有打开任何地址。"
            return "$selection_result"
          fi
          if (( selection_result == 130 || selection_result == 1 )) || [[ -z "$chosen" || "$chosen" == cancel$'\t'* ]]; then
            record_result '已取消，没有打开任何远程地址。'
            return 0
          fi
          index="${chosen%%$'\t'*}"
          if [[ "$index" != <1-> ]] || (( index > ${#urls} )) || [[ "$chosen" != "${rows[index]}" ]]; then
            record_result '✖ 无效的远程选择结果，已停止。'
            return 1
          fi
          if [[ -z "${urls[index]}" ]]; then
            record_result '✖ 所选远程地址类型暂不支持，请检查 remote 配置。'
            return 1
          fi
          if /usr/bin/open "${urls[index]}"; then
            record_result '✔ 已将选中的 Git 远程网页交给默认浏览器。'
          else
            record_result '✖ 浏览器未能打开所选地址。'
            return 1
          fi
        }
        # 编排本次只读选择请求。
        main() {
          initialize_selection # 建立本轮私有文件与日志位置。
          show_selection_intro # 先展示用途及取消方式。
          select_and_open # 仅在有效选择后打开一个网页。
        }
        main "$@"
        """#
    }

    // 路径与 URL 始终作为数据引用，不插入可执行 Shell 语句。
    func shellWord(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x5C:
                result += "\\\\"
            case 0x27:
                result += "\\'"
            case 0...0x1F, 0x7F:
                result += String(format: "\\x%02x", scalar.value)
            case 0x85, 0x2028, 0x2029:
                result += String(format: "\\u%04x", scalar.value)
            default:
                result += String(scalar)
            }
        }
        return "$'\(result)'"
    }

    // Terminal 接收一行启动命令，选择器始终运行在可见 TTY。
    private func dispatch(commandLine: String) throws {
        let script = """
        on run argv
            tell application "Terminal"
                activate
                do script (item 1 of argv)
            end tell
        end run
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, commandLine]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw failure("无法打开 Terminal 选择远程仓库，请检查自动化授权后重试。")
        }
    }

    // 统一宿主可展示的失败描述。
    private func failure(_ message: String) -> NSError {
        return NSError(domain: "JobsGitRemoteOpener", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
