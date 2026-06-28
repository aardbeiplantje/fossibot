# fossibot.pl

A lightweight BLE inspector and live monitor for the **Fossibot F1200** portable power station. Connects directly via Linux's native BLE/L2CAP socket (no BlueZ D-Bus, no external Perl modules required) and communicates using the device's Modbus-RTU-over-BLE protocol.

## Requirements

- Linux with BlueZ kernel support (`/proc/net/bluetooth` present)
- Perl 5 (core modules only: `Socket`, `Fcntl`, `Getopt::Long`, `POSIX`)
- BLE adapter in powered-on state (`bluetoothctl power on`)

## Usage

```bash
./fossibot.pl -d AA:BB:CC:DD:EE:FF [action] [options]
```

`-d` / `--device` is always required.

### Actions

| Action | Description |
|--------|-------------|
| `--info` | Connect, print device name and GATT services (default) |
| `--connect` | Connection test only |
| `--name` | Read BLE Device Name (GATT 0x2A00) |
| `--services` | Enumerate GATT primary services |
| `--chars` | Enumerate characteristics (all services, or filtered by `--service-uuid`) |
| `--read-handle H` | Read raw value from ATT handle H |
| `--write-req-handle H --write-hex BYTES` | Write bytes using ATT Write Request |
| `--write-cmd-handle H --write-hex BYTES` | Write bytes using ATT Write Command |
| `--subscribe-handle H` | Enable CCCD notifications on handle H |
| `--listen` | Print raw notifications for `--listen-sec` seconds (`0` = indefinite) |
| `--f1200-poll` | Single Modbus register snapshot, decoded (`--listen-sec 0` = poll indefinitely) |
| `--f1200-stream` | Repeated polls + notifications for `--listen-sec` (`0` = indefinite) |
| `--f1200-diff` | Continuous polling; print only registers that changed, with labels (`--listen-sec 0` = indefinite) |
| `--f1200-query [REG[-REG]]` | Ad-hoc read of a specific register or range, printed with labels |
| `--set-screen-timeout=SEC` | Set screen timeout in seconds (register `0x003E`) |
| `--set-usb-output=on\|off` | Toggle USB output switch (register `0x0018`) |
| `--set-dc-output=on\|off` | Toggle DC output switch (register `0x0019`) |
| `--set-ac-output=on\|off` | Toggle AC output switch (register `0x001A`) |
| `--set-led-mode=off\|on\|sos\|flash` | Set rear LED mode (register `0x001B`) |
| `--set-key-sound=on\|off` | Toggle key sound (register `0x0038`) |
| `--set-ac-silent-charging=on\|off` | Toggle AC silent charging (register `0x0039`) |
| `--set-usb-standby-min=MIN` | Set USB no-load standby time in minutes (register `0x003B`) |
| `--set-ac-standby-min=MIN` | Set AC no-load standby time in minutes (register `0x003C`) |
| `--set-dc-standby-min=MIN` | Set DC no-load standby time in minutes (register `0x003D`) |
| `--set-stop-charge-after-min=MIN` | Set stop-charge-after timer in minutes (register `0x003F`) |
| `--f1200-write REG=VALUE` | Legacy direct register write (still supported) |

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `--addr-type TYPE` | `public` | BLE address type: `public` or `random` |
| `--connect-timeout SEC` | `6` | Connection timeout in seconds |
| `--mtu N` | `160` | ATT MTU (23–517) |
| `--response-timeout-ms N` | `2500` | Timeout for ATT request/response |
| `--listen-sec SEC` | `10` | Duration for --listen, --f1200-stream, --f1200-diff; set `0` to run indefinitely |
| `--f1200-interval-ms N` | `1000` | Poll interval for --f1200-diff |
| `--f1200-diff-csv PATH` | — | Write changed-register events to a CSV file |
| `--set-screen-timeout=SEC` | — | Key-based settings write (recommended) |
| `--f1200-raw` | — | Also print raw hex notification bytes with poll/stream |
| `--service-uuid UUID` | — | Filter --chars to a specific service UUID |
| `--notify-handle H` | — | Filter --listen to a specific notification handle |
| `--write-hex BYTES` | — | Bytes for write actions, e.g. `"AA BB 01 02"` or `AABB0102` |
| `-v` / `--debug` | — | Verbose/debug output (repeatable) |
| `-h` / `--help` | — | Show help |

