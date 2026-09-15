# Trafiklab API — Implementation Guide

Reference for wiring the app's screens to real data. Covers which endpoint to call for each screen, required parameters, authentication, response models, and known limitations. This is a calls-and-models reference, not code — implementation is left to whichever platform/language the app ends up in (Swift, Kotlin, etc.).

---

## 1. Two APIs, two different jobs

The app needs two separate Trafiklab-hosted products, because **Trafiklab's own Stop Lookup does not support location/coordinate search** — it only searches by name or lists everything. Distance-based "nearby stops" requires ResRobot instead.

| Need | API | Why |
|---|---|---|
| **Nearby** screen — stops ranked by distance from the user | **ResRobot v2.1 — Nearby Stops** | Only endpoint here that accepts lat/lon and returns distance |
| **Search** screen — search by stop/line name | **Trafiklab Stop Lookup** | Purpose-built name search, richer data (transport modes, child stops) than ResRobot's equivalent |
| **Stop board** screen — departures at a stop | **Trafiklab Timetables** | Realtime departures/arrivals with delay, platform, cancellation |
| **Live trip** screen — tracking one departure stop-by-stop | **Trafiklab Trips** (beta) | Looks up a specific trip by `trip_id` + `start_date` |

Both products are hosted by Trafiklab but are **different generations of API** with different base URLs, different auth parameter names, and different response shapes. Don't assume a stop ID or key from one works on the other without checking (see §4).

---

## 2. Authentication

**There is no auth header.** Both APIs authenticate via a **query string parameter**, not an HTTP header:

| API | Query param | Example |
|---|---|---|
| Trafiklab Realtime APIs (Stop Lookup, Timetables, Trips) | `key` | `...?key=API_KEY` |
| ResRobot v2.1 (Nearby Stops) | `accessId` | `...?accessId=API_KEY` |

- Keys are issued per API product from `developer.trafiklab.se` — you'll register separately for the Realtime APIs product and the ResRobot v2.1 product, and get a distinct key for each.
- No `Authorization`, `X-API-Key`, or bearer token header exists for either API. If a request is failing on auth, check the query string first.
- **Because the key travels in a plain query parameter, it is trivially visible** in a mobile app's network traffic or decompiled binary. Trafiklab's own guidance ("Keeping API keys secret") recommends routing requests through your own backend rather than calling these APIs directly from the client, if you want to prevent key theft/abuse. For a small hobby-scale project this may be an acceptable risk; for anything public-facing, proxy it.

No API versioning header either — version is baked into the base URL (`/v1/`, `/v2.1/`).

---

## 3. Base URLs

```
Trafiklab Realtime APIs:  https://realtime-api.trafiklab.se/v1/
ResRobot v2.1:            https://api.resrobot.se/v2.1/
```

---

## 4. Stop IDs — the one thing that will bite you

Both APIs group stops into **rikshållplatser** (national stop groups) or **meta-stops** (e.g. "Stockholm" combining several nearby stops/modes). A physical stop can have several IDs depending on which system you're looking at:

- `stop_id` in GTFS Sverige 2
- `area_id` in GTFS Sweden 3
- the ID returned by ResRobot APIs (`extId`)

**Timetables and Trips take the *group* ID (rikshållplats/meta-stop), never the ID of an individual child stop underneath it.** Stop Lookup and ResRobot Nearby Stops both return group-level IDs already, so as long as you pass through what those two return, you're fine — the danger is only if you dig into a `stops[]` child array and use *that* id by mistake.

Practically: **ResRobot Nearby Stops' `extId` is safe to feed directly into Trafiklab Timetables' `area id` path parameter** — Trafiklab's docs confirm the Timetables area id "matches ... the ids used in the Resrobot APIs."

---

## 5. Endpoint reference

### 5.1 Trafiklab Stop Lookup — powers the Search screen

Two endpoints, identical response shape:

```
GET https://realtime-api.trafiklab.se/v1/stops/name/{searchValue}?key={key}
GET https://realtime-api.trafiklab.se/v1/stops/list?key={key}
```

| Param | Location | Required | Notes |
|---|---|---|---|
| `searchValue` | path | yes (first endpoint) | ≥1 character, matched against stop group name |
| `key` | query | yes | |

