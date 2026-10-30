// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentBar", targets: ["AgentBar"]),
        .executable(name: "agentbar-dump", targets: ["agentbar-dump"]),
    ],
    targets: [
        // Leitura e interpretação dos arquivos do Claude Code, sem UI.
        .target(name: "AgentBarCore"),
        // App da barra de menus.
        .executableTarget(name: "AgentBar", dependencies: ["AgentBarCore"]),
        // Ferramenta de diagnóstico: mostra no terminal o que o app está lendo.
        .executableTarget(name: "agentbar-dump", dependencies: ["AgentBarCore"]),
        .testTarget(name: "AgentBarCoreTests", dependencies: ["AgentBarCore"]),
    ]
)
