# ForgeWidget — Lifestyle Home Screen widget

A WidgetKit extension that shows the user's **Quality-of-Life score** and
**ARIA's top recommendation** on the Home Screen and Lock Screen.

`LifestyleWidget.swift` in this folder is compiled into the live
`ForgeWidgetExtension` target (see `ForgeSwift/ForgeWidgetExtension/`). The
`@main` entry point is `ForgeWidgetExtensionBundle`, which registers
`LifestyleWidget()` alongside the other widgets.

The data side ships in the app: `LifestyleWidgetBridge` (in
`ForgeSwift/ForgeSwift/LifestyleView.swift`) writes a `LifestyleWidgetSnapshot`
into a shared App Group every time the Lifestyle tab loads/refreshes, and calls
`WidgetCenter.shared.reloadTimelines(ofKind: "LifestyleWidget")`.

## App Group

Both the app target (`ForgeSwift`) and the widget extension must share the
same App Group id, e.g. `group.com.forge.ForgeSwift`. Keep it in sync:

- app: `LifestyleWidgetBridge.appGroup` (`LifestyleView.swift`)
- widget: `LifestyleProvider.appGroup` (`LifestyleWidget.swift`)

The storage key (`lifestyle.widget.snapshot`) must match too.

## Notes

- Supported families: `systemSmall`, `systemMedium`.
- Until the App Group capability is added, `UserDefaults(suiteName:)` writes to a
  private domain, so the widget shows placeholder/preview data — nothing crashes.
- `LifestyleWidgetSnapshot` lives in `ForgeCore` (`Utils/HomeWidgetSnapshot.swift`)
  so the app target and this widget target decode the same definition instead of
  two hand-kept copies.