Results are sorted by average daily departures (busiest first) — good default ordering for a search dropdown, no extra client-side sort needed for relevance.

**Response model — `NationalStopGroupResponse`:**

```
timestamp: string
query: { queryTime: string, query: string | null }
stop_groups: StopGroup[]
```

**`StopGroup`:**

| Field | Type | Notes |
|---|---|---|
| id | string | pass this to Timetables as `area id` |
| name | string | |
| area_type | string | `"META_STOP"` or `"RIKSHALLPLATS"` |
| average_daily_stop_times | float | traffic volume, useful for ranking |
| transport_modes | string[] | `BUS`, `TRAIN`, `TRAM`, `METRO` — empty array if no current traffic |
| stops | Stop[] | child stops — **do not** use their `id` for Timetables/Trips calls |

**`Stop`** (child object, also reused elsewhere): `id`, `name`, `lat`, `lon`.

Data updates at most once a day; treat it as effectively static and safe to cache aggressively client-side.

---

### 5.2 ResRobot Nearby Stops — powers the Nearby screen

```
GET https://api.resrobot.se/v2.1/location.nearbystops?originCoordLat={lat}&originCoordLong={lon}&accessId={key}&format=json
```

| Param | Required | Default / Max | Notes |
|---|---|---|---|
| accessId | yes | — | API key |
| originCoordLat | yes | — | WGS84 decimal degrees |
| originCoordLong | yes | — | WGS84 decimal degrees |
| maxNo | no | 10 / max 1000 | result count |
| r | no | 1000 / max 10000 | search radius, meters |
| format | no | — | `json` or `xml` |
| lang | no | `sv` | affects mode names + error text |

**Response model:**

```
StopLocation: StopLocation[]
```

**`StopLocation`:**

| Field | Type | Notes |
|---|---|---|
| id | string | internal — do not use |
| extId | string | **use this** for Timetables `area id` and as the stop identifier elsewhere |
| name | string | all-caps names (e.g. "GÖTEBORG") indicate a virtual/grouping station |
| lat / lon | string | WGS84 |
| dist | integer | distance from the query point, **meters** — this is your "180 m" label directly, no haversine math needed client-side |
| weight | integer | 0–32767, traffic volume |
| products | integer | bitmask of transport products at the stop |

**Privacy note:** Trafiklab explicitly flags that the coordinates sent here are personal data and that users should be informed/asked before their position is sent to a third party — directly relevant to the permission screens already in the storyboard.

---

### 5.3 Trafiklab Timetables — powers the Stop board screen

```
GET https://realtime-api.trafiklab.se/v1/departures/{area id}?key={key}
GET https://realtime-api.trafiklab.se/v1/departures/{area id}/{time}?key={key}
GET https://realtime-api.trafiklab.se/v1/arrivals/{area id}?key={key}
GET https://realtime-api.trafiklab.se/v1/arrivals/{area id}/{time}?key={key}
```

| Param | Location | Required | Notes |
|---|---|---|---|
| area id | path | yes | rikshållplats/meta-stop id (see §4) |
| time | path | no | `YYYY-MM-DDTHH:mm`, no seconds. Omit for "now" |
| key | query | yes | |

- **Window is fixed at 60 minutes** — there's no parameter to request more, so pagination/"load more" has to be done by re-querying with a later `time`, and any trimming to "just the next 3" (as in the storyboard) happens client-side.
- **Server-side cache is 60 seconds** — polling more often than once a minute for the same stop+time will not return fresher data. This sets a natural floor for a polling/refresh interval.

**Response model — `DeparturesResponse` / `ArrivalsResponse`:**

```
timestamp: string
query: { queryTime: string, query: string }
stops: Stop[]              // all physical stops covered by this area id
departures | arrivals: CallAtLocation[]
```

