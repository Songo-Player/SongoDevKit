# SongoDevKit

One place to build Songo #5. It brings together the repos Songo is made from, as submodules in `repos/`:

| Repo | What it is |
|---|---|
| [Songo-5](https://github.com/Songo-Player/Songo-5) | the app, a Godot project |
| [Songodot](https://github.com/Songo-Player/Songodot) | Songo's Godot 4.3 fork, with the gdtaglib (music library) and songo_player_harness (playback) modules |
| [SongoBGPlayer](https://github.com/Songo-Player/SongoBGPlayer) | the music engine (FFmpeg inside), the background player daemon and the Android playback plugin |
| [chai_retrofit](https://github.com/Songo-Player/chai_retrofit) | the `chai` device layer for handheld CFWs, shipped in the PortMaster port |

and handles everything about building them: cross compilers, export templates, editors and release packaging. The repos themselves only hold source and build scripts that expect a toolchain to be there; the toolchains live here.

## Setup

```
git clone --recurse-submodules git@github.com:Songo-Player/SongoDevKit.git
cd SongoDevKit
./songo.sh songo_status
```

All you need on the machine is Docker, git, rsync and Python 3: every build and export runs in the devkit's Docker images. The first build of each image downloads its toolchain (the android one, with the SDK, NDK and JDK, is about 5 GB), and the first Android build downloads Gradle's dependencies.

The first run makes `songo.conf` from `songo.conf.example`. The only machine-specific settings in it are the Android signing keys.

## Building

```
./songo.sh songo_build_release windows      # out/release/windows/Songo5-Setup.exe
./songo.sh songo_build_release portmaster   # out/release/portmaster/songo5.zip
./songo.sh songo_build_release android      # out/release/android/songo5.apk
./songo.sh songo_build_editor linux_x86     # out/editor/linux_x86/
./songo.sh songo_build_editor windows       # out/editor/windows/
```

To bring every repo up to the latest pushed versions first:

```
./songo.sh songo_update
```

It moves the submodules in `repos/` to the latest commit on each repo's default branch (SongoBGPlayer's own FFmpeg and mbedtls submodules stay at the commits it pins) and fast-forwards any local checkouts `songo.conf` points at, keeping uncommitted changes. A checkout on a detached HEAD, or with commits that diverged from GitHub, is left alone and reported. The submodules' new versions then show as changes in the devkit; `git add repos && git commit` records them.

Or `source songo.sh` and use the commands directly: `songo_build_release windows`. `songo_status` shows which repos are used and what's built, `songo_clean` forgets what's built (`--all` also drops the caches and outputs).

### Only what changed is built
Each piece (an editor, an export template, an engine build) is fingerprinted by what it was built from: its repo's commit, uncommitted changes and untracked files, its submodules, its build settings and its Docker image. A build skips every piece whose fingerprint hasn't changed, so after a change to Songo-5 alone, `songo_build_release windows` only re-exports and repackages, and with nothing changed it does nothing. Pieces that do rebuild still build incrementally. `--force` rebuilds everything a command needs.

| Command | Pieces it uses |
|---|---|
| `songo_build_release windows` | Linux editor (to export), Windows template, SongoBGPlayer Windows DLL |
| `songo_build_release portmaster` | Linux editor, SBC arm64 template, SongoBGPlayer arm64 engine + daemon, chai_retrofit |
| `songo_build_release android` | Linux editor, Android templates, SongoBGPlayer Android engine + AAR |
| `songo_build_editor linux_x86` | Linux editor, SongoBGPlayer x86_64 engine + daemon |
| `songo_build_editor windows` | Windows editor, SongoBGPlayer Windows DLL |

### Building local checkouts
By default everything builds from the submodules in `repos/`. To build your work in progress instead, point `songo.conf` at a local checkout, eg:

```
SONGODOT_DIR="../Songodot"
```

Builds never write into the repos: each piece builds in its own copy under `.work/`, synced from the repo's sources before each build. The repo's own build products aren't copied, since they may come from a different toolchain; each copy keeps its own between builds, so they stay incremental. Songo-5 is exported from a staged copy too, which is where the devkit drops in the Android AAR and template paths it built.

## Where things come from

- **Docker images** (`docker/`):
  - `linux-x86_64`: Ubuntu 22.04 with clang, for Songodot's Linux editor and SongoBGPlayer's x86_64 build, and the PortMaster export. Its glibc (2.35) lets that editor run on most current distros and in the other images, which run it to export.
  - `linux-arm64`: Ubuntu 20.04 (glibc 2.29 binaries, for older CFWs) with clang 10 and the arm64 sysroot for Songodot's SBC template, and GCC 9 aarch64 for SongoBGPlayer
  - `windows`: Ubuntu 24.04 with MinGW-w64 (posix threads) for Songodot and SongoBGPlayer, plus ImageMagick, Wine (to run rcedit) and NSIS for the Windows export and installer
  - `android`: Ubuntu 22.04 with JDK 17, the SDK (platform 34, build-tools 34.0.0) and NDK r23c, for Songodot's Android templates, SongoBGPlayer's Android engine and AAR, and the Gradle export. Gradle's cache lives in `.work/gradle`. The image accepts the SDK license, so keep it local rather than pushing it to a public registry.
- **Android signing:** `songo.conf`'s `ANDROID_DEBUG_KEYSTORE` (Godot's own debug keystore by default, so APKs keep the signature earlier builds had; one is generated in `.work/android` if it's missing) and optionally `ANDROID_RELEASE_KEYSTORE`, mounted read-only into the export.
- **`build_platforms/`:** each platform's packaging, run by `songo.sh` with the pieces it built:
  - `portmaster/`: the port's static files (`Songo5.sh`, `songo5/`) and `build_portmaster.sh`
  - `windows/`: `installer.nsi`, rcedit (`tools/`), and `build_windows.sh` (runs in the windows image)
  - `android/`: `build_android.sh`, the Gradle export and its checks

## Layout

```
songo.sh               the entry point
songo.conf.example     settings (copied to songo.conf)
repos/                 the submodules
docker/                the toolchain images
build_platforms/       per-platform packaging
lib/                   songo.sh's internals (common.sh, components.sh, release.sh, sync_build.sh)
out/                   results: release/, editor/, and components/ (each piece)
.work/                 work copies, caches, build stamps, the Wine prefix
```

The work copies take a few GB (each Songodot target keeps its own, since Godot regenerates headers per build profile).
