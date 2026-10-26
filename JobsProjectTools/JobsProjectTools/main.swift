//
//  main.swift
//  JobsProjectTools
//
//  Created by Jobs on 2026年10月26日，星期一.
//

import AppKit

// 纯代码宿主没有 nib 连接，进入事件循环前显式挂接并强持有代理。
private let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
