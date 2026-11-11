// ClaudeCount — a tiny menu bar app that shows your Claude 5-hour and weekly usage limits
// Data: queries /api/oauth/usage with the OAuth token Claude Code keeps in the keychain
import AppKit
import Carbon
import ServiceManagement
import Security

// MARK: - Language (Korean / English; Korean by default)
enum Lang {
    static var isKorean: Bool {
        if let v = UserDefaults.standard.string(forKey: "lang") { return v == "ko" }
        return true   // Korean by default; switch in the menu (Language) or the sign-in guide (한/EN)
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
let pollChoices = [1, 2, 5, 10]   // refresh interval options, in minutes (default 5)
let legacyBundleID = "com.local.claudecount"                // used up to 1.0.2

// MARK: - Shell helper (uses /usr/bin/security, so no keychain access prompt)
@discardableResult
func run(_ path: String, _ args: [String], input: String? = nil) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    let stdin = Pipe()
    if input != nil { p.standardInput = stdin }
    do { try p.run() } catch { return (-1, "") }
    if let input {
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try? stdin.fileHandleForWriting.close()
    }
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
    // Sent through stdin (security -i), so the token never shows up in the process list
    func quoted(_ v: String) -> String {
        "\"" + v.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    let command = "add-generic-password -U -a \(quoted(acct)) -s \(quoted(keychainService)) -w \(quoted(str))\n"
    return run("/usr/bin/security", ["-i"], input: command).status == 0
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

enum FetchError: Error, Equatable { case noCredentials, unauthorized, http(Int), parse, network }

func parseWindow(_ any: Any?) -> Window? {
    guard let d = any as? [String: Any], let u = (d["utilization"] as? NSNumber)?.doubleValue else { return nil }
    return Window(used: u, resetsAt: parseDate(d["resets_at"]))
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

// MARK: - Claude Code login helper
/// Writes a small Terminal script that installs Claude Code if it is missing, then runs `claude auth login`.
func openLoginInTerminal() {
    let ko = Lang.isKorean
    let t = { (k: String, e: String) in ko ? k : e }
    let script = """
    #!/bin/zsh
    export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
    clear
    echo "\(t("ClaudeCount: Claude 로그인을 도와드릴게요.", "ClaudeCount: let's sign in to Claude."))"
    echo ""
    if ! command -v claude >/dev/null 2>&1; then
      echo "\(t("1/2  Claude Code를 설치하고 있어요… (1분 정도 걸려요)", "1/2  Installing Claude Code… (about a minute)"))"
      curl -fsSL https://claude.ai/install.sh | bash
      export PATH="$HOME/.local/bin:$PATH"
      if ! command -v claude >/dev/null 2>&1; then
        echo ""
        echo "\(t("설치에 실패했어요. 인터넷 연결을 확인하고 ClaudeCount 메뉴에서 다시 시도해 주세요.", "Install failed. Check your internet connection and try again from the ClaudeCount menu."))"
        read -k1 "?\(t("아무 키나 누르면 닫혀요.", "Press any key to close."))"; exit 1
      fi
    fi
    echo "\(t("2/2  브라우저가 열리면 Claude 계정으로 로그인하고 「승인(Authorize)」을 눌러 주세요.", "2/2  When your browser opens, sign in to Claude and click Authorize."))"
    echo ""
    if claude auth login --claudeai; then
      echo ""
      echo "\(t("✓ 로그인 완료! 이 창은 닫아도 돼요. ClaudeCount가 곧 숫자를 보여 줄 거예요.", "✓ Signed in! You can close this window. ClaudeCount will show your numbers shortly."))"
    else
      echo ""
      echo "\(t("로그인하지 못했어요. Claude Code를 쓸 수 있는 요금제(Pro, Max 등)인지 확인해 주세요.", "Sign-in didn't finish. Make sure your plan includes Claude Code (Pro, Max, and more)."))"
    fi
    echo ""
    read -k1 "?\(t("아무 키나 누르면 닫혀요.", "Press any key to close."))"
    """
    let dir = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/ClaudeCount")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("Log in to Claude.command")
    try? script.write(to: file, atomically: true, encoding: .utf8)
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
    NSWorkspace.shared.open([file], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
}

// MARK: - Login guide window (follows along while the user signs in)
func claudeInstalled() -> Bool {
    let paths = [NSHomeDirectory() + "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
    return paths.contains { FileManager.default.isExecutableFile(atPath: $0) }
}

final class LoginGuide: NSObject, NSWindowDelegate {
    enum Step: Int { case install, browser, done }
    let panel: NSPanel
    var rows: [(icon: NSTextField, title: NSTextField, detail: NSTextField)] = []
    let footer = NSTextField(wrappingLabelWithString: "")
    var again: NSButton!
    var timer: Timer?
    let onDone: () -> Void
    let reopen: () -> Void
    var onLanguage: () -> Void = {}

    init(reopenTerminal: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.onDone = onDone; self.reopen = reopenTerminal
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        build()
        refresh()
    }

    /// (Re)builds every label in the current language
    func build() {
        rows = []
        panel.title = L("Claude 로그인", "Sign In to Claude")
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.delegate = self

        let head = NSTextField(wrappingLabelWithString: L("터미널 창이 열렸어요. 아래 순서대로 진행돼요.\n이 창은 진행 상황에 맞춰 알아서 바뀌어요.",
                                                         "A Terminal window opened. Here's what happens next —\nthis window updates as you go."))
        head.font = .systemFont(ofSize: 13)
        let steps: [(String, String)] = [
            (L("Claude Code 설치", "Install Claude Code"),
             L("없으면 터미널이 자동으로 설치해요. 1분 정도 기다려 주세요.", "Terminal installs it if it's missing. Takes about a minute.")),
            (L("브라우저에서 로그인하고 「승인」 누르기", "Sign in in your browser and click Authorize"),
             L("브라우저가 열리면 로그인하고 「Authorize(승인)」를 눌러요.\n코드가 보이면 복사해서 터미널에 붙여 넣고 Enter를 눌러요.",
               "When your browser opens, sign in to Claude and click Authorize.\nIf it shows a code, copy it into Terminal and press Return.")),
            (L("완료", "Done"), L("숫자가 메뉴바에 나타나요.", "Your numbers appear in the menu bar.")),
        ]
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        let langToggle = NSSegmentedControl(labels: ["한", "EN"], trackingMode: .selectOne, target: self, action: #selector(langChanged(_:)))
        langToggle.selectedSegment = Lang.isKorean ? 0 : 1
        langToggle.controlSize = .small
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let top = NSStackView(views: [head, spacer, langToggle]); top.alignment = .top; top.spacing = 10
        stack.addArrangedSubview(top)
        for (t, d) in steps {
            let icon = NSTextField(labelWithString: "○"); icon.font = .systemFont(ofSize: 15, weight: .semibold)
            icon.alignment = .center; icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
            let title = NSTextField(labelWithString: t); title.font = .systemFont(ofSize: 13, weight: .semibold)
            let detail = NSTextField(wrappingLabelWithString: d); detail.font = .systemFont(ofSize: 11.5); detail.textColor = .secondaryLabelColor
            detail.preferredMaxLayoutWidth = 360
            let texts = NSStackView(views: [title, detail]); texts.orientation = .vertical; texts.alignment = .leading; texts.spacing = 2
            let rowStack = NSStackView(views: [icon, texts]); rowStack.alignment = .top; rowStack.spacing = 8
            stack.addArrangedSubview(rowStack)
            rows.append((icon, title, detail))
        }
        footer.font = .systemFont(ofSize: 11); footer.textColor = .secondaryLabelColor
        footer.stringValue = L("Claude Code를 쓸 수 있는 요금제(Pro, Max 등)가 필요해요.", "Requires a Claude plan that includes Claude Code (Pro, Max, and more).")
        again = NSButton(title: L("터미널 다시 열기", "Reopen Terminal"), target: self, action: #selector(reopenTapped))
        again.bezelStyle = .rounded
        footer.maximumNumberOfLines = 1; footer.cell?.wraps = false
        head.preferredMaxLayoutWidth = 1000
        let gap = NSView(); gap.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [footer, gap, again]); buttons.alignment = .centerY; buttons.spacing = 10
        stack.addArrangedSubview(buttons)
        // Rows span the full width so the right edge lines up with the left (20pt each side)
        for row in [top, buttons] { row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true
        let content = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
        ])
        panel.contentView = content
    }

    @objc func langChanged(_ sender: NSSegmentedControl) {
        UserDefaults.standard.set(sender.selectedSegment == 0 ? "ko" : "en", forKey: "lang")
        build(); refresh()
        panel.setContentSize(panel.contentView!.fittingSize)
        onLanguage()
    }

    func show() {
        panel.layoutIfNeeded()
        panel.setContentSize(panel.contentView!.fittingSize)
        if let screen = NSScreen.main {   // top-right corner, out of the Terminal window's way
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.maxX - panel.frame.width - 20, y: f.maxY - panel.frame.height - 20))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    @objc func reopenTapped() { reopen() }

    func refresh() {
        let loggedIn = readCredentials() != nil
        let current: Step = loggedIn ? .done : (claudeInstalled() ? .browser : .install)
        for (i, r) in rows.enumerated() {
            let finished = i < current.rawValue || (current == .done && i == Step.done.rawValue)
            let active = i == current.rawValue && current != .done
            r.icon.stringValue = finished ? "✓" : (active ? "●" : "○")
            r.icon.textColor = finished ? .systemGreen : (active ? AppDelegate.claudeOrange : .tertiaryLabelColor)
            r.title.textColor = (finished || active) ? .labelColor : .tertiaryLabelColor
        }
        if loggedIn {
            timer?.invalidate()
            footer.stringValue = L("로그인 완료! 터미널 창은 닫아도 돼요.", "Signed in! You can close the Terminal window.")
            again.isHidden = true
            onDone()
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.panel.close() }
        }
    }

    func windowWillClose(_ n: Notification) { timer?.invalidate() }
}

// MARK: - Updates (GitHub Releases)
let releasesAPI = URL(string: "https://api.github.com/repos/hellocket/ClaudeCount/releases/latest")!
var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

/// "1.0.10" > "1.0.9"
func isNewer(_ a: String, than b: String) -> Bool {
    let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(x.count, y.count) {
        let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
        if p != q { return p > q }
    }
    return false
}

enum UpdateError: Error { case network, noAsset, badArchive, wrongApp }

/// True when `app` carries the same signature as this running copy (same certificate and bundle ID),
/// so a look-alike app uploaded by someone else is never installed.
func signedLikeThisApp(_ app: URL) -> Bool {
    var me: SecCode?, meStatic: SecStaticCode?, req: SecRequirement?, other: SecStaticCode?
    guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
          SecCodeCopyStaticCode(me, [], &meStatic) == errSecSuccess, let meStatic,
          SecCodeCopyDesignatedRequirement(meStatic, [], &req) == errSecSuccess, let req,
          SecStaticCodeCreateWithPath(app as CFURL, [], &other) == errSecSuccess, let other else { return false }
    let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
    return SecStaticCodeCheckValidity(other, flags, req) == errSecSuccess
}

/// Latest release on GitHub: its version and the ClaudeCount.zip download link
func latestRelease() async throws -> (version: String, zip: URL) {
    var req = URLRequest(url: releasesAPI)
    req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    req.timeoutInterval = 15
    guard let (data, resp) = try? await URLSession.shared.data(for: req),
          (resp as? HTTPURLResponse)?.statusCode == 200,
          let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tag = j["tag_name"] as? String else { throw UpdateError.network }
    let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    let assets = j["assets"] as? [[String: Any]] ?? []
    guard let link = assets.first(where: { ($0["name"] as? String) == "ClaudeCount.zip" })?["browser_download_url"] as? String,
          let zip = URL(string: link), zip.scheme == "https", zip.host == "github.com" else { throw UpdateError.noAsset }
    return (version, zip)
}

/// Download the zip, check it really is ClaudeCount, then swap the app in place and relaunch.
func installUpdate(from zip: URL) async throws {
    guard let (file, resp) = try? await URLSession.shared.download(from: zip),
          (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.network }
    let work = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeCount-update-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    guard run("/usr/bin/ditto", ["-x", "-k", file.path, work.path]).status == 0 else { throw UpdateError.badArchive }
    // find ClaudeCount.app inside the archive
    let found = FileManager.default.enumerator(at: work, includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL }.first { $0.lastPathComponent == "ClaudeCount.app" }
    guard let newApp = found, let newBundle = Bundle(url: newApp),
          newBundle.bundleIdentifier == Bundle.main.bundleIdentifier,
          signedLikeThisApp(newApp) else { throw UpdateError.wrongApp }
    run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
    // after this app quits: replace the bundle and open the new one
    let script = "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /bin/rm -rf \"$3\" && /usr/bin/ditto \"$2\" \"$3\" && /usr/bin/open \"$3\""
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), newApp.path, Bundle.main.bundlePath]
    try p.run()
}

// MARK: - Launch at login (System Settings → General → Login Items → Open at Login)
/// One-time move from the 1.0.2 identifier: copy the old settings over.
/// (A new identifier also gives macOS a fresh Menu Bar entry, so its on/off switch works again.)
func migrateFromLegacyID() {
    let d = UserDefaults.standard
    guard !d.bool(forKey: "migratedFromLegacyID") else { return }
    if let old = d.persistentDomain(forName: legacyBundleID) {
        for (k, v) in old where d.object(forKey: k) == nil { d.set(v, forKey: k) }
        d.removePersistentDomain(forName: legacyBundleID)
    }
    d.set(true, forKey: "migratedFromLegacyID")
}

/// Up to 1.0.2 "Launch at Login" was a hidden LaunchAgent file. Remove it and,
/// if it was on, turn on the standard Open at Login item instead.
func replaceLegacyLaunchAgent() {
    var wasOn = false
    for label in [legacyBundleID] {
        let path = NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist"
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
            wasOn = true
        }
    }
    if wasOn && installedInApplications() { setAutoStart(true) }
}

/// Running from a real install location (/Applications or ~/Applications), not a mounted DMG,
/// a translocated copy, or some other folder
func installedInApplications() -> Bool {
    let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
    return [ "/Applications/", NSHomeDirectory() + "/Applications/" ].contains { path.hasPrefix($0) }
}
/// On = ClaudeCount is in the Open at Login list (the same switch as in System Settings)
func autoStartEnabled() -> Bool { SMAppService.mainApp.status == .enabled }
func setAutoStart(_ on: Bool) {
    do {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    } catch {
        NSLog("ClaudeCount: Launch at Login \(on ? "on" : "off") failed: \(error)")
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
    var emphasis = false   // Claude-orange, semibold (used for "Log in to Claude")
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
        let t = NSAttributedString(string: title, attributes: [.font: emphasis ? NSFont.systemFont(ofSize: 13, weight: .semibold) : font,
                                                               .foregroundColor: emphasis && !hovering ? AppDelegate.claudeOrange : main])
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

/// A short gray note that wraps (used under the interval choices)
final class NoteView: NSView {
    init(_ text: String) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .menuFont(ofSize: 11)
        label.textColor = softGray
        let w: CGFloat = 230
        label.preferredMaxLayoutWidth = w - 28
        label.frame.size = label.sizeThatFits(NSSize(width: w - 28, height: 200))
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: label.frame.height + 8))
        label.frame.origin = NSPoint(x: 14, y: 4)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
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
        replaceLegacyLaunchAgent()
        setBoxes([nil, nil], remain: [nil, nil])
        rebuildMenu()
        restartTimer()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.scheduledUpdate() }
        HotKey.action = { [weak self] in self?.update() }
        HotKey.register(HotKey.saved)
        log("hotkey: \(HotKey.saved?.label ?? "none") \(HotKey.active ? "ok" : "fail")")
        askLaunchAtLoginOnce()
        update()
        // Check twice so a briefly hidden menu bar (login, wake) doesn't trigger the alert
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, !self.iconOnScreen() else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.warnIfIconHidden() }
        }
    }

    /// Is the menu bar icon actually on a screen? (false when macOS keeps it out of the menu bar)
    func iconOnScreen() -> Bool {
        guard item.isVisible, let w = item.button?.window, w.isVisible,
              w.frame.height > 0, w.occlusionState.contains(.visible) else { return false }   // hidden by macOS: zero height, not visible
        return NSScreen.screens.contains { $0.frame.intersects(w.frame) }
    }

    /// Icon not in the menu bar: say so once and offer Menu Bar settings.
    /// "I hid it" is remembered, so someone who hid it on purpose isn't asked again.
    func warnIfIconHidden() {
        let key = "iconHiddenOnPurpose"
        let w = item.button?.window
        log("icon check: item \(item.isVisible) window \(w?.isVisible ?? false) frame \(w.map { NSStringFromRect($0.frame) } ?? "-")")
        if iconOnScreen() { UserDefaults.standard.removeObject(forKey: key); return }
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let answer = alert(L("메뉴바에 ClaudeCount가 안 보여요", "ClaudeCount isn't in the menu bar"), "",
                           buttons: [L("메뉴 막대 설정 열기", "Open Menu Bar Settings"), L("일부러 숨겼어요", "I Hid It")])
        if answer == .alertFirstButtonReturn {
            item.isVisible = true
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!)
        } else {
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    /// First run only: ask whether ClaudeCount should start with the Mac
    func askLaunchAtLoginOnce() {
        let key = "askedLaunchAtLogin"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard !autoStartEnabled() else { return }   // already on: nothing to ask
        let answer = alert(L("맥을 켤 때 ClaudeCount도 켤까요?", "Open ClaudeCount when your Mac starts?"),
                           L("켜 두면 맥을 켤 때마다 메뉴바에 사용량이 바로 나와요.\n나중에 메뉴의 「로그인 시 자동 실행」에서 언제든 바꿀 수 있어요.",
                             "Your usage will be in the menu bar every time you log in.\nYou can change this anytime with Launch at Login in the menu."),
                           buttons: [L("자동 실행 켜기", "Turn On"), L("나중에", "Not Now")])
        if answer == .alertFirstButtonReturn { setAutoStart(true) }
        rebuildMenu()
    }

    var recorder: ShortcutRecorder?

    @objc func changeShortcut() {
        recorder = ShortcutRecorder { [weak self] in
            self?.log("hotkey: \(HotKey.saved?.label ?? "none") \(HotKey.active ? "ok" : "fail")")
            self?.rebuildMenu()
        }
        recorder?.show()
    }

    // ── Refresh interval ──
    var pollMinutes: Int {
        get { let v = UserDefaults.standard.integer(forKey: "pollMinutes"); return pollChoices.contains(v) ? v : 5 }
        set { UserDefaults.standard.set(newValue, forKey: "pollMinutes"); restartTimer() }
    }
    func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(pollMinutes * 60), repeats: true) { [weak self] _ in self?.scheduledUpdate() }
    }

    // ── Rate-limit back-off: after HTTP 429, wait 2 → 4 → 8 → 16 → 30 min before asking again ──
    var backoffMinutes = 0
    var backoffUntil: Date?
    var backoffTimer: Timer?
    func startBackoff() {
        backoffMinutes = min(max(backoffMinutes * 2, 2), 30)
        backoffUntil = Date().addingTimeInterval(TimeInterval(backoffMinutes * 60))
        backoffTimer?.invalidate()
        backoffTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(backoffMinutes * 60), repeats: false) { [weak self] _ in self?.update() }
        log("rate limited: waiting \(backoffMinutes) min")
    }
    /// Automatic refreshes (timer, wake) skip while backing off; "Refresh Now" always runs
    func scheduledUpdate() {
        if let until = backoffUntil, Date() < until { return }
        update()
    }

    var updating = false   // one refresh at a time, so two token refreshes never race each other
    @objc func update() {
        guard !updating else { return }
        updating = true
        item.button?.alphaValue = 0.4 // dim slightly while refreshing
        Task { @MainActor in
            defer { updating = false }
            do {
                last = try await fetchUsage()
                lastUpdated = Date()
                lastError = nil
                backoffMinutes = 0; backoffUntil = nil
            } catch {
                lastError = (error as? FetchError) ?? .parse
                if case .http(429) = lastError { startBackoff() }
            }
            render()
            promptLoginIfNeeded()
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

    // e.g. " · 4h01m left (07:30)"; more than a day away: " · 62h05m left (Thu 18:00)"
    func resetText(_ d: Date?) -> String {
        guard let d else { return "" }
        let s = max(0, Int(d.timeIntervalSinceNow))
        let rel = String(format: "%dh%02dm", s / 3600, (s % 3600) / 60)
        let f = DateFormatter(); f.locale = Locale(identifier: Lang.isKorean ? "ko_KR" : "en_US")
        f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "E HH:mm"
        return " · \(rel) \(L("남음", "left")) (\(f.string(from: d)))"
    }

    var usageViews: [String: UsageRowView] = [:]
    var checkViews: [String: MenuRowView] = [:]

    /// Builds a brand-new menu. Never touches a menu that is open (macOS won't resize it → blank space).
    func rebuildMenu() {
        if menuOpen { pendingRebuild = true; return }
        let menu = NSMenu()
        usageViews = [:]; checkViews = [:]
        if needsLogin {
            let login = MenuRowView(lastError == .unauthorized ? L("Claude 다시 로그인하기", "Sign In to Claude Again") : L("Claude 로그인하기", "Sign In to Claude"),
                                    right: "→") { [weak self] in self?.startLogin() }
            login.emphasis = true
            menu.addItem(row(login))
            let note = NSMenuItem()
            note.view = NoteView(L("Claude Code 로그인이 필요해요. 누르면 터미널에서 설치와 로그인을 도와드려요.",
                                   "ClaudeCount needs your Claude Code login. Click to install and sign in from Terminal."))
            menu.addItem(note)
            menu.addItem(LineItem.make())
        }
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
        if let e = errorText, !needsLogin { menu.addItem(row(InfoRowView("⚠︎ \(e)", color: softGray))) }
        if let t = lastUpdated {
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
            menu.addItem(row(InfoRowView(L("마지막 갱신 ", "Last updated ") + f.string(from: t), color: softGray)))
        }

        // ── Block: refresh ──
        menu.addItem(LineItem.make())
        let intervalItem = NSMenuItem(title: L("새로고침 간격", "Refresh Interval"), action: nil, keyEquivalent: "")
        let intervalRow = MenuRowView(L("새로고침 간격", "Refresh Interval"), right: "›", closesMenu: false) {}
        intervalItem.view = intervalRow
        intervalItem.submenu = makeIntervalMenu()
        intervalRow.onClickOverride = { [weak self, weak intervalRow] in   // click also opens the choices, in case hover doesn't
            guard let self, let intervalRow else { return }
            self.makeIntervalMenu().popUp(positioning: nil, at: NSPoint(x: intervalRow.bounds.width - 8, y: intervalRow.bounds.height), in: intervalRow)
        }
        menu.addItem(intervalItem)
        let hk = HotKey.saved.map { HotKey.active ? $0.label : "\($0.label) ⚠︎" }
        menu.addItem(row(MenuRowView(L("지금 새로고침", "Refresh Now"), right: hk) { [weak self] in self?.update() }))
        menu.addItem(row(MenuRowView(L("단축키 변경…", "Change Shortcut…"), gray: true) { [weak self] in self?.changeShortcut() }))

        // ── Block: display ──
        menu.addItem(LineItem.make())
        menu.addItem(row(SegmentRowView(title: L("표시", "Show"), segments: [L("사용량", "Used"), L("잔여량", "Remaining")],
                                        selected: showUsed ? 0 : 1, target: self, action: #selector(numbersChanged(_:)))))
        // only when the account has model limits; the title names them (e.g. "Show Fable Limit")
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
            self.makeLanguageMenu().popUp(positioning: nil, at: NSPoint(x: langRow.bounds.width - 8, y: langRow.bounds.height), in: langRow)
        }
        langItem.submenu = makeLanguageMenu()
        menu.addItem(langItem)
        let autoRow = MenuRowView(L("로그인 시 자동 실행", "Launch at Login"), checked: autoStartEnabled(),
                                  closesMenu: false) { [weak self] in self?.toggleAuto() }
        checkViews["auto"] = autoRow
        menu.addItem(row(autoRow))
        menu.addItem(row(MenuRowView(L("업데이트 확인", "Check for Updates"), right: "v\(currentVersion)") { [weak self] in
            self?.checkForUpdates()
        }))
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
    // ── Claude Code login ──
    var needsLogin: Bool {
        switch lastError { case .noCredentials?, .unauthorized?: return true; default: return false }
    }
    var loginPromptShown = false
    var guide: LoginGuide?
    @objc func startLogin() {
        openLoginInTerminal()
        // a small guide window follows along; when the login appears it fetches the numbers and closes
        guide?.panel.close()
        guide = LoginGuide(reopenTerminal: { openLoginInTerminal() }) { [weak self] in self?.update() }
        guide?.onLanguage = { [weak self] in self?.render() }
        guide?.show()
    }
    /// First time we find no login after launch: explain it and offer to start
    func promptLoginIfNeeded() {
        guard needsLogin, !loginPromptShown else { return }
        loginPromptShown = true
        let answer = alert(L("Claude 로그인이 필요해요", "Sign in to Claude"),
                           L("Claude Code 로그인으로 사용량을 가져와요.\n「로그인하기」를 누르면 터미널이 열려요.\nClaude Code가 없으면 설치까지 해 드려요.\n브라우저에서 「승인」만 누르면 끝이에요.",
                             "Works with your Claude Code login.\nClick Sign In and Terminal opens.\nIf Claude Code is missing, it gets installed.\nThen just click Authorize in your browser."),
                           buttons: [L("로그인하기", "Sign In"), L("나중에", "Later")], wide: true)
        if answer == .alertFirstButtonReturn { startLogin() }
    }

    // ── Check for updates ──
    func alert(_ title: String, _ text: String, buttons: [String], wide: Bool = false) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title; a.informativeText = text
        if wide {   // Wider alert so each line of `text` stays on one line
            a.informativeText = ""
            let para = NSMutableParagraphStyle(); para.lineSpacing = Lang.isKorean ? 2 : 0   // Korean reads better with a touch more leading
            let body = NSTextField(labelWithAttributedString: NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13), .paragraphStyle: para]))
            body.sizeToFit()
            body.frame.origin.x = 4.5   // line up with the title
            let box = NSView(frame: NSRect(x: 0, y: 0, width: body.frame.maxX + 10, height: body.frame.height))
            box.addSubview(body); a.accessoryView = box
        }
        buttons.forEach { a.addButton(withTitle: $0) }
        return a.runModal()
    }
    func checkForUpdates() {
        Task { @MainActor in
            do {
                let latest = try await latestRelease()
                guard isNewer(latest.version, than: currentVersion) else {
                    _ = alert(L("최신 버전이에요", "You're up to date"),
                              L("지금 쓰는 ClaudeCount \(currentVersion)이 최신 버전이에요.", "ClaudeCount \(currentVersion) is the latest version."),
                              buttons: [L("확인", "OK")])
                    return
                }
                let answer = alert(L("새 버전 \(latest.version)이 있어요", "Version \(latest.version) is available"),
                                   L("지금 버전은 \(currentVersion)이에요. 업데이트하면 앱이 잠깐 꺼졌다가 새 버전으로 다시 켜져요.",
                                     "You have \(currentVersion). ClaudeCount will quit briefly and reopen as the new version."),
                                   buttons: [L("지금 업데이트", "Update Now"), L("나중에", "Later")])
                guard answer == .alertFirstButtonReturn else { return }
                // Outside /Applications (a DMG, Downloads, a translocated copy) the app can't be swapped in place:
                // open the download page instead of quitting into nothing
                guard installedInApplications() else {
                    NSWorkspace.shared.open(URL(string: "https://github.com/hellocket/ClaudeCount/releases/latest")!)
                    return
                }
                item.button?.alphaValue = 0.4
                try await installUpdate(from: latest.zip)
                log("update: installing \(latest.version)")
                NSApp.terminate(nil)
            } catch UpdateError.wrongApp {
                // the download isn't signed like this app: don't install it, send people to the release page
                item.button?.alphaValue = 1
                log("update: signature check failed")
                _ = alert(L("업데이트 파일을 확인할 수 없어요", "Couldn't verify the update"),
                          L("받은 파일이 ClaudeCount의 서명과 맞지 않아 설치하지 않았어요.\nGitHub 페이지에서 직접 받아 주세요.",
                            "The download isn't signed like ClaudeCount, so it wasn't installed.\nPlease download it from the GitHub page."),
                          buttons: [L("다운로드 페이지 열기", "Open Download Page")])
                NSWorkspace.shared.open(URL(string: "https://github.com/hellocket/ClaudeCount/releases/latest")!)
            } catch {
                item.button?.alphaValue = 1
                _ = alert(L("업데이트를 확인하지 못했어요", "Couldn't check for updates"),
                          L("인터넷 연결을 확인하고 잠시 후 다시 시도해 주세요.\nhttps://github.com/hellocket/ClaudeCount/releases 에서 직접 받을 수도 있어요.",
                            "Check your internet connection and try again later.\nYou can also download it from https://github.com/hellocket/ClaudeCount/releases"),
                          buttons: [L("확인", "OK")])
            }
        }
    }

    func makeIntervalMenu() -> NSMenu {
        let m = NSMenu()
        for mins in pollChoices {
            let it = NSMenuItem(title: L("\(mins)분", mins == 1 ? "1 minute" : "\(mins) minutes"), action: #selector(setInterval(_:)), keyEquivalent: "")
            it.representedObject = mins; it.target = self
            it.state = mins == pollMinutes ? .on : .off
            m.addItem(it)
        }
        m.addItem(.separator())
        let note = NSMenuItem()
        note.view = NoteView(L("너무 자주 요청하면 서버 오류가 날 수 있어요.\n오류가 나면 잠시 쉬었다가 다시 확인해 드릴게요.",
                               "Checking too often can cause server errors.\nIf that happens, ClaudeCount waits a bit and checks again."))
        m.addItem(note)
        return m
    }
    @objc func setInterval(_ sender: NSMenuItem) {
        if let mins = sender.representedObject as? Int { pollMinutes = mins; rebuildMenu() }
    }
    func makeLanguageMenu() -> NSMenu {
        let m = NSMenu()
        for (code, name) in [("ko", "한국어"), ("en", "English")] {
            let li = NSMenuItem(title: name, action: #selector(setLanguage(_:)), keyEquivalent: "")
            li.representedObject = code; li.target = self
            li.state = (Lang.isKorean == (code == "ko")) ? .on : .off
            m.addItem(li)
        }
        return m
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

migrateFromLegacyID()   // before anything reads settings
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // no Dock icon
app.run()
