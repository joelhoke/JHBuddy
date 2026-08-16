import AppKit
import QuartzCore

@MainActor
final class BuddyWindowController: NSWindowController {
    private let avatarView: AvatarView
    private var clickThrough = false

    var isClickThrough: Bool { clickThrough }

    init(actions: ActionRegistry) {
        avatarView = AvatarView(actions: actions)
        let frame = Self.restoredFrame ?? NSRect(x: 100, y: 100, width: 280, height: 280)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.contentView = avatarView
        super.init(window: panel)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(expressionChanged(_:)),
            name: .deskBuddyExpressionChanged,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.orderFrontRegardless()
    }

    func toggleClickThrough() {
        clickThrough.toggle()
        window?.ignoresMouseEvents = clickThrough
    }

    func setExpression(_ expression: Expression) {
        avatarView.expression = expression
    }

    func showBuddy() {
        window?.orderFrontRegardless()
    }

    @objc private func expressionChanged(_ notification: Notification) {
        guard let expression = notification.object as? Expression else { return }
        setExpression(expression)
    }

    @objc private func activeSpaceDidChange(_ notification: Notification) {
        showBuddy()
        avatarView.triggerSpaceHop()
    }

    func persistFrame() {
        guard let frame = window?.frame else { return }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.frameDefaultsKey)
    }

    private static let frameDefaultsKey = "DeskBuddy.windowFrame"

    private static var restoredFrame: NSRect? {
        guard let storedFrame = UserDefaults.standard.string(forKey: frameDefaultsKey) else { return nil }
        let frame = NSRectFromString(storedFrame)
        return frame.isEmpty ? nil : frame
    }
}

@MainActor
final class AvatarView: NSView {
    var expression: Expression = .neutral {
        didSet {
            transitionStart = CACurrentMediaTime()
            previousExpression = oldValue
            needsDisplay = true
        }
    }

    private let actions: ActionRegistry
    private var previousExpression: Expression = .neutral
    private var transitionStart = CACurrentMediaTime()
    private var trackingArea: NSTrackingArea?
    private var pointerLocation = NSPoint.zero
    private var mouseDownLocation = NSPoint.zero
    private var isHovering = false
    private var redrawTimer: Timer?
    private var holdTimer: Timer?
    private var pointerIsDown = false
    private var holdMenuWasShown = false
    private var pokeStart: CFTimeInterval?
    private var spaceHopStart: CFTimeInterval?
    private let backgroundImage = AvatarView.bundledImage(named: "JHPal-BG")
    private let openEyesImage = AvatarView.bundledImage(named: "Eyes-open")
    private let closedEyesImage = AvatarView.bundledImage(named: "Eyes-closed")

