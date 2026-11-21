# Pulse VPN Manager — Installer

One-line install for OpenWrt routers. Requires an **installation password** (ask the owner).

```sh
sh -c "$(wget -qO- https://raw.githubusercontent.com/tkmw1985/tkmw1985-pulse-install/main/install.sh)"
# Installation password: ****
```

The installer is **encrypted** (AES-256) — without the password the files here are useless.
`install.sh` detects the router architecture, downloads the matching encrypted build,
decrypts it with your password, verifies SHA256, then installs.

Source code, CI and releases live in a separate private repository.
