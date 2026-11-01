import AppKit
import SwiftUI

@MainActor
final class MenuBar: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private let model = ControlModel()
    private var pendingURLs: [URL] = []
    private var ready = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "Sony headphone controls")
        item.button?.target = self
        item.button?.action = #selector(statusClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.toolTip = "Sony Control"
        model.onStatus = { [weak self] state in
            self?.item.button?.title = state?.battery.map { " \($0)%" } ?? ""
        }
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let hosting = NSHostingController(rootView: WidgetView(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 360, height: 390)
        model.start()
        ready = true
        if pendingURLs.isEmpty { showPanel() }
        else { let urls = pendingURLs; pendingURLs.removeAll(); handle(urls) }
        if ProcessInfo.processInfo.environment["SONY_WIDGET_CHECK"] == "1" {
            Task {
                do { try await model.verifyWidgetQueue(); print("WIDGET CHECK PASSED") }
                catch { fputs("WIDGET CHECK FAILED: \(error)\n", stderr) }
                captureOwnView()
                fflush(stdout)
            }
        } else if ProcessInfo.processInfo.environment["SONY_WIDGET_CAPTURE"] != nil {
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                captureOwnView()
            }
        }
    }
    private func captureOwnView() {
        guard let path = ProcessInfo.processInfo.environment["SONY_WIDGET_CAPTURE"],
              let view = popover.contentViewController?.view else { return }
        print("Popover view bounds: \(view.bounds)")
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        do {
            guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
            try data.write(to: URL(fileURLWithPath: path))
            print("Popover capture: \(path)"); fflush(stdout)
        } catch { fputs("Popover capture failed: \(error)\n", stderr) }
    }
    @objc private func statusClicked(_ sender: Any?) {
        if NSApplication.shared.currentEvent?.type == .rightMouseUp {
            popover.performClose(nil)
            let menu = NSMenu()
            for (label, action) in [("Show Controls", #selector(showPanel)), ("Reconnect", #selector(refresh)), ("Disconnect Controls", #selector(disconnect)), ("Quit Sony Control", #selector(quit))] {
                let entry = NSMenuItem(title: label, action: action, keyEquivalent: "")
                entry.target = self; menu.addItem(entry)
            }
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else if popover.isShown { popover.performClose(nil) }
        else { showPanel() }
    }
    @objc private func showPanel() {
        guard let button = item.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard ready else { pendingURLs.append(contentsOf: urls); return }
        handle(urls)
    }
    private func handle(_ urls: [URL]) {
        for url in urls where url.scheme == "sonycontrol" {
            if url.host == "mode", let mode = url.pathComponents.last, ["anc", "ambient", "off"].contains(mode) {
                model.enqueue(.mode(mode))
            } else if url.host == "controls" { showPanel() }
        }
    }
    @objc private func refresh() { model.enqueue(.refresh) }
    @objc private func disconnect() { model.disconnect() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { model.stop() }
}

@MainActor
func runMenuBar() -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = MenuBar()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
    exit(0)
}
