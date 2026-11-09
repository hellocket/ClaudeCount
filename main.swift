// ClaudeCount — a tiny menu bar app that shows your Claude 5-hour and weekly usage limits
// Data: queries /api/oauth/usage with the OAuth token Claude Code keeps in the keychain
import AppKit
import Carbon

// MARK: - Language (Korean / English, chosen in the menu; defaults to the system language)
enum Lang {
    static var isKorean: Bool {
        if let v = UserDefaults.standard.string(forKey: "lang") { return v == "ko" }
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("ko")
    }
}
func L(_ ko: String, _ en: String) -> String { Lang.isKorean ? ko : en }

// MARK: - Global hotkey (works while other apps are active; no Accessibility permission needed)
// Set by the user from the "Change Refresh Shortcut…" menu item. Default: ⌃⌥⌘U.
struct Shortcut { var keyCode: Int; var mods: Int; var label: String }

enum HotKey {
    static var ref: EventHotKeyRef?
    static var action: (() -> Void)?
    static var handlerInstalled = false
    static var active = false // whether registration currently succeeded
    static let defaultShortcut = Shortcut(keyCode: kVK_ANSI_U, mods: controlKey | optionKey | cmdKey, label: "⌃⌥⌘U")

    /// nil = shortcut turned off
    static var saved: Shortcut? {
        get {
            let d = UserDefaults.standard
            if d.bool(forKey: "hotKeyDisabled") { return nil }
            guard d.object(forKey: "hotKeyCode") != nil else { return defaultShortcut }
            return Shortcut(keyCode: d.integer(forKey: "hotKeyCode"), mods: d.integer(forKey: "hotKeyMods"),
                            label: d.string(forKey: "hotKeyLabel") ?? "?")
        }
        set {
            let d = UserDefaults.standard
            if let s = newValue {
                d.set(s.keyCode, forKey: "hotKeyCode"); d.set(s.mods, forKey: "hotKeyMods")
                d.set(s.label, forKey: "hotKeyLabel"); d.set(false, forKey: "hotKeyDisabled")
            } else {
                d.set(true, forKey: "hotKeyDisabled")
            }
        }
    }

    static func unregister() {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
        active = false
    }

    /// Tries to register. Returns false if another app already uses the combination.
    @discardableResult
    static func register(_ s: Shortcut?) -> Bool {
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKey.action?() }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        unregister()
        guard let s else { return true }
        let id = EventHotKeyID(signature: OSType(0x43554242), id: 1) // 'CUBB'
        active = RegisterEventHotKey(UInt32(s.keyCode), UInt32(s.mods), id, GetApplicationEventTarget(), 0, &ref) == noErr
        return active
    }
}

let functionKeyNames: [Int: String] = [
    kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
    kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
    kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
]
let specialKeyNames: [Int: String] = [
    kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_LeftArrow: "←", kVK_RightArrow: "→",
    kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
]

func shortcut(from e: NSEvent) -> Shortcut {
    let f = e.modifierFlags
    var mods = 0, label = ""
    if f.contains(.control) { mods |= controlKey; label += "⌃" }
    if f.contains(.option) { mods |= optionKey; label += "⌥" }
    if f.contains(.shift) { mods |= shiftKey; label += "⇧" }
    if f.contains(.command) { mods |= cmdKey; label += "⌘" }
    let k = Int(e.keyCode)
    label += functionKeyNames[k] ?? specialKeyNames[k] ?? (e.charactersIgnoringModifiers ?? "?").uppercased()
    return Shortcut(keyCode: k, mods: mods, label: label)
}

// MARK: - Shortcut recorder window
final class ShortcutRecorder: NSObject, NSWindowDelegate {
    let panel: NSPanel
    let message = NSTextField(labelWithString: "")
    var monitor: Any?
    var onDone: () -> Void

    init(onDone: @escaping () -> Void) {
        self.onDone = onDone
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 110),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        panel.title = L("새로고침 단축키", "Refresh Shortcut")
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.delegate = self
        let hint = NSTextField(labelWithString: L("Esc: 취소   ·   Delete: 단축키 끄기", "Esc: cancel   ·   Delete: turn off"))
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        message.font = .systemFont(ofSize: 13, weight: .medium)
        message.alignment = .center; hint.alignment = .center
        message.lineBreakMode = .byWordWrapping; message.maximumNumberOfLines = 2
        let stack = NSStackView(views: [message, hint])
        stack.orientation = .vertical; stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        panel.contentView = stack
    }

    func show() {
        HotKey.unregister() // release it so the current shortcut can be recorded again
        message.stringValue = L("새 단축키를 누르세요\n(현재: \(HotKey.saved?.label ?? "없음"))", "Press the new shortcut\n(current: \(HotKey.saved?.label ?? "none"))")
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handle(e); return nil
        }
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func handle(_ e: NSEvent) {
        let plain = e.modifierFlags.intersection([.control, .option, .shift, .command]).isEmpty
        let k = Int(e.keyCode)
        if plain && k == kVK_Escape { finish(); return }
        if plain && (k == kVK_Delete || k == kVK_ForwardDelete) { HotKey.saved = nil; finish(); return }
        let needsModifier = functionKeyNames[k] == nil
        if needsModifier && e.modifierFlags.intersection([.control, .option, .command]).isEmpty {
            message.stringValue = L("⌃ ⌥ ⌘ 중 하나 이상과 함께 누르세요\n(F1–F20 키는 단독으로 가능)", "Include at least one of ⌃ ⌥ ⌘\n(F1–F20 work on their own)")
            return
        }
        let s = shortcut(from: e)
        if HotKey.register(s) {
            HotKey.saved = s
            finish()
        } else {
            message.stringValue = L("\(s.label)는 다른 앱이 이미 사용 중이에요\n다른 조합을 눌러 주세요", "\(s.label) is already used by another app\nTry another combination")
        }
    }

    func finish() { panel.close() }

    func windowWillClose(_ n: Notification) {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        if !HotKey.active { HotKey.register(HotKey.saved) } // restore the previous shortcut on cancel
        onDone()
    }
}

