# Capability Security

Canopy enforces capability-based security for JavaScript FFI calls. Every
sensitive browser API (geolocation, camera, notifications, etc.) must be
explicitly declared in your `canopy.json` before it can be used at runtime.

## Declaring Capabilities

In `canopy.json`, add a `capabilities` field:

```json
{
    "type": "application",
    "source-directories": ["src"],
    "capabilities": {
        "allow": ["geolocation", "notifications"],
        "deny": ["camera"]
    }
}
```

- **allow**: capabilities your app is permitted to use
- **deny**: capabilities explicitly blocked, even if a dependency requests them

The deny list takes precedence: if a capability appears in both `allow` and
`deny`, it is denied.

You can also use the shorthand form when you only need an allow list:

```json
{
    "capabilities": ["geolocation", "notifications"]
}
```

## How It Works

### Compile-Time Validation

When you annotate FFI functions with `@capability` in their JSDoc:

```javascript
/**
 * @capability geolocation
 */
function getLocation() {
    return navigator.geolocation.getCurrentPosition(...);
}
```

The compiler checks at build time that every required capability is declared
in `canopy.json`. If a capability is missing, you get a compile error:

```
-- MISSING CAPABILITIES --

Some FFI functions require capabilities that are not declared in canopy.json:

    getLocation (ffi/geo.js) requires capability "geolocation"

Add the missing capabilities to canopy.json:

    "capabilities": ["geolocation", "notifications"]
```

If a capability is explicitly denied:

```
-- CAPABILITY VIOLATION --

Some FFI functions require capabilities that are denied or not declared:

    takePhoto (ffi/camera.js) DENIED capability "camera"
```

### Runtime Guards

At runtime, the compiled JavaScript includes a capability registry that
throws immediately if an undeclared capability is used:

```javascript
var _Canopy_capabilities = {"geolocation": true, "notifications": true};
function _Canopy_checkCapability(cap, fn) {
    if (!_Canopy_capabilities[cap]) {
        throw new Error('Capability \'' + cap + '\' required by ' + fn
            + ' but not granted in canopy.json.');
    }
}
```

This defense-in-depth approach catches issues even when compile-time checks
are bypassed.

## Deny Lists for Defense-in-Depth

The deny list is your safety net. Even if a third-party package declares
a capability, you can block it at the application level:

```json
{
    "capabilities": {
        "allow": ["geolocation"],
        "deny": ["camera", "microphone"]
    }
}
```

This ensures your app never accidentally gains access to the camera or
microphone, regardless of what dependencies request.

## Capability Auditing

Run `canopy audit --capabilities` to see a full report of which packages
require which capabilities:

```
-- CAPABILITY AUDIT --

  canopy/http
    ✓ network (allowed)

  my-company/media-picker
    ✗ camera (denied)
    ✓ file-access (allowed)

Summary: 2 capabilities allowed, 1 denied
```

## New Capability Warnings During Install

When you install or update a package, Canopy warns if new capabilities
are introduced:

```
⚠ canopy/http now requires capability: network
```

This gives you visibility into security-relevant changes before they
affect your application.

## Best Practices

1. **Start with an empty allow list** and add capabilities as needed
2. **Use the deny list** to block capabilities you never want
3. **Run `canopy audit --capabilities`** after dependency updates
4. **Review capability changes** in pull requests
5. **Document why** each capability is needed in your project README
