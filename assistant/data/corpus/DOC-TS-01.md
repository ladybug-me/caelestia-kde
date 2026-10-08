id: DOC-TS-01
title: 1. Build & Compilation Issues
source: docs/TROUBLESHOOTING.md — section 1 (Build & Compilation Issues)
tags: build, compile, cmake, g++, gcc, make, installer tui, c++20, qt6, qml module metadata, qmldir, ccache, sigsegv, exit 139, exit 127
synonyms: install fails cmake missing, g++ command not found, build errors

### 1.1 C++ Installer Compilation Fails

The installer compiles the `caelestia-install` TUI binary during `setup.sh`. The CMake project requires **C++20** (`CMAKE_CXX_STANDARD 20`).

| Symptom | Likely Cause | Fix |
|---|---|---|
| `g++: command not found` | Build tools not installed | Arch: `sudo pacman -S base-devel` — Fedora: `sudo dnf install gcc-c++` |
| `cmake: command not found` | CMake missing | Auto-installer handles this if `BASE_DISTRO` is detected; otherwise install manually |
| `[FATAL] Failed to build the Caelestia installer` | General CMake/make error | Read build log: `cat /tmp/caelestia_build.log` |
| Compiler error about modern C++ features | GCC older than 10 | Ensure GCC 10+ is installed: `g++ --version` |
| Exit 139 (SIGSEGV) at runtime | C++ bug in the TUI | Check stderr log at `/tmp/caelestia_installer_err.log` |
| Exit 127 at runtime | Missing shared library | Run `ldd` on the binary to find missing `.so` files |

### 1.2 Shell / Plugin Compilation Fails

The shell build (`08-build-shell.sh`) requires **Qt 6.9+** and several system libraries. The CMake project in `shell/CMakeLists.txt` uses `qt_standard_project_setup(REQUIRES 6.9)`.

#### Qt / QML Dependencies

| Missing Dependency | CMake Error Clue | Arch Package | Fedora Package |
|---|---|---|---|
| Qt6::Qml / Qt6::Quick | `find_package` failed | `qt6-declarative` | `qt6-qtdeclarative-devel` |
| Qt6::ShaderTools | Shader tool config | `qt6-shadertools` | `qt6-qtshadertools-devel` |
| Qt6::WaylandClient | Wayland client plugin | `qt6-wayland` | `qt6-qtwayland-devel` |
| KF6WindowSystem | KWindowSystem not found | `kwindowsystem` | `kf6-kwindowsystem-devel` |
| KGlobalAccel | kglobalaccel not found | `kglobalaccel` | `kf6-kglobalaccel-devel` |
| KPipeWire | pipewire integration | `kpipewire` | `kf6-kpipewire-devel` |

#### Library Dependencies (pkg_check_modules)

| Library | Arch Package | Fedora Package |
|---|---|---|
| `libqalculate` | `libqalculate` | `libqalculate-devel` |
| `libpipewire-0.3` | `pipewire` | `pipewire-devel` |
| `aubio` | `aubio` | `aubio-devel` |
| `libcava` | Prebuilt release asset / `libcava` | Prebuilt release asset / `celestelove/libcava` (COPR) |
| `libpulse` | `libpulse` | `pulseaudio-libs-devel` |
| `libpam` | `pam` | `pam-devel` |
| `lm_sensors` (Fedora) | not needed | `lm_sensors-devel` |

**Fedora note:** The custom `cmake/sensorslib.cmake` module loads `lm_sensors`. If it's missing, the build may silently skip sensor support.

### 1.3 "Missing QML Module Metadata" After Build

```text
[ERR] Missing QML module metadata: $HOME/.local/lib/qt6/qml/Caelestia/Config/qmldir
```

This means the CMake install step didn't copy required `qmldir` or `.so` files properly.

**Causes & fixes:**
- **Install prefix mismatch:** The build uses `-DCMAKE_INSTALL_PREFIX=$HOME/.local`. If Qt6 looks for QML modules elsewhere, the module won't load.
- **Stale build artifacts:** Run `rm -rf shell/build shell/plugin/build` before re-running
- **Partial installation:** If CMake install was interrupted, files may be missing. Re-run `08-build-shell.sh`

### 1.4 ccache Not Speeding Up Rebuilds

The project enables ccache in both `installer/CMakeLists.txt` and `shell/CMakeLists.txt`. If rebuilds are still slow:

- Check ccache stats: `ccache -s`
- The cache directory (`~/.cache/ccache`) may be too small — increase it: `ccache -M 5G`
- Debug builds (`-DCMAKE_BUILD_TYPE=Debug`) are much slower; the installer uses `Release`