// MARK: - Settings
let keychainService = "Claude Code-credentials"
let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
let oauthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
let pollInterval: TimeInterval = 300 // 5 minutes
let launchAgentLabel = "com.local.claudecount"

// MARK: - Shell helper (uses /usr/bin/security, so no keychain access prompt)
@discardableResult
func run(_ path: String, _ args: [String]) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    do { try p.run() } catch { return (-1, "") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

// MARK: - Keychain credentials
struct Credentials {
    var raw: [String: Any]          // full JSON (keeps the other fields intact)
    var oauth: [String: Any]
    var accessToken: String { oauth["accessToken"] as? String ?? "" }
    var refreshToken: String { oauth["refreshToken"] as? String ?? "" }
    var expiresAt: Double { (oauth["expiresAt"] as? NSNumber)?.doubleValue ?? 0 }
    var isExpired: Bool { expiresAt > 0 && Date().timeIntervalSince1970 * 1000 > expiresAt - 60_000 }
}

func readCredentials() -> Credentials? {
    let r = run("/usr/bin/security", ["find-generic-password", "-s", keychainService, "-w"])
    guard r.status == 0,
          let data = r.out.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauth = json["claudeAiOauth"] as? [String: Any] else { return nil }
    return Credentials(raw: json, oauth: oauth)
}

func keychainAccount() -> String? {
    let r = run("/usr/bin/security", ["find-generic-password", "-s", keychainService])
    for line in r.out.split(separator: "\n") where line.contains("\"acct\"") {
        if let s = line.range(of: "=\""), let e = line.range(of: "\"", options: .backwards), s.upperBound < e.lowerBound {
            return String(line[s.upperBound..<e.lowerBound])
        }
    }
    return nil
}

func writeCredentials(_ c: Credentials) -> Bool {
    guard let acct = keychainAccount() else { return false }
    var raw = c.raw
    raw["claudeAiOauth"] = c.oauth
    guard let data = try? JSONSerialization.data(withJSONObject: raw),
          let str = String(data: data, encoding: .utf8) else { return false }
    return run("/usr/bin/security", ["add-generic-password", "-U", "-a", acct, "-s", keychainService, "-w", str]).status == 0
}

// Refresh an expired token the same way Claude Code does, and save it back to the keychain
func refresh(_ c: Credentials) async -> Credentials? {
    guard !c.refreshToken.isEmpty else { return nil }
    var req = URLRequest(url: tokenURL)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: [
        "grant_type": "refresh_token", "refresh_token": c.refreshToken, "client_id": oauthClientID,
    ])
    guard let (data, resp) = try? await URLSession.shared.data(for: req),
          (resp as? HTTPURLResponse)?.statusCode == 200,
          let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let access = j["access_token"] as? String else { return nil }
    var n = c
    n.oauth["accessToken"] = access
    if let r = j["refresh_token"] as? String { n.oauth["refreshToken"] = r }
    if let exp = (j["expires_in"] as? NSNumber)?.doubleValue {
        n.oauth["expiresAt"] = NSNumber(value: (Date().timeIntervalSince1970 + exp) * 1000)
    }
    _ = writeCredentials(n)
    return n
}

// MARK: - Usage request
struct Window { let used: Double; let resetsAt: Date? }
struct Usage { var fiveHour: Window?; var sevenDay: Window?; var extras: [(String, Window)] = []; var credit: Credit? }
/// Extra usage credits. Amounts are already formatted as strings like "$4.20"
struct Credit { var used: String?; var limit: String?; var balance: String?; var percent: Double? }

func parseDate(_ any: Any?) -> Date? {
    guard let s = any as? String else { return nil }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
}

