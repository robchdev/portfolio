#!/usr/bin/env bash
# tv-boost — speed up a slow Android TV / Google TV over ADB (TCL, Sony, Xiaomi,
# Philips, Hisense, Nvidia Shield, Chromecast and most other brands).
#
#   ./tv-boost.sh <TV_IP> --scan                 show what would change, touch nothing
#   ./tv-boost.sh <TV_IP> [--launcher] [--dry-run] [-y]
#   ./tv-boost.sh <TV_IP> --restore [backup-file]
#
# Every change is written to a backup file first, so --restore puts the TV
# back exactly as it was. Nothing is uninstalled: apps are only disabled.
# MIT License. Use at your own risk.

set -u

# ---- what gets disabled --------------------------------------------------------
# Only telemetry, ads, shop-demo and promo services. Each list comes from
# debloat lists tested on real TVs (cleanyourtv, Universal Android Debloater).
# A package is touched only if it exists and is enabled on your TV, so lists
# for other brands do nothing on yours. Delete a line to keep that app.

GOOGLE_COMMON="
com.google.android.feedback                 # feedback reporting
com.android.tv.feedbackconsent              # feedback consent screen
com.google.android.tv.bugreportsender       # bug report uploader
com.google.android.partnersetup             # partner/referral setup
com.google.android.apps.tv.netoscope        # connectivity diagnostics
com.android.printspooler                    # printing (no printers on a TV)
com.android.dynsystem                       # developer system images
com.android.adservices.api                  # ad services (Privacy Sandbox)
com.android.ondevicepersonalization.services # ad personalization
com.android.federatedcompute.services       # ad/ML training jobs
com.google.android.play.games               # Play Games
com.google.android.videos                   # Google TV Shop / Play Movies
com.google.android.apps.tv.dreamx           # Google TV ambient screensaver
com.google.android.backdrop                 # Android TV ambient screensaver
com.android.messaging                       # SMS app (useless on a TV)
com.android.camera2                         # camera app (useless on a TV)
"

TRACKING_AND_DEMO="
tv.samba.ssm                                # Samba TV: recognises what is on screen
tv.samba.ssm.ui
tv.anoki.acr.anokiacroptin                  # Anoki screen recognition
tv.anoki.acr.controller
tv.inscape.tvclient.inscapeacr              # Inscape screen recognition
com.smartdevice.acr.recommendation          # Skyworth/Coocaa screen recognition
fusion.android.tv.demo                      # shop demo mode
com.smartdevice.common.demonow              # shop demo mode
com.smartdevice.epopplayer                  # shop promo player
"

TCL="
com.tcl.bi                                  # analytics
com.tcl.logkit                              # log upload
com.tcl.esticker                            # shop energy-label sticker
com.tcl.tv.tclhome_passive                  # pushes TCL content to the home screen
com.tcl.waterfall.overseas                  # TCL Channel promo browser
com.tcl.channelplus                         # ad-funded FAST channels
com.tcl.overseasappshow                     # app recommendations
com.tcl.repairguide                         # repair guide
com.tcl.ocean.instructions                  # e-manual
com.tcl.usercenter                          # TCL account nags
com.tcl.smartalexa                          # Alexa skill
com.tcl.notereminder                        # TCL reminders
com.tcl.copydatatotv                        # phone-to-TV data copy
com.apps.esticker                           # shop sticker (TCL/Thomson boards)
com.apps.channels                           # S-Channel promo rows
com.apps.function.gdpr                      # data-consent agent
"

SONY="
com.sony.dtv.sonyselect                     # Sony Select promo tile
com.sony.dtv.da.service                     # device agent
com.qterics.da.product                      # device agent telemetry
com.sony.dtv.multiscreendemo                # shop demo
com.sony.dtv.demosupport                    # shop demo
com.sony.dtv.demosystemsupport              # shop demo
com.sony.dtv.demomode                       # shop demo
com.sony.dtv.customersupport                # help tile
com.sony.dtv.smarthelp                      # help
com.sony.dtv.promos                         # promos
com.sony.dtv.sonybugreportsys               # bug report uploader
com.sony.dtv.imanual                        # i-Manual
com.sony.dtv.discovery                      # Discover bar
com.sony.dtv.bivlinfo                       # feeds Discover
com.sony.dtv.sonytab                        # Sony tab on the Google TV home
com.sony.dtv.notificationcenter             # Sony promo notifications
com.sonyericsson.idd.agent                  # usage data
"

XIAOMI="
com.miui.tv.analytics                       # analytics
com.xiaomi.statistic                        # usage stats
com.xm.webcontent                           # web promos
com.mitv.tvhome.michannel                   # Mi Channel rows
com.mitv.tvhome.mitvplus                    # Mi TV+ ad-funded channels
com.mitv.tvhome.oemtab                      # ad row
com.xiaomi.floatingframe                    # floating promo overlay
com.xiaomi.mitv.handbook                    # handbook
com.xiaomo.tv.milegal                       # legal notices
com.mitv.download.service                   # background downloads
com.xiaomi.android.tvsetup.partnercustomizer # installs partner apps at setup
"

