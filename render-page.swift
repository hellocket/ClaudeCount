// Render the intro page HTML to PNG (for the README image) using macOS WebKit.
// Usage: swift render-page.swift <input.html> <output.png> [width=1100]
import AppKit
import WebKit

let args = CommandLine.arguments
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
let width = CGFloat(Double(args.count > 3 ? args[3] : "1100") ?? 1100)

final class Renderer: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 900))
    func start() {
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        web.loadFileURL(input, allowingReadAccessTo: input.deletingLastPathComponent())
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // give web fonts and the label-placement script time to finish
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.measure() }
    }
    func measure() {
        web.evaluateJavaScript("document.fonts.ready.then(()=>0); window.dispatchEvent(new Event('resize')); document.documentElement.scrollHeight") { h, _ in
            let height = CGFloat((h as? NSNumber)?.doubleValue ?? 2000)
            self.web.frame = NSRect(x: 0, y: 0, width: width, height: height)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.snap(height) }
        }
    }
    func snap(_ height: CGFloat) {
        let cfg = WKSnapshotConfiguration()
        cfg.rect = NSRect(x: 0, y: 0, width: width, height: height)
        cfg.snapshotWidth = NSNumber(value: Double(width) * 2) // 2x for Retina
        web.takeSnapshot(with: cfg) { img, err in
            guard let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                print("Failed: \(err?.localizedDescription ?? "?")"); exit(1)
            }
            try! png.write(to: output)
            print("Saved: \(output.lastPathComponent) \(Int(width))x\(Int(height))")
            exit(0)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let r = Renderer()
let win = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: width, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
win.contentView = r.web
win.orderBack(nil)
r.start()
DispatchQueue.main.asyncAfter(deadline: .now() + 40) { print("Timed out"); exit(1) }
app.run()
