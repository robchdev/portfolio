#!/usr/bin/env bash
# tcl-tv-boost — speed up a slow TCL Android TV / Google TV over ADB.
#
#   ./tcl-tv-boost.sh <TV_IP> [--launcher] [--dry-run] [-y]
#   ./tcl-tv-boost.sh <TV_IP> --restore [backup-file]
#
# Every change is written to a backup file first, so --restore puts the TV
# back exactly as it was. Nothing is uninstalled: apps are only disabled.
# MIT License. Use at your own risk.

set -u

# Packages to disable. Edit freely: delete a line to keep that app.
# Only packages that exist and are enabled on your TV are touched.
BLOAT_PACKAGES="
com.tcl.bi                          # TCL usage analytics
com.tcl.smartalexa                  # Alexa integration
com.tcl.usercenter                  # TCL account
com.tcl.MultiScreenInteraction_TV   # TCL phone mirroring app
com.tcl.esticker                    # on-screen stickers/ads
com.tcl.notereminder                # TCL reminders
com.tcl.gamebar                     # game overlay
com.tcl.messagebox                  # TCL promo messages
com.tcl.overseasappshow             # app recommendations
com.tcl.copydatatotv                # phone-to-TV data copy
com.google.android.play.games       # Google Play Games
com.google.android.videos           # Google TV / Play Movies
com.android.messaging               # SMS app (useless on a TV)
com.android.camera2                 # camera app (useless on a TV)
tv.wuaki.apptv                      # Rakuten TV (preinstalled)
com.google.android.apps.tv.dreamx   # Google screensaver
"

ANIM_SCALE=0.5
LAUNCHER_PKG=com.spocky.projengmenu            # Projectivy Launcher (free, Play Store)
GOOGLE_LAUNCHER=com.google.android.apps.tv.launcherx
SETUP_WRAITH=com.google.android.tungsten.setupwraith

DRY_RUN=0; ASSUME_YES=0; DO_LAUNCHER=0; RESTORE=0; RESTORE_FILE=""; TARGET=""

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
die()  { printf 'Error: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --launcher) DO_LAUNCHER=1 ;;
    --dry-run)  DRY_RUN=1 ;;
    -y|--yes)   ASSUME_YES=1 ;;
    --restore)  RESTORE=1
                if [ $# -gt 1 ] && [ "${2#-}" = "$2" ]; then RESTORE_FILE=$2; shift; fi ;;
    -h|--help)  usage 0 ;;
    -*)         die "unknown option $1 (see --help)" ;;
    *)          [ -z "$TARGET" ] || die "only one TV address, please"; TARGET=$1 ;;
  esac
  shift
done
[ -n "$TARGET" ] || usage 1
command -v adb >/dev/null 2>&1 || die "adb not found. Install Android platform-tools first."

confirm() {
  [ "$ASSUME_YES" = 1 ] && return 0
  printf '%s [y/N] ' "$1"; read -r a
  case "$a" in y|Y|yes|s|S|si) return 0 ;; *) return 1 ;; esac
}

# ---- connection -------------------------------------------------------------

case "$TARGET" in *:*) SERIAL=$TARGET ;; *.*) SERIAL=$TARGET:5555 ;; *) SERIAL=$TARGET ;; esac
case "$SERIAL" in *.*:*)
  say "Connecting to $SERIAL ... (accept the prompt on the TV if it appears)"
  adb connect "$SERIAL" >/dev/null 2>&1 ;;
esac
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ "$(adb -s "$SERIAL" get-state 2>/dev/null)" = device ] && break
  sleep 1
done
[ "$(adb -s "$SERIAL" get-state 2>/dev/null)" = device ] || die "cannot reach $SERIAL.
  - Is the TV on and on the same network?
  - Settings > System > About > tap 'Build' 7 times, then
    Settings > System > Developer options > USB debugging (and Network debugging if present): ON"

sh_tv()  { adb -s "$SERIAL" shell "$@" </dev/null 2>/dev/null | tr -d '\r'; }
run_tv() {  # state-changing command: printed in dry-run, executed otherwise
  if [ "$DRY_RUN" = 1 ]; then say "  [dry-run] adb shell $*"; else sh_tv "$@" >/dev/null; fi
}

