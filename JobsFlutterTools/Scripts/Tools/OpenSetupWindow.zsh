#!/bin/zsh
# GUI 转发器：优先随包窗口并显示真实 PTY；项目变更仍须在窗口下半终端中确认。
typeset SETUP_GUI_TOOLS="${0:A:h}" SETUP_GUI_CACHE="" SETUP_GUI_KEY="" SETUP_GUI_BINARY=""
# 仅解析固定动作与绝对路径，启动器不执行SDK或依赖业务。
setup_gui_prepare() {
    setopt NO_NOMATCH PIPE_FAIL
    [[ $# == 2 && "$1" == --project && "$2" == /* && -d "$2" ]] || { print -u2 '用法：OpenSetupWindow.zsh --project <Flutter项目绝对路径>'; exit 2; }
    [[ -f "$SETUP_GUI_TOOLS/SetupGUIAssets/terminal.html" ]] || exit 1
    SETUP_GUI_CACHE="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/JobsFlutterSetupGUI.XXXXXX")" || exit 1
    SETUP_GUI_BINARY="$SETUP_GUI_CACHE/Flutter项目配置.app/Contents/MacOS/JobsFlutterSetup"
    /bin/mkdir -p "${SETUP_GUI_BINARY:h}" || exit 1
    /bin/cat > "$SETUP_GUI_CACHE/Flutter项目配置.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.jobs.flutterprojectsetup.window</string><key>CFBundleExecutable</key><string>JobsFlutterSetup</string><key>CFBundleName</key><string>Flutter项目配置</string><key>CFBundlePackageType</key><string>APPL</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
    if [[ -f "$SETUP_GUI_TOOLS/JobsFlutterSetup" && -x "$SETUP_GUI_TOOLS/JobsFlutterSetup" && ! -L "$SETUP_GUI_TOOLS/JobsFlutterSetup" ]]; then
        /bin/cp -p "$SETUP_GUI_TOOLS/JobsFlutterSetup" "$SETUP_GUI_BINARY" || exit 1
        return 0
    fi
    [[ -f "$SETUP_GUI_TOOLS/SetupProjectWindow.swift" && ! -L "$SETUP_GUI_TOOLS/SetupProjectWindow.swift" ]] || { print -u2 '缺少随包窗口及窗口源码，请重新取得完整发布包。'; exit 1; }
    if ! /usr/bin/xcode-select -p > "$SETUP_GUI_CACHE/developer-path.log" 2>&1; then
        /usr/bin/osascript -e 'display alert "缺少窗口构建工具" message "当前为仅源码入口，未包含预编译窗口。请本人安装Apple Command Line Tools或完整Xcode后重试，或使用已构建的完整扩展包。" as warning' >/dev/null 2>&1
        exit 1
    fi
    /usr/bin/xcrun swiftc "$SETUP_GUI_TOOLS/SetupProjectWindow.swift" -o "$SETUP_GUI_BINARY" 2> "$SETUP_GUI_CACHE/compile.log" || {
        /usr/bin/osascript -e 'display alert "Flutter 配置窗口无法启动" message "窗口编译失败，请查看系统临时目录 JobsFlutterSetupGUI 中的 compile.log。" as critical' >/dev/null 2>&1
        exit 1
    }
}
# 编译成功后移交窗口，脚本退出不关闭窗口拥有的PTY。
setup_gui_launch() {
    exec "$SETUP_GUI_BINARY" --project "$2" --tools "$SETUP_GUI_TOOLS"
}
# 内部转发入口不重复终端确认，实际业务在GUI中保留完整自述。
main() {
    setup_gui_prepare "$@" # 校验固定参数并复用随包窗口，源码模式才编译。
    setup_gui_launch "$@" # 打开里程碑与真实交互终端。
}
main "$@"