## Examples

```bash
# Quick device summary
./fossibot.pl -d 08:92:72:0D:93:C6

# Continuous live diff (changed registers only, 1 s interval)
./fossibot.pl -d 08:92:72:0D:93:C6 --f1200-diff --listen-sec 3600

# Save all register changes to CSV
./fossibot.pl -d 08:92:72:0D:93:C6 --f1200-diff \
    --f1200-diff-csv changes.csv --listen-sec 3600

# One-shot snapshot of all known registers
./fossibot.pl -d 08:92:72:0D:93:C6 --f1200-query

# Read a single register
./fossibot.pl -d 08:92:72:0D:93:C6 --f1200-query 0x0038

# Read a register range
./fossibot.pl -d 08:92:72:0D:93:C6 --f1200-query 0x0000-0x000F

# Set screen timeout to 180 seconds
./fossibot.pl -d 08:92:72:0D:93:C6 --set-screen-timeout=180

# Toggle outputs and sound with key-based options
./fossibot.pl -d 08:92:72:0D:93:C6 \
    --set-ac-output=on --set-dc-output=on --set-key-sound=off

# Legacy raw register write (still supported)
./fossibot.pl -d 08:92:72:0D:93:C6 --f1200-write 0x003E=180

# Read WiFi credentials (FC03 holding registers)
./fossibot.pl -d 08:92:72:0D:93:C6 --f1200-query 0x0004-0x0007

# Read device startup configuration registers
./fossibot.pl -d 08:92:72:0D:93:C6 --f1200-query 0x0031-0x0034

# Stream decoded output for 60 seconds
./fossibot.pl -d 08:92:72:0D:93:C6 --f1200-stream --listen-sec 60

# Poll indefinitely (Ctrl+C to stop)
./fossibot.pl -d 08:92:72:0D:93:C6 --f1200-poll --listen-sec 0

# Diff indefinitely (Ctrl+C to stop)
./fossibot.pl -d 08:92:72:0D:93:C6 --f1200-diff --listen-sec 0
```

## Decoded Modbus Registers

Registers have **context-dependent meanings** based on read type:  
**Input Registers (FC 0x04)** are live telemetry from device.  
**Holding Registers (FC 0x03)** include settings/configuration plus a startup snapshot of persistent capability/firmware information.

### Input Registers (FC 0x04 – Live Telemetry)

