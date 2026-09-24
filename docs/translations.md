# Translations

How the Caelestia shell is translated: where the catalogues live, how to add or
update a language, and how Crowdin keeps them in sync. Nothing here depends on
another document; the short version that ships beside the catalogues themselves
is `shell/translations/README.md`.

## Catalogues

The translatable strings sit in `shell/` (QML sources), wrapped in `qsTr()` at
the call site. Qt Linguist tooling turns them into one catalogue per language:

| File | What it is |
| --- | --- |
| `shell/translations/caelestia_<code>.ts` | The source catalogue for language `<code>` (Qt Linguist XML). Editable by hand or with Qt Linguist. |
| `shell/translations/caelestia_<code>.qm` | The compiled catalogue next to its source. Committed so a build without Qt's Linguist tools still ships every language instead of silently falling back to English. Never edited by hand. |

English is the source language: strings are written in English in the QML, so
`en` needs no catalogue of its own. `caelestia_en.ts` exists only as the source
that Crowdin uploads; it is not loaded at runtime.

Language codes are the ones Qt looks for (`pt_BR`, `zh_CN`, ...), which is why
`crowdin.yml` maps Crowdin's own codes onto them (see below).

## At runtime

The C++ `Translations` singleton (in the shell plugin) installs a `QTranslator`
for the active language and loads `caelestia_<code>.qm` from the directory
`translations/` next to the running shell - both for an installed shell and for
one run straight out of a checkout. The language is a shell setting: Nexus ->
Language & region writes it, and a language with no catalogue falls back to
English. `"system"` follows the locale.

## Adding or updating a language locally

`tools/update-translations.sh` drives Qt's `lupdate`/`lrelease` and finds them
on any distro layout:

```bash
tools/update-translations.sh          # refresh every catalogue that exists
tools/update-translations.sh es       # start a new one (Spanish here)
```

The script regenerates the `.ts` from the current sources (marking vanished
strings obsolete, not deleting history), then recompiles the matching `.qm`.
Edit the `.ts` (Qt Linguist is the comfortable way), rerun the script to
recompile, and commit **both** files together - a `.ts` without its `.qm` ships
the previous translation, a `.qm` without its `.ts` cannot be improved on
Crowdin.

After changing `qsTr()` strings in the QML sources, refresh the catalogues the
same way, then rebuild the shell so the compiled catalogues land in the install
tree (`bash scripts/08-build-shell.sh`).

The build itself does the right thing either way: with Qt's Linguist tools
installed it recompiles every `.ts` and installs those, so an edited
translation never waits for a refreshed committed `.qm`; without them it
installs the committed `.qm` files as-is.

## Crowdin

Translating in the browser instead of a local Qt Linguist is supported through
Crowdin. `crowdin.yml` at the repository root defines the mapping:

- source: `/shell/translations/caelestia_en.ts`
- translation: `/shell/translations/caelestia_%two_letters_code%.ts`
- `languages_mapping` renames a few of Crowdin's two-letter codes to the ones
  Qt looks for: `pt-PT` -> `pt_PT`, `pt-BR` -> `pt_BR`, `zh-CN` -> `zh_CN`,
  `zh-TW` -> `zh_TW`. (The two Chinese catalogues are contributed by hand; both
  entries sit idle on the Crowdin project today.)

The `Crowdin` workflow (`.github/workflows/crowdin.yml`) runs on pushes to
`dev` that touch the shell or the catalogues, daily, and on demand:

1. `synchronize` regenerates the English source catalogue, uploads it, and
   downloads every language's progress as a pull request to `dev` (branch
   `i18n/crowdin`). Partially translated catalogues are included deliberately -
   machine translation that leaves a few strings short used to hold back whole
   languages.
2. `compile` recompiles every `.qm` on that branch and pushes the commit, so
   the PR is mergeable as it stands.

The workflow is gated on the upstream repository (it needs the upstream
Crowdin project's secrets), so a fork sees no automatic synchronization - forks
translate through the local flow above.

## Rules of thumb

- Wrap user-facing strings in `qsTr()` when you add them; run
  `tools/update-translations.sh` before committing so the catalogues follow.
- Commit the `.ts` and the `.qm` of a language together.
- Never hand-edit a `.qm`; rerun the script or the compile job instead.
- Prefer early translation: a string built from fragments cannot be translated
  word-order-correctly in every language.
