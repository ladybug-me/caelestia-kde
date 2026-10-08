id: DOC-TS-06
title: 6. Network & Proxy Issues
source: docs/TROUBLESHOOTING.md — section 6 (Network & Proxy Issues)
tags: network, proxy, mirror ranking, pacman mirrors, git submodules, src/dots empty, aur behind proxy
synonyms: git clone fails, submodule empty

### 6.1 Pacman Mirror Ranking Fails

On CachyOS, the installer uses the native `cachyos-rate-mirrors` command, which ranks both Arch and CachyOS repositories. Other Arch-based systems use `reflector` as a fallback. Fedora refreshes its configured DNF metadata and Debian-based systems refresh their configured APT indexes; neither needs mirror-list rewriting during installation. Failure modes:
- **Offline:** Mirror ranking fails and the existing mirror lists are kept
- **cachyos-rate-mirrors unavailable:** CachyOS mirror ranking is skipped and the existing mirror lists are kept
- **reflector not installed:** On non-Cachy Arch systems, it is auto-installed via `pacman -Sy reflector`; if that fails, ranking is skipped
- **DNF or APT refresh fails:** Fedora/Debian package installation continues and reports the package-manager error later if the configured sources remain unavailable

### 6.2 Git / Submodule Failures

The submodule `src/dots` is critical. If it cannot be fetched:

```text
[ERR] src/dots is still empty, and the installer cannot deploy without it.
```

Step 02a checks the submodule has content and fetches it again by other means before reporting this: a normal update, then a sync of the recorded URL followed by another update, then a forced update, and finally a plain clone of the URL `.gitmodules` records. So this message means all four were attempted and every one failed, which is usually a network that cannot reach GitHub or a checkout that cannot be written to.

This is a **hard failure** - the installer cannot proceed past config deployment. Fetch it by hand and re-run the step:

```bash
git -C ~/caelestia-kde submodule update --init --recursive src/dots
bash ~/caelestia-kde/scripts/02a-submodules.sh
```

The shared folder mounted at `/mnt/hgfs/` is read-only, so an install run from there cannot fetch anything: clone the repository to a writable directory first.

**Behind a proxy?**
```bash
git config --global http.proxy http://proxy:port
git config --global https.proxy http://proxy:port
export GIT_SSL_NO_VERIFY=1
```

### 6.3 AUR Builds Fail Behind Proxy

`makepkg -si` downloads sources from various URLs. Set proxy environment variables before running `setup.sh`:
```bash
export http_proxy=http://proxy:port
export https_proxy=http://proxy:port
export ALL_PROXY=http://proxy:port
```
