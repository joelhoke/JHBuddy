import AppKit
import Foundation

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
application.run()

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let actions = ActionRegistry()
    private var buddyWindow: BuddyWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        actions.registerDefaults()
        buddyWindow = BuddyWindowController(actions: actions)
        buddyWindow?.showWindow(nil)
        configureStatusItem()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func toggleClickThrough(_ sender: NSMenuItem) {
        buddyWindow?.toggleClickThrough()
        sender.state = buddyWindow?.isClickThrough == true ? .on : .off
    }

    @objc private func showBuddy(_ sender: Any?) {
        buddyWindow?.showBuddy()
    }

    @objc private func setExpression(_ sender: NSMenuItem) {
        guard let expression = Expression(rawValue: sender.tag) else { return }
        buddyWindow?.setExpression(expression)
    }

    @objc private func quit(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "◉"

        let menu = NSMenu()
        let expressionMenu = NSMenu(title: "Expression")
        for expression in Expression.allCases {
            let item = NSMenuItem(
                title: expression.displayName,
                action: #selector(setExpression(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = expression.rawValue
            expressionMenu.addItem(item)
        }
        let expressionItem = NSMenuItem(title: "Expression", action: nil, keyEquivalent: "")
        expressionItem.submenu = expressionMenu
        menu.addItem(expressionItem)

        let clickThroughItem = NSMenuItem(
            title: "Click-Through",
            action: #selector(toggleClickThrough(_:)),
            keyEquivalent: ""
        )
        clickThroughItem.target = self
        menu.addItem(clickThroughItem)
        let showBuddyItem = NSMenuItem(title: "Show Buddy", action: #selector(showBuddy(_:)), keyEquivalent: "")
        showBuddyItem.target = self
        menu.addItem(showBuddyItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit DeskBuddy", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }
}

enum Expression: Int, CaseIterable {
    case neutral
    case happy
    case sad
    case angry
    case inquisitive
    case confused
    case sleepy

    var displayName: String {
        switch self {
        case .neutral: "Neutral"
        case .happy: "Happy"
        case .sad: "Sad"
        case .angry: "Angry"
        case .inquisitive: "Inquisitive"
        case .confused: "Confused"
        case .sleepy: "Sleepy"
        }
    }

    var palette: AvatarPalette {
        switch self {
        case .neutral: .init(base: NSColor(srgbRed: 0.04, green: 0.49, blue: 0.67, alpha: 1), highlight: .init(srgbRed: 0.37, green: 0.78, blue: 0.95, alpha: 1), shadow: .init(srgbRed: 0.01, green: 0.19, blue: 0.31, alpha: 1))
        case .happy: .init(base: .init(srgbRed: 0.11, green: 0.65, blue: 0.46, alpha: 1), highlight: .init(srgbRed: 0.69, green: 0.94, blue: 0.48, alpha: 1), shadow: .init(srgbRed: 0.01, green: 0.28, blue: 0.20, alpha: 1))
        case .sad: .init(base: .init(srgbRed: 0.16, green: 0.35, blue: 0.77, alpha: 1), highlight: .init(srgbRed: 0.45, green: 0.60, blue: 0.96, alpha: 1), shadow: .init(srgbRed: 0.04, green: 0.09, blue: 0.32, alpha: 1))
        case .angry: .init(base: .init(srgbRed: 0.78, green: 0.16, blue: 0.19, alpha: 1), highlight: .init(srgbRed: 1.0, green: 0.43, blue: 0.19, alpha: 1), shadow: .init(srgbRed: 0.31, green: 0.01, blue: 0.04, alpha: 1))
        case .inquisitive: .init(base: .init(srgbRed: 0.45, green: 0.28, blue: 0.83, alpha: 1), highlight: .init(srgbRed: 0.82, green: 0.62, blue: 1.0, alpha: 1), shadow: .init(srgbRed: 0.17, green: 0.06, blue: 0.39, alpha: 1))
        case .confused: .init(base: .init(srgbRed: 0.89, green: 0.44, blue: 0.12, alpha: 1), highlight: .init(srgbRed: 1.0, green: 0.80, blue: 0.35, alpha: 1), shadow: .init(srgbRed: 0.36, green: 0.11, blue: 0.02, alpha: 1))
        case .sleepy: .init(base: .init(srgbRed: 0.18, green: 0.38, blue: 0.53, alpha: 1), highlight: .init(srgbRed: 0.48, green: 0.65, blue: 0.74, alpha: 1), shadow: .init(srgbRed: 0.03, green: 0.12, blue: 0.19, alpha: 1))
        }
    }
}

struct AvatarPalette {
    let base: NSColor
    let highlight: NSColor
    let shadow: NSColor
}

struct BuddyActionContext {
    let expression: Expression
    let location: NSPoint
}

struct BuddyAction: Hashable {
    let id: String

    init(_ id: String) {
        self.id = id
    }

    static let click = BuddyAction("click")
    static let doubleClick = BuddyAction("doubleClick")
    static let secondaryClick = BuddyAction("secondaryClick")
}

@MainActor
final class ActionRegistry {
    typealias Handler = (BuddyActionContext) -> Void
    private var handlers: [BuddyAction: Handler] = [:]

    func register(_ action: BuddyAction, handler: @escaping Handler) {
        handlers[action] = handler
    }

    func perform(_ action: BuddyAction, context: BuddyActionContext) {
        handlers[action]?(context)
    }

    func registerDefaults() {
        register(.click) { [weak self] context in
            guard let self else { return }
            let expressions = Expression.allCases
            let nextIndex = (context.expression.rawValue + 1) % expressions.count
            self.perform(.expressionChanged(expressions[nextIndex]))
        }
        register(.doubleClick) { _ in
            NSSound.beep()
        }
        register(.secondaryClick) { _ in
            NSSound.beep()
        }
    }

    private func perform(_ change: RegistryChange) {
        NotificationCenter.default.post(
            name: .deskBuddyExpressionChanged,
            object: change.expression
        )
    }
}

private enum RegistryChange {
    case expressionChanged(Expression)

    var expression: Expression {
        switch self {
        case let .expressionChanged(expression): expression
        }
    }
}

extension Notification.Name {
    static let deskBuddyExpressionChanged = Notification.Name("DeskBuddy.expressionChanged")
}
