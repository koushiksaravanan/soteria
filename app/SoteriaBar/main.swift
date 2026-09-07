// SoteriaBar — menu-bar front-end for the soteria CLI. AppKit only, no Xcode needed.
// All enforcement lives in the CLI; this app builds commands, opens them in
// Terminal, and surfaces Undo / audit log / self-test. Approvals still happen
// in the terminal (ask-socket GUI comes later).
import AppKit
import Foundation
import Security

// MARK: - model

struct Harness {
    let key: String
    let title: String
    let profile: String
    let bin: [String]
    let credential: String
}

struct Mode {
    let key: String
    let title: String
    let net: String
    let ask: String
}

let harnesses = [
    Harness(key: "claude", title: "Claude Code", profile: "claude-code",
            bin: ["claude", "--dangerously-skip-permissions"], credential: "anthropic"),
    Harness(key: "codex", title: "Codex", profile: "codex",
            bin: ["codex", "--dangerously-bypass-approvals-and-sandbox"], credential: "openai"),
]

let modes = [
    Mode(key: "lockdown", title: "Lockdown", net: "minimal", ask: "strict"),
    Mode(key: "balanced", title: "Balanced", net: "developer", ask: "escalations"),
    Mode(key: "wild", title: "Wild", net: "developer", ask: "irreversible-only"),
]

func shQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// argv for `soteria run ...` (unquoted). Mirrors the web wizard + CLI launch.
func buildRunArgv(binary: String, harness: Harness, mode: Mode, project: String,
                  detached: Bool = false, memory: String = "", maxProcs: String = "") -> [String] {
    var argv = [binary, "run",
     "--profile", harness.profile,
     "--allow", project,
     "--network-profile", mode.net,
     "--rollback",
     "--deny-commands", "docker,kubectl,podman",
     "--ask-mode", mode.ask,
     "--credential", harness.credential]
    let mem = memory.trimmingCharacters(in: .whitespaces)
    if !mem.isEmpty { argv += ["--memory", mem] }
    let mp = maxProcs.trimmingCharacters(in: .whitespaces)
    if !mp.isEmpty { argv += ["--max-processes", mp] }
    if detached { argv += ["--detached"] }
    return argv + ["--"] + harness.bin
}

func renderCommandFile(argv: [String]) -> String {
    "#!/bin/sh\n" + "exec " + argv.map(shQuote).joined(separator: " ") + "\n"
}

func findBinary() -> String? {
    var cands: [String] = []
    if let env = ProcessInfo.processInfo.environment["SOTERIA_BIN"], !env.isEmpty {
        cands.append(env)
    }
    let macos = Bundle.main.bundlePath + "/Contents/MacOS"
    cands += [macos + "/soteria", "/usr/local/bin/soteria", "/opt/homebrew/bin/soteria"]
    let fm = FileManager.default
    return cands.first { fm.isExecutableFile(atPath: $0) }
}

/// Menu-bar icon: `MenuIcon.png` (+ `@2x`) from bundle Resources when the
/// artist has supplied one, else the system shield. Template rendering makes
/// a black-on-transparent glyph adapt to light/dark bars automatically.
func menuIcon() -> NSImage? {
    if let url = Bundle.main.url(forResource: "MenuIcon", withExtension: "png"),
       let img = NSImage(contentsOf: url) {
        img.isTemplate = true
        img.size = NSSize(width: 18, height: 18)
        return img
    }
    return NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "Soteria")
}

func runCLI(_ binary: String, _ args: [String]) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: binary)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    do {
        try p.run()
    } catch {
        return (127, "")
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

// MARK: - anthropic auth (Keychain only — secrets never touch argv or disk)

let kKeychainService = "soteria"

struct KeyService {
    let key: String
    let title: String
    let account: String
    let envVar: String
    let placeholder: String
    let consoleOAuth: Bool
}

let keyServices = [
    KeyService(key: "anthropic", title: "Anthropic", account: "anthropic_api_key",
               envVar: "ANTHROPIC_API_KEY", placeholder: "sk-ant-…", consoleOAuth: true),
    KeyService(key: "openai", title: "OpenAI", account: "openai_api_key",
               envVar: "OPENAI_API_KEY", placeholder: "sk-…", consoleOAuth: false),
]

func keychainHas(service: String = kKeychainService, account: String) -> Bool {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                            kSecAttrService as String: service,
                            kSecAttrAccount as String: account]
    return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
}

