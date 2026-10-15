#!/usr/bin/env bash
# Configuration-only checks: no Backhaul process, service or network changes.
set -eo pipefail
((BASH_VERSINFO[0] >= 4)) || { echo 'Bash 4+ required'; exit 1; }
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
source <(sed -n '/^colorize() {/,/^install_jq() {/p' "$repo_dir/backhaul.sh" | sed '$d')
source <(sed -n '/^declare -A CONFIG/,/^SERVER_IP=/p' "$repo_dir/backhaul.sh" | sed '$d')
SERVER_IP=192.0.2.1
colorize() { :; }
ip() { echo 'default via 192.0.2.254 dev eth0'; }
fail() { echo "FAIL: $*" >&2; exit 1; }
assert_value() { [[ "$(edit_value "$1")" == "$2" ]] || fail "$1: $(edit_value "$1") != $2"; }

# Both menu branches share the profile selection; only spoof asks for spoof IPs.
for encapsulation in ipx ipx-spoof; do
    for profile in icmp ipip udp tcp gre bip; do
        reset_config
        prompt_transport_section server > /dev/null <<< "$(printf 'tun\n%s\n' "$encapsulation")"
        answers=$(printf '%s\n\n192.0.2.2\n' "$profile")
        if [[ "$encapsulation" == ipx-spoof ]]; then
            answers+=$'\n203.0.113.2\n203.0.113.1'
        fi
        answers+=$'\neth0\n0\n0'
        prompt_ipx_section true server > /dev/null <<< "$answers"
        [[ "${CONFIG[ipx_profile]}" == "$profile" && "${CONFIG[ipx_interface]}" == eth0 ]] || fail 'IPX profile prompt sequence'
        if [[ "$encapsulation" == ipx-spoof ]]; then
            [[ "${CONFIG[ipx_custom_packet]}" == true && "${CONFIG[ipx_spoof_src_ip]}" == 203.0.113.2 ]] || fail 'spoof branch'
        else
            [[ "${CONFIG[ipx_custom_packet]}" == false && -z "${CONFIG[ipx_spoof_src_ip]+present}" ]] || fail 'ordinary branch'
        fi
    done
done

reset_config
prompt_transport_section server > /dev/null <<'EOF'
tun
ipx-spoof
EOF
[[ "${CONFIG[transport_type]}" == tun && "${CONFIG[tun_encapsulation]}" == ipx && "${CONFIG[ipx_custom_packet]}" == true ]] || fail 'spoof selection'
prompt_ipx_section true server > /dev/null <<'EOF'
icmp

192.0.2.2
999.1.1.1
203.0.113.2
203.0.113.1



