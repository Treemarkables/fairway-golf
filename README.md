# Fairway

A golf GPS for iPhone and Apple Watch. Distance to the green from your wrist, one-tap
club logging, and per-club distance statistics built from the shots you actually hit.

Everything runs on the device. There is no account, no server, and no subscription.

---

## What it does

**Distance to the green.** Front, centre and back, measured along your line of play
rather than as raw distance to the nearest bit of outline — so a green lying side-on
still reports the depth you have to work with. Updates live from the watch's own GPS.

**Club logging.** Swipe up on the watch, spin the Digital Crown to your club, tap. The
shot is stamped at your position; where it finished is filled in by the next shot you
log, or by walking to the next hole. One tap, because anything longer doesn't get done
mid-round.

**Per-club statistics.** Average, median, spread and consistency for every club, plus a
gapping chart showing where you have no club for the shot. Outlier trimming means one
shank doesn't move the number you plan around.

**GPS tracking that survives a round.** The watch runs an `HKWorkoutSession` for the
duration — that's what stops watchOS suspending the app the moment your wrist drops, and
it's the difference between live distances for four and a half hours and distances that
freeze on the second tee.

---

## What you need

| | |
|---|---|
| **A Mac with Xcode 15+** | No way around it — watchOS apps can't be built anywhere else. Xcode is free. |
| **Apple Developer Program, USD $99/year** | Free provisioning expires every 7 days, and the HealthKit entitlement needs a paid account. |
| **iPhone (iOS 17+) and Apple Watch Series 3 or later (watchOS 10+)** | Series 3 is where built-in watch GPS starts. Older watches would relay the phone's location, meaning you carry the phone. |

Nothing else costs anything. Maps are MapKit, sync is WatchConnectivity, storage is
local JSON files, and course data is free (see below).

---

## Course data

To show a distance, the app needs to know where the green is. Two free routes, both
built in:

**Mark it yourself** *(recommended if you play a handful of courses)*
Create a blank course, then on each hole walk the edge of the green tapping **Add point**
four or five times. One round of setup and it's exact, offline, forever. A single dropped
pin also works — you just get one distance instead of front/centre/back.

**Import from OpenStreetMap**
Search by course name or list courses near you. Free, no API key, no account. OSM golf
data is mapped by volunteers, so a large club is often complete and a small one may have
nothing — whatever comes back is fully editable afterwards.

A commercial course API could be slotted in behind the same `Course` model if you ever
want nationwide coverage, but nothing in the app depends on one.

---

## An honest note on the numbers

Your club distances are **total** distance — where the ball came to rest, roll included.
They will read longer than launch-monitor carry numbers, and they move with firm ground,
wind and slope. That makes them right for picking a club on the course you play, and
wrong for comparing against a fitting session.

GPS accuracy is roughly 3–5 m. Distance-to-green is a difference of two positions so some
error cancels; expect around ±3–4 m. Fine for club selection, not for settling arguments.

Expect a round to cost roughly a third of the watch's battery.

---

## Building it

```bash
brew install xcodegen
xcodegen generate
open Fairway.xcodeproj
```

Set your development team in **Signing & Capabilities** for both app targets, then run.
Full instructions, including first-round setup on the course, are in
[`docs/BUILD.md`](docs/BUILD.md). The architecture is described in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

The `.xcodeproj` is generated from `project.yml` and deliberately not committed — it
merges badly and regenerating it is one command.

---

## Layout

```
Sources/
  Shared/      Models, geodesy, statistics, persistence, sync — compiled into both apps
  iOS/         iPhone app: map, course editing, OSM import, statistics, settings
  Watch/       Watch app: distance readout, club picker, workout-session GPS keep-alive
Tests/         Logic tests for the geometry, the statistics engine and the round engine
```
