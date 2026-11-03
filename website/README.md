# Website

The static site that this repository deploys: React 19 + TypeScript + Vite, with the React Compiler and Oxlint. See the [root README](../README.md) for how it is deployed.

## Requirements

- Node 26, which CI uses to build
- pnpm 11 (`11.16.0` in CI)

## Commands

```bash
pnpm install    # install dependencies (CI uses --frozen-lockfile)
pnpm dev        # dev server with HMR
pnpm build      # type-check (tsc -b) + production build into dist/
pnpm preview    # serve dist/ locally
pnpm lint       # Oxlint
```

## How it is deployed

`pnpm build` writes to `dist/`. Terraform (`../infrastructure`) uploads that folder to S3, and CloudFront serves it:

- **Long cache:** files under `dist/assets/` are cached for a year (`immutable`). Vite puts a content hash in their names (e.g. `index-z1dqokgX.js`), so a change produces a new file name. Don't put files without a hash into an `assets/` folder.
- **Always revalidated:** everything else, such as `index.html` and files from `public/`, is revalidated on every request, so a new deploy shows up right away.
- **Client-side routing:** unknown paths return `index.html` with status 200, so routes work on refresh.

A push to `dev`, `staging` or `main` that changes this folder deploys the matching stage.

## Dependency release age

By default, pnpm 11 holds back package versions that were published very recently, to protect against compromised releases. When a dependency is pinned to such a version, `pnpm install` adds it to `minimumReleaseAgeExclude` in `pnpm-workspace.yaml`. That file currently lists the Babel 8.1.0 packages and `@vitejs/plugin-react@6.2.1`.

- Review new entries in that file, then commit them together with `pnpm-lock.yaml`.
- Remove an entry once that version is old enough.
- To make pnpm stop instead of adding exclusions automatically, set `minimumReleaseAgeStrict: true`.

---

# Vite template notes

This project started from the Vite React + TypeScript template, which gives a minimal setup to get React working in Vite with HMR and some Oxlint rules.

Currently, two official plugins are available:

- [@vitejs/plugin-react](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react) uses [Oxc](https://oxc.rs)
- [@vitejs/plugin-react-swc](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react-swc) uses [SWC](https://swc.rs/)

## React Compiler

The React Compiler is enabled on this template. See [this documentation](https://react.dev/learn/react-compiler) for more information.

Note: This will impact Vite dev & build performances.
You can also try [the experimental native React Compiler support in plugin-react](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react/README.md#rust-react-compiler) by using `compiler: true` in the plugin options instead of using the Babel plugin.

## Expanding the Oxlint configuration

If you are developing a production application, we recommend enabling type-aware lint rules by installing `oxlint-tsgolint` and editing `.oxlintrc.json`:

```json
{
  "$schema": "./node_modules/oxlint/configuration_schema.json",
  "plugins": ["react", "typescript", "oxc"],
  "options": {
    "typeAware": true
  },
  "rules": {
    "react/rules-of-hooks": "error",
    "react/only-export-components": ["warn", { "allowConstantExport": true }]
  }
}
```

See the [Oxlint rules documentation](https://oxc.rs/docs/guide/usage/linter/rules) for the full list of rules and categories.
