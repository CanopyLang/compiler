# Plan 32: Mobile Deployment

## Priority: LOW — Tier 4
## Effort: 2-3 weeks
## Depends on: Plan 01 (ESM), Plan 05 (CanopyKit)

## Problem

React Native, Flutter, and Capacitor dominate mobile. Canopy has no mobile story. Even a basic "Canopy in a mobile shell" approach would significantly expand the addressable market.

## Solution: Capacitor + Tauri Integration

Canopy compiles to JavaScript. Capacitor and Tauri both wrap JavaScript web apps in native mobile/desktop shells. This is a documentation and tooling problem, not a compiler problem.

### Capacitor (Mobile)

```bash
canopy kit new my-app --template mobile
cd my-app
canopy kit build
npx cap add ios
npx cap add android
npx cap sync
npx cap open ios
```

The `--template mobile` flag:
1. Scaffolds a CanopyKit project with Capacitor pre-configured
2. Adds `@capacitor/core` and platform packages
3. Configures the build output directory for Capacitor
4. Includes a `capacitor.config.ts` pointing to Canopy's build output

### Capability Integration

Capacitor plugins map naturally to Canopy capabilities:

```canopy
-- Using Capacitor Camera plugin via FFI
foreign import javascript "external/camera.js" as Camera

-- @canopy-type Task CameraError Photo
-- @capability permission camera
-- @capability userActivation Click
takePhoto : Task CameraError Photo
takePhoto = Camera.takePhoto
```

The capability system ensures that:
- Camera access requires explicit `permission camera` capability
- The app's `capabilities.json` manifest lists all device APIs used
- App store reviewers can verify permissions match the manifest

### Tauri (Desktop)

```bash
canopy kit new my-app --template desktop
cd my-app
canopy kit build
cargo tauri dev
```

Same approach: Canopy builds to web output, Tauri wraps it in a native desktop window with access to system APIs via FFI.

## Implementation

### Phase 1: Documentation + Templates (Week 1)
- "Building Mobile Apps with Canopy" guide
- "Building Desktop Apps with Canopy" guide
- CanopyKit template: `--template mobile`
- CanopyKit template: `--template desktop`

### Phase 2: Capacitor Plugin FFI Bindings (Week 2)
- FFI bindings for common Capacitor plugins (Camera, Filesystem, Geolocation, Push Notifications)
- Capability annotations for each plugin
- Example mobile app

### Phase 3: Testing + Polish (Week 3)
- Test on iOS simulator and Android emulator
- Test Tauri on macOS, Windows, Linux
- Performance profiling on mobile devices

## Definition of Done

- [ ] `canopy kit new my-app --template mobile` produces a working Capacitor project
- [ ] `canopy kit new my-app --template desktop` produces a working Tauri project
- [ ] At least 4 Capacitor plugin FFI bindings with capability annotations
- [ ] Documentation covers the full workflow from `canopy kit new` to app store submission
- [ ] Example app demonstrates camera, geolocation, and push notifications
