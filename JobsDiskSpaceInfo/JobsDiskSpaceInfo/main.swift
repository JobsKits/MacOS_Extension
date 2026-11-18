//
//  main.swift
//  JobsDiskSpaceInfo
//
//  Created by Jobs on 2026年11月15日，星期日.
//

import AppKit

private let appDelegate = AppDelegate.make()
NSApplication.shared.byDelegate(appDelegate)
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
