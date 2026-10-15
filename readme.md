# BH Script

Interactive Bash installer and tunnel manager for BH. Configure IRAN (server) and KHAREJ (client) tunnels, manage systemd services, view logs, and update the BH executable.

## Requirements

- A Linux server with systemd and root access.
- Bash 4 or newer, curl, and jq. When running as root, the script installs missing jq with apt-get directly; sudo is not required inside the script.
- OpenSSL for generating TLS certificates when needed.
- Access to raw.githubusercontent.com to download the script and executable.

The bundled `bh` executable targets Linux x86-64. Use a compatible server.

## Install and run

Run this command in a root Bash shell on each server:

```bash
bash <(curl -fLsS --ipv4 https://raw.githubusercontent.com/MatinDehghanian/bh/refs/heads/main/bh.sh)
```

If you are logged in as a non-root user, enter a root shell first:

```bash
sudo -i
```

To save the script locally and run it:

```bash
curl -fLsS --ipv4 https://raw.githubusercontent.com/MatinDehghanian/bh/refs/heads/main/bh.sh -o bh.sh
chmod +x bh.sh
sudo ./bh.sh
```

When you first create a tunnel (or choose **4. Install / update BH Core**), the script downloads the executable from:

```text
https://raw.githubusercontent.com/MatinDehghanian/bh/refs/heads/main/bh
```

It checks that the download is an x86-64 ELF executable, applies `chmod +x`, and installs it under the executable name expected by existing systemd services. Failed or invalid downloads preserve the previous core. Existing installation paths and tunnel services are preserved.

## Configure a tunnel

1. On IRAN, choose **1. New tunnel → 1. IRAN** for quick setup.
2. Select a transport by number or name (Enter chooses TCP), enter the listen address (default `:8443`), accept the generated token, and enter your application ports, for example `443,8443=443`.
3. Review the summary and enter `y` to create and start the tunnel. Enter the IRAN address that KHAREJ can reach and copy the setup link.
4. On KHAREJ, choose **1. New tunnel → 2. KHAREJ · paste an IRAN setup link**, paste the link, and approve the preview.
5. Open **2. My tunnels** to test connectivity, edit settings, inspect logs, or control the service.

Quick setup uses the existing defaults for performance, heartbeats, multiplexing and logging. To customize every setting during creation, choose **4. Advanced · IRAN** or **5. Advanced · KHAREJ** in New tunnel. **3. KHAREJ · enter connection details manually** is available when you cannot use a setup link; paste the same token or IPX PSK used on IRAN.

The script offers `tcp`, `tcpmux`, `xtcpmux`, `ws`, `wss`, `wsmux`, `wssmux`, `xwsmux`, `anytls`, and `tun`. TUN/IPX asks for the additional device, address and encryption settings it needs. Every new tunnel requires a preview confirmation; a failed initial start removes its newly created config and service.

## Terminal interface

The home screen shows the local server address, core installation state, and counts of running tunnels and tunnels needing attention. **My tunnels** shows active, inactive, failed, and missing-service states. A repair action recreates missing services after confirmation.

Menus stay open after actions; **0** goes back and **q** exits the home screen. Press Enter to keep a default, type `/cancel` at setup prompts to return, or use Ctrl+D to leave input. Boolean prompts accept `y`/`n` and `true`/`false`. Tokens and PSKs are hidden in settings summaries. Logs show the last 60 lines without trapping navigation in a live stream.

Colors are enabled on capable terminals. Redirected output is plain text; `NO_COLOR=1` or `--no-color` disables colors. Help and version work without root, downloads or systemd:

```bash
bash bh.sh --help
bash bh.sh --version
bash bh.sh --no-color
```

Opening the manager does not download the core or query third-party geolocation services. Loading the script with `source` defines its helpers without starting the application or changing the system.

## Manage and update

