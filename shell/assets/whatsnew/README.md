# What's New assets

Media for the What's New window. The entries themselves are declared in
`shell/modules/whatsnew/Entries.qml`; this directory only holds the files they
point at.

## Adding an entry

Append an object to the end of `list` in `Entries.qml`:

```qml
{
    "id": "some_short_handle",
    "revision": 16,
    "icon": "extension",
    "title": qsTr("A headline"),
    "description": qsTr("The full text, shown when the entry is opened."),
    "mediaUrl": "some_screenshot.png"
}
```

- `id` - a stable handle. Never reuse or rename one.
- `revision` - higher than every entry above it. Revisions are what the shell
  records acknowledgement against, so changing one either re-shows the entry to
  everybody or hides it from them. Never renumber or reorder a shipped entry.
  Pruning entries from the list is fine; acknowledged revisions that no longer
  match an entry are ignored.
- `icon` - a Material icon name. Optional.
- `title`, `description` - wrapped in `qsTr()` so lupdate can extract them.
  See [Writing the copy](#writing-the-copy) - the description has a length
  budget the build checks.
- `mediaUrl` - a filename in this directory, or `root:/assets/...` to point at a
  shared shell asset. `.mp4`, `.webm`, `.mkv`, `.avi` and `.mov` play muted on a
  loop; anything else is shown as a still. Optional.
- `mediaTransparent` - set it when the media should not get the backing panel.
  Optional.

`.github/scripts/test_repo_integrity.py` fails the build when a revision is
duplicated or out of order, an id is duplicated, a title or description is not
wrapped for extraction, a media path escapes this directory, or a media file
does not exist.

## Writing the copy

The list shows `title` and `description` on one elided line each, so the
description is a label rather than a release note: one sentence, at most 90
characters, no closing benefit clause.

- Name the surface and the action: "Turn autostart entries on or off, or add an
  app, in Nexus → Session."
- Leave out "now" and "no longer". Every entry in this list has just shipped, so
  the tense carries no information.
- Put the why in the commit, the docs, or the pull request. The entry says what
  changed and where to find it.

`.github/scripts/test_repo_integrity.py` fails the build on a description that
runs past 90 characters, spans more than one sentence, or says "now".

## State

Acknowledgement is stored in `~/.local/state/caelestia/whatsnew.json`:

```json
{ "schemaVersion": 1, "acknowledged": [9, 10, 11] }
```

Opening an entry adds its revision to that list. Closing the window changes
nothing. Revisions that no longer match an entry are ignored, so pruning an old
entry neither re-shows nor hides anything for a user who already acknowledged
it.
