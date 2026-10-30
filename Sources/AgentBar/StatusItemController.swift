import AppKit
import SwiftUI

/// Item na barra de menus: rótulo de duas linhas em SwiftUI e popover ao clicar.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let labelView = ClickThroughHostingView(rootView: StatusItemLabel(session: 27, week: 45))

    override init() {
        super.init()

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView())

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))

        labelView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(labelView)
        NSLayoutConstraint.activate([
            labelView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            labelView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            labelView.topAnchor.constraint(equalTo: button.topAnchor),
            labelView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        statusItem.length = labelView.fittingSize.width
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Sem ativar o app, o popover não recebe foco e não fecha ao clicar fora.
            NSApp.activate()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}

/// Deixa o clique passar para o botão do item da barra, que é quem abre o popover.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
