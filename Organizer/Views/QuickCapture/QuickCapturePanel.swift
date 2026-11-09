import AppKit
import SwiftUI

/// Schwebendes Eingabefeld wie Spotlight. Erscheint über allen Apps, ohne Organizer nach vorne zu holen.
final class QuickCaptureController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private unowned let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func toggle() {
        if let panel, panel.isVisible { close() } else { show() }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        // Inhalt jedes Mal neu, damit Eingabe und Fokus frisch sind.
        panel.contentView = NSHostingView(rootView:
            QuickCaptureView(style: .panel, onDone: { [weak self] in self?.close() })
                .padding(20)
                .frame(width: 640)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .environment(model)
                .onExitCommand { [weak self] in self?.close() }
        )
        panel.setContentSize(panel.contentView!.fittingSize)
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - frame.height * 0.28))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func makePanel() -> NSPanel {
        let panel = CapturePanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 120),
                                 styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
                                 backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.setAccessibilityLabel("Schnellerfassung")
        panel.delegate = self
        return panel
    }
}

/// Randloses Panel, das trotzdem Tastatureingaben annimmt.
private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
