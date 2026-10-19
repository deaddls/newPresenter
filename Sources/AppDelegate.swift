import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = GlitchController()
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
#if VGAGLITCH2
    private var pollHotKey: HotKey?
    private static let title = "VGA Glitch 2"
    private static let appName = "VGAGlitch2"
    private static let symbol = "banknote"
#else
    private static let title = "VGA Glitch"
    private static let appName = "VGAGlitch"
    private static let symbol = "display"
#endif

    // hold-to-stop state
    private var pressBegan: Double?
    private var pressHandled = false
    private var holdTimer: Timer?
    private static let holdToStop = 3.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !Settings.hideIcon { showStatusItem() }

        hotKey = HotKey(keyCode: kVK_ANSI_G, modifiers: controlKey | optionKey | cmdKey)
        hotKey?.onPress = { [weak self] in self?.hotKeyDown() }
        hotKey?.onRelease = { [weak self] in self?.hotKeyUp() }
        if hotKey == nil {
            NSLog("VGAGlitch: could not register ⌃⌥⌘G")
            alert("Tastenkürzel ⌃⌥⌘G ist schon belegt",
                  "Eine andere App nutzt diese Kombination. Starten/Stoppen geht weiterhin über das Menüleisten-Symbol.")
        }
#if VGAGLITCH2
        pollHotKey = HotKey(keyCode: kVK_ANSI_B, modifiers: controlKey | optionKey | cmdKey, id: 2)
        pollHotKey?.onPress = { [weak self] in self?.controller.poll.show() }
#endif

        let args = CommandLine.arguments
        // --smoke <seconds>: start, run briefly, quit (for testing; never prompts)
        if let i = args.firstIndex(of: "--smoke"), i + 1 < args.count, let seconds = Double(args[i + 1]) {
            controller.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApp.terminate(nil) }
            return
        }

        if !CGPreflightScreenCaptureAccess() {
            // Shows the system prompt once; without it only overlay effects (blue, black, noise) work.
            CGRequestScreenCaptureAccess()
        }

        if args.contains("--start") { controller.start() }
    }

    /// Opening the app again while it runs brings a hidden menu bar icon back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if statusItem == nil {
            Settings.hideIcon = false
            showStatusItem()
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    // MARK: - Hotkey

    private func hotKeyDown() {
        // Ignore key repeat, but recover if a release event ever went missing.
        if let began = pressBegan, CACurrentMediaTime() - began < 10 { return }
        pressBegan = CACurrentMediaTime()
        pressHandled = false
        holdTimer?.invalidate()

        if !controller.running {
            controller.start()
            pressHandled = true
        } else {
            let timer = Timer(timeInterval: Self.holdToStop, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.pressHandled = true
                self.controller.stop()
            }
            RunLoop.main.add(timer, forMode: .common)
            holdTimer = timer
        }
    }

    private func hotKeyUp() {
        holdTimer?.invalidate()
        holdTimer = nil
        pressBegan = nil
        guard !pressHandled, controller.running else { return }
        if Settings.shortPressStops {
            controller.stop()
        } else {
            controller.burst()
        }
    }

    // MARK: - Menu bar

    private func showStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: Self.symbol, accessibilityDescription: Self.title)
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let running = controller.running

        let header = NSMenuItem(title: running ? "\(Self.title) – aktiv" : "\(Self.title) – aus", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(item(running ? "Stoppen" : "Starten", #selector(toggle)))
        let burst = item("Sofort einen Glitch auslösen", #selector(burstNow))
        burst.isEnabled = running
        menu.addItem(burst)

        let hint = NSMenuItem(title: "⌃⌥⌘G = Start · 3 s halten = Stopp", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
#if VGAGLITCH2
        menu.addItem(.separator())
        menu.addItem(submenu("Bildschirme", ["Nur Beamer", "Laptop + Beamer"],
                             selected: Settings.allScreens ? 1 : 0, #selector(setScreens(_:))))
        let poll = item("„Bargeld abschaffen?“ zufällig einblenden", #selector(togglePoll))
        poll.state = Settings.pollEnabled ? .on : .off
        menu.addItem(poll)
        menu.addItem(item("Umfrage jetzt zeigen (⌃⌥⌘B)", #selector(showPoll)))
#else
        let target = NSMenuItem(title: "Wirkt nur auf Beamer / externe Bildschirme", action: nil, keyEquivalent: "")
        target.isEnabled = false
        menu.addItem(target)
#endif
        menu.addItem(.separator())

        menu.addItem(submenu("Intensität", ["Leicht", "Mittel", "Heftig"], selected: Settings.intensity, #selector(setIntensity(_:))))
        menu.addItem(submenu("„Kein Signal“-Meldung", ["Deutsch", "English", "Aus"],
                             selected: Settings.osdLanguage, #selector(setOSD(_:))))
        let short = item("Kurz drücken stoppt sofort", #selector(toggleShortPress))
        short.state = Settings.shortPressStops ? .on : .off
        short.toolTip = "Aus: kurzer Druck während aktiv löst einen Extra-Glitch aus. Stoppen dann nur per 3 s halten."
        menu.addItem(short)
        menu.addItem(.separator())

        if CGPreflightScreenCaptureAccess() {
            let ok = NSMenuItem(title: "Bildschirmaufnahme erlaubt ✓", action: nil, keyEquivalent: "")
            ok.isEnabled = false
            menu.addItem(ok)
        } else {
            menu.addItem(item("⚠︎ Bildschirmaufnahme erlauben … (nur Overlay-Effekte)", #selector(openPrivacySettings)))
        }
        menu.addItem(item("Menüleisten-Symbol ausblenden", #selector(hideIcon)))
        menu.addItem(.separator())
        menu.addItem(item("Beenden", #selector(quit)))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func submenu(_ title: String, _ options: [String], selected: Int, _ action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (i, option) in options.enumerated() {
            let child = item(option, action)
            child.tag = i
            child.state = i == selected ? .on : .off
            sub.addItem(child)
        }
        parent.submenu = sub
        return parent
    }

    @objc private func toggle() {
        controller.running ? controller.stop() : controller.start()
    }

    @objc private func burstNow() { controller.burst() }

    @objc private func setIntensity(_ sender: NSMenuItem) { Settings.intensity = sender.tag }

    @objc private func setOSD(_ sender: NSMenuItem) { Settings.osdLanguage = sender.tag }

    @objc private func toggleShortPress() { Settings.shortPressStops.toggle() }

#if VGAGLITCH2
    @objc private func setScreens(_ sender: NSMenuItem) {
        Settings.allScreens = sender.tag == 1
        controller.syncScreens()
    }

    @objc private func togglePoll() { Settings.pollEnabled.toggle() }

    @objc private func showPoll() { controller.poll.show() }
#endif

    @objc private func openPrivacySettings() {
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func hideIcon() {
        alert("Menüleisten-Symbol wird ausgeblendet",
              "Die App läuft weiter und reagiert auf ⌃⌥⌘G. Um das Symbol zurückzuholen, öffne \(Self.appName) einfach noch einmal.")
        Settings.hideIcon = true
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
