# OnBoard

A SwiftUI app for following buses and other public transport in Sweden, built on
Trafiklab's Realtime APIs and ResRobot.

OnBoard is also an **example of an iOS architecture driven by SwiftUI**: the app
uses only Apple frameworks — SwiftUI, SwiftData, Observation, CoreLocation, and
Foundation — and has **no external dependencies**. Every dependency (network,
storage, location) is a small protocol injected through the SwiftUI
environment, so the same views run in previews, unit tests, and UI tests.

## Features

- **Nearby** — finds stops around your location (ResRobot Nearby Stops) and
  shows upcoming departures for a chosen stop (Timetables).
- **Favorites** — saves stops persistently with SwiftData.
- **Search** — searches stops by name (Stop Lookup) and follows a vehicle's
  live trip between stops (Trips).

## Architecture

The app is organized into feature folders, each owning one screen:

```
OnBoard/
├── MyApp.swift            # App entry point; builds and injects dependencies
├── MainView.swift         # Tab layout; owns and publishes shared models
├── Api/                   # Trafiklab client, secrets, canned service mocks
├── Network/               # NetworkProtocol, LiveNetwork, MockNetwork
├── Location/              # Location authorization and permission UI
├── Nearby/                # NearbyModel + NearbyView
├── Favorites/             # FavoritesModel + FavoritesView
├── Search/                # SearchModel + SearchView
├── StopDetails/          # StopDetailsModel + StopDetailsView
└── RouteDetails/         # RouteDetailsModel + RouteDetailsView
```

The core patterns:

- **Observable models**: each screen's state lives in a `@MainActor
  @Observable final class` model that owns one load lifecycle and surfaces
  errors as a `failure: String?`. A model's `init` takes no dependencies;
  load/mutate methods receive them (`loadStops(network:latitude:longitude:)`),
  so tests inject mocks directly.
- **Environment injection**: `NetworkProtocol` is published with
  `.environment(\.network, network)` and models with `.environment(model)`;
  views read them with `@Environment(\.network)` and `@Environment(Model.self)`.
  The environment defaults to `LiveNetwork`, so views render in previews
  without wiring.
- **Protocol-oriented dependencies**: `LiveNetwork` (URLSession) is the
  production transport; `MockNetwork` and `MockTrafiklabService` provide
  handler registration, request tracking, and canned responses for tests
  and previews.
- **SwiftData persistence**: the app entry point builds the `ModelContainer`
  and injects it with `.modelContainer(container)`; views hand the
  environment's `ModelContext` to their model's load/mutate methods. Each
  feature persists one aggregate root (e.g. `StoredFavorites` with a cascading
  relationship to `[Favorite]`).
- **Presentation on the domain type**: display logic (transport mode icons,
  labels, parsed dates) lives in computed properties on the value types via
  `Type+Feature.swift` extensions next to their consumers, so it is shared
  instead of duplicated per screen.

UI tests substitute mocks through launch arguments (`--mock-network`,
`--skip-location-permission`, `--mock-storage`) checked in `MyApp`, which keeps
the entry point self-contained.

## API keys

The app reads its Trafiklab API keys from a `Secrets.env` file bundled with the
build. The file is git-ignored, so it is not part of the repository:

1. Register at [developer.trafiklab.se](https://developer.trafiklab.se) and
   create one key per product: "Trafiklab Realtime APIs" (Stop Lookup,
   Timetables, Trips) and "ResRobot v2.1" (Nearby Stops).
2. Create `OnBoard/Secrets.env` with your keys:
   ```
   TRAFIKLAB_REALTIME_KEY=your-realtime-key
   TRAFIKLAB_RESROBOT_KEY=your-resrobot-key
   ```
3. Build and run. Xcode's file-system-synchronized target bundles the file into
   the app automatically.

Without the file every screen shows its load failure instead of silently
sending empty keys.
