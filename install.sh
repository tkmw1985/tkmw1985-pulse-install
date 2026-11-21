#!/bin/sh
# ==================================================================
#  PULSE VPN MANAGER — public bootstrap installer (password-gated)
#  One permanent URL. Asks for a password, downloads the ENCRYPTED
#  installer for this router's arch, decrypts it, verifies SHA256,
#  then runs it. No GitHub token needed. The encrypted blob is
#  useless without the password.
#
#     sh -c "$(wget -qO- https://raw.githubusercontent.com/tkmw1985/tkmw1985-pulse-install/main/install.sh)"
#     Installation password: ****
#
#  Non-interactive:  PULSE_PASS=... sh install.sh
# ==================================================================
set -u

BASE="https://raw.githubusercontent.com/tkmw1985/tkmw1985-pulse-install/main"
MIRROR="${PULSE_MIRROR:-}"
PASS="${PULSE_PASS:-}"
TMP=/tmp/pulse-boot; rm -rf "$TMP"; mkdir -p "$TMP"

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; CYN='\033[0;36m'; NC='\033[0m'
ok(){ printf "${GRN}[ OK ]${NC} %s\n" "$1"; }
inf(){ printf "${CYN}[ .. ]${NC} %s\n" "$1"; }
wrn(){ printf "${YLW}[ !! ]${NC} %s\n" "$1"; }
die(){ printf "${RED}[ERR ]${NC} %s\n" "$1" >&2; exit 1; }

# ---- 1. detect arch ---------------------------------------------
PKGARCH=""; [ -f /etc/openwrt_release ] && { . /etc/openwrt_release; PKGARCH="${DISTRIB_ARCH:-}"; }
MACH=$(uname -m 2>/dev/null || echo "")
case "$PKGARCH$MACH" in
  *aarch64*|*arm64*)  RARCH=aarch64;;
  *arm_*|*armv7*|*armhf*) RARCH=arm;;
  *mipsel*|*mipsle*)  RARCH=mipsel;;
  *mips*)             RARCH=mips;;
  *x86_64*|*amd64*)   RARCH=x86_64;;
  *riscv64*)          RARCH=riscv64;;
  *) RARCH=unknown;;
esac
[ "$RARCH" = unknown ] && die "Unsupported architecture ($PKGARCH / $MACH)."
if command -v curl >/dev/null 2>&1; then FETCH=curl
elif command -v wget >/dev/null 2>&1; then FETCH=wget
else die "curl or wget required."; fi
inf "architecture: $RARCH"

get(){ # $1 url  $2 out  (public, no auth)
  if [ "$FETCH" = curl ]; then curl -fsSL -o "$2" "$1"; else wget -q -O "$2" "$1"; fi
}
fetch(){ # $1 relpath  $2 out — try main URL then mirror
  get "$BASE/$1" "$2" 2>/dev/null && [ -s "$2" ] && return 0
  [ -n "$MIRROR" ] && get "$MIRROR/$1" "$2" 2>/dev/null && [ -s "$2" ] && { wrn "used mirror for $1"; return 0; }
  return 1
}

# ---- 2. ensure openssl (for decryption) -------------------------
ensure_openssl(){
  command -v openssl >/dev/null 2>&1 && return 0
  inf "installing openssl-util…"
  if command -v apk >/dev/null 2>&1; then apk update >/dev/null 2>&1; apk add openssl-util >/dev/null 2>&1
  elif command -v opkg >/dev/null 2>&1; then opkg update >/dev/null 2>&1; opkg install openssl-util >/dev/null 2>&1; fi
  command -v openssl >/dev/null 2>&1 || die "openssl not available (install openssl-util manually)."
}

# ---- 3. manifest: arch -> enc file + expected decrypted sha ------
fetch "manifest.txt" "$TMP/manifest.txt" || die "cannot fetch manifest (check network / URL)."
ROW=$(awk -v a="$RARCH" '$1==a{print; exit}' "$TMP/manifest.txt")
[ -n "$ROW" ] || die "no build published for arch '$RARCH' yet."
ENC=$(echo "$ROW" | awk '{print $2}')
WANT=$(echo "$ROW"  | awk '{print $3}')
[ -n "$ENC" ] && [ -n "$WANT" ] || die "malformed manifest row."

# ---- 4. password ------------------------------------------------
if [ -z "$PASS" ]; then
  printf "Installation password: "
  stty -echo 2>/dev/null; IFS= read -r PASS; stty echo 2>/dev/null; echo
fi
[ -n "$PASS" ] || die "Installation password required."

# ---- 5. download + decrypt + verify -----------------------------
ensure_openssl
inf "downloading encrypted installer…"
fetch "$ENC" "$TMP/pkg.enc" || die "cannot download $ENC."
inf "decrypting…"
if ! openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass pass:"$PASS" -in "$TMP/pkg.enc" -out "$TMP/installer.sh" 2>/dev/null; then
  die "Wrong password or corrupted download — access denied."
fi
GOT=$(sha256sum "$TMP/installer.sh" 2>/dev/null | awk '{print $1}')
[ "$GOT" = "$WANT" ] || die "integrity check failed (sha mismatch) — refusing to run."
ok "password accepted, installer verified"

# ---- 6. run -----------------------------------------------------
chmod +x "$TMP/installer.sh"
sh "$TMP/installer.sh" "$@"
ok "done."
