# Implementation Plan: Bottom Platform Selector Toolbar for Stop Details

**Feature:** Add a bottom toolbar to `StopDetailsView` with quick-select buttons for each physical platform at a combined stop. The toolbar replaces the tab bar when the stop details screen is shown. **Tapping the selected platform again deselects it (shows all platforms).**

**Status:** Draft  
**Priority:** Medium  
**Estimated Effort:** 2–3 days (1–2 days core, 1 day polish + edge cases)  
**Target Files:** `StopDetailsView.swift`, `MainView.swift`, new helpers

---

## 🎯 Overview

### Goal
Allow users to **quickly switch between physical platforms** (e.g., "Platform A", "Platform B") at a combined/meta-stop directly from the stop details screen, without navigating back. The selector appears as a **bottom toolbar** that replaces the app’s tab bar while the stop details view is active.

### User Flow
1. User opens a stop (e.g., *Stockholm Centralstation*) from Nearby or Search.
2. The stop details screen loads, showing departures from **all platforms** by default.
3. A **bottom toolbar** appears with buttons for each platform (e.g., `[Platform A] [Platform B]`).
4. User taps a platform button → the list filters to show **only departures from that platform**.
5. User taps the **same platform again** → deselects it, showing **all platforms** again.
6. The **tab bar is hidden** while this screen is active, giving the toolbar full bottom-edge real estate.

### Visual Mockup
```
┌─────────────────────────────────────┐
│  ← Stockholm Centralstation         ✓ │  ← Header (unchanged)
├─────────────────────────────────────┤
│  Updated 2 min ago                    │  ← Subtitle (unchanged)
├─────────────────────────────────────┤
│  • Line 17 → Mörby centrum (5 min)   │
│  • Line 19 → Fruängen (8 min)        │
│  • Line 3 → Sundbyberg (20 min)      │  ← Departures list
│  ...                                 │
├─────────────────────────────────────┤
│ [Plattform A] [Plattform B]           │  ← NEW: Bottom toolbar (replaces tab bar)
└─────────────────────────────────────┘
```

---

## 🔧 Technical Approach

### Core Decisions

| Decision | Rationale |
|----------|-----------|
| **Use SwiftUI’s `.toolbar(placement: .bottomBar)`** | Native placement at the bottom of the screen. |
| **Hide the global `TabView` when stop details is shown** | Ensures the toolbar truly replaces the tab bar (not stacks above it). |
| **Group departures by `stop.id`/`stop.name`** | Uses existing data from `DeparturesResponse.stops` and `CallAtLocation.stop`. |
| **Single-source state in `StopDetailsModel`** | Keeps platform list and selected platform in the model, not the view. |
| **Scrollable toolbar for >4 platforms** | Horizontal `ScrollView` inside the toolbar for stops with many platforms. |
| **Toggle behavior** | Tapping the selected platform again deselects it (no "All" button needed). |

### Data Flow
```
DeparturesResponse
├── stops: [TimetableStop]      // All physical platforms (e.g., [Platform A, Platform B])
└── departures: [CallAtLocation]
    └── stop: TimetableStop?   // Which platform this departure uses

StopDetailsModel
├── departures: [CallAtLocation]  // All departures (unchanged)
├── selectedPlatformId: String?    // NEW: Currently selected platform (nil = show all)
└── platforms: [Platform]          // NEW: Extracted from response.stops

StopDetailsView
├── Toolbar (bottomBar)           // NEW: Platform selector (toggle behavior)
└── DeparturesList                 // Filters by selectedPlatformId
```

---

## 📁 File Changes

| File | Change Type | Description |
|------|-------------|-------------|
| `StopDetails/StopDetailsView.swift` | Modify | Add bottom toolbar, filter departures by platform |
| `StopDetails/StopDetailsModel.swift` | Modify | Add `selectedPlatformId`, `platforms`, and `togglePlatform` |
| `MainView.swift` | Modify | Hide tab bar when stop details is shown |
| `StopDetails/PlatformSelectorToolbar.swift` | **New** | Reusable toolbar component |
| `StopDetails/Platform.swift` | **New** | Lightweight model for platform data |

---

## 🚀 Implementation Steps

### Phase 1: Model Layer (1–2 hours)
**Goal:** Extract platform data and track selection in `StopDetailsModel`.

#### 1.1 Create `Platform` Model
Create a new file `OnBoard/StopDetails/Platform.swift`:
```swift
/// A physical platform within a meta-stop, used for filtering departures.
struct Platform: Identifiable, Hashable, Equatable, Sendable {
    let id: String
    let name: String
    let lat: Double?
    let lon: Double?

    init(from stop: TimetableStop) {
        self.id = stop.id ?? UUID().uuidString
        self.name = stop.name ?? "Unknown"
        self.lat = stop.lat
        self.lon = stop.lon
    }
}
```

