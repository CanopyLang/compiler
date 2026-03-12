# Deployment

This guide covers deploying Canopy applications to various hosting platforms.

## Building for Production

```bash
canopy make --optimize
```

This produces a single optimized JavaScript file with dead code elimination, minification, and tree shaking. The output is in your project's `build/` directory.

For HTML output (includes the HTML wrapper):

```bash
canopy make --optimize --output=build/index.html
```

## Static Hosting

Canopy applications are static sites by default — just HTML, CSS, and JavaScript. Any static hosting provider works.

### Vercel

Create `vercel.json` in your project root:

```json
{
  "buildCommand": "canopy make --optimize --output=build/index.html",
  "outputDirectory": "build",
  "rewrites": [
    { "source": "/(.*)", "destination": "/index.html" }
  ]
}
```

Deploy:

```bash
npx vercel
```

### Netlify

Create `netlify.toml`:

```toml
[build]
  command = "canopy make --optimize --output=build/index.html"
  publish = "build"

[[redirects]]
  from = "/*"
  to = "/index.html"
  status = 200
```

### GitHub Pages

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Canopy
        run: curl -sSL https://canopy-lang.org/install.sh | sh
      - name: Build
        run: canopy make --optimize --output=build/index.html
      - name: Deploy
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./build
```

## CanopyKit Deployment

CanopyKit applications support both static site generation (SSG) and server-side rendering (SSR).

### Static Site Generation (Default)

```bash
canopy kit-build
```

Outputs a fully static site to `build/`. Deploy to any static host.

### Node.js Server

```bash
canopy kit-build --target node
```

Generates a `build/server.js` entry point. Deploy:

```bash
cd build && node server.js
```

### Docker

```dockerfile
FROM node:20-alpine AS build
RUN npm install -g canopy
COPY . /app
WORKDIR /app
RUN canopy kit-build --target node

FROM node:20-alpine
COPY --from=build /app/build /app
WORKDIR /app
EXPOSE 3000
CMD ["node", "server.js"]
```

## Environment Variables

Canopy reads environment variables at build time through the FFI:

```javascript
// src/ffi/env.js

/**
 * @canopy-type String
 */
function getApiUrl() {
  return process.env.API_URL || "https://api.example.com";
}
```

```canopy
port getApiUrl : () -> String
```

Set variables when building:

```bash
API_URL=https://api.prod.com canopy make --optimize
```

## Build Optimization

### Code Splitting

Use `lazy import` to split your application into chunks loaded on demand:

```canopy
lazy import Pages.Dashboard
lazy import Pages.Settings
```

### Bundle Analysis

Check your output size:

```bash
ls -la build/*.js
```

For detailed analysis, use the capabilities manifest:

```bash
canopy audit --capabilities
```

## Client-Side Routing

For single-page applications with client-side routing, configure your server to serve `index.html` for all routes. The redirect/rewrite rules shown above for each platform handle this.
