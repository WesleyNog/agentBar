import AgentBarCore
import AppKit
import Observation
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class SettingsModel {
    let store: AgentBarStore
    var errorMessage: String?
    private(set) var loginItemStatus: SMAppService.Status = LoginItem.status

    init(store: AgentBarStore) {
        self.store = store
    }

    private var installer: StatusLineInstaller {
        StatusLineInstaller(paths: store.paths)
    }

    // MARK: Status line

    func connect() {
        run { try installer.connect() }
    }

    func disconnect() {
        run { try installer.disconnect() }
    }

    private func run(_ change: () throws -> Void) {
        do {
            try change()
            errorMessage = nil
        } catch StatusLineInstaller.InstallError.invalidSettings {
            errorMessage = String(localized: "settings.json isn't valid JSON, so AgentBar didn't change it.")
        } catch {
            errorMessage = String(localized: "Couldn't change settings.json: \(error.localizedDescription)")
        }
        Task { await store.refreshNow() }
    }

    // MARK: Abrir no login

    var loginItemEnabled: Bool {
        loginItemStatus == .enabled || loginItemStatus == .requiresApproval
    }

    func setLoginItem(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Couldn't change Open at login: \(error.localizedDescription)")
        }
        refreshLoginItemStatus()
    }

    func refreshLoginItemStatus() {
        loginItemStatus = LoginItem.status
    }

    // MARK: Pasta do Claude Code

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.directoryURL = store.paths.root
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose the Claude Code folder (usually ~/.claude).")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        AppPreferences.setClaudeDirectory(url)
        store.setPaths(AppPreferences.claudePaths)
    }

    func useDefaultFolder() {
        AppPreferences.setClaudeDirectory(nil)
        store.setPaths(AppPreferences.claudePaths)
    }
}

struct SettingsView: View {
    let model: SettingsModel
    @State private var confirmingConnect = false
    @State private var confirmingDisconnect = false

    private var paths: ClaudePaths { model.store.paths }
    private var statusLine: StatusLineInstaller.State? { model.store.snapshot.statusLine }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Claude Code connection") {
                connectionSection.padding(8)
            }
            GroupBox("General") {
                loginSection.padding(8)
            }
            GroupBox("Claude Code folder") {
                folderSection.padding(8)
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("AgentBar \(appVersion) · Unofficial project, not affiliated with Anthropic.")
                    .foregroundStyle(.secondary)
                Spacer()
                Link(destination: Self.repository) {
                    Text(verbatim: "GitHub")
                }
            }
            .font(.caption)
        }
        .padding(20)
        .frame(width: 480)
        .alert("Connect AgentBar to Claude Code?", isPresented: $confirmingConnect) {
            Button("Connect") { model.connect() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: connectMessage)
        }
        .alert("Disconnect AgentBar from Claude Code?", isPresented: $confirmingDisconnect) {
            Button("Disconnect") { model.disconnect() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("AgentBar will put back the status line you had before and remove its script. Your usage limits will stop updating.")
        }
        .onAppear { model.refreshLoginItemStatus() }
    }

    // MARK: Seções

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                connectionStatus
                Spacer()
                switch statusLine {
                case .connected:
                    Button("Disconnect…") { confirmingDisconnect = true }
                case .otherCommand, .notConfigured:
                    Button("Connect…") { confirmingConnect = true }
                        .keyboardShortcut(.defaultAction)
                case nil:
                    EmptyView()
                }
            }
            Text("AgentBar reads your usage limits from Claude Code's status line. Connecting installs a small script and points the status line in settings.json to it. The status line you use today keeps working, and settings.json is backed up first.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var connectionStatus: some View {
        switch statusLine {
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .otherCommand(let command):
            VStack(alignment: .leading, spacing: 2) {
                Label("Not connected", systemImage: "circle")
                Text("Current status line: \(command)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .notConfigured:
            Label("Not connected", systemImage: "circle")
        case nil:
            Label("settings.json isn't valid JSON. Fix it to connect.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var loginSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Open at login", isOn: Binding(get: { model.loginItemEnabled }, set: { model.setLoginItem($0) }))
                .disabled(!LoginItem.isAvailable)
            if model.loginItemStatus == .requiresApproval {
                HStack {
                    Text("Allow AgentBar in System Settings › General › Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open") { SMAppService.openSystemSettingsLoginItems() }
                        .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: paths.root.path)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack {
                if AppPreferences.hasCustomClaudeDirectory {
                    Button("Use default") { model.useDefaultFolder() }
                }
                Spacer()
                Button("Choose…") { model.chooseFolder() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Textos

    private var connectMessage: String {
        let settings = (paths.settingsFile.path as NSString).abbreviatingWithTildeInPath
        let backups = (paths.backupsDirectory.path as NSString).abbreviatingWithTildeInPath
        if case .otherCommand(let command) = statusLine {
            return String(localized: "AgentBar will change the status line in \(settings). Your current status line (\(command)) keeps running through AgentBar's script. A backup of settings.json is saved in \(backups).")
        }
        return String(localized: "AgentBar will add a status line to \(settings). A backup of settings.json is saved in \(backups).")
    }

    private static let repository = URL(string: "https://github.com/WesleyNog/agentBar")!

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

/// Janela de ajustes própria: o app não tem menu principal nem cena SwiftUI.
@MainActor
final class SettingsWindowController {
    private let model: SettingsModel
    private var window: NSWindow?

    init(store: AgentBarStore) {
        model = SettingsModel(store: store)
    }

    func show() {
        if window == nil {
            let content = NSHostingController(rootView: SettingsView(model: model))
            content.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: content)
            window.title = String(localized: "AgentBar Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        model.refreshLoginItemStatus()
        NSApp.activateFromMenuBar()
        window?.makeKeyAndOrderFront(nil)
    }
}
