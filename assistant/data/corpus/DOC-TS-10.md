id: DOC-TS-10
title: 10. Update Issues
source: docs/TROUBLESHOOTING.md — section 10 (Update Issues)
tags: update, updater, update.sh, caelestia updater, re-clone, cache, install latest version

### 10.1 Fixing caelestia updater (Recommended)

By deleting the build cache and the update checker cache:

```bash
rm -rf ~/.config/caelestia-update/repo ~/.cache/caelestia-update-repo
```

**Note:** This will have the updater clone the repo again which takes time according to your internet speed. Hence, the logs might seem stuck or tell you to restart the process, but just wait for it to finish.

### 10.2 Using update.sh

You can simply run `bash update.sh` in the cloned repo folder (~/caelestia-kde) to update to latest version.

### 10.3 Install latest version from repo

Run the following command to simply install the latest shell using installer.
```bash
curl -fsSL https://raw.githubusercontent.com/ladybug-me/caelestia-kde/main/install.sh | sh
```

- If it gives an error due to already present `~/caelestia-kde` directory in your pc, then remove that directory first and then run the above command. **Make sure to copy the `backups/` folder somewhere and then put it back here after installation completes.**
