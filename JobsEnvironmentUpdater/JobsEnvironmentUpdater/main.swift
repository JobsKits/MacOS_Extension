//
//  main.swift
//  JobsEnvironmentUpdater
//
//  Created by Jobs on 2026年11月17日，星期二.
//

import AppKit

private let appDelegate = AppDelegate.make()
NSApplication.shared.byDelegate(appDelegate)
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