PHILIPS="
org.droidtv.demome                          # shop demo
org.droidtv.nettvrecommender                # Top Picks promo row
org.droidtv.recommendation                  # its backend
org.droidtv.usagelogger                     # usage telemetry
org.droidtv.candeebug                       # analytics uploader
org.droidtv.gel                             # metrics collector
org.droidtv.nettv.market                    # Smart TV Collection store (Play Store stays)
"

HISENSE="
com.hisense.service.message                 # push messages
com.hisense.evservice                       # screen recognition
com.hisense.storemode                       # shop demo
com.hisense.demonstrate                     # demo reels
com.hisense.app.logreport                   # log reporter
com.hisense.logupload                       # log upload
com.hisense.platformreport                  # reporting
com.hisense.business.ad                     # ads
com.hisense.service.ad                      # ads
"

OTHERS="
com.nvidia.feedback                         # Nvidia: feedback
com.nvidia.diagtools                        # Nvidia: log collector
com.nvidia.stats                            # Nvidia: usage stats
com.smartdevice.recommendation              # Skyworth/Coocaa: promo rows
com.smartdevice.leanbacklauncher.customizer # Skyworth: injects home rows
com.smartdevice.recordactivation            # Skyworth: activation tracking
com.Smartdevice.emanual                     # Skyworth/Panasonic: e-manual
com.panasonic.demomode                      # Panasonic: shop demo
com.haier.tvhousekeeper                     # Haier: cleaner
com.haier.oemtabprovider                    # Haier: promo tab
com.xgimi.bugreportsender                   # XGIMI: bug reports
"

# Never disabled, whatever the lists say: inputs, remote, updates, store, keyboard...
PROTECTED="
com.android.vending com.google.android.gms com.google.android.gsf com.android.location.fused
com.android.tv.settings com.android.systemui com.android.packageinstaller com.android.providers.tv
com.google.android.tungsten.setupwraith com.google.android.katniss com.google.android.apps.mediashell
com.google.android.tv.remote.service com.google.android.tv.axel com.google.android.tvrecommendations
com.tcl.tv com.tcl.tvinput com.tcl.suspension com.tcl.ttvs com.tcl.messagebox com.tcl.providers.config
com.tcl.initsetup com.tcl.tcl_bt_rcu_service com.tcl.autopair com.tcl.partnercustomizer com.tcl.settings
com.tcl.system.server com.tcl.systemserver com.tcl.guard com.tcl.useragreement com.tcl.dashboard
com.sony.dtv.tvx com.sony.dtv.ecodashboard
"

ANIM_SCALE=0.5
LAUNCHER_PKG=com.spocky.projengmenu            # Projectivy Launcher (free, Play Store)

DRY_RUN=0; ASSUME_YES=0; DO_LAUNCHER=0; RESTORE=0; SCAN=0; RESTORE_FILE=""; TARGET=""

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
die()  { printf 'Error: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --launcher) DO_LAUNCHER=1 ;;
    --dry-run)  DRY_RUN=1 ;;
    --scan)     SCAN=1; DRY_RUN=1 ;;
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
BACKUP_DIR="${TV_BOOST_BACKUPS:-$HOME/.tv-boost}"
OLD_BACKUP_DIR="$HOME/.tcl-tv-boost"   # backups made by tcl-tv-boost.sh

ENABLED=$(sh_tv pm list packages -e | sed 's/^package://')
is_enabled()   { printf '%s\n' "$ENABLED" | grep -qxF "$1"; }
is_protected() { printf '%s\n' $PROTECTED | grep -qxF "$1"; }
pkg_present()  { sh_tv pm list packages "$1" | grep -qx "package:$1"; }
current_home() { sh_tv cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tail -1; }
resumed_activity() { sh_tv dumpsys activity activities | grep -m1 -E 'mResumedActivity|topResumedActivity'; }
names() { printf '%s\n' "$@" | sed 's/#.*//' | tr -s ' \t' '\n' | grep -v '^$'; }

# ---- restore ------------------------------------------------------------------

if [ "$RESTORE" = 1 ]; then
  if [ -z "$RESTORE_FILE" ]; then
    RESTORE_FILE=$(ls -t "$BACKUP_DIR/$SAFE_ID"-*.backup "$OLD_BACKUP_DIR/$SAFE_ID"-*.backup 2>/dev/null | head -1)
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
      secure)   if [ "$value" = null ]; then run_tv settings delete secure "$key"
                else run_tv settings put secure "$key" "$value"; fi
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

# ---- plan ------------------------------------------------------------------------

