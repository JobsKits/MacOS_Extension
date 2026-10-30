//
//  main.swift
//  JobsFileCreator
//
//  Created by Jobs on 2026年10月29日，星期四.
//

import AppKit

// 纯代码宿主必须在进入事件循环前挂接并强持有委托。
private let appDelegate = AppDelegate()
NSApplication.shared.byDelegate(appDelegate)
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
