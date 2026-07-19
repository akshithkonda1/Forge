# ForgeWidget — Lifestyle Home Screen widget

A WidgetKit extension that shows the user's **Quality-of-Life score** and
**ARIA's top recommendation** on the Home Screen and Lock Screen.

These two Swift files are **scaffolding** — they are intentionally **not** part
of the app target (so CI's app build never compiles them and they cannot break
the app). The data side already ships in the app: `LifestyleWidgetBridge`
(in `ForgeSwift/ForgeSwift/LifestyleView.swift`) writes a `LifestyleWidgetSnapshot`
into a shared App Group every time the Lifestyle tab loads/refreshes, and calls
`WidgetCenter.shared.reloadTimelines(ofKind: "LifestyleWidget")`.

To light it up you just need to add the extension target in Xcode.

## One-time setup (in Xcode)

1. **Add the target:** File ▸ New ▸ Target… ▸ **Widget Extension**. Name it
   `ForgeWidget`. Uncheck "Include Configuration App Intent" (this widget is
   static). Finish, and **activate** the scheme if prompted.
2. **Use these files:** delete the auto-generated `ForgeWidget.swift`
   boilerplate, then add `LifestyleWidget.swift` and `ForgeWidgetBundle.swift`
   from this folder to the **ForgeWidget** target (Target Membership: ForgeWidget
   only — *not* the app).
3. **Add the App Group to BOTH targets** (Signing & Capabilities ▸ + Capability ▸
   App Groups):
   - app target `ForgeSwift`
   - extension target `ForgeWidget`
   Use the **same** id on both, e.g. `group.com.forge.ForgeSwift`.
4. **Keep the id in sync** — it is referenced in two places and must match the
   capability:
   - app: `LifestyleWidgetBridge.appGroup` (`LifestyleView.swift`)
   - widget: `LifestyleProvider.appGroup` (`LifestyleWidget.swift`)
   The storage key (`lifestyle.widget.snapshot`) must match too.
5. **Build & run**, then long-press the Home Screen ▸ + ▸ search "Lifestyle" ▸
   add. Open the Lifestyle tab once so the first snapshot is written.

## Notes

- Supported families: `systemSmall`, `systemMedium`. Extend
  `supportedFamilies` (and add a Lock Screen `accessoryRectangular` layout) if
  you want more.
- Until the App Group capability is added, `UserDefaults(suiteName:)` writes to a
  private domain, so the widget shows placeholder/preview data — nothing crashes.
- `LifestyleWidgetSnapshot` is duplicated here because the widget target can't
  see app-target types. If you'd rather share one definition, move the struct to
  a file with membership in *both* targets and delete the copy here.
