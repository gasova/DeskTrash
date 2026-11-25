import AppKit
import ServiceManagement

// MARK: - Finder bridge
// Everything goes through Finder so that Put Back, external volumes,
// the trash sound and the "empty" warning all behave like the real Trash.

enum Finder {
    static func run(_ script: String, args: [String] = [], completion: ((String?) -> Void)? = nil) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script] + args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { proc in
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let result = proc.terminationStatus == 0 ? (text ?? "") : nil
            DispatchQueue.main.async { completion?(result) }
        }
        do {
            try process.run()
        } catch {
            completion?(nil)
        }
    }

    static let deleteScript = """
    on run argv
        set theItems to {}
        repeat with p in argv
            set end of theItems to (POSIX file (contents of p) as alias)
        end repeat
        tell application "Finder" to delete theItems
    end run
    """

    static let countScript = "tell application \"Finder\" to count items of trash"

    static let openScript = """
    tell application "Finder"
        open trash
        activate
    end tell
    """

    static let emptyScript = """
    tell application "Finder"
        activate
        empty trash
    end tell
    """
}

// MARK: - View

final class TrashView: NSView {
    var onOpen: (() -> Void)?
    var onMoved: (() -> Void)?
    var onDrop: (([URL]) -> Void)?
    var menuProvider: (() -> NSMenu)?

    var isFull = false { didSet { needsDisplay = true } }
    private var highlighted = false { didSet { needsDisplay = true } }

    private var dragStartMouse = NSPoint.zero
    private var dragStartOrigin = NSPoint.zero
    private var didDrag = false

    private let title: String = {
        let name = FileManager.default.displayName(atPath: NSHomeDirectory() + "/.Trash")
        return (name.isEmpty || name.hasPrefix(".")) ? "Trash" : name
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect) {
        let iconRect = NSRect(x: (bounds.width - 64) / 2, y: 28, width: 64, height: 64)
        if highlighted {
            NSColor.white.withAlphaComponent(0.28).setFill()
            NSBezierPath(roundedRect: iconRect.insetBy(dx: -5, dy: -5), xRadius: 10, yRadius: 10).fill()
        }
        let icon = NSImage(named: isFull ? NSImage.trashFullName : NSImage.trashEmptyName)
        icon?.draw(in: iconRect)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .shadow: shadow,
            .paragraphStyle: paragraph,
        ]
        (title as NSString).draw(in: NSRect(x: 2, y: 4, width: bounds.width - 4, height: 18),
                                 withAttributes: attributes)
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin ?? .zero
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        let dx = now.x - dragStartMouse.x
        let dy = now.y - dragStartMouse.y
        if !didDrag && abs(dx) < 3 && abs(dy) < 3 { return }
        didDrag = true
        window?.setFrameOrigin(NSPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag {
            onMoved?()
        } else if event.clickCount == 2 {
            onOpen?()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }

    // MARK: Drop target

    private func operation(for sender: NSDraggingInfo) -> NSDragOperation {
        let mask = sender.draggingSourceOperationMask
        if mask.contains(.generic) { return .generic }
        if mask.contains(.move) { return .move }
        return mask.contains(.copy) ? .copy : []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        highlighted = true
        return operation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        operation(for: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = false }

    override func draggingEnded(_ sender: NSDraggingInfo) { highlighted = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlighted = false
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let view = TrashView(frame: NSRect(x: 0, y: 0, width: 96, height: 100))
    private var timer: Timer?
    private var polling = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: view.frame, styleMask: .borderless,
                          backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        // Just above the Finder desktop icons, below every normal window.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = view
        window.setFrameOrigin(startOrigin())
        window.orderFrontRegardless()

        view.onOpen = { Finder.run(Finder.openScript) }
        view.onMoved = { [weak self] in self?.saveOrigin() }
        view.onDrop = { [weak self] urls in self?.trash(urls) }
        view.menuProvider = { [weak self] in self?.makeMenu() ?? NSMenu() }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: Actions

    private func trash(_ urls: [URL]) {
        Finder.run(Finder.deleteScript, args: urls.map(\.path)) { [weak self] result in
            if result == nil { NSSound.beep() }
            self?.refresh()
        }
    }

    private func refresh() {
        guard !polling else { return }
        polling = true
        Finder.run(Finder.countScript) { [weak self] result in
            guard let self else { return }
            self.polling = false
            if let result, let count = Int(result) {
                self.view.isFull = count > 0
            }
        }
    }

    @objc private func openTrash() { Finder.run(Finder.openScript) }

    @objc private func emptyTrash() {
        Finder.run(Finder.emptyScript) { [weak self] _ in self?.refresh() }
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let open = NSMenuItem(title: "Open", action: #selector(openTrash), keyEquivalent: "")
        let empty = NSMenuItem(title: "Empty Trash", action: #selector(emptyTrash), keyEquivalent: "")
        empty.isEnabled = view.isFull
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let quitItem = NSMenuItem(title: "Quit DeskTrash", action: #selector(quit), keyEquivalent: "")

        for item in [open, empty, .separator(), login, .separator(), quitItem] {
            if !item.isSeparatorItem { item.target = self }
            menu.addItem(item)
        }
        return menu
    }

    // MARK: Position

    private func startOrigin() -> NSPoint {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "originX") != nil {
            let saved = NSPoint(x: defaults.double(forKey: "originX"),
                                y: defaults.double(forKey: "originY"))
            if isOnScreen(saved) { return saved }
        }
        return defaultOrigin()
    }

    private func defaultOrigin() -> NSPoint {
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: frame.maxX - view.frame.width - 16, y: frame.minY + 16)
    }

    private func isOnScreen(_ origin: NSPoint) -> Bool {
        let rect = NSRect(origin: origin, size: view.frame.size)
        return NSScreen.screens.contains { $0.frame.intersects(rect) }
    }

    private func saveOrigin() {
        let origin = window.frame.origin
        UserDefaults.standard.set(Double(origin.x), forKey: "originX")
        UserDefaults.standard.set(Double(origin.y), forKey: "originY")
    }

    @objc private func screensChanged() {
        if !isOnScreen(window.frame.origin) {
            window.setFrameOrigin(defaultOrigin())
        }
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
