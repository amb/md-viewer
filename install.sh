#!/bin/zsh
set -eu

usage() {
  echo 'Usage: ./install.sh [--no-build] [--user | APPLICATIONS_DIR]'
  echo "Build and install MD View into /Applications (or ~/Applications with --user)."
}

project_dir="${0:A:h}"
apps_dir=/Applications
build=true
destination_set=false
while (( $# )); do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --no-build) build=false ;;
    --user) $destination_set && { usage >&2; exit 2; }; apps_dir="$HOME/Applications"; destination_set=true ;;
    -*) usage >&2; exit 2 ;;
    *) $destination_set && { usage >&2; exit 2; }; apps_dir="$1"; destination_set=true ;;
  esac
  shift
done
apps_dir="${apps_dir:A}"
source_app="$project_dir/dist/MD View.app"
target_app="$apps_dir/MD View.app"
[[ "$source_app" != "$target_app" ]] || { echo "Choose a destination outside dist/." >&2; exit 1; }

cd "$project_dir"
if $build; then ./build_app.sh; fi
[[ -x "$source_app/Contents/MacOS/MDView" ]] || { echo "Build missing; run ./build_app.sh first." >&2; exit 1; }
/usr/bin/codesign --verify --strict "$source_app"
if [[ -L "$target_app" ]]; then
  echo "Refusing to replace a symlink: $target_app" >&2; exit 1
fi
if [[ -e "$target_app" ]]; then
  existing_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target_app/Contents/Info.plist" 2>/dev/null || true)
  [[ "$existing_id" == local.mdview.app ]] || { echo "Refusing to replace another app: $target_app" >&2; exit 1; }
fi
/bin/mkdir -p "$apps_dir"
[[ -w "$apps_dir" ]] || { echo "Cannot write $apps_dir; try --user." >&2; exit 1; }

stage=$(/usr/bin/mktemp -d "$apps_dir/.md-view-install.XXXXXX")
cleanup() {
  local install_result=$?
  trap - EXIT
  if [[ -d "$stage/previous.app" && ! -e "$target_app" ]]; then
    if ! /bin/mv "$stage/previous.app" "$target_app"; then
      echo "Restore failed; previous app retained in $stage/previous.app" >&2
      exit 1
    fi
  fi
  /bin/rm -rf -- "$stage"
  exit "$install_result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
/usr/bin/ditto "$source_app" "$stage/MD View.app"
/usr/bin/codesign --verify --strict "$stage/MD View.app"
# ditto preserves the old bundle date; refresh it so macOS notices updated icons.
/usr/bin/touch "$stage/MD View.app"
if [[ -e "$target_app" ]]; then /bin/mv "$target_app" "$stage/previous.app"; fi
/bin/mv "$stage/MD View.app" "$target_app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$target_app"
echo "Installed $target_app"
echo 'Run: open -a "MD View"'
echo 'If MD View is already running, quit and reopen it to use this installation.'
