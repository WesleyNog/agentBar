// Desenha o ícone do AgentBar e gera Resources/AppIcon.icns.
// Uso: swift scripts/make-icon.swift [pasta-de-saída]   (padrão: Resources)
//
// Duas barras de uso (sessão e semana) sobre um fundo escuro, com três pontos
// em cima representando os agentes de um workflow.
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources", isDirectory: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Desenha numa grade de 1024 pontos; `scale` ajusta para o tamanho pedido.
func drawIcon(in context: CGContext, scale: CGFloat) {
    context.scaleBy(x: scale, y: scale)

    // Corpo no grid de ícones do macOS: 824 pontos com margem de 100.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, alpha: 0.35).cgColor)
    context.addPath(bodyPath)
    context.setFillColor(color(0x161B2E).cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    let background = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0x2B3557).cgColor, color(0x12172A).cgColor] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    // Barras: trilho claro e preenchimento colorido.
    func bar(y: CGFloat, fraction: CGFloat, fill: NSColor) {
        let track = CGRect(x: 232, y: y, width: 560, height: 92)
        context.addPath(CGPath(roundedRect: track, cornerWidth: 46, cornerHeight: 46, transform: nil))
        context.setFillColor(color(0xFFFFFF, alpha: 0.14).cgColor)
        context.fillPath()

        let filled = CGRect(x: track.minX, y: y, width: max(track.height, track.width * fraction), height: track.height)
        context.addPath(CGPath(roundedRect: filled, cornerWidth: 46, cornerHeight: 46, transform: nil))
        context.setFillColor(fill.cgColor)
        context.fillPath()
    }
    bar(y: 452, fraction: 0.64, fill: color(0xFF8A5B))
    bar(y: 300, fraction: 0.38, fill: color(0x5AC8FA))

    // Agentes: três pontos ligados por uma linha.
    let dots = [CGPoint(x: 300, y: 690), CGPoint(x: 512, y: 690), CGPoint(x: 724, y: 690)]
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.35).cgColor)
    context.setLineWidth(14)
    context.move(to: dots[0])
    context.addLine(to: dots[2])
    context.strokePath()
    for (index, dot) in dots.enumerated() {
        let radius: CGFloat = 44
        context.addEllipse(in: CGRect(x: dot.x - radius, y: dot.y - radius, width: radius * 2, height: radius * 2))
        context.setFillColor((index == 1 ? color(0xFF8A5B) : color(0xFFFFFF, alpha: 0.9)).cgColor)
        context.fillPath()
    }
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    graphics.imageInterpolation = .high
    drawIcon(in: graphics.cgContext, scale: CGFloat(size) / 1024)
    graphics.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

for points in [16, 32, 128, 256, 512] {
    try png(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try png(size: 1024).write(to: output.appendingPathComponent("AppIcon-preview.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil falhou") }
print(output.appendingPathComponent("AppIcon.icns").path)
