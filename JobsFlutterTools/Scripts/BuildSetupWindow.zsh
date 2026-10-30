#!/bin/zsh
# 内部Xcode构建入口：资源复制后生成配置窗口可执行文件，签名前写入产物，不写源码目录。
typeset BUILD_SETUP_OUTPUT="" BUILD_SETUP_SOURCE="" BUILD_SETUP_WORK=""
# 仅在Xcode产物环境中工作，限定平台、架构及部署目标。
build_setup_initialize() {
    setopt NO_NOMATCH PIPE_FAIL
    [[ -n "${TARGET_BUILD_DIR:-}" && -n "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" && -n "${SRCROOT:-}" ]] || { print -u2 '此脚本只供Xcode构建阶段使用。'; exit 2; }
    BUILD_SETUP_SOURCE="$SRCROOT/Scripts/Tools/SetupProjectWindow.swift"
    BUILD_SETUP_OUTPUT="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Tools/JobsFlutterSetup"
    [[ -f "$BUILD_SETUP_SOURCE" && -d "${BUILD_SETUP_OUTPUT:h}" ]] || { print -u2 '配置窗口源码或已复制Tools资源缺失。'; exit 1; }
    BUILD_SETUP_WORK="$(/usr/bin/mktemp -d "${TEMP_DIR:-${TMPDIR:-/tmp}}/JobsFlutterSetupBuild.XXXXXX")" || exit 1
    print -r -- "构建配置窗口：$BUILD_SETUP_SOURCE → $BUILD_SETUP_OUTPUT；目标macOS ${MACOSX_DEPLOYMENT_TARGET:-12.0}。"
}
# 为当前target全部架构构建并合并，成品不依赖目标电脑安装swiftc或CLT。
build_setup_compile() {
    local architecture="" target="${MACOSX_DEPLOYMENT_TARGET:-12.0}" sdk="${SDKROOT:-}" result=0
    local -a architectures products
    architectures=( ${=ARCHS:-arm64} )
    [[ "$target" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ]] || exit 2
    [[ -d "$sdk" ]] || sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)" || exit 1
    for architecture in "${architectures[@]}"; do
        [[ "$architecture" == arm64 || "$architecture" == x86_64 ]] || { print -u2 "不支持的窗口架构：$architecture"; exit 2; }
        /usr/bin/xcrun --sdk macosx swiftc -sdk "$sdk" -target "$architecture-apple-macos$target" "$BUILD_SETUP_SOURCE" -o "$BUILD_SETUP_WORK/JobsFlutterSetup-$architecture" || exit $?
        products+=("$BUILD_SETUP_WORK/JobsFlutterSetup-$architecture")
    done
    (( ${#products} > 0 )) || exit 2
    /usr/bin/xcrun lipo -create "${products[@]}" -output "$BUILD_SETUP_WORK/JobsFlutterSetup" || exit $?
    /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --timestamp=none "$BUILD_SETUP_WORK/JobsFlutterSetup" || exit $?
    /bin/mv -f "$BUILD_SETUP_WORK/JobsFlutterSetup" "$BUILD_SETUP_OUTPUT" || exit 1
    /bin/chmod 755 "$BUILD_SETUP_OUTPUT" || exit 1
    /usr/bin/codesign --verify --strict "$BUILD_SETUP_OUTPUT" || exit 1
    /bin/rm -f -- "${products[@]}"
    /bin/rmdir "$BUILD_SETUP_WORK" || exit 1
}
# 构建阶段只生成随包窗口，不运行或注册Finder扩展。
main() {
    build_setup_initialize # 确认源码、产物及已复制资源位置。
    build_setup_compile # 编译全部目标架构并签名配置窗口。
}
main "$@"