| Register | Label | Notes |
|----------|-------|-------|
| `0x0002` | Input power mode | `1` = 200 W, `2` = 400 W |
| `0x0003` | AC charging power (W) | Power delivered to battery charger only |
| `0x0004` | DC input power (W) | DC power from external source |
| `0x0006` | AC input power total (W) | Mains draw = charging + DC output load. Confirmed with 26 W DC load: 0x0006=128, 0x0003=102, 0x0014=26 |
| `0x000D` | AC charging rate (W) | AC power to battery from mains |
| `0x000F` | Rear LED brightness | `0` = off, `10` = on |
| `0x0012` | AC output voltage (V) | Scale ÷ 10. Displays jitter due to AC ripple/estimation |
| `0x0013` | AC output frequency (Hz) | Scale ÷ 10. Confirmed by HA integration (`inputs[19] / 10`) |
| `0x0014` | Total output power (W) | Matches app "Total Output"; tracks DC output (+ USB). Observed: 0, 13, 26 W |
| `0x0015` | AC input voltage (V) | Scale ÷ 10; may be stale/noisy when AC absent |
| `0x0016` | AC input frequency (Hz) | Scale ÷ 100; noisy when AC absent/transitioning |
| `0x0019` | Rear LED mode | `0`=off, `1`=solid on, `2`=SOS flashing, `3`=flashing |
| `0x001E` | USB output power (W) | Scale ÷ 10. Confirmed: raw 39–40 = device display shows "3" (3.9–4.0 W) |
| `0x0027` | Total output power [b] (W) | Mirrors `0x0014` in all observed cases |
| `0x0029` | Active output list | Bit-parsed: `USB|DC+AC|LED` from binary flags. Also noted as aggregate converter/output power with offset baseline when USB/DC enabled |
| `0x002A` | DC bus config + current | Bit `0x4000` = DC enabled; low 14 bits = current ÷ 100 (A) |
| `0x0030` | Status flags | `0x8000` = AC present, `0x4000` = Charging mode, `0x0000` = idle/transition |
| `0x0035` | State of Charge Slave 1 (%) | Scale ÷ 10 then subtract 0.1 |
| `0x0037` | State of Charge Slave 2 (%) | Scale ÷ 10 then subtract 0.1 |
| `0x0038` | State of Charge high-res (%) | Scale ÷ 10 (exact same formula as HA: registers[56] / 1000 × 100 = percentage) |
| `0x003A` | Estimated time to full (min) | Counts down while charging; ramps from ~374 min at low SoC |
| `0x003B` | Time remaining (min) | Discharge estimate. Without load: ~4496 units = 3 d, 2 h, 56 m; ±60 min jitter due to AC ripple/estimation |

### Holding Registers (FC 0x03 – Settings & Configuration)

| Register | Label | Notes |
|----------|-------|-------|
| `0x0004–0x0007` | WiFi SSID / Password | 8 bytes total (4 each for SSID + password); written via FC 0x07 |
| `0x000C` | Energy mgmt discharge limit | Setting (%). App shows 10 % as raw `9` (possible UI offset) |
| `0x000E` | EPS AC charge limit | Setting in 0.1% units (`1000` = 100.0%) |
| `0x0014` | Max charging current (A) | Amperes as plain integer |
| `0x0018` | USB output switch | `0` = off, `1` = on |
| `0x0019` | DC output switch | `0` = off, `1` = on |
| `0x001A` | AC output switch | `0` = off, `1` = on |
| `0x001B` | LED light mode | `0`=off, `1`=always on, `2`=SOS, `3`=flash |
| `0x0038` | Key sound toggle | `0` = off, `1` = on |
| `0x0039` | AC silent charging | `0` = off, `1` = on |
| `0x003B` | USB no-load standby time (min) | Minutes. `0` = never? |
| `0x003C` | AC no-load standby time (min) | Minutes. `0` = never; `0x03C0`=16 h |
| `0x003D` | DC no-load standby time (min) | Minutes. Same behaviour as `0x003C` |
| `0x003E` | Screen shutdown timeout (sec) | Seconds. Observed: `0x00B4`=180 s = 3 m |
| `0x003F` | Stop charge after (min) | Minutes |
| `0x0042` | Max discharge limit | Setting in 0.1% units |
| `0x0043` | EPS AC charge limit [b] | Mirror of `0x000E` |
| `0x0044` | Whole machine unused time (min) | Minutes |

### Device Startup Registers (FC 0x03 Snapshot – Configuration at Boot)

Discovered in full holding-register dump (frame 6940 of `new.6.pcapng`). Fetched by the app on startup, likely device capabilities/firmware info or persistent status:

