//
//  main.swift
//  PicPress
//

import AppKit

// Swift 5 language mode does not isolate top-level code, so hop onto the main
// actor explicitly: every piece of AppKit wiring below is main-actor bound.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.setActivationPolicy(.regular)

    let delegate = AppDelegate()
    application.delegate = delegate

    application.run()
}
