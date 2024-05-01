//
//  main.swift
//  BatFi
//
//  Created by Adam Różyński on 01/05/2024.
//

import Foundation
import Sentry

let app: NSApplication = SentryCrashExceptionApplication.shared
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