/// {"amount_minor": 420, "currency": "USD", "exponent": 2} → "$4.20"
func money(_ any: Any?) -> String? {
    guard let d = any as? [String: Any], let minor = (d["amount_minor"] as? NSNumber)?.doubleValue else { return nil }
    let exp = (d["exponent"] as? NSNumber)?.intValue ?? 2
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = (d["currency"] as? String) ?? "USD"
    f.locale = Locale(identifier: "en_US")
    f.minimumFractionDigits = exp; f.maximumFractionDigits = exp
    return f.string(from: NSNumber(value: minor / pow(10, Double(exp))))
}

enum FetchError: Error { case noCredentials, unauthorized, http(Int), parse, network }

func parseWindow(_ any: Any?) -> Window? {
    guard let d = any as? [String: Any], let u = (d["utilization"] as? NSNumber)?.doubleValue else { return nil }
    var reset: Date?
    if let s = d["resets_at"] as? String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        reset = f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
    return Window(used: u, resetsAt: reset)
}

func callUsage(_ token: String) async throws -> Usage {
    var req = URLRequest(url: usageURL)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.timeoutInterval = 20
    guard let (data, resp) = try? await URLSession.shared.data(for: req) else { throw FetchError.network }
    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
    if code == 401 { throw FetchError.unauthorized }
    guard code == 200 else { throw FetchError.http(code) }
    guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw FetchError.parse }
    // Cache the last response (usage numbers only, no token) for troubleshooting
    let cacheDir = NSHomeDirectory() + "/Library/Caches/ClaudeCount"
    try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
    try? data.write(to: URL(fileURLWithPath: cacheDir + "/last-usage.json"))
    return parseUsage(j)
}

// MARK: - Response parsing (server JSON → Usage)
func parseUsage(_ j: [String: Any]) -> Usage {
    var u = Usage(fiveHour: parseWindow(j["five_hour"]), sevenDay: parseWindow(j["seven_day"]))
    // Model-specific weekly limits (e.g. Fable): weekly_scoped entries in "limits"
    if let limits = j["limits"] as? [[String: Any]] {
        for l in limits where (l["kind"] as? String) == "weekly_scoped" {
            guard let p = (l["percent"] as? NSNumber)?.doubleValue else { continue }
            let scope = l["scope"] as? [String: Any]
            let name = ((scope?["model"] as? [String: Any])?["display_name"] as? String)
                ?? ((scope?["surface"] as? [String: Any])?["display_name"] as? String)
                ?? (scope?["surface"] as? String) ?? "Other"
            u.extras.append((name, Window(used: p, resetsAt: parseDate(l["resets_at"]))))
        }
    }
    // fallback for the older response format
    if u.extras.isEmpty {
        for (k, label) in [("seven_day_opus", "Opus"), ("seven_day_sonnet", "Sonnet")] {
            if let w = parseWindow(j[k]) { u.extras.append((label, w)) }
        }
    }
    // Extra usage credits: shown only when enabled or when there is a balance
    if let sp = j["spend"] as? [String: Any],
       (sp["enabled"] as? Bool) == true || money(sp["balance"]) != nil {
        u.credit = Credit(used: money(sp["used"]), limit: money(sp["limit"]), balance: money(sp["balance"]),
                          percent: (sp["percent"] as? NSNumber)?.doubleValue)
    }
    return u
}

func fetchUsage() async throws -> Usage {
    guard var c = readCredentials() else { throw FetchError.noCredentials }
    if c.isExpired, let n = await refresh(c) { c = n }
    do {
        return try await callUsage(c.accessToken)
    } catch FetchError.unauthorized {
        // Claude Code may have refreshed it meanwhile: re-read, and refresh ourselves if that fails
        if let again = readCredentials(), again.accessToken != c.accessToken,
           let u = try? await callUsage(again.accessToken) { return u }
        guard let n = await refresh(readCredentials() ?? c) else { throw FetchError.unauthorized }
        return try await callUsage(n.accessToken)
    }
}

// MARK: - Launch at login (LaunchAgent)
var launchAgentPath: String { NSHomeDirectory() + "/Library/LaunchAgents/\(launchAgentLabel).plist" }
func autoStartEnabled() -> Bool { FileManager.default.fileExists(atPath: launchAgentPath) }
func setAutoStart(_ on: Bool) {
    if on {
        let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let plist: [String: Any] = ["Label": launchAgentLabel, "ProgramArguments": [exe], "RunAtLoad": true]
        try? FileManager.default.createDirectory(atPath: NSHomeDirectory() + "/Library/LaunchAgents", withIntermediateDirectories: true)
        (plist as NSDictionary).write(toFile: launchAgentPath, atomically: true)
    } else {
        try? FileManager.default.removeItem(atPath: launchAgentPath)
    }
}

// MARK: - One menu row: text + colored progress bar
// Color follows what is left: green, orange at 25% or less, red at 10% or less
func barColor(_ remaining: Int) -> NSColor {
    remaining <= 10 ? .systemRed : remaining <= 25 ? .systemOrange : .systemGreen
}

