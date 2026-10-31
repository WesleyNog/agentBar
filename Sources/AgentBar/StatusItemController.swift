import AgentBarCore
import AppKit
import SwiftUI

/// Item na barra de menus: rótulo de duas linhas em SwiftUI e popover ao clicar.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let popoverState = PopoverState()
    private let labelView: ClickThroughHostingView<StatusItemLabel>
    var openSettings: () -> Void = {}

    init(store: AgentBarStore) {
        labelView = ClickThroughHostingView(rootView: StatusItemLabel(store: store))
        super.init()

        let actions = PopoverActions(
            openSettings: { [weak self] in
                self?.popover.performClose(nil)
                self?.openSettings()
            },
            quit: { NSApp.terminate(nil) }
        )
        let content = NSHostingController(rootView: PopoverView(store: store, state: popoverState, actions: actions))
        content.sizingOptions = .preferredContentSize
        popover.contentViewController = content
        popover.behavior = .transient
        popover.delegate = self

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.setAccessibilityLabel("AgentBar")

        labelView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(labelView)
        NSLayoutConstraint.activate([
            labelView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            labelView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            labelView.topAnchor.constraint(equalTo: button.topAnchor),
            labelView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        // As porcentagens reservam a largura de "100%", então o item não muda de tamanho.
        statusItem.length = labelView.fittingSize.width
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Sem ativar o app, o popover não recebe foco e não fecha ao clicar fora.
            NSApp.activateFromMenuBar()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        // Ao reabrir, começa sempre pela lista.
        popoverState.selectedRunID = nil
    }
}

extension NSApplication {
    /// Traz o app para a frente a partir de um clique no item da barra de menus.
    /// O `activate()` cooperativo (macOS 14+) é recusado nesse caso: o clique na barra
    /// não conta como interação com o app, e o popover ficaria sem foco.
    func activateFromMenuBar() {
        activate(ignoringOtherApps: true)
    }
}

/// Deixa o clique passar para o botão do item da barra, que é quem abre o popover.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
