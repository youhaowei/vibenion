import AppKit
import SwiftUI

@MainActor
final class IslandPanelController {
    private enum Metrics {
        static let panelSize = CGSize(width: 600, height: 420)
    }

    private let panel: NSPanel
    private let presentation = IslandPresentation()
    private let hostingController: NSHostingController<IslandRootView>
    private let store: AgentSessionStore

    var isVisible: Bool {
        panel.isVisible
    }

    init(store: AgentSessionStore) {
        self.store = store

        let initialNotch = Self.geometry(for: NSScreen.builtInOrMain)
        let rootView = IslandRootView(store: store, presentation: presentation, notch: initialNotch)
        hostingController = NSHostingController(rootView: rootView)
        hostingController.safeAreaRegions = []
        hostingController.sceneBridgingOptions = []

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.panelSize.width, height: Metrics.panelSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .mainMenu + 3
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)
    }

    func show() {
        positionPanel()
        panel.orderFrontRegardless()
    }

    func toggleExpanded() {
        presentation.isExpanded.toggle()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func positionPanel() {
        let screen = NSScreen.builtInOrMain
        let notch = Self.geometry(for: screen)
        hostingController.rootView = IslandRootView(store: store, presentation: presentation, notch: notch)

        let screenFrame = screen.frame
        let x = screenFrame.midX - Metrics.panelSize.width / 2
        let y = screenFrame.maxY - Metrics.panelSize.height
        panel.setFrame(
            NSRect(x: x.rounded(), y: y.rounded(), width: Metrics.panelSize.width, height: Metrics.panelSize.height),
            display: true
        )
    }

    private static func geometry(for screen: NSScreen) -> NotchGeometry {
        NotchGeometry(notchSize: screen.notchSize, hasRealNotch: screen.hasNotch)
    }
}