final class UsageRowView: NSView {
    let label = NSTextField(labelWithString: "")
    var fraction: CGFloat?   // nil = text only, no bar
    var color: NSColor
    let inset: CGFloat = 14, barH: CGFloat = 6

    static func styled(_ text: String, name: String) -> NSAttributedString {
        let attr = NSMutableAttributedString(string: text, attributes: [.font: NSFont.menuFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
        // bold the leading name (5h, 7d, Fable, Extra, …)
        let nameLen = (name as NSString).length
        if nameLen > 0 { attr.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 13), range: NSRange(location: 0, length: nameLen)) }
        // bold the countdown (e.g. 3h47m); percent and the time in parentheses stay regular
        if let re = try? NSRegularExpression(pattern: "\\d+h\\d+m") {
            for m in re.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
                attr.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 13), range: m.range)
            }
        }
        return attr
    }

    init(text: String, name: String, fraction: CGFloat?, color: NSColor) {
        self.fraction = fraction.map { max(0, min(1, $0)) }
        self.color = color
        // size for the widest case ("100%") so switching Used/Remaining never changes the width
        let widest = text.replacingOccurrences(of: "\\d+%", with: "100%", options: .regularExpression)
        let probe = NSTextField(labelWithAttributedString: UsageRowView.styled(widest, name: name))
        let width = max(rowWidth, ceil(probe.intrinsicContentSize.width) + 6 + inset * 2)
        let hasBar = fraction != nil
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: hasBar ? 42 : 26))
        autoresizingMask = .width
        label.attributedStringValue = UsageRowView.styled(text, name: name)
        label.frame = NSRect(x: inset, y: hasBar ? 18 : 4, width: width - inset * 2, height: 18)
        label.autoresizingMask = .width
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Change the contents without rebuilding the menu
    func update(text: String, name: String, fraction: CGFloat?, color: NSColor) {
        label.attributedStringValue = UsageRowView.styled(text, name: name)
        self.fraction = fraction.map { max(0, min(1, $0)) }
        self.color = color
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let fraction else { return }
        let track = NSRect(x: inset, y: 7, width: bounds.width - inset * 2, height: barH)
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: barH / 2, yRadius: barH / 2).fill()
        guard fraction > 0 else { return }
        var fill = track; fill.size.width = max(barH, track.width * fraction)
        color.setFill()
        NSBezierPath(roundedRect: fill, xRadius: barH / 2, yRadius: barH / 2).fill()
    }
}

// MARK: - Control rows inside the menu
let menuInset: CGFloat = 14
let rowWidth: CGFloat = 226
let rowHeight: CGFloat = 24   // every text row in the lower blocks
let textInset: CGFloat = menuInset + 2   // matches native menu text and NSTextField padding
/// One soft gray for secondary text, shortcuts and dividers
let softGray = NSColor.labelColor.withAlphaComponent(0.4)   // one lighter gray for all gray text; adapts to dark mode

/// "Numbers   [ Used | Remaining ]"
final class SegmentRowView: NSView {
    init(title: String, segments: [String], selected: Int, target: AnyObject, action: Selector) {
        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 13)
        let seg = NSSegmentedControl(labels: segments, trackingMode: .selectOne, target: target, action: action)
        seg.selectedSegment = selected
        seg.controlSize = .mini          // a bit smaller than .small
        seg.font = .systemFont(ofSize: 9.5)
        seg.sizeToFit()
        label.sizeToFit()
        let width = max(rowWidth, menuInset + label.frame.width + 12 + seg.frame.width + menuInset)
        let h = max(rowHeight, seg.frame.height + 4)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: h))
        autoresizingMask = .width
        label.frame.origin = NSPoint(x: textInset - 2, y: (h - label.frame.height) / 2)  // NSTextField adds 2pt padding
        seg.frame.origin = NSPoint(x: width - menuInset - seg.frame.width, y: (h - seg.frame.height) / 2)
        seg.autoresizingMask = .minXMargin
        addSubview(label); addSubview(seg)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// A clickable menu row: text on the left, optional text or ✓ on the right, hover highlight.
final class MenuRowView: NSView {
    let title: String, right: String?, gray: Bool, closes: Bool
    var checked: Bool? { didSet { needsDisplay = true } }
    let onClick: () -> Void
    var hovering = false { didSet { needsDisplay = true } }

