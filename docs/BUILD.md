# Building and running Fairway

## Prerequisites

- **macOS with Xcode 15 or later.** There is no way to build a watchOS app without a Mac.
- **An Apple Developer Program membership (USD $99/year).** Strictly speaking the app
  will build and run on the simulator without one, but you cannot keep it on your own
  wrist: free provisioning profiles expire after 7 days, and the HealthKit entitlement
  the watch app needs is not available to free accounts.
- **XcodeGen** — `brew install xcodegen`.

## Generate the project

```bash
xcodegen generate
open Fairway.xcodeproj
```

`Fairway.xcodeproj` is a build artefact generated from `project.yml`, and is git-ignored
on purpose. Re-run `xcodegen generate` after adding or moving source files. Editing the
project inside Xcode works, but changes to target settings will be lost on the next
generate — put them in `project.yml` instead.

## Signing

Both app targets need a team before they will run on hardware:

1. Select the **Fairway** target → *Signing & Capabilities* → pick your team.
2. Do the same for **FairwayWatch**.
3. Confirm **HealthKit** appears under the watch target's capabilities. It comes from
   `Sources/Watch/Resources/FairwayWatch.entitlements`; if Xcode has dropped it, add the
   capability back with the **+** button.

Alternatively set `DEVELOPMENT_TEAM` in `project.yml` once and regenerate.

Bundle identifiers are `nz.fairway.golf` and `nz.fairway.golf.watchkitapp`. If you change
the first, the second must stay equal to it plus `.watchkitapp` — that pairing is what
makes the watch app install alongside the phone app. Change both in `project.yml`, plus
`WKCompanionAppBundleIdentifier` in the watch target's `info:` block.

## Running

Pick the **Fairway** scheme and a physical iPhone. The watch app installs onto the paired
watch automatically, though the first install can take a couple of minutes — watch it in
*Window → Devices and Simulators*.

The simulator is fine for the UI, but it cannot produce a meaningful GPS fix and it
cannot run a workout session, so anything to do with distances has to be tested outdoors.

## Tests

```bash
xcodebuild test -scheme Fairway -destination 'platform=iOS Simulator,name=iPhone 15'
```

`FairwayTests` compiles the shared sources directly rather than testing through the app
bundle, so the geometry, statistics and round logic run without a host application or a
device.

## First round on the course

1. On the phone, add a course — **Courses → + → Import from OpenStreetMap**, or **Blank
   course** if your club isn't mapped.
2. If any hole shows no green, open it and mark one. Standing on the green, tap **Add
   point** four or five times as you walk the edge. Front and back numbers need the
   outline; a single pin gives one distance only.
3. **Settings → Send courses and bag to watch**, and check the watch reports the course.
4. On the watch, start the round. Grant location and health permissions when asked —
   the health one is what keeps GPS alive, so declining it will make distances freeze
   whenever your wrist drops.
5. Play. Swipe up for the club picker, tap a club as you hit, swipe down for the card.

## Troubleshooting

**Distances freeze between holes.** The workout session isn't running — the distance
screen shows "Background tracking off" when this happens. Check HealthKit permission on
the watch under *Settings → Privacy & Security → Health*.

**The watch has no courses.** Open the phone app and use **Send courses and bag to
watch**, or on the watch tap **Ask iPhone again**. The watch keeps its own copy so it can
play without the phone, which means it needs an explicit sync after you edit a course.

**OpenStreetMap import returns nothing.** Coverage is volunteer-mapped and genuinely
patchy. Try a shorter search term, or the **Near me** button while at the course. If the
club simply isn't mapped, mark the greens by hand — it's one round of work.

**Overpass returns an error about rate limits.** The public Overpass endpoint throttles
heavy use. Wait a minute and try again.

**No distances even with a green marked.** Check the GPS dot on the watch's distance
screen. Red means no usable fix — a cold start outdoors can take 30–60 seconds.