func keychainSet(service: String = kKeychainService, account: String, secret: String) -> Bool {
    let data = Data(secret.utf8)
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                            kSecAttrService as String: service,
                            kSecAttrAccount as String: account]
    var st = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if st == errSecItemNotFound {
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        st = SecItemAdd(add as CFDictionary, nil)
    }
    return st == errSecSuccess
}

/// Console OAuth leaves this file; the soteria proxy can then use the session.
func claudeConsoleAuthed() -> Bool {
    FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.claude/.credentials.json")
}

func keyStatus(_ s: KeyService) -> String {
    if s.key == "anthropic" && claudeConsoleAuthed() { return "Connected via Anthropic Console (OAuth, host-side only)" }
    if keychainHas(account: s.account) { return "Connected via API key (Keychain)" }
    if let k = ProcessInfo.processInfo.environment[s.envVar], !k.isEmpty {
        return "Connected via API key (environment)"
    }
    return "Not connected"
}

// MARK: - app

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var binary: String?
    var dialog: SessionDialog?
    var login: LoginPanel?

    func applicationDidFinishLaunching(_ n: Notification) {
        binary = findBinary()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = statusItem.button {
            b.image = menuIcon()
            if b.image == nil { b.title = "S" }
        }
        rebuildMenu()
        if ProcessInfo.processInfo.environment["SOTERIA_DIALOG_ON_LAUNCH"] == "1"
            || ProcessInfo.processInfo.environment["SOTERIA_SHOW"] == "dialog" {
            DispatchQueue.main.async { self.openDialog(nil) }
        } else if ProcessInfo.processInfo.environment["SOTERIA_SHOW"] == "login" {
            DispatchQueue.main.async { self.openLogin(nil) }
        }
    }

    func rebuildMenu() {
        let menu = NSMenu()
        let newItem = NSMenuItem(title: "New secure session…", action: #selector(openDialog(_:)), keyEquivalent: "")
        newItem.isEnabled = binary != nil
        menu.addItem(newItem)
        let ghosts = NSMenuItem(title: "Ghost sessions…", action: #selector(ghostSessions(_:)), keyEquivalent: "")
        ghosts.isEnabled = binary != nil
        menu.addItem(ghosts)
        let undo = NSMenuItem(title: "Undo latest snapshot…", action: #selector(undoLatest(_:)), keyEquivalent: "")
        undo.isEnabled = binary != nil
        menu.addItem(undo)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Connect API keys…", action: #selector(openLogin(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit SoteriaBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func openInTerminal(argv: [String]) {
        openScript(renderCommandFile(argv: argv))
    }

    func openScript(_ text: String) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("soteria-run-\(Int(Date().timeIntervalSince1970)).command")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            alert("Could not write launcher: \(error)")
        }
    }

    @objc func openDialog(_ sender: Any?) {
        guard binary != nil else { alert("soteria CLI not found"); return }
        if let d = dialog, d.window.isVisible {
            d.window.makeKeyAndOrderFront(nil)  // single instance: focus, don't stack
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let d = SessionDialog(owner: self)
        dialog = d
        d.show()
    }

    @objc func openLogin(_ sender: Any?) {
        if let p = login, p.window.isVisible {
            p.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let p = LoginPanel(owner: self)
        login = p
        p.show()
    }

    @objc func undoLatest(_ sender: NSMenuItem) {
        guard let binary else { return }
        let (rc, out) = runCLI(binary, ["list"])
        guard rc == 0 else { alert("list failed"); return }
        guard let sid = out.split(separator: "\n").first.map(String.init) else {
            alert("No snapshots"); return
        }
        let id = sid.split(separator: " ").first.map(String.init) ?? sid
        let a = NSAlert()
        a.messageText = "Undo snapshot \(id)?"
        a.informativeText = "Restores project files to the pre-session state."
        a.addButton(withTitle: "Undo")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let (uRC, uOut) = runCLI(binary, ["undo", id, "--yes"])
        alert(uRC == 0 ? "Undone:\n\(uOut)" : "Undo failed:\n\(uOut)")
    }

    @objc func ghostSessions(_ sender: NSMenuItem) {
        guard let binary else { return }
        let (rc, out) = runCLI(binary, ["sessions"])
        guard rc == 0 else { alert("sessions failed"); return }
        let lines = out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        guard let first = lines.first, !first.hasPrefix("(no sessions)") else {
            alert("No ghost sessions.")
            return
        }
        let latest = first.split(separator: " ").first.map(String.init) ?? ""
        let a = NSAlert()
        a.messageText = "Ghost sessions"
        a.informativeText = lines.prefix(8).joined(separator: "\n")
        a.addButton(withTitle: "Attach latest in Terminal")
        a.addButton(withTitle: "Stop latest")
        a.addButton(withTitle: "OK")
        let resp = a.runModal()
        if resp == .alertFirstButtonReturn, !latest.isEmpty {
            openInTerminal(argv: [binary, "attach", latest, "--follow"])
        } else if resp == .alertSecondButtonReturn, !latest.isEmpty {
            let (sRC, sOut) = runCLI(binary, ["stop", latest])
            alert(sRC == 0 ? sOut : "Stop failed:\n\(sOut)")
        }
    }

    func alert(_ text: String) {
        let a = NSAlert()
        a.messageText = text
        a.runModal()
    }
}

// MARK: - session dialog

/// Click-to-session dialog: harness × strictness × backend × project → Run.
final class SessionDialog: NSObject, NSWindowDelegate {
    weak var owner: AppDelegate?
    var window: NSWindow!
    var harnessPop = NSPopUpButton()
    var modePop = NSPopUpButton()
    var backendPop = NSPopUpButton()
    var askPop = NSPopUpButton()
    var netPop = NSPopUpButton()
    var denyField = NSTextField()
    var pathField = NSTextField()
    var imageField = NSTextField()
    var imageRow = NSStackView()
    var detachedBox = NSButton()
    var memField = NSTextField()
    var procField = NSTextField()
    var helpLabel = NSTextField()
    var preview = NSTextView()
    var previewScroll = NSScrollView()
    var showCmdBox = NSButton()
    var avail: [String: Bool] = ["local": true, "docker": false, "nono": false]

    static let backends = [
        (key: "local", title: "Local kernel box", need: "local"),
        (key: "docker", title: "Docker container", need: "docker"),
        (key: "nono", title: "nono engine", need: "nono"),
    ]
    static let modeHelp = [
        "lockdown": "Offline or LLM-only. Asks on everything new. (network: minimal · ask: strict)",
        "balanced": "Project write + dev net. Asks on push/deploy. (network: developer · ask: escalations)",
        "wild": "Broadest dev access. Asks irreversible-only. (network: developer · ask: irreversible-only)",
    ]
    static let askChoices = ["From strictness", "strict", "escalations", "irreversible-only", "never"]
    static let netChoices = ["From strictness", "minimal", "developer", "claude-code", "codex"]
    static let installHint = ["claude": "npm i -g @anthropic-ai/claude-code",
                              "codex": "npm i -g @openai/codex"]

    init(owner: AppDelegate) {
        self.owner = owner
        super.init()
        build()
        refresh(nil)
    }

    static func shellOK(_ launchPath: String, _ args: [String], timeout: TimeInterval = 4) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return false }
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { p.waitUntilExit(); sem.signal() }
        if sem.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            return false
        }
        return p.terminationStatus == 0
    }

    static func backendOK(_ need: String) -> Bool {
        switch need {
        case "local": return true
        case "docker": return shellOK("/bin/sh", ["-c", "command -v docker >/dev/null && docker info >/dev/null 2>&1"])
        case "nono": return shellOK("/bin/sh", ["-c", "command -v nono >/dev/null"])
        default: return false
        }
    }

    func row(_ label: String, _ control: NSView) -> NSStackView {
        let l = NSTextField(labelWithString: label)
        l.alignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 92).isActive = true
        control.translatesAutoresizingMaskIntoConstraints = false
        let r = NSStackView(views: [l, control])
        r.orientation = .horizontal
        r.spacing = 8
        r.alignment = .centerY
        return r
    }

    func build() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 620),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "New Secure Session"
        window.isReleasedWhenClosed = false

        for h in harnesses { harnessPop.addItem(withTitle: h.title) }
        for m in modes { modePop.addItem(withTitle: m.title) }
        modePop.selectItem(at: 1)  // balanced
        for b in Self.backends {
            backendPop.addItem(withTitle: b.title)
            backendPop.lastItem?.isEnabled = (b.key == "local")  // rest enable as probes return
        }
        for pop in [harnessPop, modePop, backendPop] as [NSPopUpButton] {
            pop.target = self
            pop.action = #selector(refresh(_:))
        }
        askPop.addItems(withTitles: Self.askChoices)
        netPop.addItems(withTitles: Self.netChoices)
        for pop in [askPop, netPop] {
            pop.target = self
            pop.action = #selector(refresh(_:))
        }
        denyField.placeholderString = "e.g. aws,terraform (adds to docker,kubectl,podman)"

        pathField.placeholderString = "/path/to/project"
        let browse = NSButton(title: "Browse…", target: self, action: #selector(browse(_:)))
        browse.bezelStyle = .rounded
        let pathRow = row("Project:", NSStackView(views: [pathField, browse]))
        (pathRow.views[1] as? NSStackView)?.orientation = .horizontal
        (pathRow.views[1] as? NSStackView)?.spacing = 8
        pathField.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true

        imageField.stringValue = "soteria-toolbox"
        imageRow = row("Image:", imageField)
        detachedBox = NSButton(checkboxWithTitle: "Run detached (ghost session — see menu › Ghost sessions…)",
                               target: self, action: #selector(refresh(_:)))
        memField.stringValue = "2G"
        memField.widthAnchor.constraint(equalToConstant: 70).isActive = true
        procField.stringValue = "256"
        procField.widthAnchor.constraint(equalToConstant: 70).isActive = true
        let capsRow = NSStackView(views: [NSTextField(labelWithString: "Memory cap:"),
                                          memField,
                                          NSTextField(labelWithString: "Max processes:"),
                                          procField])
        capsRow.orientation = .horizontal
        capsRow.spacing = 8
        capsRow.alignment = .centerY

        helpLabel = NSTextField(labelWithString: "")
        helpLabel.textColor = .secondaryLabelColor
        helpLabel.font = .systemFont(ofSize: 11)
        helpLabel.lineBreakMode = .byWordWrapping

        showCmdBox = NSButton(checkboxWithTitle: "Show exact command",
                                      target: self, action: #selector(toggleCmd(_:)))
        let scroll = previewScroll
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        preview.isEditable = false
        preview.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        scroll.documentView = preview
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 110).isActive = true

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(close(_:)))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let run = NSButton(title: "Open Secure Session", target: self, action: #selector(run(_:)))
        run.bezelStyle = .rounded
        run.keyEquivalent = "\r"
        let btnRow = NSStackView(views: [NSView(), cancel, run])
        btnRow.orientation = .horizontal
        btnRow.spacing = 8

        let stack = NSStackView(views: [
            row("Agent:", harnessPop), row("Strictness:", modePop),
            row("Ask override:", askPop), row("Network override:", netPop),
            row("Runs in:", backendPop),
            pathRow, imageRow,
            row("Extra denials:", denyField),
            detachedBox, row("Limits:", capsRow),
            helpLabel, showCmdBox, scroll, btnRow,
        ])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
        ])
        harnessPop.target = self
        harnessPop.action = #selector(harnessChanged(_:))
    }

    func selected() -> (Harness, Mode, String) {
        let h = harnesses[harnessPop.indexOfSelectedItem]
        let m = modes[modePop.indexOfSelectedItem]
        let b = Self.backends[backendPop.indexOfSelectedItem].key
        return (h, m, b)
    }

    /// Resolved (network, ask): strictness preset unless an override popup is set.
    func resolvedPolicy() -> (net: String, ask: String) {
        let m = modes[modePop.indexOfSelectedItem]
        let askVals = ["", "strict", "escalations", "irreversible-only", "never"]
        let ai = askPop.indexOfSelectedItem
        let ni = netPop.indexOfSelectedItem
        let ask = (ai > 0 && ai < askVals.count) ? askVals[ai] : m.ask
        let net = (ni > 0 && ni < Self.netChoices.count) ? Self.netChoices[ni] : m.net
        return (net, ask)
    }

    func currentArgv() -> [String]? {
        guard let binary = owner?.binary else { return nil }
        let (h, _, b) = selected()
        let (net, ask) = resolvedPolicy()
        let project = pathField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !project.isEmpty else { return nil }
        var deny = ["docker", "kubectl", "podman"]
        for extra in denyField.stringValue.split(separator: ",") {
            let t = extra.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty && !deny.contains(t) { deny.append(t) }
        }
        var argv = [binary, "run", "--backend", b, "--profile", h.profile,
                    "--allow", project, "--network-profile", net, "--rollback",
                    "--deny-commands", deny.joined(separator: ","), "--ask-mode", ask]
        if b == "docker" {
            let img = imageField.stringValue.trimmingCharacters(in: .whitespaces)
            argv += ["--image", img.isEmpty ? "soteria-toolbox" : img]
        }
        // Credential follows the agent: the human authenticates per session
        // (login flow / ephemeral key), never via checkboxes. Extra services
        // stay CLI-only: append --credential there.
        argv += ["--credential", h.credential]
        let mem = memField.stringValue.trimmingCharacters(in: .whitespaces)
        if !mem.isEmpty { argv += ["--memory", mem] }
        let mp = procField.stringValue.trimmingCharacters(in: .whitespaces)
        if !mp.isEmpty { argv += ["--max-processes", mp] }
        if detachedBox.state == .on { argv += ["--detached"] }
        return argv + ["--"] + h.bin
    }

    @objc func harnessChanged(_ sender: Any?) {
        refresh(nil)
    }

    @objc func refresh(_ sender: Any?) {
        let (_, m, b) = selected()
        let (net, ask) = resolvedPolicy()
        var help = Self.modeHelp[m.key] ?? ""
        help += "\nResolves to --network-profile \(net) --ask-mode \(ask)."
        if avail[b] != true { help += " (backend unavailable on this machine)" }
        helpLabel.stringValue = help
        imageRow.isHidden = (b != "docker")  // image only matters for containers
        preview.string = currentArgv().map { renderCommandFile(argv: $0) } ?? "# pick a project folder above"
    }

    /// Probe docker/nono off the main thread: dialog opens instantly, items
    /// enable as results land. (Synchronous `docker info` on a cold daemon
    /// used to beachball the app at startup.)
    func probeBackends() {
        DispatchQueue.global(qos: .utility).async {
            var found: [String: Bool] = [:]
            for b in Self.backends where b.key != "local" {
                found[b.key] = Self.backendOK(b.need)
            }
            DispatchQueue.main.async {
                for (i, b) in Self.backends.enumerated() {
                    if b.key == "local" { continue }
                    self.avail[b.key] = found[b.key] ?? false
                    self.backendPop.item(at: i)?.isEnabled = found[b.key] ?? false
                }
                self.refresh(nil)
            }
        }
    }

    @objc func toggleCmd(_ sender: Any?) {
        previewScroll.isHidden = (showCmdBox.state != .on)
    }

    @objc func browse(_ sender: Any?) {        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { resp in
            if resp == .OK, let dir = panel.url?.path {
                self.pathField.stringValue = dir
                self.refresh(nil)
            }
        }
    }

    @objc func run(_ sender: Any?) {
        guard let argv = currentArgv() else {
            owner?.alert("Pick a project folder first.")
            return
        }
        let h = harnesses[harnessPop.indexOfSelectedItem]
        let tool = h.bin.first ?? h.key
        if !Self.shellOK("/bin/sh", ["-c", "command -v \(tool) >/dev/null"]) {
            let hint = Self.installHint[tool] ?? "install \(tool)"
            owner?.alert("“\(tool)” not found on your Mac.\nInstall it first:\n\(hint)")
            return
        }
        let project = pathField.stringValue.trimmingCharacters(in: .whitespaces)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: project, isDirectory: &isDir), isDir.boolValue else {
            owner?.alert("Project folder does not exist:\n\(project)")
            return
        }
        owner?.openInTerminal(argv: argv)
        window.close()
    }

    @objc func close(_ sender: Any?) {
        window.close()
    }

    func show() {
        harnessChanged(nil)
        previewScroll.isHidden = true  // command hidden until asked for
        window.delegate = self
        probeBackends()
        // Pin to the primary (menu-bar) display: window.center() follows the
        // mouse/key screen, which stranded the dialog on unseen displays.
        if let screen = NSScreen.screens.first {
            let vf = screen.visibleFrame
            let f = window.frame
            window.setFrameOrigin(NSPoint(x: vf.midX - f.width / 2, y: vf.midY - f.height / 2))
        } else {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if owner?.dialog === self { owner?.dialog = nil }
    }
}