    init(_ title: String, right: String? = nil, checked: Bool? = nil, gray: Bool = false,
         closesMenu: Bool = true, onClick: @escaping () -> Void) {
        self.title = title; self.right = right; self.checked = checked; self.gray = gray
        self.closes = closesMenu; self.onClick = onClick
        super.init(frame: NSRect(x: 0, y: 0, width: rowWidth, height: rowHeight))
        autoresizingMask = .width
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    var onClickOverride: (() -> Void)?
    override func mouseUp(with event: NSEvent) {
        if let o = onClickOverride { o(); return }
        hovering = false
        if closes { enclosingMenuItem?.menu?.cancelTracking() }
        DispatchQueue.main.async { self.onClick() }
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovering {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 5, yRadius: 5).fill()
        }
        let font = NSFont.menuFont(ofSize: 13)
        let main: NSColor = hovering ? .selectedMenuItemTextColor : (gray ? softGray : .labelColor)
        let side: NSColor = hovering ? .selectedMenuItemTextColor : softGray
        let t = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: main])
        t.draw(at: NSPoint(x: textInset, y: (bounds.height - t.size().height) / 2))
        // submenu arrow: a chevron a little larger than the text glyph, in the shortcut gray
        if right == "›" {
            let color = hovering ? NSColor.selectedMenuItemTextColor : softGray
            let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            if let img = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
                // paint the shape with exactly the text gray: draw the shape, then replace its color (sourceIn)
                let tinted = NSImage(size: img.size, flipped: false) { r in
                    img.draw(in: r)
                    color.set()
                    r.fill(using: .sourceIn)
                    return true
                }
                tinted.draw(at: NSPoint(x: bounds.width - menuInset - img.size.width, y: (bounds.height - img.size.height) / 2),
                            from: .zero, operation: .sourceOver, fraction: 1)
            }
            return
        }
        var rightText = right
        if let checked { rightText = checked ? "✓" : nil }
        if let r = rightText {
            let color: NSColor = checked == true ? (hovering ? .selectedMenuItemTextColor : NSColor.labelColor.withAlphaComponent(0.7)) : side
            let a = NSAttributedString(string: r, attributes: [.font: font, .foregroundColor: color])
            a.draw(at: NSPoint(x: bounds.width - menuInset - a.size().width, y: (bounds.height - a.size().height) / 2))
        }
    }
}

/// A non-clickable text row in the same layout
final class InfoRowView: NSView {
    let text: String, color: NSColor
    init(_ text: String, color: NSColor = .labelColor) {
        self.text = text; self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: rowWidth, height: rowHeight))
        autoresizingMask = .width
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let t = NSAttributedString(string: text, attributes: [.font: NSFont.menuFont(ofSize: 13), .foregroundColor: color])
        t.draw(at: NSPoint(x: textInset, y: (bounds.height - t.size().height) / 2))
    }
}

func row(_ view: NSView) -> NSMenuItem { let m = NSMenuItem(); m.view = view; return m }

/// A light gray divider spanning the same width as the progress bars
enum LineItem {
    static func make() -> NSMenuItem {
        let m = NSMenuItem()
        m.view = LineView(frame: NSRect(x: 0, y: 0, width: rowWidth, height: 15))  // gap between blocks
        return m
    }
}
final class LineView: NSView {
    override init(frame: NSRect) { super.init(frame: frame); autoresizingMask = .width }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: menuInset, y: floor(bounds.midY), width: bounds.width - menuInset * 2, height: 1).fill()
    }
}

/// Menu-style key equivalent for showing the global shortcut on the right of "Refresh Now"
func menuKeyEquivalent(_ s: Shortcut) -> (char: String, mods: NSEvent.ModifierFlags)? {
    var mods: NSEvent.ModifierFlags = []
    if s.mods & controlKey != 0 { mods.insert(.control) }
    if s.mods & optionKey != 0 { mods.insert(.option) }
    if s.mods & shiftKey != 0 { mods.insert(.shift) }
    if s.mods & cmdKey != 0 { mods.insert(.command) }
    let fkeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                 kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
    if let i = fkeys.firstIndex(of: s.keyCode) {
        return (String(UnicodeScalar(UInt16(NSF1FunctionKey + i))!), mods)
    }
    let special: [Int: Int] = [kVK_LeftArrow: NSLeftArrowFunctionKey, kVK_RightArrow: NSRightArrowFunctionKey,
                               kVK_UpArrow: NSUpArrowFunctionKey, kVK_DownArrow: NSDownArrowFunctionKey,
                               kVK_Home: NSHomeFunctionKey, kVK_End: NSEndFunctionKey,
                               kVK_PageUp: NSPageUpFunctionKey, kVK_PageDown: NSPageDownFunctionKey]
    if let f = special[s.keyCode] { return (String(UnicodeScalar(UInt16(f))!), mods) }
    if s.keyCode == kVK_Space { return (" ", mods) }
    if s.keyCode == kVK_Return { return ("\r", mods) }
    if s.keyCode == kVK_Tab { return ("\t", mods) }
    guard let last = s.label.last else { return nil }
    return (String(last).lowercased(), mods)
}

