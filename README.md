# fossibot.pl

A lightweight BLE inspector and live monitor for the **Fossibot F1200** portable
power station.  
Connects directly via Linux's native BLE/L2CAP socket (no BlueZ D-Bus, no
external Perl modules required) and communicates using the device's Modbus-RTU-
over-BLE protocol.

---

## Requirements

- Linux with BlueZ kernel support (`/proc/net/bluetooth` present)
- Perl 5 (core modules only: `Socket`, `Fcntl`, `Getopt::Long`, `POSIX`)
- BLE adapter in powered-on state (`bluetoothctl power on`)

---

## Usage

```
./fossibot.pl -d AA:BB:CC:DD:EE:FF [action] [options]
```

`-d` / `--device` is always required.

---

## Actions

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
| `--listen` | Print raw notifications for `--listen-sec` seconds |
| `--f1200-poll` | Single Modbus register snapshot, decoded |
| `--f1200-stream` | Repeated polls + decoded output for `--listen-sec` |
| `--f1200-diff` | Continuous polling; print only registers that changed, with labels |
| `--f1200-query [REG[-REG]]` | Ad-hoc read of a specific register or range, printed with labels |

---

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `--addr-type TYPE` | `public` | BLE address type: `public` or `random` |
| `--connect-timeout SEC` | `6` | Connection timeout in seconds |
| `--mtu N` | `160` | ATT MTU (23–517) |
| `--response-timeout-ms N` | `2500` | Timeout for ATT request/response |
| `--listen-sec SEC` | `10` | Duration for `--listen`, `--f1200-stream`, `--f1200-diff` |
| `--f1200-interval-ms N` | `1000` | Poll interval for `--f1200-diff` |
| `--f1200-diff-csv PATH` | — | Write changed-register events to a CSV file |
| `--f1200-raw` | — | Also print raw hex notification bytes with poll/stream |
| `--service-uuid UUID` | — | Filter `--chars` to a specific service UUID |
| `--notify-handle H` | — | Filter `--listen` to a specific notification handle |
| `--write-hex BYTES` | — | Bytes for write actions, e.g. `"AA BB 01 02"` or `AABB0102` |
| `-v` / `--debug` | — | Verbose/debug output (repeatable) |
| `-h` / `--help` | — | Show help |

---

## Examples

```bash
# Quick device summary
./fossibot.pl -d 08:92:72:0D:93:C6

# Continuous live diff (changed registers only, 1 s interval)
./fossibot.pl -d 08:92:72:0D:93:C6 --f1200-diff --listen-sec 3600

# Save all register changes to CSV
./fossibot.pl -d 08:92:72:0D:93:C6 --f1200-diff --f1200-diff-csv changes.csv --listen-sec 3600

# One-shot snapshot of all known registers
./fossibot.pl -d 08:92:72:0D:93:C6 --f1200-query

# Read a single register
./fossibot.pl -d 08:92:72:0D:93:C6 --f1200-query 0x0038

# Read a register range
./fossibot.pl -d 08:92:72:0D:93:C6 --f1200-query 0x0000-0x000F

# Read WiFi credentials (FC03 holding registers)
./fossibot.pl -d 08:92:72:0D:93:C6 --f1200-query 0x0004-0x0007

# Read device startup configuration registers
./fossibot.pl -d 08:92:72:0D:93:C6 --f1200-query 0x0031-0x0034

# Stream decoded output for 60 seconds
./fossibot.pl -d 08:92:72:0D:93:C6 --f1200-stream --listen-sec 60
```

---

## Decoded Modbus Registers

Registers have **context-dependent meanings** based on read type:
- **Input Registers (FC 0x04)**: Live telemetry from device
- **Holding Registers (FC 0x03)**: Settings and configuration; also fetched at app startup

### Input Registers (FC 0x04 - Live Telemetry)

| Register | Label | Notes |
|----------|-------|-------|
| `0x0002` | Input power mode | `1` = 200 W, `2` = 400 W |
| `0x0003` | AC charging power (W) | Power delivered to battery charger only |
| `0x0004` | DC input power (W) | DC power from external source |
| `0x0006` | AC input power total (W) | Mains draw = charging + DC output load |
| `0x000D` | AC charging rate (W) | AC power to battery from mains |
| `0x000F` | Rear LED brightness | `0` = off, `10` = on |
| `0x0012` | AC output voltage (V) | Scale ÷ 10 |
| `0x0013` | AC output frequency (Hz) | Scale ÷ 10 |
| `0x0014` | Total output power (W) | Matches app "Total Output" |
| `0x0015` | AC input voltage (V) | Scale ÷ 10 |
| `0x0016` | AC input frequency (Hz) | Scale ÷ 100 |
| `0x0019` | Rear LED mode | `0` = off, `1` = solid, `2` = SOS, `3` = flashing |
| `0x001E` | USB output power (W) | Scale ÷ 10 |
| `0x0027` | Total output power [b] (W) | Mirrors `0x0014` |
| `0x0029` | Active output list | Bit-parsed: USB, DC, AC, LED active states |
| `0x002A` | DC bus config | Bit `0x4000` = DC enabled; low 14 bits = current ÷ 100 (A) |
| `0x0030` | Status flags | Bit `0x8000` = AC present, bit `0x4000` = charging mode |
| `0x0035` | State of Charge Slave 1 (%) | Scale ÷ 10, subtract 0.1 |
| `0x0037` | State of Charge Slave 2 (%) | Scale ÷ 10, subtract 0.1 |
| `0x0038` | State of Charge high-res (%) | Scale ÷ 10 |
| `0x003A` | Estimated time to full (min) | Counts down while charging |
| `0x003B` | Time remaining (min) | Discharge time estimate |