| Register | Label | Notes |
|----------|-------|-------|
| `0x0001` | Device model/mode info | Model identifier / capabilities |
| `0x000F` | Firmware/feature info | Feature flag register |
| `0x0010` | Config [a] | Unknown power param (e.g. 0xE800) |
| `0x0012` | Config [b] | Maybe 0.1-unit scale, unconfirmed |
| `0x0013` | Config [c] | Unknown scale (e.g. 0x0800) |
| `0x0027` | Output config [a] | Output-related (noted changing with USB state) |
| `0x002B` | Output config [b] | E.g. 0x0200 in capture |
| `0x0031` | Status flags [a] | Persistent status/error indicator |
| `0x0032` | Status flags [b] | E.g. 0x1200 |
| `0x0034` | Status flags [c] | E.g. 0x1300 |
| `0x0040` | Device status [b] | E.g. 0x0800 |
| `0x0045` | Event/error log [a] | History (e.g. 0x8400) |
| `0x0046` | Event/error log [b] | E.g. 0x1E00 |

> Register mappings derived from live observation, diff analysis, and cross-verification against the Home Assistant integration (`sydpower/modbus.py`). Some labels are provisional.  
> **Critical fixes verified via HA:** SOC formula corrected to ÷10 (was erroneously ÷2), `0x0029` reclassified to "Active output list", new registers `0x0035`/`0x0037` added as SOC Slave 1/2.

## BLE Protocol Notes

- **Transport**: ATT/L2CAP over BLE (PSM 4, CID 4)
- **Write handle**: `0x0036`
- **Notify handle**: `0x0038`
- **CCCD handle**: `0x0039`
- **Modbus framing**: RTU-over-BLE using slave address `0x11`, function codes 0x03/0x04/0x06/0x07
- **CRC byte order**: high byte first (non-standard, confirmed from captures)
- Responses may arrive in multiple BLE notification fragments; reassembly is automatic

## PCAPNG Capture Analysis

Eight captures (`change_screen_timeout.pcapng`, `new.*.pcapng`) totaling ~5.5 MB.  
All reads consistently span registers 0x0000..0x004F (80 registers).

**Function codes observed**:
| FC | Name | Count | Details |
|----|------|-------|---------|
| `0x03` | Read Holding Registers | 63 | Start=0x0000, count=80 (config read) |
| `0x04` | Read Input Registers | 41 | Start=0x0000, count=80 (telemetry) |
| `0x06` | Write Single Register | 11 | Config writes to `0x0014`, `0x0018–0x001B`, `0x0038–0x003E` etc. |
| `0x07` | Diagnostics/Test | 2 | ASCII payloads: "TESTTAST", "TUSTTOST" (device self-test commands) |

> 44 registers have explicit labels in the decoder; 36 candidates remain unlabeled pending further analysis.

## PCAPNG Verification Report

Verification performed against eight nRF Sniffer captures (`change_screen_timeout.pcapng`, `new.pcapng`, `new.1–6.pcapng`) using `tshark -V` verbose parsing and Python regex extraction of ATT/L2CAP/Modbus payloads.

### Verification Summary

| Constant/Feature | Status | Details |
|-----------------|--------|---------|
| Slave address `0x11` | **PASS** | Code and captures both use `0x11`. Prior session's reported mismatch (`0xF6` vs `0x11`) has been fixed — code now correct. |
| Write handle `0x0036` | **PASS** | Matches code constant, all capture payloads, and README. |
| Notify handle `0x0038` | **PASS** | Matches code constant, all capture notifications, and README. |
| CCCD handle `0x0039` | **PASS** | Verified CCCD write (`Client Characteristic Configuration`, UUID `0x2902`) with value `0x0001` (Notification enabled) in captures. |
| Service UUID `0xA002` | **PASS** | Matches code constant and GATT discovery in captures (`Group End Handle: 0x0028` start, UUID `0xA002`). |
| FC03/FC04/FC06/FC07 | **PASS** | All four function codes observed with correct Modbus byte layouts matching README table. |
| Register span `0x0000..0x004F` (80 regs) | **PASS** | Every FC03/FC04 request uses `start=0x0000, count=80`. |
| CRC high-byte-first | **PASS** | Captured CRC bytes (e.g. `110300000050` → `66 47`) match code's `($crc >> 8) & 0xFF, $crc & 0xFF` — high byte first, non-standard. |
| Modbus payload structure | **PASS** | 8-byte requests: `[slave:1][FC:1][reg_hi:1][reg_lo:1][count_hi:1][count_lo:1][CRC_hi:1][CRC_lo:1]` — confirmed in all captures. |
| SOC ÷10 formula | **PASS** | Code `return $raw / 10.0` matches corrected HA integration. `0x0035`/`0x0037` use `(raw / 10.0) - 0.1`. |