// MARK: - Menu bar UI
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    // An open menu can't shrink, so changes from a background refresh wait until it closes
    var menuOpen = false
    var pendingRebuild = false
    func menuWillOpen(_ menu: NSMenu) { menuOpen = true }
    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        if pendingRebuild { pendingRebuild = false; rebuildMenu() }
    }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var timer: Timer?
    var last: Usage?
    var lastUpdated: Date?
    var lastError: FetchError?
    var errorText: String? {
        guard let e = lastError else { return nil }
        switch e {
        case .noCredentials: return L("Claude Code 로그인 정보 없음 (터미널에서 claude 로그인 필요)", "No Claude Code login (run claude in Terminal to log in)")
        case .unauthorized: return L("인증 만료 — 터미널에서 claude 를 한 번 실행하세요", "Login expired — run claude in Terminal once")
        case .http(let c): return L("서버 오류 (HTTP \(c))", "Server error (HTTP \(c))")
        case .network: return L("네트워크 오류", "Network error")
        case .parse: return L("응답 해석 실패", "Couldn’t read the response")
        }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        setBoxes([nil, nil], remain: [nil, nil])
        rebuildMenu()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in self?.update() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.update() }
        HotKey.action = { [weak self] in self?.update() }
        HotKey.register(HotKey.saved)
        log("hotkey: \(HotKey.saved?.label ?? "none") \(HotKey.active ? "ok" : "fail")")
        update()
    }

    var recorder: ShortcutRecorder?

    @objc func changeShortcut() {
        recorder = ShortcutRecorder { [weak self] in
            self?.log("hotkey: \(HotKey.saved?.label ?? "none") \(HotKey.active ? "ok" : "fail")")
            self?.rebuildMenu()
        }
        recorder?.show()
    }

    @objc func update() {
        item.button?.alphaValue = 0.4 // dim slightly while refreshing
        Task { @MainActor in
            do {
                last = try await fetchUsage()
                lastUpdated = Date()
                lastError = nil
            } catch {
                lastError = (error as? FetchError) ?? .parse
            }
            render()
        }
    }

    func remaining(_ w: Window?) -> Int? { w.map { max(0, min(100, Int((100 - $0.used).rounded()))) } }

    // Display mode chosen in the menu: false = remaining, true = used (persists across launches)
    var showUsed: Bool {
        get { UserDefaults.standard.bool(forKey: "showUsed") }
        set { UserDefaults.standard.set(newValue, forKey: "showUsed") }
    }

    func render() {
        item.button?.alphaValue = 1
        let rem = [remaining(last?.fiveHour), remaining(last?.sevenDay)]
        let shown = showUsed ? rem.map { $0.map { 100 - $0 } } : rem
        setBoxes(shown, remain: rem)
        log("\(showUsed ? "used" : "left") 5h \(shown[0].map(String.init) ?? "–")  7d \(shown[1].map(String.init) ?? "–")")
        rebuildMenu()
    }

    // Menu bar icon: [5-hour] ✻ [weekly], Claude orange, Monoplex KR Nerd Text Italic
    // With "Hide Weekly Usage" on: ✻ [5-hour]
    static let claudeOrange = NSColor(srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1)
    static let iconFont: NSFont = NSFont(name: "MonoplexKRNerd-TextItalic", size: 15.7)
        ?? NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

    var hideWeekly: Bool {
        get { UserDefaults.standard.bool(forKey: "hideWeekly") }
        set { UserDefaults.standard.set(newValue, forKey: "hideWeekly") }
    }

    enum IconPart { case number(String), star }

    func setBoxes(_ values: [Int?], remain: [Int?]) {
        let font = AppDelegate.iconFont
        let num = { (v: Int?) in IconPart.number(v.map(String.init) ?? "–") }
        let parts: [IconPart] = hideWeekly ? [.star, num(values[0])] : [num(values[0]), .star, num(values[1])]
        let star: CGFloat = 4.9, gap: CGFloat = 4, h: CGFloat = 22
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: AppDelegate.claudeOrange]
        func w(_ p: IconPart) -> CGFloat {
            switch p { case .number(let s): return NSAttributedString(string: s, attributes: attrs).size().width
                       case .star: return star }
        }
        let width = ceil(parts.map(w).reduce(0, +) + gap * CGFloat(parts.count - 1))
        let image = NSImage(size: NSSize(width: width, height: h), flipped: false) { _ in
            var x: CGFloat = 0
            for p in parts {
                switch p {
                case .number(let s):
                    let str = NSAttributedString(string: s, attributes: attrs)
                    str.draw(at: NSPoint(x: x, y: (h - str.size().height) / 2))
                case .star:
                    // draw the ✻ ourselves so it sits exactly in the middle
                    let c = NSPoint(x: x + star / 2, y: h / 2)
                    let path = NSBezierPath()
                    for k in 0..<3 {
                        let a = CGFloat(k) * .pi / 3 + .pi / 2
                        path.move(to: NSPoint(x: c.x + cos(a) * star / 2, y: c.y + sin(a) * star / 2))
                        path.line(to: NSPoint(x: c.x - cos(a) * star / 2, y: c.y - sin(a) * star / 2))
                    }
                    path.lineWidth = 1.2; path.lineCapStyle = .round
                    AppDelegate.claudeOrange.setStroke(); path.stroke()
                }
                x += w(p) + gap
            }
            return true
        }
        image.isTemplate = false
        item.button?.title = ""
        item.button?.image = image
        let kind = showUsed ? L("사용", "used") : L("남은", "left")
        item.button?.toolTip = hideWeekly ? L("5시간 (\(kind) %)", "5-hour (% \(kind))")
                                          : L("왼쪽: 5시간 · 오른쪽: 주간 (\(kind) %)", "Left: 5-hour · Right: weekly (% \(kind))")
    }

    func log(_ text: String) {
        // status log (never contains tokens or other secrets)
        let line = "\(Date()) \(text)\(errorText.map { " | \($0)" } ?? "")\n"
        let logPath = NSHomeDirectory() + "/Library/Logs/ClaudeCount.log"
        if let h = FileHandle(forWritingAtPath: logPath) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
        else { try? line.write(toFile: logPath, atomically: true, encoding: .utf8) }
    }

    // e.g. " · 4h01m 남음 (07:30)"; more than a day away: " · 62h05m 남음 (목 18:00)"
    func resetText(_ d: Date?) -> String {
        guard let d else { return "" }
        let s = max(0, Int(d.timeIntervalSinceNow))
        let rel = String(format: "%dh%02dm", s / 3600, (s % 3600) / 60)
        let f = DateFormatter(); f.locale = Locale(identifier: Lang.isKorean ? "ko_KR" : "en_US")
        f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "E HH:mm"
        return " · \(rel) \(L("남음", "left")) (\(f.string(from: d)))"
    }

    func info(_ title: String) -> NSMenuItem {
        // not clickable, but drawn in the same color as other menu items
        let m = NSMenuItem(title: title, action: nil, keyEquivalent: ""); m.isEnabled = false
        m.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.labelColor])
        return m
    }

    var usageViews: [String: UsageRowView] = [:]
    var checkViews: [String: MenuRowView] = [:]

    /// Builds a brand-new menu. Never touches a menu that is open (macOS won't resize it → blank space).
    func rebuildMenu() {
        if menuOpen { pendingRebuild = true; return }
        let menu = NSMenu()
        usageViews = [:]; checkViews = [:]
        if let u = last {
            // Show model limits (e.g. Fable) only once used, or when "Always Show" is on, so accounts without access are not confused
            let extras = u.extras.filter { showModelLimits || $0.1.used > 0 }
            let rows: [(String, Window?)] = [("5h", u.fiveHour), ("7d", u.sevenDay)] + extras.map { ($0.0, Optional($0.1)) }
            for (label, w) in rows {
                guard let w else { continue }
                let rem = remaining(w)!
                let shown = showUsed ? Int(w.used.rounded()) : rem
                let v = UsageRowView(text: "\(label) \(shown)%\(resetText(w.resetsAt))", name: label,
                                     fraction: CGFloat(shown) / 100, color: barColor(rem))
                usageViews[label] = v
                menu.addItem(row(v))
            }
            // Extra credits: "used / limit" with a bar when there is a limit, "balance left" otherwise
            if let c = u.credit {
                let row = NSMenuItem()
                if let used = c.used, let limit = c.limit {
                    let p = c.percent ?? 0
                    row.view = UsageRowView(text: "Extra \(used) / \(limit)", name: "Extra",
                                            fraction: CGFloat(p) / 100, color: barColor(Int((100 - p).rounded())))
                } else if let bal = c.balance {
                    row.view = UsageRowView(text: "Extra \(bal) \(L("남음", "left"))", name: "Extra", fraction: nil, color: .labelColor)
                } else {
                    row.view = UsageRowView(text: "Extra \(c.used ?? "$0.00") \(L("사용", "used"))", name: "Extra", fraction: nil, color: .labelColor)
                }
                menu.addItem(row)
            }
        }
        menu.addItem(row(MenuRowView(L("Extra 사용량 구매…", "Buy Extra Usage…")) { [weak self] in self?.openBilling() }))

        // status lines stay in the same block, under Buy Extra Usage
        if let e = errorText { menu.addItem(row(InfoRowView("⚠︎ \(e)", color: softGray))) }
        if let t = lastUpdated {
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
            menu.addItem(row(InfoRowView(L("마지막 갱신 ", "Last updated ") + f.string(from: t), color: softGray)))
        }

        // ── Block: refresh ──
        menu.addItem(LineItem.make())
        let hk = HotKey.saved.map { HotKey.active ? $0.label : "\($0.label) ⚠︎" }
        menu.addItem(row(MenuRowView(L("지금 새로고침", "Refresh Now"), right: hk) { [weak self] in self?.update() }))
        menu.addItem(row(MenuRowView(L("단축키 변경…", "Change Shortcut…"), gray: true) { [weak self] in self?.changeShortcut() }))

        // ── Block: display ──
        menu.addItem(LineItem.make())
        menu.addItem(row(SegmentRowView(title: L("표시", "Show"), segments: [L("사용량", "Used"), L("잔여량", "Remaining")],
                                        selected: showUsed ? 0 : 1, target: self, action: #selector(numbersChanged(_:)))))
        // only when the account has model limits; the title names them (e.g. "Fable 한도 보기")
        if let u = last, !u.extras.isEmpty {
            let names = u.extras.map { $0.0 }.joined(separator: " · ")
            menu.addItem(row(MenuRowView(L("\(names) 한도 보기", "Show \(names) Limit"), checked: showModelLimits,
                                         closesMenu: false) { [weak self] in self?.toggleModelLimits() }))
        }
        let weeklyRow = MenuRowView(L("주간 사용량 보기", "Show Weekly Usage"), checked: !hideWeekly,
                                    closesMenu: false) { [weak self] in self?.toggleHideWeekly() }
        checkViews["weekly"] = weeklyRow
        menu.addItem(row(weeklyRow))

        // ── Block: app ──
        menu.addItem(LineItem.make())
        let langItem = NSMenuItem(title: L("언어", "Language"), action: nil, keyEquivalent: "")
        let langRow = MenuRowView(L("언어", "Language"), right: "›", closesMenu: false) {}
        langItem.view = langRow
        langRow.onClickOverride = { [weak self, weak langRow] in   // click also opens the choices, in case hover doesn't
            guard let self, let langRow else { return }
            let pop = NSMenu()
            for (code, name) in [("ko", "한국어"), ("en", "English")] {
                let li = NSMenuItem(title: name, action: #selector(self.setLanguage(_:)), keyEquivalent: "")
                li.representedObject = code; li.target = self
                li.state = (Lang.isKorean == (code == "ko")) ? .on : .off
                pop.addItem(li)
            }
            pop.popUp(positioning: nil, at: NSPoint(x: langRow.bounds.width - 8, y: langRow.bounds.height), in: langRow)
        }
        let langMenu = NSMenu()
        for (code, name) in [("ko", "한국어"), ("en", "English")] {
            let li = NSMenuItem(title: name, action: #selector(setLanguage(_:)), keyEquivalent: "")
            li.representedObject = code; li.target = self
            li.state = (Lang.isKorean == (code == "ko")) ? .on : .off
            langMenu.addItem(li)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)
        let autoRow = MenuRowView(L("로그인 시 자동 실행", "Launch at Login"), checked: autoStartEnabled(),
                                  closesMenu: false) { [weak self] in self?.toggleAuto() }
        checkViews["auto"] = autoRow
        menu.addItem(row(autoRow))
        let quit = row(MenuRowView(L("종료", "Quit"), right: "⌘Q") { NSApp.terminate(nil) })
        quit.keyEquivalent = "q"; quit.action = #selector(NSApplication.terminate(_:))  // ⌘Q still works while the menu is open
        menu.addItem(quit)
        menu.showsStateColumn = false
        menu.delegate = self
        item.menu = menu
    }

    var showModelLimits: Bool {
        get { UserDefaults.standard.bool(forKey: "showModelLimits") }
        set { UserDefaults.standard.set(newValue, forKey: "showModelLimits") }
    }
    @objc func toggleModelLimits() {
        // adds or removes a row: close, rebuild, and reopen so the menu gets the right size
        showModelLimits.toggle()
        item.menu?.cancelTracking()
        DispatchQueue.main.async {
            self.menuOpen = false; self.rebuildMenu()
            self.item.button?.performClick(nil)
        }
    }
    @objc func toggleHideWeekly() {
        hideWeekly.toggle()
        checkViews["weekly"]?.checked = !hideWeekly
        render()   // menu bar icon now; the menu itself is rebuilt when it closes
    }
    /// Update the usage rows of the open menu for the current Used/Remaining mode
    func refreshUsageRows() {
        guard let u = last else { return }
        let rows: [(String, Window?)] = [("5h", u.fiveHour), ("7d", u.sevenDay)] + u.extras.map { ($0.0, Optional($0.1)) }
        for (label, w) in rows {
            guard let w, let v = usageViews[label] else { continue }
            let rem = remaining(w)!
            let shown = showUsed ? Int(w.used.rounded()) : rem
            v.update(text: "\(label) \(shown)%\(resetText(w.resetsAt))", name: label, fraction: CGFloat(shown) / 100, color: barColor(rem))
        }
    }
    // Open usage settings in the Claude desktop app if installed, otherwise in the browser
    @objc func openBilling() {
        let appURL = URL(string: "claude://claude.ai/settings/usage")!
        if NSWorkspace.shared.urlForApplication(toOpen: appURL) != nil {
            NSWorkspace.shared.open(appURL)
        } else {
            NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
        }
    }
    @objc func numbersChanged(_ sender: NSSegmentedControl) {
        showUsed = sender.selectedSegment == 0
        refreshUsageRows()   // update the open menu in place
        render()             // menu bar icon; menu rebuilt on close
    }
    @objc func setLanguage(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.representedObject as? String, forKey: "lang")
        render()
    }
    @objc func toggleAuto() {
        setAutoStart(!autoStartEnabled())
        checkViews["auto"]?.checked = autoStartEnabled()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // no Dock icon
app.run()
