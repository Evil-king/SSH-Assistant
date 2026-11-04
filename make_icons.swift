import Cocoa

// 生成两个 1024×1024 的 app 图标：SSH 主机（选择器）与 添加SSH（带加号）
func drawIcon(to path: String, withPlus: Bool) {
    let size: CGFloat = 1024
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    // 背景：圆角方形 + 蓝色渐变
    let inset: CGFloat = 70
    let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let bgPath = NSBezierPath(roundedRect: body, xRadius: 225, yRadius: 225)
    let bg = NSGradient(colors: [
        NSColor(srgbRed: 0.25, green: 0.48, blue: 0.98, alpha: 1),
        NSColor(srgbRed: 0.05, green: 0.17, blue: 0.48, alpha: 1),
    ])!
    bg.draw(in: bgPath, angle: -90)

    // 外描边
    NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.12).setStroke()
    bgPath.lineWidth = 6
    bgPath.stroke()

    // 终端窗口
    let win = NSRect(x: 180, y: 300, width: 664, height: 480)
    let winPath = NSBezierPath(roundedRect: win, xRadius: 46, yRadius: 46)
    NSColor(srgbRed: 0.04, green: 0.06, blue: 0.10, alpha: 0.94).setFill()
    winPath.fill()

    // 标题栏三个圆点
    let dots: [(CGFloat, NSColor)] = [
        (180 + 46, NSColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1)),
        (180 + 88, NSColor(srgbRed: 1, green: 0.74, blue: 0.25, alpha: 1)),
        (180 + 130, NSColor(srgbRed: 0.27, green: 0.80, blue: 0.35, alpha: 1)),
    ]
    for (x, color) in dots {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: 300 + 480 - 56, width: 26, height: 26)).fill()
    }

    let green = NSColor(srgbRed: 0.33, green: 0.90, blue: 0.55, alpha: 1)

    // 提示符 >
    let font = NSFont(name: "Menlo-Bold", size: 290) ?? NSFont.monospacedSystemFont(ofSize: 300, weight: .bold)
    let prompt = NSAttributedString(string: ">_", attributes: [.font: font, .foregroundColor: green])
    prompt.draw(at: NSPoint(x: 250, y: 430))

    if withPlus {
        // 窗口内右侧一个大加号，表示「添加」
        green.setStroke()
        let bar = NSBezierPath()
        bar.lineWidth = 44
        bar.lineCapStyle = .round
        bar.move(to: NSPoint(x: 700, y: 460))
        bar.line(to: NSPoint(x: 700, y: 660))
        bar.move(to: NSPoint(x: 600, y: 560))
        bar.line(to: NSPoint(x: 800, y: 560))
        bar.stroke()
    }

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("render failed")
        exit(1)
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

let args = CommandLine.arguments
guard args.count > 1 else {
    print("usage: make_icons <outdir>")
    exit(2)
}
let dir = args[1]
drawIcon(to: dir + "/icon-hosts.png", withPlus: false)
drawIcon(to: dir + "/icon-add.png", withPlus: true)
