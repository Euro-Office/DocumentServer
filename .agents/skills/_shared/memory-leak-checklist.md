# Memory-leak sweep (web-apps / front-end focus)

The editors are long-lived SPAs with canvas and real-time collaboration: leaks accumulate as
documents, panels, and views are opened/closed. Sweep the diff with this checklist. Anchors:
`web-apps/apps/*`, `sdkjs/common/` (e.g. `sdkjs/common/CollaborativeEditingBase.js`).

## Checks (everything created must be released in `destroy`/teardown)

- [ ] **Event listeners**: every `addEventListener` / `on(...)` / jQuery `.on(...)` has its matching
      `removeEventListener` / `off(...)` on teardown. Watch `window`, `document`, `resize`, `scroll`,
      `keydown`.
- [ ] **Timers**: every `setInterval`/`setTimeout`/`requestAnimationFrame` is cleared
      (`clearInterval`/`clearTimeout`/`cancelAnimationFrame`).
- [ ] **Canvas / contexts**: 2D/WebGL contexts and large buffers released; no `ImageData`/canvas
      retained out of use; render caches bounded or cleared.
- [ ] **Collaborative handlers**: subscriptions to co-editing events / websockets / engine callbacks
      (`Asc`/sdkjs) unregistered when the document closes or the view changes.
- [ ] **DOM references**: detached nodes not retained by closures; refs set to `null` on destroy.
- [ ] **Observers / pub-sub**: `MutationObserver`/`ResizeObserver`/`IntersectionObserver` disconnected;
      internal event buses have their `unsubscribe`.
- [ ] **Cycles**: no object↔DOM cycles that prevent GC; no globals growing without bound.

## How to verify

- Open/close the same document N times and watch the heap (DevTools → Memory → snapshots) with no
  monotonic growth of detached nodes / listeners.
- Check that every component with `init`/`create` has a **symmetric** `destroy`/`dispose`.
