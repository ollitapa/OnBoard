# Mocks and tests

## The doctrine

**A mock's job is fidelity of the bytes, not of the data model.**

An app whose fixtures drifted from the real wire shape passed every test while
every live response failed to decode. Everything below exists to prevent that.

## Fixtures are wire-shape JSON

- A fixture is a multiline JSON string in the endpoint's **wire shape**, keyed by
  what the request looks up (`departuresByAreaId`, `stopGroupsByName`,
  `tripsByKey`). Paste a captured response in verbatim.
- **Never configure a mock with hand-built API model values.** That makes the
  mock a second, drifting implementation of the endpoint.
- Key dictionaries by the thing you look up, even when a value repeats inside the
  JSON (`stopGroupsByName` repeats the name in key and value). A dictionary
  lookup replaces substring matching or range scanning inside JSON strings,
  which is fragile.

## The serving path never decodes

Pick a string by key, join the chosen strings into the response envelope, serve
`Data(body.utf8)`. No decode, no re-encode.

The model under test then runs its **real production `Codable` decode** on
exactly the fixture bytes, so a broken fixture surfaces as a model failure —
which is where you want it.

A test that needs to read expected values back can decode the stored fixture
with `JSONDecoder` instead of duplicating literals.

## Resolve moving parts once, at creation

- Relative timestamp markers (`"now"`, `"now+2"`, `"now-10"`, in minutes) become
  absolute timestamps when the service is built, so previews and UI tests always
  show fresh times with no per-request recomputation.
- Validate every fixture loudly at that same moment — a malformed one traps with
  the fixture named, rather than silently serving an empty response later.

## Ordering and request parsing

- Dictionary fixtures are unordered: give the served result an explicit,
  documented order, and document where it deviates from the real API (e.g.
  name-sorted instead of the API's busiest-first).
- Parse request paths with small regex captures
  (`url.path.firstMatch(of: #/departures/([^/]+)/#)`) instead of
  split-and-index arithmetic. Prefer `String.replacing(_:with:)` with a
  capture-group regex over a manual scan-and-rebuild loop.

## When to use the bare `MockNetwork` instead

Keep a bare `MockNetwork` — handler registration plus `TestableRequest`
recording, mutex-guarded for actor-independence — for exactly two jobs:

1. Asserting on a specific **request shape**.
2. Feeding **invalid JSON** to exercise decode-failure paths.

A preview wired to a handler-less `MockNetwork` on a screen with a `.task` load
renders `NoResponseConfigured`, not data. Use the fixture-based mock service for
previews that need content.

## Preview/test helpers live in the app target

`mockNetwork()`, `previewLocationAuthorization()`, `mockModelContainer()`, and
`emptyModelContainer()` are top-level functions in the **app** target, not the
test target, because previews and the UI-test launch-argument harness both call
them. Add a new helper alongside its dependency, plus a matching `--mock-*`
branch in the app entry point if a UI test needs it.

## Test conventions

- Swift Testing (`@Test`, `#expect`). Model tests are `@MainActor` and construct
  `Model()` directly, injecting the mock through the load method — no container,
  no factory, no DI framework.
- Prefer `== []` over `isEmpty` in expectations; the framework then shows actual
  vs expected.
- Rely on **synthesized** `Equatable`/`Hashable` on value types. Never write a
  custom `==` keyed on `id` alone (that makes equality inconsistent with hashing)
  — model the collection as `Dictionary<id, value>` or find entries with a
  predicate (`favorites.firstIndex { $0.id == stopId }`).
- `@Model` classes are the exception: the macro synthesizes `==` as **object
  identity**, not memberwise. Compare a value snapshot — a small `Equatable`
  struct, **not** a tuple (Swift tuples don't conform to `Equatable`, so
  `[Tuple] == [Tuple]` won't compile).
- Return the `ModelContainer` (not a captured `ModelContext`) from test helpers,
  and pass `container.mainContext` at each call site.

## Shape of a model test

```swift
import Testing
@testable import MyApp

@MainActor
struct MyModelTests {
    @Test func loadsRows() async throws {
        let service = MockMyService(rowsById: ["42": #"{"rows":[...]}"#])
        let model = MyModel()

        await model.loadRows(network: service, id: "42")

        #expect(model.failure == nil)
        #expect(model.rows == [Row(id: "1", name: "…")])
    }
}
```
