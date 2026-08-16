# DeskBuddy

A native macOS desktop companion with a transparent, draggable window, animated 3D-feeling expressions, and an extensible action registry.

## Run

```sh
cd /Users/joelhoke/Documents/DeskBuddy
swift run
```

Click the buddy to make it squash and spring back, while cycling expressions. Double-click for a confirmation sound, and drag it to reposition it. It remains visible across macOS Spaces and application fullscreen Spaces. Hold it for 0.65 seconds to open its options menu, including expression selection and Close Buddy. Use the JH menu-bar icon to show a closed buddy, select an expression, or enable click-through mode. Its last position is remembered.

## Adding future actions

Register a handler in `ActionRegistry.registerDefaults()` or from your own module:

```swift
actions.register(.doubleClick) { context in
    // Trigger an app command, script, local API, etc.
}
```

`BuddyActionContext` contains the active expression and pointer location. Rendering remains separate from actions so integrations do not affect animation performance.

Custom action identifiers are unlimited:

```swift
actions.register(BuddyAction("open-reminders")) { context in
    // Add a future integration.
}
```

## Art assets

`JHLogo.svg` is used as the menu-bar icon and rendered as a template image, so macOS automatically displays it in the appropriate light or dark appearance. `JHPal-BG.png` is the avatar background and `Eyes-open.png` / `Eyes-closed.png` are composited as the active eye state. Every emotional state adds a 50%-opacity multiply tint over the supplied background, so expressions retain the source art while shifting color. A future Blender/Metal asset pipeline can replace `AvatarView.draw(_:)` while preserving the window, behavior, and action APIs.