| Menu option | Action |
| --- | --- |
| 1. New tunnel | Create a server or client tunnel and its systemd service. |
| 2. My tunnels | Edit, test connectivity, export setup links, check health, start/stop, restore the previous config, inspect logs, or delete a tunnel. |
| 3. Tunnel status | Check configured tunnel services. |
| 4. Install / update BH Core | Download the latest executable from this repository. Restart existing tunnel services afterward through tunnel management. |
| 5. Update script | Download the latest script from this repository's GitHub raw URL, validate it, and install it as executable `/usr/bin/bh`. Run `bh` to reopen it. Failed updates keep the installed script. |
| 6. Remove BH Core | Remove the core after deleting all tunnel services. |
| 7. Compare transports | Compare transport availability between IRAN and KHAREJ, one temporary tunnel at a time, with ping, jitter, upload and download results. |
| 0. Exit | Close the menu. |

## File locations

The manager keeps using the existing core/configuration directory and systemd service identifiers so updates continue managing installed tunnels. Server configurations are named `iran<port>.toml`, client configurations `kharej<port>.toml`, and certificates are stored in `cert_files/` within the configuration directory. Use **Health check and file locations** for the exact paths on a server.

Rerun the install command whenever you want to open the menu again. After **5. Update script**, run `bh` directly.

## Edit an existing tunnel

1. Choose **2. My tunnels** and select your tunnel.
2. Choose **1) Edit settings**.
3. Select a settings group, then the numbered setting to change. Current values are displayed (credentials stay hidden); press Enter to keep a value. Boolean settings and choices such as transport use numbered options.
4. To change transport, open **Transport and connection options** and select **Type**. The editor keeps shared settings and asks for missing transport details, including mux, TLS, TUN, and IPX settings. TUN forwarding supports individual ports and `port=port` mappings; incompatible ranges will prompt for replacement.
5. Choose **s) Save changes & restart** to apply your edits. Choose **0) Back · discard unsaved edits** to discard them.

Saving creates a `.toml.bak` backup and restarts the existing tunnel service. If the restart fails or the service is inactive, the script restores the previous configuration and attempts to restart it. Service and configuration filenames stay the same, even if you edit a connection port.

When changing transport or security settings, update the other server to match. The menu edits the selected server's configuration only.

The editor supports the TOML format generated by this script. It preserves additional compatible scalar fields and sections, but refuses unsupported TOML syntax without changing the file. Saving removes comments and normalizes formatting.

## Setup KHAREJ from a link

1. Configure IRAN first. After creation, the script asks for the IRAN IP/domain that KHAREJ can reach and prints a `bh://1.…` setup link. You can also generate it later from **My tunnels → select an IRAN tunnel → 3) Copy KHAREJ setup link**.
2. On KHAREJ, choose **New tunnel → 2) KHAREJ · paste an IRAN setup link** and paste it.
3. The script fills in the matching transport, credentials, mux settings, tuning and connection details. For TUN it swaps the local/remote addresses; for IPX it swaps the peer IPs and asks for the local network interface.
4. Review the preview, then enter `y` to create and start the tunnel.

**IPX Spoof:** All IPX profiles (`icmp`, `ipip`, `udp`, `tcp`, `gre`, `bip`) support `custom_packet`, which defaults to `false` and is written explicitly in generated configurations. For a new ordinary tunnel, select `tun` → `ipx`; for spoofing, select `tun` → `ipx-spoof`. Both branches offer the same six profiles and setup steps. The spoof branch enables `custom_packet` automatically and asks for spoof source/destination addresses. This writes `type = "tun"`, `encapsulation = "ipx"`, and `[ipx] custom_packet = true`, with `tcp` as the default profile, just like ordinary IPX. Enter the real server addresses in `listen_ip` / `dst_ip`, and the whitelisted addresses in `spoof_src_ip` / `spoof_dst_ip`. On KHAREJ, reverse the spoof source and destination from IRAN; setup links do this automatically and still request KHAREJ's local interface. For an existing `tun/ipx` tunnel, enable `custom_packet` in the **IPX encapsulation** editor to enter both spoof addresses. To match the supplied examples, disable encryption and select `iptables` as the IRAN port forwarder (for example, `9090=9090`). Encryption and forwarding remain configurable. The automatic transport comparison tests ordinary IPX profiles; it does not test Spoof addresses.

