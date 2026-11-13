//
//  main.swift
//  JobsFileHasher
//
//  Created by Jobs on 2026年11月6日，星期五.
//

import AppKit

if CommandLine.arguments.count > 1,
   CommandLine.arguments[1] == "--hash-file" {
    guard CommandLine.arguments.count == 3 else {
        print("✖ 文件指纹入口仅接受一个绝对文件路径。")
        exit(2)
    }
    exit(FileHashCommand.run(path: CommandLine.arguments[2]))
}

// 纯代码宿主须在进入事件循环前强持有并挂接委托。
private let appDelegate = AppDelegate()
NSApplication.shared.byDelegate(appDelegate)
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
