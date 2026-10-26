//
//  AppDelegate.swift
//  PicPress
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var controller: MainViewController?
    /// Files that arrive through "Open With" before the window exists yet.
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        let controller = MainViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "PicPress"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.minSize = NSSize(width: 700, height: 520)
        window.setContentSize(NSSize(width: 760, height: 600))
        window.center()
        window.setFrameAutosaveName("PicPressMainWindow")
        window.makeKeyAndOrderFront(nil)

        self.controller = controller
        self.window = window

        NSApp.activate(ignoringOtherApps: true)

        if !pendingURLs.isEmpty {
            let urls = pendingURLs
            pendingURLs.removeAll()
            controller.queue.add(urls: urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let controller else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        window?.makeKeyAndOrderFront(nil)
        controller.queue.add(urls: urls)
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.queue.cleanupTemporaryFiles()
    }

    // MARK: - Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        // Application menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(withTitle: "关于 PicPress",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 PicPress",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "隐藏其他",
                                         action: #selector(NSApplication.hideOtherApplications(_:)),
                                         keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "显示全部",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 PicPress",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        // File menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "文件")
        fileMenuItem.submenu = fileMenu

        let addItem = NSMenuItem(title: "添加图片…", action: #selector(addFiles), keyEquivalent: "o")
        addItem.target = self
        fileMenu.addItem(addItem)

        let exportItem = NSMenuItem(title: "全部导出…", action: #selector(exportAll), keyEquivalent: "e")
        exportItem.target = self
        fileMenu.addItem(exportItem)

        fileMenu.addItem(.separator())

        let clearItem = NSMenuItem(title: "清空列表", action: #selector(clearAll), keyEquivalent: "\u{8}")
        clearItem.keyEquivalentModifierMask = [.command, .shift]
        clearItem.target = self
        fileMenu.addItem(clearItem)

        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "关闭窗口",
                         action: #selector(NSWindow.performClose(_:)),
                         keyEquivalent: "w")

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "最小化",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放",
                           action: #selector(NSWindow.performZoom(_:)),
                           keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func addFiles() {
        controller?.queue.chooseFiles()
    }

    @objc private func exportAll() {
        controller?.queue.exportAll()
    }

    @objc private func clearAll() {
        controller?.queue.clear()
    }
}