EOF
[[ "${CONFIG[ipx_profile]}" == icmp && "${CONFIG[ipx_spoof_src_ip]}" == 203.0.113.2 ]] || fail 'spoof prompts/defaults'
CONFIG[tun_name]=backhaul
CONFIG[tun_local_addr]=10.10.1.1/24
CONFIG[tun_remote_addr]=10.10.1.2/24
CONFIG[tun_health_port]=1234
CONFIG[tun_mtu]=1320
CONFIG[enable_encryption]=false
CONFIG[log_level]=debug
CONFIG[auto_tuning]=true
CONFIG[tuning_profile]=balanced
CONFIG[workers]=0
CONFIG[channel_size]=10_000
CONFIG[so_sndbuf]=0
CONFIG[batch_size]=2048
CONFIG[forwarder]=iptables
CONFIG[ports_mapping]=9090=9090
generate_toml_config server "$test_dir/iran1234.toml" true true
edit_mode=server
edit_load_config "$test_dir/iran1234.toml"
edit_normalize
assert_value ipx.custom_packet true
assert_value ipx.spoof_dst_ip 203.0.113.1
edit_write_config "$test_dir/roundtrip.toml"
link=$(peer_setup_link "$test_dir/iran1234.toml")
load_setup_link "$link" > /dev/null
assert_value ipx.mode client
assert_value ipx.listen_ip 192.0.2.2
assert_value ipx.dst_ip 192.0.2.1
assert_value ipx.spoof_src_ip 203.0.113.1
assert_value ipx.spoof_dst_ip 203.0.113.2
assert_value tun.local_addr 10.10.1.2/24
[[ -z "${EDIT_VALUES[ipx.interface]+present}" ]] || fail 'peer interface not cleared'
edit_mode=client
edit_write_config "$test_dir/kharej1234.toml"
EDIT_VALUES[ipx.spoof_src_ip]='"256.1.1.1"'
if validate_setup_settings > /dev/null; then fail 'invalid spoof address accepted'; fi
unset 'EDIT_VALUES[ipx.spoof_src_ip]'
if validate_setup_settings > /dev/null; then fail 'missing spoof address accepted'; fi
edit_load_config "$test_dir/kharej1234.toml"
EDIT_VALUES[ipx.custom_packet]=false
edit_normalize
[[ -z "${EDIT_VALUES[ipx.spoof_src_ip]+present}${EDIT_VALUES[ipx.spoof_dst_ip]+present}" ]] || fail 'disabled spoof addresses retained'
# Switching the mode through the editor must request both addresses.
EDIT_VALUES[ipx.custom_packet]=true
EDIT_VALUES[ipx.interface]='"eth1"'
edit_complete_transport > /dev/null <<'EOF'
203.0.113.1
203.0.113.2
EOF
assert_value ipx.spoof_src_ip 203.0.113.1
assert_value ipx.spoof_dst_ip 203.0.113.2
EDIT_VALUES[transport.type]='"tcp"'
edit_normalize
[[ -z "${EDIT_VALUES[ipx.custom_packet]+present}" ]] || fail 'IPX retained after transport switch'
# Every IPX profile supports custom_packet; absent values must emit false.
for profile in icmp ipip udp tcp gre bip; do
    CONFIG[ipx_profile]="$profile"
    unset 'CONFIG[ipx_custom_packet]'
    generate_toml_config server "$test_dir/default-$profile.toml" true true
    CONFIG[ipx_custom_packet]=true
    generate_toml_config server "$test_dir/custom-$profile.toml" true true
done
"${PYTHON:-python3}" - "$test_dir" <<'PY'
from pathlib import Path
import sys, tomllib
root = Path(sys.argv[1])
a, b, c = [tomllib.loads((root / f).read_text()) for f in ('iran1234.toml', 'roundtrip.toml', 'kharej1234.toml')]
for profile in ('icmp', 'ipip', 'udp', 'tcp', 'gre', 'bip'):
    default = tomllib.loads((root / f'default-{profile}.toml').read_text())['ipx']
    custom = tomllib.loads((root / f'custom-{profile}.toml').read_text())['ipx']
    assert default['profile'] == custom['profile'] == profile
    assert default['custom_packet'] is False
    assert 'spoof_src_ip' not in default and 'spoof_dst_ip' not in default
    assert custom['custom_packet'] is True
    assert custom['spoof_src_ip'] == '203.0.113.2'
    assert custom['spoof_dst_ip'] == '203.0.113.1'
assert a == b
assert a['transport']['type'] == c['transport']['type'] == 'tun'
assert a['tun']['encapsulation'] == c['tun']['encapsulation'] == 'ipx'
assert a['ipx']['custom_packet'] is c['ipx']['custom_packet'] is True
assert a['ipx']['spoof_src_ip'] == c['ipx']['spoof_dst_ip']
assert a['ipx']['spoof_dst_ip'] == c['ipx']['spoof_src_ip']
assert a['security']['enable_encryption'] is c['security']['enable_encryption'] is False
assert a['ports'] == {'forwarder': 'iptables', 'mapping': ['9090=9090']}
assert 'ports' not in c
print('PASS: spoof selection, prompts, TOML roundtrip, peer reversal, validation and editor transitions')
PY