After editing IRAN, export a fresh link and apply it on KHAREJ. If exactly one existing KHAREJ tunnel has the same credential, it updates that tunnel with a backup and restart instead of creating another instance. Conflicting filenames and TUN devices are refused.

Links contain credentials and are encoded, not encrypted. Share them privately. These are this script's links; BackPack's `backpack://` format is not compatible. IRAN setups generate a random token or IPX PSK; manual KHAREJ setup requires the matching credential.

## Test one tunnel's connection

Choose **My tunnels → select a tunnel → 2) Test connection**. Diagnostics require Python 3; on Debian/Ubuntu, install it with `apt-get install -y python3` if needed.

Choose one test:

- **1) Quick TCP reachability:** ten sequential TCP connects to the selected tunnel address. On KHAREJ this measures the route to IRAN; on IRAN it checks the local listener only. It reports connection success, connect latency and jitter. These results do not prove authentication or forwarded traffic, and failed connects are not a measurement of packet loss. IPX does not use this TCP listener check.
- **2) Real traffic test (IRAN):** select one configured port mapping. The script prints a `bh-test://1.…` link. On KHAREJ, select the matching tunnel, choose **3) Start responder**, and paste that test link. Once KHAREJ says **Ready**, press Enter on IRAN. The test verifies 60 echoes over one persistent connection, then an exact 1 MiB bulk echo. It reports round-trip latency, jitter and the combined upload/download echo rate.

The KHAREJ backend port must be unused: the responder refuses occupied ports and never stops an application. If necessary, add an unused mapping such as `55000=55000` through **Edit → Port mappings**, then remove it after testing. Range mappings let you choose one port in the range.

Only the selected existing tunnel carries this test traffic. This selected-tunnel test starts no additional BH core, changes no tunnel configuration, and does not try other transports or mappings. A lock allows one diagnostic test per server at a time. Use main-menu **7. Compare transports** for an automatic comparison of transport candidates.

Keep the test link private. The temporary responder supports PROXY protocol headers and exits when the test finishes, when you cancel with Ctrl+C, or after ten minutes. A successful echo test proves the selected path carried those test bytes; it does not test every forwarded service or guarantee future route quality.

## Compare all transports: availability, ping and speed

This adapts [BackPack's Connection Test](https://github.com/AminMGMT/BackPack/blob/main/internal/manage/conntest.go) to the transports supported by this repository's BH core. It creates temporary paired test tunnels and runs **one transport at a time**. It compares `tcp`, `tcpmux`, `xtcpmux`, `ws`, `wss`, `wsmux`, `wssmux`, `xwsmux`, `anytls`, `tun/tcp`, and `tun/ipx` with each of `icmp`, `ipip`, `udp`, `tcp`, `gre`, and `bip`.

1. On IRAN, choose **7. Compare transports → 1) IRAN**. Enter the public address and two unused TCP ports (defaults: control `54000`, tunnel `54001`). The tunnel port is reused for every candidate so the comparison uses the same port on the route.
2. Choose **Quick** (10 echoes over 5 seconds per working transport) or **Stability** (60 echoes over 60 seconds). Stability helps detect connections that drop after a short time. Each working transport also transfers a verified 8 MiB upload and 8 MiB download.
3. Confirm the temporary pause. Copy the displayed `bh-compare://1.…` link.
4. On KHAREJ, choose **7. Compare transports → 2) KHAREJ**, paste the link and confirm its temporary pause. Testing then starts automatically; both servers show the results.