BRAND=$(sh_tv getprop ro.product.manufacturer)
MODEL=$(sh_tv getprop ro.product.model)
SDK=$(sh_tv getprop ro.build.version.sdk)
RELEASE=$(sh_tv getprop ro.build.version.release)
say "Connected: $BRAND $MODEL, Android $RELEASE (SDK $SDK)"

SAFE_ID=$(printf '%s' "$BRAND-$MODEL-$SERIAL" | tr -c 'A-Za-z0-9._-' '_')
BACKUP_DIR="${TCL_BOOST_BACKUPS:-$HOME/.tcl-tv-boost}"

pkg_enabled() { sh_tv pm list packages -e "$1" | grep -qx "package:$1"; }
pkg_present() { sh_tv pm list packages "$1" | grep -qx "package:$1"; }
current_home() { sh_tv cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tail -1; }
resumed_activity() { sh_tv dumpsys activity activities | grep -m1 -E 'mResumedActivity|topResumedActivity'; }

# ---- restore ------------------------------------------------------------------

if [ "$RESTORE" = 1 ]; then
  if [ -z "$RESTORE_FILE" ]; then
    RESTORE_FILE=$(ls -t "$BACKUP_DIR/$SAFE_ID"-*.backup 2>/dev/null | head -1)
  fi
  [ -n "$RESTORE_FILE" ] && [ -f "$RESTORE_FILE" ] || die "no backup found for this TV in $BACKUP_DIR"
  say "Restoring from $RESTORE_FILE"
  confirm "Put the TV back as it was?" || exit 0
  # Undo in reverse order (e.g. re-enable the old launcher before making it home again)
  while read -r kind key value; do
    case "$kind" in
      setting)  if [ "$value" = null ]; then run_tv settings delete global "$key"
                else run_tv settings put global "$key" "$value"; fi
                say "  setting $key -> $value" ;;
      disabled) run_tv pm enable "$key"; say "  re-enabled $key" ;;
      home)     run_tv cmd package set-home-activity --user 0 "$key"; say "  home -> $key" ;;
    esac
  done <<EOF
$(awk '{ l[NR] = $0 } END { for (i = NR; i > 0; i--) print l[i] }' "$RESTORE_FILE")
EOF
  run_tv input keyevent KEYCODE_HOME
  say "Done. Restart the TV to finish (hold the power button > Restart)."
  exit 0
fi

# ---- boost -----------------------------------------------------------------------

case "$BRAND" in *[Tt][Cc][Ll]*) ;; *)
  say "Note: this is not a TCL. The script should be safe on any Android TV, but the list was tested on TCL."
  confirm "Continue anyway?" || exit 0 ;;
esac

BACKUP=/dev/null
if [ "$DRY_RUN" = 0 ]; then
  mkdir -p "$BACKUP_DIR" || die "cannot create $BACKUP_DIR"
  BACKUP="$BACKUP_DIR/$SAFE_ID-$(date +%Y%m%d-%H%M%S).backup"
  : > "$BACKUP"
fi
note() { printf '%s\n' "$*" >> "$BACKUP"; }

FREE_BEFORE=$(sh_tv cat /proc/meminfo | awk '/MemAvailable/ {print int($2/1024)}')

step "Plan"
say "  - animations: ${ANIM_SCALE}x (snappier menus)"
[ "${SDK:-0}" -ge 30 ] && say "  - freeze cached background apps (saves RAM)"
TO_DISABLE=""
for p in $(printf '%s\n' "$BLOAT_PACKAGES" | sed 's/#.*//'); do
  pkg_enabled "$p" && TO_DISABLE="$TO_DISABLE $p"
done
if [ -n "$TO_DISABLE" ]; then
  say "  - disable these apps:"; for p in $TO_DISABLE; do say "      $p"; done
else
  say "  - no listed apps to disable (already done, or not on this TV)"
