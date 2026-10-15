#!/usr/bin/env bash
# Exercise the installer with fixture downloads; no external files or services.
set -eo pipefail
((BASH_VERSINFO[0] >= 4)) || { echo 'Bash 4+ required'; exit 1; }
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
source <(sed -n '/^colorize() {/,/^install_jq() {/p' "$repo_dir/bh.sh" | sed '$d')
source <(sed -n '/^download_bh() {/,/^install_jq$/p' "$repo_dir/bh.sh" | sed '$d')
source <(sed -n '/^declare -A CONFIG/,/^SERVER_IP=/p' "$repo_dir/bh.sh" | sed '$d')
source <(sed -n '/^update_script() {/,/^configure_tunnel() {/p' "$repo_dir/bh.sh" | sed '$d')
colorize() { printf '%s\n' "$2"; }
press_key() { :; }
sleep() { :; }
fail() { echo "FAIL: $*" >&2; exit 1; }
config_dir="$test_dir/configs"
mkdir -p "$config_dir" "$test_dir/bin"
curl() {
    printf '%s\n' "$*" >> "$test_dir/downloads.log"
    local output arg
    while (($#)); do
        arg="$1"; shift
        if [[ "$arg" == -o ]]; then output="$1"; shift; fi
    done
    [[ "${download_failure:-false}" == false ]] || return 22
    printf '%s\n' "${download_body:-#!/bin/bash}" > "$output"
}
# Linux mv -T isn't available in the macOS test environment.
mv() {
    [[ "$1" == -fT ]] && { shift; command mv -f "$@"; return; }
    command mv "$@"
}
download_body=core-fixture
download_bh '' > /dev/null
[[ -x "$config_dir/backhaul_premium" ]] || fail 'download not installed under the service executable name'
[[ "$(cat "$config_dir/backhaul_premium")" == core-fixture ]] || fail 'core content changed'
[[ ! -e "$config_dir/bh" ]] || fail 'download name leaked into installed executable path'
grep -q 'https://raw.githubusercontent.com/MatinDehghanian/bh/refs/heads/main/bh$' "$test_dir/downloads.log" || fail 'wrong core URL'
download_failure=true
if (download_bh menu > /dev/null); then fail 'failed core download reported success'; fi
[[ "$(cat "$config_dir/backhaul_premium")" == core-fixture ]] || fail 'failed download replaced core'
download_failure=false
# Redirect only this function's install directory into the isolated fixture.
eval "$(declare -f update_script | sed "s@/usr/bin@$test_dir/bin@g")"
download_body=$'#!/bin/bash\nprintf "BH\\n"'
(update_script > /dev/null)
[[ -x "$test_dir/bin/bh" ]] || fail 'bh command not installed'
[[ "$("$test_dir/bin/bh")" == BH ]] || fail 'installed command failed'
grep -q 'https://raw.githubusercontent.com/MatinDehghanian/bh/refs/heads/main/bh.sh$' "$test_dir/downloads.log" || fail 'wrong script URL'
cp "$test_dir/bin/bh" "$test_dir/before.sh"
download_body='not a shell script'
if (update_script > /dev/null); then fail 'invalid script accepted'; fi
cmp "$test_dir/before.sh" "$test_dir/bin/bh"
# New links use the public name; older links remain usable.
for scheme in bh bh-test; do
    link=$(encode_bh_link "$scheme" '{"v":1}')
    [[ "$link" == "$scheme://1."* ]] || fail 'wrong public link scheme'
    [[ "$(decode_bh_link "$scheme" "$link" | jq -r .v)" == 1 ]] || fail 'new link rejected'
    legacy="backhaul${scheme#bh}://1.${link#*://1.}"
    [[ "$(decode_bh_link "$scheme" "$legacy" | jq -r .v)" == 1 ]] || fail 'previous link rejected'
done
EDIT_VALUES[ports.forwarder]='"backhaul"'
edit_prompt_field ports.forwarder '"backhaul"' <<< '' > "$test_dir/editor.log"
[[ "$(edit_value ports.forwarder)" == backhaul ]] || fail 'engine forwarder enum changed'
[[ "$(edit_display_value ports.forwarder)" == BH ]] || fail 'forwarder display name'
if grep -qi backhaul "$test_dir/editor.log"; then fail 'legacy name in forwarder prompt'; fi
echo 'PASS: renamed core download, install-time rename, bh command, failed-update preservation and link/forwarder compatibility'