**`Stop`** (this endpoint's variant): `id`, `name`, `lat`, `lon`, `transport_modes: string[]`, `alerts: Alert[]`.

**`CallAtLocation`** — one departure/arrival row, i.e. the model for each `dep-row` in the app:

| Field | Type | Maps to storyboard |
|---|---|---|
| scheduled | string (`YYYY-MM-DDTHH:mm:ss`) | scheduled time |
| realtime | string | the "2 min" countdown — falls back to `scheduled` if no live data |
| delay | integer (seconds, can be negative) | drives the delay pill — `0` if no realtime data |
| canceled | boolean | drives the cancelled pill/strikethrough |
| is_realtime | boolean | whether `realtime`/`delay`/`realtime_platform` are live or just copied from scheduled — **check this before styling a row as "on time," or a row with no live data will look falsely confirmed on-time** |
| route.designation | string | the line-badge number (e.g. "3", "T14") |
| route.transport_mode | string | `BUS` / `METRO` / `TRAM` / `TRAIN` / `TAXI` / `BOAT` — drives which mode icon renders in the badge |
| route.direction | string | destination text — note this can change mid-route ("A via B" → "A" after passing B) |
| route.name | string | only set for lines known by name rather than number (e.g. Saltsjöbanan) |
| agency.name / agency.operator | string | operator branding, if ever surfaced |
| trip.trip_id + trip.start_date | string | **needed to open the Live Trip screen** — pass both to Trafiklab Trips |
| stop | Stop | which physical stop within the area this call happens at (an area can bundle multiple platforms/modes) |
| scheduled_platform / realtime_platform | Platform \| null | `{id, designation}` — the "Läge C" text |
| alerts | Alert[] | service messages for this specific departure |

---

### 5.4 Trafiklab Trips (beta) — powers the Live Trip screen

```
GET https://realtime-api.trafiklab.se/v1/trips/{trip_id}/{start_date}?key={key}
```

- `trip_id` and `start_date` come straight off a `CallAtLocation.trip` object from the Timetables response — the user reaches this screen by tapping a departure row, so both values are already in hand from the previous call.
- Marked **beta** — treat the response shape as more likely to change than Stop Lookup/Timetables, and don't be surprised by field additions without notice even beyond the usual policy.

⚠️ **Important gap:** none of the Trafiklab realtime endpoints return a live GPS position for the vehicle. What Trips/Timetables give you is a **stop-by-stop schedule with delay/ETA per stop** — which is enough to build the "passed / current / upcoming" stop list in the storyboard, but **not** enough to animate a bus icon moving continuously along the route line between stops. That would require a separate GTFS-Realtime `VehiclePositions` feed (GTFS Sweden 3 Realtime / GTFS Regional Realtime), which is a protobuf-based feed, not part of these three JSON APIs. Worth deciding early whether the live-trip screen's moving marker is "snaps to next stop" (achievable now) or "smoothly animates between stops" (needs the extra feed).

---

## 6. Data format

- **Trafiklab Realtime APIs (Stop Lookup, Timetables, Trips): JSON only.** No `format` parameter, no XML option.
- **ResRobot v2.1: JSON or XML**, selected via the `format` query parameter. Use `format=json` consistently for this app.

No `Accept` or `Content-Type` request headers are needed — these are all unauthenticated-transport GET endpoints returning JSON by default/by parameter, not content-negotiated.

---

## 7. Errors, rate limits, and caching behavior

- Exceeding your quota returns an HTTP error response for too many requests (standard 429-style behavior); back off and retry with delay rather than hammering.
- **Free/hobby tier ("bronze") is capped around 10,000 requests/month**, intended for small private projects (~5 people). A production app for real users will need a higher tier — talk to Trafiklab before launch.
- Trafiklab explicitly suggests **varying polling frequency by time of day** rather than polling on a fixed short interval around the clock — e.g. every 1–2 minutes during commute hours, every 5–10 minutes late at night. Given Timetables' own 60-second server cache, polling faster than 60s never helps anyway.
- Recommended pattern: fetch delay/scheduled/realtime timestamps on a moderate interval (not every few seconds), then **compute and re-render the "X min" countdown text client-side every ~10 seconds** from the already-fetched timestamp, rather than re-fetching to update the countdown. This keeps the UI feeling live without burning quota.
- New fields can be added to any response without notice — parsing should ignore unrecognized fields rather than fail on them. Both APIs are marked "stable," meaning breaking changes (renamed/removed fields, new required params) come with advance notice (3–6 months), but additive changes don't.

---

## 8. Attribution

Trafiklab Realtime APIs are licensed **CC-BY 4.0**: a small "data from Trafiklab.se" credit is required somewhere in the UI (footer, about screen, etc.), along with a link to the license if being strict about it. ResRobot data carries its own license terms — confirm before combining attribution text for both into one line.
