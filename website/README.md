# The Caelestia website

The project's site: <https://ladybug-me.github.io/caelestia-kde>.

It is a static Astro build that treats the repository as its source of truth —
the docs are the project's own markdown, read at build time, and the palettes are
the shell's own scheme files. That is why most of it is generated rather than
written:

| What | Where it comes from |
| --- | --- |
| Docs pages | `README.md` sections, `docs/TROUBLESHOOTING.md`, `.github/CONTRIBUTING.md` |
| Palettes | `src/schemes/**`, by way of `scripts/gen-palettes.mjs` |
| Logo and screenshots | `assets/`, by way of `scripts/sync-assets.mjs` |
| The typeface | `shell/assets/google-sans-flex/`, subset at build time |

The palettes are the one thing the build changes rather than copies. A scheme
file is written for the shell's own components, where a role that reads fine
inside a popout can sit below the ratio a paragraph needs on a page, so the
generator measures every pair the stylesheet paints and moves a role just far
enough towards white or black to clear its floor: 4.5:1, including the accent,
which is also the focus ring. The build names each role it moved, and
`npm run test:unit` fails if a pair ships below its floor.

## Working on it

```bash
cd website
npm ci
npm run dev
```

`npm run dev` and `npm run build` both regenerate the palettes and stage the
assets first (npm's `predev`/`prebuild` hooks), so a fresh checkout needs nothing
else.

## Checks

```bash
npm run check      # types (astro check), formatting, eslint, stylelint
npm run test:unit  # the gesture arithmetic, the palette parser, the docs loader
npm run test:e2e   # the browser: drags, flicks, interruptions, reduced motion
npm run lint:docs  # markdown, with the repository's own markdownlint config
```

The unit tests cover the maths that decides how a gesture behaves; the browser
tests cover the part a unit test cannot see, which is whether that maths is
actually wired to the pointer.

## Deploying

`.github/workflows/website.yml` builds on every pull request and publishes on a
push to `main`. Pages must be set to **GitHub Actions** as its source once, in
the repository's settings; the base path (`/caelestia-kde`) is the `BASE_PATH`
constant in `astro.config.mjs`, so moving to a custom domain is a change to that
value plus a `CNAME` file.

## Layout

```text
scripts/     the build steps: palette generation, asset staging, shared parsing
src/loaders/ the docs loader that reads the repository's markdown
src/lib/     motion (springs, drag, projection), palettes, and the demos
src/styles/  tokens, materials, components, motion preferences
src/pages/   the routes
tests/       vitest (unit) and Playwright (browser)
```

## Translations

The site is English only. It is built so that adding a locale is a change rather
than a rewrite:

- Astro's `i18n` config plus a locale segment in `src/pages/` is all the routing
  it needs; the default locale can stay unprefixed, so no existing URL moves.
- The words live in the components and layouts. The content — the docs, the
  palette names, the shell's own strings — comes from the repository, and the
  repository already ships its translations through Crowdin under
  `shell/translations/`, so a locale's shell strings and its site's words would
  come from the same place.