### Holding Registers (FC 0x03 - Settings & Configuration)

| Register | Label | Notes |
|----------|-------|-------|
| `0x0004-0x0007` | WiFi SSID / Password | 8 bytes total (4 bytes SSID + 4 bytes password), written via FC 0x07 |
| `0x000C` | Energy mgmt discharge limit | Setting (%); App 10% observed as raw `9` (possible UI offset) |
| `0x000E` | EPS AC charge limit | Setting, 0.1% units (`1000` = 100.0%) |
| `0x0014` | Max charging current | Setting in Amperes |
| `0x0018` | USB output switch | Setting: `0` = off, `1` = on |
| `0x0019` | DC output switch | Setting: `0` = off, `1` = on |
| `0x001A` | AC output switch | Setting: `0` = off, `1` = on |
| `0x001B` | LED light mode | Setting: `0` off, `1` always, `2` SOS, `3` flash |
| `0x0038` | Key sound toggle | Setting: `0` = off, `1` = on |
| `0x0039` | AC silent charging | Setting: `0` = off, `1` = on |
| `0x003B` | USB no-load standby time | Setting in minutes |
| `0x003C` | AC no-load standby | Setting in minutes; `0` = never, `0x03C0` = 16h |
| `0x003D` | DC no-load standby | Setting in minutes; `0` = never, `0x03C0` = 16h |
| `0x003E` | Screen shutdown timeout | Setting in seconds (`0x00B4` = 180s = 3m) |
| `0x003F` | Stop charge after | Setting in minutes |
| `0x0042` | Max discharge limit | Setting, 0.1% units |
| `0x0043` | EPS AC charge limit [b] | Mirror of `0x000E` |
| `0x0044` | Whole machine unused time | Setting in minutes |

### Device Startup Registers (FC 0x03 Snapshot - Device Configuration)

Discovered in full holding-register dump (frame 6940 of new.6.pcapng), fetched by app at startup. Likely device capabilities, firmware info, or persistent status:

| Register | Label | Notes |
|----------|-------|-------|
| `0x0001` | Device model/mode info | Device capabilities or model identifier |
| `0x0010` | Power config [a] | Unknown power parameter (0xE800 in capture) |
| `0x0013` | Power config [c] | Unknown power parameter (0x0800 in capture) |
| `0x002B` | Output config [b] | Output-related setting (0x0200 in capture) |
| `0x0031` | Status flags [a] | Persistent status or error indicator (0x2000 in capture) |
| `0x0032` | Status flags [b] | Persistent status or error indicator (0x1200 in capture) |
| `0x0034` | Status flags [c] | Persistent status or error indicator (0x1300 in capture) |
| `0x0040` | Device status [b] | Device status or error log (0x0800 in capture) |
| `0x0045` | Event/error log [a] | Event or error history (0x8400 in capture) |
| `0x0046` | Event/error log [b] | Event or error history (0x1E00 in capture) |

> All register mappings were derived by live observation and diff analysis.
> Some labels are provisional and may be refined with further testing.
> 
> **Correlation & Verification:** The Home Assistant integration in `ha-fossibot/custom_components/fossibot-ha/sydpower/modbus.py` 
> was used to cross-verify register mappings against HA's `parse_registers()` function. Critical fixes applied:
> - Fixed SOC formula: now ÷10 (was ÷2, incorrect)
> - Added `0x000D` (AC charging rate) and `0x0013` (AC output frequency) 
> - Corrected `0x0029` from "Converter power" to "Active output list" (bit-parsed)
> - Added `0x0035` (SOC Slave 1) and `0x0037` (SOC Slave 2)

---

## BLE Protocol Notes

- **Transport**: ATT/L2CAP over BLE (PSM 4, CID 4)
- **Write handle**: `0x0036`
- **Notify handle**: `0x0038`
- **CCCD handle**: `0x0039`
- **Modbus framing**: RTU-over-BLE using slave address `0x11`, function code
  `0x04` (Read Input Registers)
- **CRC byte order**: high byte first (non-standard; confirmed from captures)
- Responses may arrive in multiple BLE notification fragments; the script
  reassembles them automatically

---

## License

See [LICENSE](LICENSE).
