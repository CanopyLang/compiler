# Plan 27: Mobile Deployment

## Priority: LOW -- Tier 4
## Status: ~20% complete
## Effort: 2-3 weeks
## Depends on: Plan 01 (ESM), Plan 05 (CanopyKit)

## What Already Exists

### Progressive Web App (`canopy/pwa` -- 7 files)
- Service worker registration and lifecycle management
- Web app manifest generation
- Offline caching strategies (cache-first, network-first, stale-while-revalidate)
- Push notification support
- Install prompt handling
- Background sync

### Mobile-Adjacent Packages
- `canopy/camera` -- camera access (works on mobile browsers and Capacitor)
- `canopy/web-audio` -- audio playback and recording
- `canopy/browser` (5 files) -- viewport size, orientation, online/offline detection
- `canopy/indexed-db` (7 files) -- offline data persistence

### Build Infrastructure
- ESM output (Plan 01) -- compatible with Capacitor and Tauri bundling
- CanopyKit build pipeline produces static web assets

## What Remains

### Phase 1: Capacitor Templates and Documentation (Week 1)
- `canopy kit new my-app --template mobile` scaffolding:
  - Pre-configured `capacitor.config.ts` pointing to Canopy build output
  - `@capacitor/core` and platform packages included
  - Build script that runs `canopy kit build` then `npx cap sync`
- `canopy kit new my-app --template desktop` for Tauri:
  - Pre-configured `tauri.conf.json`
  - Rust scaffolding for Tauri
  - Build script integration
- Documentation: full workflow from `canopy kit new` to app store submission

### Phase 2: Capacitor Plugin FFI Bindings (Week 2)
- FFI bindings for common Capacitor plugins with capability annotations:
  - Camera (extends existing `canopy/camera` for native features)
  - Filesystem (native file access beyond web sandbox)
  - Geolocation (high-accuracy GPS)
  - Push Notifications (APNs/FCM)
  - Haptics (vibration feedback)
  - App (lifecycle events, deep links)
- Each binding uses the capability system:
  ```canopy
  foreign import javascript "external/camera.js" as Camera

  -- @capability permission camera
  takePhoto : Task CameraError Photo
  ```
- App manifest lists all device API capabilities for app store review

### Phase 3: Testing and Polish (Week 3)
- Test on iOS simulator and Android emulator
- Test Tauri on macOS, Windows, Linux
- Performance profiling on mobile devices (startup time, memory usage)
- Mobile-specific responsive patterns documentation
- Example app demonstrating camera, geolocation, push notifications, and offline mode

## Architecture

Canopy compiles to JavaScript. Capacitor and Tauri both wrap web apps in native shells. This is a tooling and documentation effort, not a compiler change.

```
┌──────────────────────────────────────┐
│  Canopy App (Web)                    │
│  canopy kit build -> static assets   │
└──────────────┬───────────────────────┘
               │
       ┌───────┴───────┐
       ▼               ▼
┌─────────────┐  ┌─────────────┐
│  Capacitor  │  │   Tauri     │
│  iOS/Android│  │  macOS/Win/ │
│  Native     │  │  Linux      │
│  Shell      │  │  Native     │
└─────────────┘  └─────────────┘
```

## Definition of Done

- [ ] `canopy kit new my-app --template mobile` produces a working Capacitor project
- [ ] `canopy kit new my-app --template desktop` produces a working Tauri project
- [ ] At least 6 Capacitor plugin FFI bindings with capability annotations
- [ ] Documentation covers full workflow from scaffolding to app store submission
- [ ] Example app demonstrates camera, geolocation, push notifications, offline mode
- [ ] Tested on iOS simulator, Android emulator, and Tauri desktop targets

## Risks

- **Capacitor version churn**: Capacitor major versions may break templates. Pin versions and document upgrade path.
- **Native API gaps**: Some native features have no web equivalent. Must clearly document what works via PWA vs what requires Capacitor.
- **App store requirements**: iOS and Android have increasingly strict requirements for web-based apps. Must ensure templates meet current guidelines.
