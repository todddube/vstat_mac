//  main.swift
//  A plain AppKit entry point.
//
//  This was a SwiftUI `App` with a `Settings` scene, and the Settings window
//  did not open: reaching it means sending `showSettingsWindow:` — a selector
//  SwiftUI installs on the responder chain but does not expose or document —
//  and for an accessory app that responder chain is not reliably in place.
//
//  Owning the windows outright removes the guesswork. SwiftUI still draws
//  everything; it just no longer decides when a window exists.

import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
