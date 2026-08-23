//  Log.swift
//  Loggers are process-wide and isolation-free on purpose: any layer may log
//  without hopping actors.

import os

enum Log {
    private static let subsystem = "com.todddube.VibeStats"

    static let app     = Logger(subsystem: subsystem, category: "app")
    static let menuBar = Logger(subsystem: subsystem, category: "menubar")
    static let engine  = Logger(subsystem: subsystem, category: "engine")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let store   = Logger(subsystem: subsystem, category: "store")
    static let notify  = Logger(subsystem: subsystem, category: "notifications")
}