    init(actions: ActionRegistry) {
        self.actions = actions
        super.init(frame: .zero)
        wantsLayer = true
        layer?.isOpaque = false
        redrawTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.needsDisplay = true
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            redrawTimer?.invalidate()
            redrawTimer = nil
        }
    }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let circle = bounds.insetBy(dx: 10, dy: 10)
        let dx = point.x - circle.midX
        let dy = point.y - circle.midY
        return dx * dx + dy * dy <= (circle.width / 2) * (circle.width / 2) ? self : nil
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func mouseMoved(with event: NSEvent) {
        pointerLocation = convert(event.locationInWindow, from: nil)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        pointerIsDown = true
        holdMenuWasShown = false
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.pointerIsDown else { return }
                self.holdMenuWasShown = true
                self.showOptionsMenu()
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if hypot(location.x - mouseDownLocation.x, location.y - mouseDownLocation.y) >= 6 {
            holdTimer?.invalidate()
            holdTimer = nil
        }
        window?.performDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { (window?.windowController as? BuddyWindowController)?.persistFrame() }
        pointerIsDown = false
        holdTimer?.invalidate()
        holdTimer = nil
        guard !holdMenuWasShown else { return }
        let location = convert(event.locationInWindow, from: nil)
        let moved = hypot(location.x - mouseDownLocation.x, location.y - mouseDownLocation.y)
        guard moved < 6 else { return }
        triggerPoke()
        let context = BuddyActionContext(expression: expression, location: location)
        actions.perform(event.clickCount > 1 ? .doubleClick : .click, context: context)
    }

    override func rightMouseDown(with event: NSEvent) {
        actions.perform(
            .secondaryClick,
            context: BuddyActionContext(expression: expression, location: convert(event.locationInWindow, from: nil))
        )
    }

    @objc private func chooseExpression(_ sender: NSMenuItem) {
        guard let expression = Expression(rawValue: sender.tag) else { return }
        self.expression = expression
    }

    @objc private func closeBuddy(_ sender: Any?) {
        window?.orderOut(nil)
    }

    @objc private func quitBuddy(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }

    private func showOptionsMenu() {
        let menu = NSMenu()
        let expressionMenu = NSMenu(title: "Expression")
        for expression in Expression.allCases {
            let item = NSMenuItem(title: expression.displayName, action: #selector(chooseExpression(_:)), keyEquivalent: "")
            item.target = self
            item.tag = expression.rawValue
            expressionMenu.addItem(item)
        }
        let expressionItem = NSMenuItem(title: "Expression", action: nil, keyEquivalent: "")
        expressionItem.submenu = expressionMenu
        menu.addItem(expressionItem)
        menu.addItem(.separator())
        let closeItem = NSMenuItem(title: "Close Buddy", action: #selector(closeBuddy(_:)), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)
        let quitItem = NSMenuItem(title: "Quit DeskBuddy", action: #selector(quitBuddy(_:)), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        menu.popUp(positioning: nil, at: mouseDownLocation, in: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds.insetBy(dx: 12, dy: 12)
        let now = CACurrentMediaTime()
        let transition = min(1, (now - transitionStart) / 0.28)
        let palette = expression.palette
        let previousPalette = previousExpression.palette
        let emotionalColor = previousPalette.base.blended(withFraction: transition, of: palette.base) ?? palette.base
        let breathe = sin(now * 1.7) * 2
        let sphere = rect.insetBy(dx: -breathe, dy: -breathe)
        let spaceHop = currentSpaceHop(at: now)
        drawSpaceHole(in: rect, intensity: spaceHop.holeIntensity)

        let pokeScale = currentPokeScale(at: now)
        context.saveGState()
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.scaleBy(x: pokeScale.width, y: pokeScale.height)
        context.translateBy(x: -bounds.midX, y: -bounds.midY)
        context.translateBy(x: 0, y: spaceHop.verticalOffset)

        context.saveGState()
        context.setShadow(offset: .init(width: 0, height: 8), blur: 18, color: NSColor.black.withAlphaComponent(0.30).cgColor)
        backgroundImage.draw(in: sphere, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        context.restoreGState()

        context.saveGState()
        context.addEllipse(in: sphere)
        context.clip()
        context.setBlendMode(.multiply)
        context.setFillColor(emotionalColor.withAlphaComponent(0.5).cgColor)
        context.fill(sphere)
        context.restoreGState()

        let face = NSRect(x: sphere.minX + sphere.width * 0.17, y: sphere.minY + sphere.height * 0.26, width: sphere.width * 0.66, height: sphere.height * 0.46)
        drawFace(in: face, context: context, time: now)
        context.restoreGState()
    }

    private func drawFace(in rect: NSRect, context: CGContext, time: CFTimeInterval) {
        let blink = expression == .sleepy || (time.truncatingRemainder(dividingBy: 5.6) > 5.45)
        let eyesImage = blink ? closedEyesImage : openEyesImage
        let aspectRatio = eyesImage.size.width / eyesImage.size.height
        let width = rect.width * 0.96
        let height = width / aspectRatio
        let offsetX = isHovering ? max(-5, min(5, (pointerLocation.x - bounds.midX) * 0.05)) : sin(time * 0.7) * 1.5
        let eyeRect = NSRect(
            x: rect.midX - width / 2 + offsetX,
            y: rect.minY + rect.height * 0.18,
            width: width,
            height: height
        )
        eyesImage.draw(in: eyeRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

        let mouthY = rect.minY + rect.height * 0.75
        let mouthWidth = rect.width * 0.34
        let curve: CGFloat
        switch expression {
        case .happy: curve = 22
        case .sad: curve = -18
        case .angry: curve = -9
        case .inquisitive: curve = 8
        case .confused: curve = 3
        case .sleepy: curve = 0
        case .neutral: curve = 5
        }
        let mouth = NSBezierPath()
        mouth.move(to: .init(x: rect.midX - mouthWidth / 2, y: mouthY))
        mouth.curve(
            to: .init(x: rect.midX + mouthWidth / 2, y: mouthY),
            controlPoint1: .init(x: rect.midX - mouthWidth * 0.20, y: mouthY + curve),
            controlPoint2: .init(x: rect.midX + mouthWidth * 0.20, y: mouthY + curve)
        )
        mouth.lineWidth = 6
        NSColor.white.withAlphaComponent(0.92).setStroke()
        mouth.stroke()
    }

    private static func bundledImage(named name: String) -> NSImage {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else {
            fatalError("Missing required avatar asset: \(name).png")
        }
        return image
    }

    private func triggerPoke() {
        pokeStart = CACurrentMediaTime()
        needsDisplay = true
    }

    func triggerSpaceHop() {
        spaceHopStart = CACurrentMediaTime()
        needsDisplay = true
    }

    private func currentPokeScale(at time: CFTimeInterval) -> CGSize {
        guard let pokeStart else { return .init(width: 1, height: 1) }
        let elapsed = time - pokeStart
        if elapsed >= 0.52 {
            self.pokeStart = nil
            return .init(width: 1, height: 1)
        }
        if elapsed < 0.09 {
            let progress = elapsed / 0.09
            return .init(width: 1 - 0.14 * progress, height: 1 + 0.13 * progress)
        }
        if elapsed < 0.20 {
            let progress = (elapsed - 0.09) / 0.11
            return .init(width: 0.86 + 0.26 * progress, height: 1.13 - 0.21 * progress)
        }
        let recovery = (elapsed - 0.20) / 0.32
        let spring = cos(recovery * .pi * 4) * (1 - recovery)
        return .init(width: 1 + 0.12 * spring, height: 1 - 0.08 * spring)
    }

    private func currentSpaceHop(at time: CFTimeInterval) -> (verticalOffset: CGFloat, holeIntensity: CGFloat) {
        guard let spaceHopStart else { return (0, 0) }
        let elapsed = time - spaceHopStart
        if elapsed >= 0.56 {
            self.spaceHopStart = nil
            return (0, 0)
        }
        let progress = max(0, min(1, elapsed / 0.56))
        let verticalOffset = -34 * sin(progress * .pi)
        let holeIntensity = sin(progress * .pi)
        return (verticalOffset, holeIntensity)
    }

    private func drawSpaceHole(in rect: NSRect, intensity: CGFloat) {
        guard intensity > 0 else { return }
        let holeWidth = rect.width * (0.24 + 0.16 * intensity)
        let holeHeight = 13 * intensity
        let hole = NSRect(
            x: rect.midX - holeWidth / 2,
            y: rect.maxY - 29 - holeHeight / 2,
            width: holeWidth,
            height: holeHeight
        )
        let path = NSBezierPath(ovalIn: hole)
        NSColor.black.withAlphaComponent(0.5 * intensity).setFill()
        path.fill()
    }
}
