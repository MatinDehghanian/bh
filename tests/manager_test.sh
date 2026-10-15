#!/usr/bin/env bash
# Exercise real menu/wizard flows against temporary files and simulated services.
set -eo pipefail
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'status=$?; if ((status)); then tail -60 "$test_dir/output.log" >&2; fi; rm -rf "$test_dir"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Loading the library must not download, install, query hosts, or create directories.
(
    curl() { exit 80; }
    mkdir() { exit 81; }
    systemctl() { exit 82; }
    source "$repo_dir/bh.sh"
)
source "$repo_dir/bh.sh"
bash "$repo_dir/bh.sh" --help > "$test_dir/output.log"
[[ "$(bash "$repo_dir/bh.sh" --version)" == "$SCRIPT_VERSION" ]] || fail 'version flag'
config_dir="$test_dir/configs"
service_dir="$test_dir/services"
CERT_DIR="$test_dir/certs"
CERT_FILE="$CERT_DIR/cert.crt"
KEY_FILE="$CERT_DIR/cert.key"
SERVER_IP=192.0.2.10
mkdir -p "$config_dir" "$service_dir" "$CERT_DIR"
sleep() { :; }
press_key() { :; }
systemctl() {
    printf '%s\n' "$*" >> "$test_dir/services.log"
    case "$1" in
        list-units)
            printf '%s\n' 'backhaul-iran8443.service loaded active running BH' \
                'backhaul-kharej9443.service loaded failed failed BH'
            ;;
        enable|restart|is-active) [[ ! -f "$test_dir/fail-start" ]] || return 1 ;;
        disable) [[ ! -f "$test_dir/fail-stop" ]] || return 1 ;;
    esac
    return 0
}

for address in 192.0.2.1:1 example.org:65535 '[2001:db8::1]:8443' '[::1]:443' '[::ffff:192.0.2.1]:443' '[1:2:3:4:5:6:7:8]:443' '[::1:2:3:4:5:6:7]:443'; do
    valid_endpoint "$address" || fail "valid endpoint refused: $address"
done
for address in 999.1.1.1:443 host:0 host:65536 host:abc ':443' '-host:443' 'host..org:443' '[:::1]:443' '[1::2:]:443' '[:1::2]:443' '[1::2::3]:443' '[1:2]:443' '[1:2:3:4:5:6:7:8:9]:443'; do
    if valid_endpoint "$address"; then fail "invalid endpoint accepted: $address"; fi
done
if valid_choice 'tcp tcpmux ws' 'tcp tcpmux'; then fail 'multiple choices accepted as one'; fi
validate_setting tuning.workers 0 || fail 'auto workers rejected'
for pair in 'tun.mtu 0' 'tun.health_port 65536' 'mux.mux_version 3' 'ipx.icmp_type 256' 'security.kdf_iterations 0'; do
    read -r id value <<< "$pair"
    if validate_setting "$id" "$value"; then fail "bad value accepted: $pair"; fi
done
EDIT_VALUES[transport.type]='"tcp"'
for mappings in '443,,444' ',443' '443,' '500-443' '443=65536' '0'; do
    if edit_valid_mappings "$mappings"; then fail "bad mapping accepted: $mappings"; fi
done
prompt_boolean Example true CONFIG[example] <<< YES > "$test_dir/output.log"
[[ "${CONFIG[example]}" == true ]] || fail 'yes answer rejected'
if prompt_boolean Example true CONFIG[example] < /dev/null > "$test_dir/output.log"; then fail 'EOF accepted'; fi
if prompt_with_default Example x CONFIG[example] <<< /cancel > "$test_dir/output.log"; then fail 'cancel accepted'; fi
if read_option < /dev/null; then fail 'EOF did not exit home menu'; fi
if decode_bh_link bh "$(encode_bh_link bh '{"v":1}{"v":1}')" > "$test_dir/output.log" 2>&1; then fail 'multiple link payloads accepted'; fi
cat > "$test_dir/duplicate.toml" <<'EOF'
[transport]
type = "tcp"
[transport]
nodelay = true
EOF
if edit_load_config "$test_dir/duplicate.toml" > "$test_dir/output.log"; then fail 'duplicate TOML sections accepted'; fi
echo 'PASS: side-effect-free loading, CLI help/version, IPv4/IPv6, validation and EOF/cancellation'

# Only transport, address, token, ports and approval are needed for quick TCP setup.
configure_server server quick > "$test_dir/output.log" <<'EOF'



443,8443=443
y

