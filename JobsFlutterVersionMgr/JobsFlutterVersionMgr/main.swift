//
//  main.swift
//  JobsFlutterVersionMgr
//
//  Created by Jobs on 2026年10月19日，星期一.
//

import AppKit

// 纯代码宿主没有 nib 连接，必须显式挂接并强持有代理。
private let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
