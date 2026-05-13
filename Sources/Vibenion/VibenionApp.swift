import AppKit
import SwiftUI

@main
struct VibenionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panelController: IslandPanelController?
    private let store = AgentSessionStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        showIsland()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles.rectangle.stack", accessibilityDescription: "Vibenion")
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.action = #selector(toggleIsland)
        item.button?.target = self
        statusItem = item
    }

    @objc private func toggleIsland() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
            return
        }

        guard let panelController else {
            showIsland()
            return
        }

        if panelController.isVisible {
            panelController.toggleExpanded()
        } else {
            panelController.show()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Vibenion", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        if let button = statusItem?.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showIsland() {
        if panelController == nil {
            panelController = IslandPanelController(store: store)
        }
        panelController?.show()
    }
}
