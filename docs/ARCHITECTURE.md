# Architecture

Two SwiftUI apps over one shared core. No server, no database, no accounts.

```
Sources/Shared    →  compiled into BOTH the iOS and watchOS targets
Sources/iOS       →  iPhone app
Sources/Watch     →  Apple Watch app
```

The shared sources are compiled into each target directly rather than packaged as a
framework. For a codebase this size that avoids a lot of module and access-control
ceremony for no benefit.

---

## The shot model

This is the one idea the whole app rests on.

A `Shot` records **where it was struck from**, not where it landed. Its endpoint is
filled in later — by the next shot logged on that hole, or by walking to the next hole:

```
tap "7i" at position A   →  Shot(origin: A, end: nil)
tap "PW" at position B   →  Shot(origin: A, end: B)   ← the 7 iron measured itself
                            Shot(origin: B, end: nil)
walk to the next hole    →  Shot(origin: B, end: C)
```

That is why one tap per shot is enough to build club statistics, and why moving to the
next hole is a meaningful action rather than just navigation. `RoundEngine.closeOpenShot`
is where it happens.

The consequence, stated plainly in the UI: these are **total** distances, roll included,
not carry. GPS can only see where the ball came to rest.

---

## Layers

### `Shared/Utilities`

`Geodesy` — haversine distance, bearings, centroids, point-in-polygon, and
`greenDistances`, which is the interesting one. Front and back are computed by projecting
every vertex of the green onto the player→centre axis, so the numbers follow the line of
play rather than the compass. Pure Foundation, no CoreLocation, so it is directly
testable.

`Units` — everything is stored in metres and converted only for display.

### `Shared/Models`

`Course` → `Hole` → `Green` (a polygon; one point is a valid degenerate case, being a
pin dropped by hand), `Club`/`Bag`, and `Round` → `HoleScore` → `Shot`. All plain
`Codable` value types.

### `Shared/Services`

| | |
|---|---|
| `RoundEngine` | Owns the round in play. Takes plain `GeoPoint`s, so identical logic runs on both devices and is testable without a simulator. |
| `ClubStatsEngine` | Pure functions: rounds + bag → per-club statistics and gapping. All the filtering rules live here. |
| `LocationService` | CoreLocation wrapper. Rejects invalid fixes and stale cached ones, and grades signal quality. |
| `DataStore` | All persistence, via `FileStore` (atomic JSON writes). |
| `ConnectivityService` | `WCSession` both ways: live messages when reachable, queued `transferUserInfo` when not — which is most of a round. |

### Platform layers

`AppModel` (iOS) and `WatchModel` (watchOS) wire the same services together and own the
round lifecycle for their device. The watch additionally owns `WorkoutManager`.

---

## Why there's a workout session

`WorkoutManager` starts an `HKWorkoutSession` with activity type `.golf` when a round
begins. This is not a fitness feature.

watchOS suspends a foreground app within seconds of the wrist dropping. An active workout
session is what grants the app runtime and keeps CoreLocation delivering fixes for the
length of a round. Without it, distances freeze the moment you put your arm down and walk
to your ball — which is exactly when you need them.

It's also why the watch target needs the HealthKit entitlement, and therefore why a paid
developer account is a hard requirement. The distance screen shows a warning when the
session isn't running, because the failure mode is otherwise silent and confusing.

---

## Phone ↔ watch sync

The watch keeps its **own** copy of courses, bag and settings so it can play a round with
the phone in the car. Sync is deliberately coarse:

- **Phone → watch:** the whole library (courses, bag, settings), pushed on edit and on
  request. Small enough that whole-object replacement beats any merge strategy.
- **Either → other:** the whole round, on every mutation. Whichever device is driving is
  the authority; the other adopts what it receives.

Rounds merge by id with the newer copy winning (`DataStore.mergeRounds`).

---

## Course data

`OverpassImporter` (iOS only) queries the public Overpass API for OpenStreetMap golf
tagging: `leisure=golf_course` for the grounds, `golf=hole` for the tee-to-green centre
line (carrying `ref`, `par` and `handicap`), and `golf=green` for the putting surface.

Greens carry no hole number in OSM, so each is matched to the hole line whose far end it
sits closest to, within 150 m. Beyond that no match is recorded — a wrong green is worse
than a missing one.

Nothing depends on the importer. Every course is editable by hand, and marking greens
on foot is a first-class path rather than a fallback.

---

## Deliberate omissions

**Slope-adjusted distance** needs a terrain elevation dataset, which Apple does not
provide. It would mean a paid elevation API and a lot of trust in the data.

**Automatic shot detection** from the accelerometer is unreliable enough that a missed or
phantom shot silently corrupts the club statistics. A tap is more work and much more
trustworthy.

**Hazard and layup distances** would need far more course geometry than OSM reliably
carries.

**Cloud sync.** CloudKit would be free with the developer account and is the obvious
place to go next, but on-device storage keeps the app dependency-free and there is
nothing here worth losing sleep over.
