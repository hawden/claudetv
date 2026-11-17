#!/usr/bin/env bash
# claudetv — debloat an Amazon Fire TV stick (Fire OS) over ADB, reversibly.
#
# Everything here is undoable: packages are disabled for the default user, never deleted from the
# system partition. `restore` (or a factory reset) brings them all back.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LISTS="$ROOT/lists"
BACKUPS="$ROOT/backups"
DEFAULT_LISTS=(telemetry ads)
DRY_RUN=0
ASSUME_YES=0

die()  { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

adbc() {
  if [[ -n "${CLAUDETV_DEVICE:-}" ]]; then adb -s "$CLAUDETV_DEVICE" "$@"; else adb "$@"; fi
}
# Run a shell command on the device; strip the carriage returns older adb adds.
ash() { adbc shell "$@" 2>&1 | tr -d '\r'; }

usage() {
  cat <<EOF
Usage: ./claudetv.sh [--dry-run] [--yes] <command> [args]

  connect <ip>          Connect to the stick over Wi-Fi (port 5555)
  info                  Show model and Fire OS version, check it's supported
  scan                  List every Amazon package and whether it's enabled
  backup                Save the current package state to backups/
  debloat [list ...]    Disable packages from lists/ (default: ${DEFAULT_LISTS[*]})
                        Available lists: $(list_names | tr '\n' ' ')
  restore [pkg ...]     Re-enable packages (default: every package in every list)
  launcher <file.apk>   Install a custom launcher APK (e.g. Projectivy Launcher)

Set CLAUDETV_DEVICE=<serial or ip:port> if more than one device is connected.
EOF
}

list_names() { for f in "$LISTS"/*.txt; do basename "$f" .txt; done | grep -vx protected; }

# Print the package names in a list file (comments and blank lines removed).
read_list() {
  local file="$LISTS/$1.txt"
  [[ -f "$file" ]] || die "no such list: $1 (available: $(list_names | tr '\n' ' '))"
  sed -e 's/#.*//' -e 's/[[:space:]]//g' "$file" | grep -v '^$' || true
}

is_protected() { read_list protected | grep -qxF "$1"; }

# Package-state helpers. `pm list packages` prints "package:<name>".
pkgs()          { ash pm list packages "$@" | sed -n 's/^package://p'; }
installed()     { grep -qxF "$1" <<<"$INSTALLED"; }
known_to_user() { grep -qxF "$1" <<<"$ALL_PKGS"; }
load_state() {
  INSTALLED="$(pkgs)"
  ALL_PKGS="$(pkgs -u)"     # includes packages removed for the user
  DISABLED="$(pkgs -d)"
}

require_device() {
  local state
  state="$(adbc get-state 2>/dev/null || true)"
  [[ "$state" == "device" ]] || die "no device connected. Enable ADB debugging on the stick, then run: ./claudetv.sh connect <stick-ip>
(The Fire TV Stick 4K Select runs Vega OS and does not support ADB. See docs/vega-select.md.)"
  local maker
  maker="$(ash getprop ro.product.manufacturer)"
  [[ "$maker" == "Amazon" ]] || die "connected device is made by '$maker', not Amazon; refusing to continue"
}

confirm() {
  [[ $ASSUME_YES -eq 1 || $DRY_RUN -eq 1 ]] && return 0
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

cmd_connect() {
  [[ $# -eq 1 ]] || die "usage: connect <ip>"
  local target="$1"; [[ "$target" == *:* ]] || target="$target:5555"
  adb connect "$target"
  echo "If the stick shows an 'Allow USB debugging?' prompt, accept it, then run ./claudetv.sh info"
}

cmd_info() {
  require_device
  local model device os
  model="$(ash getprop ro.product.model)"
  device="$(ash getprop ro.product.device)"
  os="$(ash getprop ro.build.version.name)"
  echo "Model:    $model"
  echo "Codename: $device"
  echo "Software: ${os:-unknown}"
  case "$device" in
    mantis) echo "This is the 1st-gen Fire TV Stick 4K (2018). Fully supported." ;;
    *)      echo "Not tested on this model. Fire OS devices should work; run 'scan' first and debloat with --dry-run." ;;
  esac
}

cmd_scan() {
  require_device
  load_state
  local p state
  grep '^com\.amazon\.' <<<"$ALL_PKGS" | sort | while read -r p; do
    if ! installed "$p"; then state="removed-for-user"
    elif grep -qxF "$p" <<<"$DISABLED"; then state="disabled"
    else state="enabled"; fi
    printf '%-18s %s\n' "$state" "$p"
  done
}

cmd_backup() {
  require_device
  mkdir -p "$BACKUPS"
  local serial file
  serial="$(ash getprop ro.serialno)"
  file="$BACKUPS/${serial:-device}-$(date +%Y%m%d-%H%M%S).txt"
  {
    echo "# claudetv backup $(date)"
    echo "# model: $(ash getprop ro.product.model)  software: $(ash getprop ro.build.version.name)"
    echo "## installed";        pkgs
    echo "## disabled";         pkgs -d
    echo "## known-to-user";    pkgs -u
  } > "$file"
  info "Saved $file"
}

disable_pkg() {
  local p="$1" out
  if is_protected "$p"; then echo "  protected     $p (never touched)"; return; fi
  if ! known_to_user "$p"; then echo "  not present   $p"; return; fi
  if ! installed "$p"; then echo "  already off   $p"; return; fi
  if grep -qxF "$p" <<<"$DISABLED"; then echo "  already off   $p"; return; fi
  if [[ $DRY_RUN -eq 1 ]]; then echo "  would disable $p"; return; fi

  out="$(ash pm disable-user --user 0 "$p")"
  if grep -q 'new state: disabled' <<<"$out"; then echo "  disabled      $p"; return; fi
  # Some Fire OS builds block disable-user for system apps; removing for the user is still reversible.
  out="$(ash pm uninstall -k --user 0 "$p")"
  if grep -q 'Success' <<<"$out"; then echo "  removed(user) $p"; return; fi
  echo "  FAILED        $p: $(head -1 <<<"$out")"
}

cmd_debloat() {
  require_device
  local lists=("$@"); [[ ${#lists[@]} -gt 0 ]] || lists=("${DEFAULT_LISTS[@]}")
  local l
  for l in "${lists[@]}"; do
    [[ "$l" != protected ]] || die "'protected' is the list of packages never to touch"
    read_list "$l" >/dev/null   # validate names before changing anything
  done
  if printf '%s\n' "${lists[@]}" | grep -qx updates; then
    echo "WARNING: the 'updates' list blocks system updates, including security fixes."
    confirm "Disable system updates anyway?" || die "aborted"
  fi
  if [[ $DRY_RUN -eq 0 ]]; then
    cmd_backup
    confirm "Disable packages from: ${lists[*]}?" || die "aborted"
  fi
  load_state
  local p
  for l in "${lists[@]}"; do
    info "List: $l"
    while read -r p; do disable_pkg "$p"; done < <(read_list "$l")
  done
  [[ $DRY_RUN -eq 1 ]] && info "Dry run: nothing was changed." || info "Done. Reboot the stick to apply everything: adb reboot"
}

enable_pkg() {
  local p="$1" out
  if ! known_to_user "$p"; then echo "  not present   $p"; return; fi
  if [[ $DRY_RUN -eq 1 ]]; then echo "  would enable  $p"; return; fi
  if ! installed "$p"; then
    out="$(ash cmd package install-existing "$p")"
    grep -q 'installed' <<<"$out" || out="$(ash pm install-existing "$p")"
    grep -q 'installed' <<<"$out" || { echo "  FAILED        $p: $(head -1 <<<"$out")"; return; }
  fi
  out="$(ash pm enable "$p")"
  if grep -q 'new state: enabled' <<<"$out"; then echo "  enabled       $p"
  else echo "  FAILED        $p: $(head -1 <<<"$out")"; fi
}

cmd_restore() {
  require_device
  local targets=("$@")
  if [[ ${#targets[@]} -eq 0 ]]; then
    local l
    mapfile -t targets < <(for l in $(list_names); do read_list "$l"; done | sort -u)
  fi
  load_state
  info "Re-enabling ${#targets[@]} package(s)"
  local p
  for p in "${targets[@]}"; do enable_pkg "$p"; done
  [[ $DRY_RUN -eq 1 ]] || info "Done. Reboot the stick: adb reboot"
}

cmd_launcher() {
  [[ $# -eq 1 && -f "$1" ]] || die "usage: launcher <path-to-launcher.apk>"
  require_device
  if [[ $DRY_RUN -eq 1 ]]; then info "Would install $1"; return; fi
  adbc install -r "$1"
  cat <<'EOF'
Installed. Fire OS doesn't let you change the default home screen, so open the new launcher and
turn on its "override current launcher" / home-button option in its settings. That uses an
accessibility service, which you must allow when the launcher asks.
EOF
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1; shift ;;
      --yes|-y)  ASSUME_YES=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) break ;;
    esac
  done
  [[ $# -gt 0 ]] || { usage; exit 1; }
  local cmd="$1"; shift
  case "$cmd" in
    connect|info|scan|backup|debloat|restore|launcher) command -v adb >/dev/null || die "adb not found. Install Android platform-tools first."
                                                       "cmd_$cmd" "$@" ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
