# OnBoard

A SwiftUI app for following buses and other public transport in Sweden, built on
Trafiklab's Realtime APIs and ResRobot.

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
