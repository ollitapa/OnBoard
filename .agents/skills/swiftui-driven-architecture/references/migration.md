# Migrating an existing app

Apply in this order, one seam at a time. Each phase leaves the app building and
running; nothing here requires a big-bang rewrite.

## Phase 0 — Fit-check and decide the injection level

Inventory the app's dependencies (network, storage, location, analytics).

Decide **what** gets the protocol:

- If requests need cross-cutting concerns (auth, retry, caching, per-request
  analytics), make the **API client** the protocol injected through the
  environment (`@Entry var api: any MyAPI`), with the transport a private detail
  of its live implementation.
- Otherwise inject the **transport** (`@Entry var network: NetworkProtocol`) and
  let each model build its API client from it.

Do not retrofit this later — deciding it first avoids rework.

Also decide, and write down, the **container-failure policy**: `fatalError` when
the app is useless without persistence, or catch and rebuild the container when
the store can be recreated/migrated.

## Phase 1 — Extract one protocol seam

Pick the worst dependency (usually networking). Define a minimal protocol
mirroring only the calls the app actually makes, with one live implementation
forwarding to the existing code. No globals.

**Rule of need**: if you can't name a second implementation you'd actually want
(mock, preview stub, cache-decorated), skip the protocol for now.

## Phase 2 — Publish with `@Entry`, default to live

```swift
extension EnvironmentValues {
    @Entry var network: NetworkProtocol = LiveNetwork()
}
```

Existing call sites keep working while you migrate them to
`@Environment(\.network)` gradually, and views render with zero wiring so
previews don't break mid-migration.

## Phase 3 — Migrate one screen to a screen model

Choose a single view as the reference template. Create the
`@MainActor @Observable` model with an empty `init()`, `failure` / `isLoading` /
rows state, and a `loadX(network:...)` method that surfaces errors as `failure`.
Trigger it from `.task` / `.task(id:)` with the cancellation-guarded `defer`.

This screen becomes the exemplar every other screen is ported against. See
[assets/screen-model.md](../assets/screen-model.md) and
[assets/screen-view.md](../assets/screen-view.md).

## Phase 4 — Storage seam

Move `ModelContainer` construction to the app entry point
(`.modelContainer(container)`), define one aggregate root per feature, pass
`ModelContext` into model methods as a parameter, create the aggregate on demand
on first write, and keep display invariants (sorting) in the model.

## Phase 5 — Test infrastructure

Build a feature-specific mock service configured by wire-shape JSON fixtures
(validated at creation, time-relative markers resolved once), plus a bare
`MockNetwork` for request-shape and invalid-input assertions. Migrate tests
screen by screen using the reference screen's test as the pattern. See
[references/mocks-and-tests.md](./mocks-and-tests.md).

## Phase 6 — Harness and composition root

Move remaining dependency construction into the app entry point's `make*()`
factories. Add `--mock-*` string launch arguments checked inline there (UI tests
pass the literal strings, so these are deliberately not shared constants). Wire
previews with `@Previewable @State`.

At the end of this phase previews, unit tests, and UI tests all run the same
code path production uses.

## Phase 7 — Replicate per screen

Add each remaining screen as a feature folder (model + view + presentation
extensions). Extract shared UI into `DesignSystem/` only once a pattern appears
on **two or more** screens.