EOF
[[ -f "$config_dir/iran8443.toml" && -f "$service_dir/backhaul-iran8443.service" ]] || fail 'quick setup not installed'
edit_mode=server
edit_load_config "$config_dir/iran8443.toml"
[[ "$(edit_value transport.type)" == tcp && "$(edit_value ports.mapping)" == '443, 8443=443' ]] || fail 'quick settings'
[[ ${#EDIT_VALUES[security.token]} -ge 64 ]] || fail 'random token missing'
if grep -q "$(edit_value security.token)" "$test_dir/output.log"; then fail 'raw token exposed'; fi
python3 - "$config_dir/iran8443.toml" <<'PY'
import os, sys, tomllib
with open(sys.argv[1], 'rb') as stream:
    config = tomllib.load(stream)
assert config['transport']['nodelay'] is True
assert config['transport']['accept_udp'] is False
assert config['tuning']['tuning_profile'] == 'balanced'
assert os.stat(sys.argv[1]).st_mode & 0o777 == 0o600
PY
echo 'PASS: complete quick-setup flow creates valid private TOML and the matching service'

# The selected tunnel menu stays open after a service action and handles Back.
tunnel_management > "$test_dir/output.log" <<'EOF'
1
5
0
0
EOF
grep -q '^restart backhaul-iran8443.service$' "$test_dir/services.log" || fail 'menu did not restart selected tunnel'
[[ "$(grep -c 'CONFIGURE & VERIFY' "$test_dir/output.log")" == 2 ]] || fail 'menu did not stay open after action'
echo 'PASS: tunnel navigation returns to the same tunnel after an action'

# Cancellation at the preview must leave no config or service behind.
configure_server server quick > "$test_dir/output.log" <<'EOF'
1
:9555

443
n
EOF
[[ ! -e "$config_dir/iran9555.toml" && ! -e "$service_dir/backhaul-iran9555.service" ]] || fail 'preview cancellation wrote files'
configure_server server quick <<< /cancel > "$test_dir/output.log"
configure_server server quick < /dev/null > "$test_dir/output.log"

# A failed start rolls back only the new files, preserving an existing tunnel.
cp "$config_dir/iran8443.toml" "$test_dir/before.toml"
touch "$test_dir/fail-start"
if configure_server server quick > "$test_dir/output.log" <<'EOF'
tcp
:9556

443
y
EOF
then fail 'failed start reported success'; fi
[[ ! -e "$config_dir/iran9556.toml" && ! -e "$service_dir/backhaul-iran9556.service" ]] || fail 'failed start left files'
cmp "$test_dir/before.toml" "$config_dir/iran8443.toml"
if restart_service backhaul-iran8443.service > "$test_dir/output.log"; then fail 'restart failure reported success'; fi
rm "$test_dir/fail-start"
echo 'PASS: cancelled/failed setup cleans up, restart errors propagate, existing tunnels survive'

# Deletion is opt-in and disables inactive services as well as active ones.
cp "$config_dir/iran8443.toml" "$config_dir/iran8443.toml.bak"
destroy_tunnel "$config_dir/iran8443.toml" <<< n > "$test_dir/output.log"
cmp "$test_dir/before.toml" "$config_dir/iran8443.toml"
touch "$test_dir/fail-stop"
if destroy_tunnel "$config_dir/iran8443.toml" <<< y > "$test_dir/output.log"; then fail 'failed stop permitted deletion'; fi
[[ -f "$config_dir/iran8443.toml" ]] || fail 'failed stop deleted config'
rm "$test_dir/fail-stop"
destroy_tunnel "$config_dir/iran8443.toml" <<< y > "$test_dir/output.log"
[[ ! -e "$config_dir/iran8443.toml" && ! -e "$config_dir/iran8443.toml.bak" && ! -e "$service_dir/backhaul-iran8443.service" ]] || fail 'delete incomplete'
grep -q '^disable --now backhaul-iran8443.service$' "$test_dir/services.log" || fail 'service not disabled'
echo 'PASS: deletion requires confirmation and a successful service stop, then removes backup too'

touch "$config_dir/iran8443.toml" "$service_dir/backhaul-iran8443.service"
touch "$config_dir/kharej9443.toml" "$service_dir/backhaul-kharej9443.service"
touch "$config_dir/iran9555.toml" "$config_dir/unknown.toml"
display_menu > "$test_dir/output.log"
grep -q '3 total  /  1 running  /  2 need attention' "$test_dir/output.log" || fail 'dashboard status counts'
if grep -q $'\033' "$test_dir/output.log"; then fail 'ANSI escapes in redirected output'; fi
[[ "${#TUNNEL_FILES[@]}" == 3 ]] || fail 'unknown config was included'
echo 'PASS: dashboard counts active/failed/missing services and redirected output has no ANSI escapes'

# Conflicting TUN names must not replace the current in-memory settings.
cat > "$config_dir/iran9555.toml" <<'EOF'
[transport]
type = "tun"
[tun]
name = "bh-test"
EOF
EDIT_VALUES=([transport.type]='"tun"' [tun.name]='"bh-test"' [security.token]='"keep-me"')
if check_tun_conflict "$config_dir/kharej1234.toml" > "$test_dir/output.log"; then fail 'duplicate TUN name accepted'; fi
[[ "$(edit_value security.token)" == keep-me ]] || fail 'conflict check changed edits'
echo 'PASS: TUN device collision detection preserves unsaved settings'

if command -v openssl >/dev/null; then
    generate_tls_certificate "$CERT_FILE" "$KEY_FILE" > "$test_dir/output.log"
    openssl x509 -in "$CERT_FILE" -checkend 0 -noout > /dev/null
    python3 - "$KEY_FILE" <<'PY'
import os, sys
assert os.stat(sys.argv[1]).st_mode & 0o777 == 0o600
PY
    cp "$KEY_FILE" "$test_dir/key-before"
    if (openssl() { return 1; }; generate_tls_certificate "$CERT_FILE" "$KEY_FILE") > "$test_dir/output.log"; then
        fail 'certificate generation failure was accepted'
    fi
    cmp "$KEY_FILE" "$test_dir/key-before"
    echo 'PASS: real TLS certificate generation uses private keys and preserves them on failure'
fi
