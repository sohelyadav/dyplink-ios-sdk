# Dyplink iOS SDK

Deep linking, deferred deep links, attribution, events, in-app messages,
banners, and push notifications for Dyplink.

Requires iOS 14. No external dependencies — `URLSession` and `Foundation`
only.

## Installation

Swift Package Manager:

```swift
.package(url: "https://github.com/sohelyadav/dyplink-ios-sdk", from: "0.1.0")
```

Four products; `DyplinkCore` is the only mandatory one, and each of the
others depends on it. Take only what the app uses:

| Product | What it does |
|---|---|
| `DyplinkCore` | Identity, events, deep links, deferred matching, offline queue, sessions |
| `DyplinkPush` | APNs token registration, campaign engagement, rich notification rendering |
| `DyplinkBanners` | `BannerCarouselView`, a native carousel of a widget's banners |
| `DyplinkMessages` | In-app messages: modal, sheet, full screen, and top and bottom banners |

## Getting started

```swift
import DyplinkCore

let config = DyplinkConfig.Builder(
    baseUrl: "https://your-dyplink-host",
    apiKey: "<project API key>",
    projectId: "<project id>"
).build()

Dyplink.shared.initialize(config: config)

// Where a deep link should take the app.
Dyplink.shared.onDeepLink = { result in
    router.go(result)
}
```

Then, from the app's own entry points:

```swift
// A universal link or custom-scheme URL.
Dyplink.shared.handleDeepLink(url: url)

// After a fresh install, to claim the click that led to it.
let match = await Dyplink.shared.matchDeferredDeepLink()

// Who this is, once they log in.
try await Dyplink.shared.identify(
    IdentifyParams.Builder().externalUserId("u_42").build()
)
```

## In-app messages

```swift
import DyplinkMessages

DyplinkMessages.shared.messageListener = self

DyplinkMessages.shared.onAppOpen()              // app foreground
DyplinkMessages.shared.onScreenView("Home")     // screen change
DyplinkMessages.shared.onEvent("purchase")      // custom event
```

The SDK draws the message itself, in whichever of the five layouts the
campaign chose, with its picture, its theme and its buttons. A tapped
`deep_link` or `url` button is opened after `onButtonAction` runs, so an app
that routes its own links should do it there.

## Push notifications

```swift
import DyplinkPush

DyplinkPush.shared.initialize()
try await DyplinkPush.shared.registerToken(deviceToken)   // Data or String

// From the app's own notification handlers — the SDK never intercepts a
// notification, it reports what it is handed.
DyplinkPush.shared.reportNotificationDelivered(userInfo: userInfo)

// A tap, from `didReceive(_:withCompletionHandler:)`. Reports the click —
// carrying which button was pressed, when one was — and hands back where it
// leads, if anywhere.
if let destination = DyplinkPush.shared.reportNotificationResponse(response) {
    router.go(destination)
}
```

### Rich notifications need two app extensions

No push provider carries an image, a carousel or a countdown natively, so
the client draws them — and on iOS the only things allowed to draw on a
notification are app extensions, which belong to the app rather than to a
library. The SDK supplies the contents of both; the targets are the app's.

| Extension | What it adds | Entry point |
|---|---|---|
| Notification **Service** | The campaign's image | `DyplinkNotificationService.populate(_:withContentHandler:)` |
| Notification **Content** | Carousels and countdowns | `DyplinkNotificationContent.makeView(for:)` |

Both files document exactly what the target and its `Info.plist` must say;
read them before creating the targets, because every way of getting it wrong
fails silently — the push simply arrives plain.

One thing is not an extension detail and has to be set on the campaign too:
**a campaign with no iOS category never matches a content extension**, so
the carousel never draws.

### Action buttons

A notification's buttons come from a `UNNotificationCategory` — iOS cannot
build them from a payload, it only draws the buttons of the category the
notification names. A campaign's buttons are authored in the dashboard, so
there is no category for them to name, and the notification **service**
extension above is what closes the gap: it registers a category carrying the
campaign's `dyplink_actions` while the push is in flight. Add that extension
and the buttons appear; the host app's own categories are left untouched.

Which category they go onto matters when the campaign also names an iOS
category for a content extension (a carousel or a countdown). A notification
has only one category identifier, and the content extension is matched on
that string — so the buttons are registered **onto the category the campaign
names**, rather than onto an identifier of the SDK's own, and both the
buttons and the carousel survive. Only that category's actions are replaced;
its intent identifiers, options and hidden-preview copy are kept. Note that
a category is app-wide: while a campaign's buttons are attached to an
identifier, any other notification naming it shows them too.

Two things outside the SDK decide whether they ever get the chance:

- `aps` must carry `mutable-content: 1`, or iOS never wakes the extension.
- A pressed button is reported as `metadata.actionId`, matching Android, but
  only if the tap is reported through `reportNotificationResponse(_:)` (or
  `reportNotificationClicked(userInfo:actionIdentifier:)`). The plain
  `reportNotificationClicked(userInfo:)` cannot tell a button from the
  notification body, because `userInfo` does not say.

## Related SDKs

- [Android SDK](https://github.com/sohelyadav/dyplink-android-sdk)
- [Flutter SDK](https://github.com/sohelyadav/dyplink-flutter-sdk)

## License

TBD
