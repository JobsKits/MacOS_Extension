//
//  main.swift
//  JobsHiddenFilesToggler
//
//  Created by Jobs on 2026年10月23日，星期五.
//

import AppKit

// 纯代码宿主没有 nib 连接，代理必须挂接并保留到事件循环结束。
private let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