#### 1.2 Update `StopDetailsModel`
Add to `StopDetailsModel.swift`:
```swift
@MainActor
@Observable
final class StopDetailsModel {
    // ... existing properties ...

    /// All physical platforms at the current stop.
    private(set) var platforms: [Platform] = []

    /// The currently selected platform ID (nil = show all platforms).
    /// **Toggle behavior:** Setting to the same ID deselects it (sets to nil).
    var selectedPlatformId: String? = nil {
        didSet {
            // Reset to nil if the selected platform no longer exists
            if let id = selectedPlatformId, !platforms.contains(where: { $0.id == id }) {
                selectedPlatformId = nil
            }
        }
    }

    /// Departures filtered by the selected platform (or all if nil).
    var filteredDepartures: [CallAtLocation] {
        guard let selectedPlatformId else { return departures }
        return departures.filter { $0.stop?.id == selectedPlatformId }
    }

    /// Toggles the selected platform. If the same platform is passed, deselects it.
    func togglePlatform(_ platformId: String?) {
        if selectedPlatformId == platformId {
            selectedPlatformId = nil  // Deselect if tapping the same platform
        } else {
            selectedPlatformId = platformId
        }
    }

    /// Load departures and extract platforms from the response.
    func loadDepartures(network: some NetworkProtocol, areaId: String) async {
        isLoading = true
        defer { if !Task.isCancelled { isLoading = false } }

        do {
            let api = Trafiklab(network: network)
            let response = try await api.departures(at: areaId)
            try Task.checkCancellation()

            departures = response.departures
            platforms = response.stops?.map(Platform.init) ?? []
            // Reset selection if platforms changed
            if !platforms.contains(where: { $0.id == selectedPlatformId }) {
                selectedPlatformId = nil
            }
            lastUpdated = Date()
            failure = nil
        } catch is CancellationError {
            // Ignore
        } catch {
            departures = []
            platforms = []
            selectedPlatformId = nil
            failure = String(describing: error)
        }
    }
}
```

---

### Phase 2: Toolbar Component (2–3 hours)
**Goal:** Create a reusable, scrollable bottom toolbar for platform selection with toggle behavior.

#### 2.1 Create `PlatformSelectorToolbar`
New file `OnBoard/StopDetails/PlatformSelectorToolbar.swift`:
```swift
import SwiftUI

/// A horizontal scrollable toolbar for selecting between platforms at a combined stop.
/// - Displays a button for each platform.
/// - **Toggle behavior:** Tapping the selected platform deselects it (shows all).
/// - Automatically scrolls to center the selected platform.
/// - Uses the app’s design tokens (colors, typography).
struct PlatformSelectorToolbar: View {
    @Binding var selectedPlatformId: String?
    let platforms: [Platform]
    let onToggle: (String?) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Platform buttons
                    ForEach(platforms) { platform in
                        PlatformButton(
                            label: platform.name,
                            isSelected: selectedPlatformId == platform.id,
                            action: { onToggle(platform.id) }
                        )
                        .id(platform.id)
                    }
                }
                .padding(.horizontal, 8)
                .onChange(of: selectedPlatformId) { _ in
                    // Scroll to the selected button (or first button if deselected)
                    withAnimation {
                        let targetId = selectedPlatformId ?? platforms.first?.id
                        if let targetId {
                            proxy.scrollTo(targetId, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(height: 44) // Match tab bar height
        .background(Color.panel.shadow(.drop(color: .black.opacity(0.1), radius: 2)))
    }
}

/// A pill-style button for platform selection.
/// **Toggle behavior:** Tapping a selected button deselects it.
private struct PlatformButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? .white : .ink)
                
                if isSelected {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.8))
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected 
                    ? Color.magenta 
                    : Color.panel
            )
            .clipShape(Capsule())
            .shadow(
                color: isSelected ? .magenta.opacity(0.3) : .clear,
                radius: 2,
                y: 1
            )
        }
        .buttonStyle(.plain)
    }
}
```

---

### Phase 3: View Layer (2–3 hours)
**Goal:** Integrate the toolbar into `StopDetailsView` and filter the departures list.

#### 3.1 Update `StopDetailsView`
Modify `OnBoard/StopDetails/StopDetailsView.swift`:

```swift
struct StopDetailsView: View {
    // ... existing properties ...

    var body: some View {
        Group {
            if let failure = model.failure {
                UnavailableScreen(...)
            } else if model.filteredDepartures.isEmpty {
                // ... existing empty/loading states ...
            } else {
                DeparturesList(departures: model.filteredDepartures)
            }
        }
        // ... existing modifiers (navigationTitle, etc.) ...
        .toolbar {
            // Top bar items (unchanged)
            ToolbarItem(placement: .topBarTrailing) {
                FavoriteToggle(...)
            }

            // NEW: Bottom toolbar for platform selection
            ToolbarItem(placement: .bottomBar) {
                if model.platforms.count > 1 {
                    PlatformSelectorToolbar(
                        selectedPlatformId: $model.selectedPlatformId,
                        platforms: model.platforms,
                        onToggle: model.togglePlatform
                    )
                }
            }
        }
        .toolbarBackground(.hidden, for: .tabBar) // Hide the tab bar
        .task(id: refreshTrigger) {
            await model.loadDepartures(network: network, areaId: stopId)
            try? await Task.sleep(for: .seconds(60))
            refreshTrigger += 1
        }
    }
}

// Update DeparturesList to use filteredDepartures
private struct DeparturesList: View {
    let departures: [CallAtLocation] // Now receives pre-filtered list
    // ... rest unchanged ...
}
```

---

### Phase 4: Hide Tab Bar (1–2 hours)
**Goal:** Hide the global `TabView` when `StopDetailsView` is shown, so the bottom toolbar replaces it cleanly.

#### 4.1 Modify `MainView`
In `OnBoard/MainView.swift`, use `.toolbarBackground(.hidden, for: .tabBar)` in `StopDetailsView`:

```swift
// No changes needed to MainView if using .toolbarBackground(.hidden, for: .tabBar)
// The toolbar is hidden directly in StopDetailsView (see Phase 3.1)
```

> ✅ **Simpler approach:** The `.toolbarBackground(.hidden, for: .tabBar)` modifier in `StopDetailsView` hides the tab bar while that view is active. No changes to `MainView` are required.

---

### Phase 5: Polish & Edge Cases (1 day)

| Task | Description |
|------|-------------|
| **Empty platform names** | Fall back to `id` or "Platform {index}" if `name` is nil |
| **Single-platform stops** | Hide the toolbar if `platforms.count <= 1` |
| **Long platform names** | Truncate names in buttons (e.g., `.lineLimit(1)`) |
| **Accessibility** | Add `accessibilityLabel` to buttons (e.g., "Platform A, 3 departures") |
| **Haptic feedback** | Light tap on platform selection |
| **Animation** | Smooth transitions when filtering |
| **State persistence** | Restore selected platform when returning to the stop |

#### Example: Hide Toolbar for Single-Platform Stops
```swift
.toolbar {
    ToolbarItem(placement: .bottomBar) {
        if model.platforms.count > 1 {
            PlatformSelectorToolbar(...)
        }
    }
}
```

#### Example: Truncate Long Names
```swift
// In PlatformButton
Text(label)
    .lineLimit(1)
    .truncationMode(.tail)
    .frame(maxWidth: 120) // Prevent overly wide buttons
```

#### Example: Accessibility Label
```swift
// In PlatformButton
Button(action: action) {
    // ... existing content ...
}
.accessibilityLabel("Platform \(label), \(isSelected ? "selected" : "not selected")")
.accessibilityHint(isSelected ? "Tap to show all platforms" : "Tap to filter to this platform")
```

---

## 🧪 Testing Checklist

| Test Case | How to Test | Expected Result |
|-----------|-------------|-----------------|
| **Toolbar appears** | Open a stop with >1 platform | Bottom toolbar with platform buttons is visible |
| **Toolbar hidden for ≤1 platform** | Open a stop with ≤1 platform | No toolbar appears |
| **Select platform** | Tap a platform button | List filters to show only that platform’s departures |
| **Deselect platform** | Tap the selected platform again | List shows all departures |
| **Toolbar replaces tab bar** | Check bottom of screen | Tab bar is hidden; toolbar is at the bottom |
| **Horizontal scrolling** | Swipe left/right on toolbar | Toolbar scrolls to show all platforms |
| **Selection persists** | Filter to Platform A, navigate away, return | Platform A is still selected |
| **Empty state** | Select a platform with no departures | "No departures" message appears |
| **Orientation change** | Rotate device | Toolbar adapts to new width |
| **Accessibility** | VoiceOver on toolbar | Announces selected platform and count |

---

## 📏 Success Metrics

