# Licenses

**Songo#5** (the app and its plugins) and **SongoBGPlayer** (`libsongo_engine`, and
`songo_bgplayer` on Linux) are Copyright (C) 2025-2026 Riley Cleary, licensed under
the GNU GPL, version 3 or (at your option) any later version: `@LICENSE@`.

`SOURCES.txt` says where the source code for everything here is, and the exact
commits this release was built from. Paths are relative to this file.

## In the runtime (Songodot)

- **Songodot**, a fork of Godot Engine 4.3. MIT: `godot/LICENSE.txt`.
  The libraries inside it are listed, with their licenses, in `godot/COPYRIGHT.txt`.
- **TagLib** v2.1.1 + 3 commits (3c917caf52b6), copyright Scott Wheeler, Lukas
  Lalinsky, Tsuda Kageyu, Stephen F. Booth, Urs Fleisch and other TagLib
  contributors. Upstream offers it under LGPL-2.1 or MPL-1.1; it's used here under
  the **GNU Lesser General Public License 2.1**: `taglib/COPYING.LGPL`. The TagLib
  source files are unmodified (only a build config header, `taglib_config.h`, is
  added). It's statically linked into the runtime. Its source is in Songodot's
  `thirdparty/taglib`, with everything needed to rebuild the runtime with a
  modified TagLib (see `SOURCES.txt`), and upstream at
  https://github.com/taglib/taglib.
- **UTF8-CPP** v3.2.3, used by TagLib. Boost Software License 1.0:
  `utfcpp/LICENSE`.

## In the music engine (`libsongo_engine`)

- **FFmpeg** n8.1.2, unmodified, built without GPL or nonfree parts. LGPL version
  3 or later: `ffmpeg/COPYING.LGPLv3` (which adds to `ffmpeg/COPYING.GPLv3`).
  Some files are under LGPL 2.1 or later: `ffmpeg/COPYING.LGPLv2.1`. How it's
  built: `ffmpeg/building.md`. This software uses libraries from the FFmpeg
  project (https://ffmpeg.org).
- **Mbed TLS** v3.6.7. Used under Apache-2.0: `mbedtls/LICENSE`.

## In the app

Fonts, icons, artwork and sounds: `songo5/THIRD_PARTY.md`, with the fonts'
licenses in `songo5/licenses/`.