### Known Issues

- **Register `0x0029` label inconsistency**: Holding register branch (`fossibot_register_pretty`, line ~1557) labels it as "Converter info", while the input register branch and README label it as "Active output list" with bit-parsing. The README/input interpretation is correct per HA integration. The holding branch should be updated.

### Capture File Statistics

| File | Frames | FC03/FC04 Requests | FC06 Writes | Notifications (0x38) | Notes |
|------|--------|--------------------|-------------|--------------------|-------|
| `change_screen_timeout.pcapng` | 7,831 | FC03+FC06 writes | FC06 to `0x003E` (180s) | 28 | Screen timeout write session |
| `new.1.pcapng` | 6,409 | FC03 (69 writes) | — | 39 | Full holding-register poll |
| `new.2.pcapng` | 7,928 | FC04 (4 writes) | FC06 to `0x0014` | 4 | Input register poll |
| `new.3.pcapng` | 17,797 | FC03 (23 writes) | FC06 to `0x0038,0x003B,0x003D,0x0044` | 16 | Multi-register writes + config |
| `new.4.pcapng` | 12,925 | — | — | 1 | Connection test, minimal activity |
| `new.5.pcapng` | 17,037 | FC04+FC06 (26 writes) | FC06 to `0x0018,0x001A,0x001B` | 22 | Output toggle session |
| `new.6.pcapng` | 9,763 | FC03+FC04+FC07 (19) | — | 11 | Includes FC07 diagnostics ("TESTTAST", "TESTTOST") |
| `new.pcapng` | 9,063 | FC03+FC04 (31 writes) | — | 17 | Baseline session |
| **Total** | **88,753** | **106 requests** | **11 writes** | **138** | ~5.5 MB total |

### Detailed Function Code Verification

| FC | Modbus meaning | Capture payload (hex) | Code function | Status |
|----|----------------|----------------------|---------------|--------|
| `0x03` | Read Holding Registers | `11 03 00 00 00 50 66 47` (start=0, count=80) | `f1200_send_read()` | **PASS** |
| `0x04` | Read Input Registers | `11 04 00 00 00 50 a6 f2` (start=0, count=80) | `f1200_send_poll()` | **PASS** |
| `0x06` | Write Single Register | `11 06 00 3E 00 B4 e1 ea` (reg=0x3E, val=0xB4) | `f1200_send_write_single()` | **PASS** |
| `0x07` | Diagnostics | `11 07 04 04 54 45 53 54 54 41 53 54 d0 61` ("TESTTAST") | FC07 handler in `decode_f1200_payload()` | **PASS** |

### CRC Verification

Modbus CRC-16 calculated over the data portion, then sent high-byte-first on wire:

```
FC03 data:  110300000050 → CRC(modbus)=0x6647 → wire=66 47 ✓
FC04 data:  110400000050 → CRC(modbus)=0xA6F2 → wire=a6 f2 ✓
FC06 data:  1106003E00B4 → CRC(modbus)=0xE1EA → wire=e1 ea ✓
FC06 data:  110600140006 → CRC(modbus)=0x5C4B → wire=5c 4b ✓
FC06 data:  110600380000 → CRC(modbus)=0x970A → wire=97 0a ✓
```

All captured CRC bytes match code's `($crc >> 8) & 0xFF, $crc & 0xFF` (high byte first).

## License

See [LICENSE](LICENSE).