TO_DISABLE=""
for p in $(names "$GOOGLE_COMMON" "$TRACKING_AND_DEMO" "$TCL" "$SONY" "$XIAOMI" "$PHILIPS" "$HISENSE" "$OTHERS"); do
  is_enabled "$p" && ! is_protected "$p" && TO_DISABLE="$TO_DISABLE $p"
done
# Play auto-install configs: they only reinstall partner apps after an update or reset.
for p in $(printf '%s\n' "$ENABLED" | grep '^android\.autoinstalls\.config\.'); do
  TO_DISABLE="$TO_DISABLE $p"
done

if [ "$SCAN" = 1 ]; then
  step "Would be disabled on this TV"
  if [ -n "$TO_DISABLE" ]; then for p in $TO_DISABLE; do say "  $p"; done
  else say "  (nothing from the lists)"; fi
  step "Other system apps worth a look (NOT touched by the script)"
  KNOWN=" $TO_DISABLE $(names "$GOOGLE_COMMON" "$TRACKING_AND_DEMO" "$TCL" "$SONY" "$XIAOMI" "$PHILIPS" "$HISENSE" "$OTHERS" | tr '\n' ' ') "
  sh_tv pm list packages -s -e | sed 's/^package://' | sort | while read -r p; do
    case "$KNOWN" in *" $p "*) continue ;; esac
    is_protected "$p" && continue
    if printf '%s' "$p" | grep -qiE 'analytic|statist|telemetr|usage|logger|logkit|logreport|logupload|bugreport|feedback|report|acr|samba|demo|promo|recommend|advert|\.ad\.|adservice|sticker|emanual|manual|handbook|helpguide|smarthelp|partnercustom|autoinstall|market|appstore|channelplus|fast'; then
      say "  $p"
    fi
  done
  say ""
  say "  Brand: $BRAND $MODEL. If your brand is missing from the lists, send this output"
  say "  (and what each app does, if you know) to roberto.chiarelladev@gmail.com."
  say "  Nothing was changed."
  exit 0
fi

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
if [ -n "$TO_DISABLE" ]; then
  say "  - disable these apps:"; for p in $TO_DISABLE; do say "      $p"; done
else
  say "  - no listed apps to disable (already done, or none on this TV)"
fi
[ "$DO_LAUNCHER" = 1 ] && say "  - replace the home screen with Projectivy Launcher"
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
  if [ "$DRY_RUN" = 1 ]; then
    run_tv pm disable-user --user 0 "$p"
  elif sh_tv pm disable-user --user 0 "$p" | grep -q 'disabled'; then
    note "disabled $p"; say "  $p"
  else
    say "  $p: refused by the system, skipped"
  fi
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
  OLD_HOME=$(current_home)
  OLD_HOME_PKG=${OLD_HOME%%/*}
  if [ "$DRY_RUN" = 0 ] && ! pkg_present "$LAUNCHER_PKG"; then
    say "  Projectivy is not installed: skipping the launcher step (your home screen stays)."
  elif [ "$OLD_HOME_PKG" = "$LAUNCHER_PKG" ]; then
    say "  Projectivy is already the home screen."
  else
    COMP=$(sh_tv cmd package query-activities --components -a android.intent.action.MAIN -c android.intent.category.HOME | grep -m1 "^$LAUNCHER_PKG/")
    COMP=${COMP:-$LAUNCHER_PKG/.ui.home.MainActivity}
    note "home $OLD_HOME"
    run_tv cmd package set-home-activity --user 0 "$COMP"
    # The old home stays enabled: on Google TV it also handles the remote's app buttons
    # (Netflix, YouTube, Prime...). Projectivy's accessibility service sends Home to Projectivy.
    A11Y_SVC="$LAUNCHER_PKG/$LAUNCHER_PKG.services.ProjectivyAccessibilityService"
    A11Y_OLD=$(sh_tv settings get secure enabled_accessibility_services)
    case "$A11Y_OLD" in
      *"$A11Y_SVC"*) ;;
      *) note "secure enabled_accessibility_services $A11Y_OLD"
         note "secure accessibility_enabled $(sh_tv settings get secure accessibility_enabled)"
         if [ -z "$A11Y_OLD" ] || [ "$A11Y_OLD" = null ]; then A11Y_NEW=$A11Y_SVC; else A11Y_NEW="$A11Y_OLD:$A11Y_SVC"; fi
         run_tv settings put secure enabled_accessibility_services "$A11Y_NEW"
         run_tv settings put secure accessibility_enabled 1 ;;
    esac
    if [ "$DRY_RUN" = 0 ]; then
      sh_tv input keyevent KEYCODE_HOME; sleep 3
      if resumed_activity | grep -q "$LAUNCHER_PKG"; then
        say "  Projectivy is now the home screen."
      else
        say "  The old home screen still answers the Home button. On the TV open"
        say "  Projectivy > Settings > General and turn on \"Override current launcher\"."
      fi
    else
      say "  [dry-run] would check that Home opens Projectivy"
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