| Metric | Target |
|--------|--------|
| **Time to select a platform** | <1 second (vs. ~3–5 seconds to navigate back and reopen) |
| **User satisfaction** | 80% of users find platform switching "easy" or "very easy" |
| **Code complexity** | <200 lines of new code |
| **Performance impact** | No additional API calls; filtering is O(n) client-side |

---

## 🚨 Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **Tab bar hiding doesn’t work** | Medium | High | Test early; fall back to `.toolbarBackground(.hidden)` |
| **Toolbar too wide for small screens** | Low | Medium | Use `ScrollView` and truncate names |
| **Platform names are unclear** | Medium | Medium | Add tooltips or icons; use `id` as fallback |
| **State management bugs** | Medium | High | Write unit tests for `StopDetailsModel` |

---

## 📚 Dependencies

| Dependency | Status |
|------------|--------|
| SwiftUI | ✅ Available |
| `TimetableStop` model | ✅ Exists in `TrafiklabAPI.swift` |
| `CallAtLocation` model | ✅ Exists in `TrafiklabAPI.swift` |
| Design tokens (colors, fonts) | ✅ Exists in `Assets.xcassets` |

---

## 📅 Timeline (Suggested)

| Day | Task | Owner |
|-----|------|-------|
| 1 | Model layer (Phase 1) | Backend/Logic |
| 1 | Toolbar component (Phase 2) | UI |
| 2 | View integration (Phase 3) | UI |
| 2 | Tab bar hiding (Phase 4) | UI/Logic |
| 3 | Polish & edge cases (Phase 5) | All |
| 3 | Testing & QA | All |

---

## ✅ Acceptance Criteria

- [ ] Bottom toolbar appears when viewing a stop with >1 platform
- [ ] Toolbar contains a button for each platform
- [ ] Tapping a platform button filters departures to that platform only
- [ ] Tapping the selected platform again deselects it (shows all departures)
- [ ] Tab bar is hidden while the toolbar is shown
- [ ] Toolbar scrolls horizontally if needed
- [ ] Works in both portrait and landscape
- [ ] Localized to Swedish, Finnish, English
- [ ] Accessible via VoiceOver
- [ ] No regressions in existing functionality

---

## 📎 Appendices

### A. Example API Response (Timetables)
```json
{
  "timestamp": "2025-01-01T12:00:00",
  "query": { "queryTime": "2025-01-01T12:00:00", "query": "740000001" },
  "stops": [
    { "id": "740000001-1", "name": "Plattform A", "lat": 59.330, "lon": 18.060 },
    { "id": "740000001-2", "name": "Plattform B", "lat": 59.330, "lon": 18.070 }
  ],
  "departures": [
    {
      "scheduled": "2025-01-01T12:05:00",
      "route": { "designation": "17", "direction": "Mörby centrum" },
      "stop": { "id": "740000001-1", "name": "Plattform A" }
    },
    {
      "scheduled": "2025-01-01T12:10:00",
      "route": { "designation": "17", "direction": "Ropsten" },
      "stop": { "id": "740000001-2", "name": "Plattform B" }
    }
  ]
}
```

### B. Localization Strings
> **Note:** No "All" button is needed. The toggle behavior (tapping selected platform again) replaces it.

If you need to add a hint or empty state message:
```xml
<!-- English -->
<key>platformFilterHint</key>
<string>Tap a platform to filter</string>
<key>platformEmpty</key>
<string>No departures from this platform</string>

<!-- Swedish -->
<key>platformFilterHint</key>
<string>Tryck på en plattform för att filtrera</string>
<key>platformEmpty</key>
<string>Inga avgångar från denna plattform</string>

<!-- Finnish -->
<key>platformFilterHint</key>
<string>Napauta alustaa suodattaaksesi</string>
<key>platformEmpty</key>
<string>Ei lähtöjä tältä alustalta</string>
```

### C. Design Tokens Used
| Token | Usage |
|-------|-------|
| `Color.magenta` | Selected platform button background |
| `Color.panel` | Unselected platform button background |
| `Color.ink` | Unselected button text |
| `.font(.subheadline.weight(.medium))` | Button text style |
| `xmark.circle.fill` | SF Symbol for deselect indicator on selected button |

---

## 🏁 Next Steps

1. **Review this plan** and confirm the approach (especially tab bar hiding strategy).
2. **Create a Git branch**: `git checkout -b feature/platform-selector-toolbar`
3. **Implement Phase 1** (model layer) and test with mock data.
4. **Implement Phase 2** (toolbar component) and verify UI.
5. **Integrate and test** end-to-end.