The table reports **AVAILABLE**, **UNSTABLE**, **DOWN**, **ERROR**, or **SKIPPED**, with average ping, jitter, upload/download Mbit/s and verified echo counts. **AVAILABLE** requires every echo and both payload transfers to succeed. Ping is application round-trip latency through the actual tunnel, rather than ICMP ping to the public server. Speeds are measured from IRAN: upload sends to KHAREJ, download receives from KHAREJ. Skipped prerequisites and startup errors have their own explanation; missing measurements show `-`. The fastest fully verified candidate is identified, and both servers save `transport-test-results.json` in the configuration directory without test credentials.

The comparison requires Python 3.9+, the installed executable, systemd, and a working TCP control path from KHAREJ to IRAN. Allow the selected control and tunnel TCP ports through existing firewalls. The script does not open firewall ports automatically. TLS tests generate a temporary certificate using OpenSSL. TUN requires root, `/dev/net/tun` and iproute2; IPX also requires an IPv4 path and a usable interface, which the tester detects from the control connection. Raw IPX profiles can fail through NAT or protocol filters even when TCP works. Missing prerequisites are reported as **SKIPPED**, not a measured route failure.

Existing running managed BH services are temporarily stopped on each server after confirmation; their configuration files and boot settings are preserved. IRAN waits for KHAREJ before pausing its services. Only one temporary BH core runs per server, and KHAREJ must acknowledge that its previous core stopped before the next candidate starts. An unmanaged BH core causes the comparison to stop instead of starting another instance. Temporary TUN devices use a random name and an unused subnet in `198.18.0.0/15`; forwarding uses BH rather than iptables, and automatic kernel tuning is disabled for test configurations.

On completion, Ctrl+C, or a handled failure, test processes, sockets, files and owned TUN interfaces are cleaned up, and previously running services are restarted. A failed service restore names the affected unit and recovery command. Use an SSH connection that does not depend on a tunnel being paused. IRAN waits up to ten minutes for KHAREJ, links expire after one hour, and the shared diagnostic lock prevents overlapping tests. Keep the test link private and keep both terminals open. Quick and stability results describe the tested route and settings at that time; they do not guarantee future reliability or production workload performance.

## Health and recovery

The selected tunnel's management menu also offers:

- **4) Health check & file locations:** core executable permissions, service state, weak default-token detection, TLS expiry, config/backup/service paths and the selected service's recent logs. It reports suggestions without changing settings.
- **6) Start / stop tunnel:** controls only that service. Stopping does not disable its existing boot setting.
- **9) Restore previous settings:** previews the transport in the `.toml.bak` file, then restores and restarts only the selected tunnel after confirmation. If the restored configuration cannot start, it recovers the current configuration.

The [BackPack feature review](docs/backpack-review.md) records the source reviewed, the features adapted, and which features require a different tunnel engine.

## Verify editor changes

Tests use temporary files and simulated systemd services. With Bash 4+, jq, and Python 3.11+ installed:

```bash
bash tests/bh_install_test.sh
bash tests/tunnel_edit_test.sh
bash tests/tunnel_features_test.sh
bash tests/ipx_spoof_test.sh
bash tests/manager_test.sh
python3 tests/connection_tool_test.py
python3 tests/transport_comparison_test.py
```

The connection-tool test uses loopback sockets and takes about one minute to verify the full echo soak. The comparison tests exercise paired coordination, sequential engine cleanup, cancellation, separate verified upload/download measurements, and configuration generation for all 16 cases. Tests simulate systemd and comparison engines; they do not run the Linux BH binary or contact your servers. Use `TEST_BASH=/path/to/bash` for the connection-tool Python test if your default Bash is older than version 4.

The manager regression tests cover the full quick-setup flow, private file permissions, EOF/cancellation, invalid addresses and ports, failed-start cleanup, safe deletion, dashboard states, and TUN device conflicts.
