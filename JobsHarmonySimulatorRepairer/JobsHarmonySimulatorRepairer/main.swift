//
//  main.swift
//  JobsHarmonySimulatorRepairer
//
//  Created by Jobs on 2026年10月24日，星期六.
//

import AppKit

// 纯代码宿主没有 nib 连接，代理必须挂接并保留到事件循环结束。
private let appDelegate = AppDelegate()
NSApplication.shared.byDelegate(appDelegate)
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