fi
[ "$DO_LAUNCHER" = 1 ] && say "  - replace the Google home screen with Projectivy Launcher"
say "  - optimize installed apps (background compile)"
[ "$DRY_RUN" = 1 ] && say "  (dry run: nothing will be changed)"
confirm "Apply?" || exit 0

step "Animations and memory"
for k in window_animation_scale transition_animation_scale animator_duration_scale; do
  note "setting $k $(sh_tv settings get global "$k")"
  run_tv settings put global "$k" "$ANIM_SCALE"
done
if [ "${SDK:-0}" -ge 30 ]; then
  note "setting cached_apps_freezer $(sh_tv settings get global cached_apps_freezer)"
  run_tv settings put global cached_apps_freezer enabled
fi
say "  ok"

step "Disabling apps"
for p in $TO_DISABLE; do
  note "disabled $p"
  run_tv pm disable-user --user 0 "$p"
  [ "$DRY_RUN" = 1 ] || say "  $p"
done

if [ "$DO_LAUNCHER" = 1 ]; then
  step "Launcher"
  if ! pkg_present "$LAUNCHER_PKG"; then
    say "  Opening Projectivy Launcher in the Play Store on the TV. Install it with the remote."
    run_tv am start -a android.intent.action.VIEW -d "market://details?id=$LAUNCHER_PKG"
    if [ "$DRY_RUN" = 0 ]; then
      printf '  Press Enter here when it is installed... '; read -r _
    fi
  fi
  if [ "$DRY_RUN" = 0 ] && ! pkg_present "$LAUNCHER_PKG"; then
    say "  Projectivy is not installed: skipping the launcher step (the Google home stays)."
  else
    COMP=$(sh_tv cmd package query-activities --components -a android.intent.action.MAIN -c android.intent.category.HOME | grep -m1 "^$LAUNCHER_PKG/")
    COMP=${COMP:-$LAUNCHER_PKG/.ui.home.MainActivity}
    note "home $(current_home)"
    run_tv cmd package set-home-activity --user 0 "$COMP"
    if pkg_enabled "$GOOGLE_LAUNCHER"; then
      note "disabled $GOOGLE_LAUNCHER"
      run_tv pm disable-user --user 0 "$GOOGLE_LAUNCHER"
    fi
    if [ "$DRY_RUN" = 0 ]; then
      sh_tv input keyevent KEYCODE_HOME; sleep 3
      # Some Google TV builds send HOME to a setup "recovery" screen once launcherx is gone.
      if resumed_activity | grep -q "$SETUP_WRAITH" && pkg_enabled "$SETUP_WRAITH"; then
        note "disabled $SETUP_WRAITH"
        run_tv pm disable-user --user 0 "$SETUP_WRAITH"
        run_tv cmd package set-home-activity --user 0 "$COMP"
        sh_tv input keyevent KEYCODE_HOME; sleep 3
      fi
      if resumed_activity | grep -q "$LAUNCHER_PKG"; then
        say "  Projectivy is now the home screen."
      else
        say "  Projectivy did not take over: undoing the launcher changes for safety."
        run_tv pm enable "$GOOGLE_LAUNCHER"
        pkg_present "$SETUP_WRAITH" && run_tv pm enable "$SETUP_WRAITH"
        run_tv input keyevent KEYCODE_HOME
      fi
    else
      say "  [dry-run] would verify the home screen and undo it if Projectivy does not open"
    fi
  fi
fi

step "Optimizing apps (can take a few minutes)"
run_tv cmd package bg-dexopt-job
say "  ok"

step "Done"
if [ "$DRY_RUN" = 0 ]; then
  say "  Backup: $BACKUP"
  say "  Undo everything:  $0 $TARGET --restore"
  FREE_NOW=$(sh_tv cat /proc/meminfo | awk '/MemAvailable/ {print int($2/1024)}')
  say "  Free RAM now: ${FREE_NOW} MB (was ${FREE_BEFORE} MB). It improves further after a restart."
  if confirm "Restart the TV now?"; then sh_tv reboot; say "  Restarting."; fi
fi