// MARK: - anthropic login

/// Per-service API keys, stored straight into the login Keychain via SecItem
/// (never argv, never disk). Boxed sessions use the Keychain key: the proxy
/// finds it and agents only ever see a phantom token. Console OAuth stays a
/// host-side-only convenience for direct (unboxed) claude use.
final class LoginPanel: NSObject, NSWindowDelegate {
    weak var owner: AppDelegate?
    var window: NSWindow!
    var servicePop = NSPopUpButton()
    var statusLabel = NSTextField()
    var keyField = NSSecureTextField()
    var consoleBtn = NSButton()
    var consoleNote = NSTextField()

    func selectedService() -> KeyService {
        let i = servicePop.indexOfSelectedItem
        return (i >= 0 && i < keyServices.count) ? keyServices[i] : keyServices[0]
    }

    init(owner: AppDelegate) {
        self.owner = owner
        super.init()
        build()
    }

    func row(_ label: String, _ control: NSView) -> NSStackView {
        let l = NSTextField(labelWithString: label)
        l.alignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 92).isActive = true
        control.translatesAutoresizingMaskIntoConstraints = false
        let r = NSStackView(views: [l, control])
        r.orientation = .horizontal
        r.spacing = 8
        r.alignment = .centerY
        return r
    }

    func build() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 340),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Connect API keys"
        window.isReleasedWhenClosed = false
        window.delegate = self

        for s in keyServices { servicePop.addItem(withTitle: s.title) }
        servicePop.target = self
        servicePop.action = #selector(serviceChanged(_:))

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        consoleBtn = NSButton(title: "Log in via Console…", target: self, action: #selector(consoleLogin(_:)))
        consoleBtn.bezelStyle = .rounded
        consoleNote = NSTextField(labelWithString: "Opens a Terminal running claude; complete the browser OAuth there. (Host-side use only — boxed sessions take API key, below.)")
        consoleNote.textColor = .secondaryLabelColor
        consoleNote.font = .systemFont(ofSize: 11)

        keyField.placeholderString = "sk-ant-…"
        let saveBtn = NSButton(title: "Save API key", target: self, action: #selector(saveKey(_:)))
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        let keyNote = NSTextField(labelWithString: "Stored in your login Keychain (service “soteria”). Agents only ever see a phantom token.")
        keyNote.textColor = .secondaryLabelColor
        keyNote.font = .systemFont(ofSize: 11)
        keyNote.lineBreakMode = .byWordWrapping

        let closeBtn = NSButton(title: "Done", target: self, action: #selector(close(_:)))
        closeBtn.bezelStyle = .rounded
        closeBtn.keyEquivalent = "\u{1b}"
        let btnRow = NSStackView(views: [NSView(), closeBtn])
        btnRow.orientation = .horizontal

        let stack = NSStackView(views: [
            row("Service:", servicePop), statusLabel, consoleBtn, consoleNote,
            row("API key:", keyField), saveBtn, keyNote, btnRow,
        ])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
        ])
        refreshStatus()
    }

    func refreshStatus() {
        let s = selectedService()
        statusLabel.stringValue = "Status: " + keyStatus(s)
        keyField.placeholderString = s.placeholder
        consoleBtn.isHidden = !s.consoleOAuth
        consoleNote.isHidden = !s.consoleOAuth
    }

    @objc func serviceChanged(_ sender: Any?) {
        keyField.stringValue = ""
        refreshStatus()
    }

    @objc func consoleLogin(_ sender: Any?) {
        // Login is a user-driven trusted ceremony, not agent execution.
        // Claude's OAuth needs a real browser, a localhost callback, and
        // Keychain writes across ~/Library — probed: binds work fine in the
        // box (python + node both listen OK), so the callback failure is
        // Claude-side (stale holder of its fixed port or wrapper interference),
        // not the sandbox. Run it plain; agent sessions stay boxed.
        // If this still fails: quit stale Terminals/claude processes and retry,
        // or use the API-key path below (no OAuth involved).
        owner?.openScript("#!/bin/sh\nexec claude\n")
    }

    @objc func saveKey(_ sender: Any?) {
        let secret = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else { return }
        if keychainSet(account: selectedService().account, secret: secret) {
            keyField.stringValue = ""
            refreshStatus()
        } else {
            owner?.alert("Could not write to Keychain.")
        }
    }

    @objc func close(_ sender: Any?) {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        if owner?.login === self { owner?.login = nil }
    }

    func show() {
        refreshStatus()
        if let screen = NSScreen.screens.first {
            let vf = screen.visibleFrame
            let f = window.frame
            window.setFrameOrigin(NSPoint(x: vf.midX - f.width / 2, y: vf.midY - f.height / 2))
        } else {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

// Headless check: `SoteriaBar --print-command claude balanced /tmp/x`
// prints the exact .command content without starting the GUI.
if CommandLine.arguments.count == 5, CommandLine.arguments[1] == "--print-command",
   let h = harnesses.first(where: { $0.key == CommandLine.arguments[2] }),
   let m = modes.first(where: { $0.key == CommandLine.arguments[3] }) {
    print(renderCommandFile(argv: buildRunArgv(binary: findBinary() ?? "soteria", harness: h, mode: m,
                                                project: CommandLine.arguments[4])), terminator: "")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
