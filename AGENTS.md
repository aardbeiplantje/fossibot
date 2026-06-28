# Fossibot Analysis & Verification Agent Instructions

## Context
This workspace contains `fossibot.pl`, a Perl script that communicates with the **Fossibot F1200** portable power station via BLE using Modbus-RTU-over-BLE protocol. There are 8 `.pcapng` capture files containing actual ATT/L2CAP traffic for cross-referencing against the code and register mappings in README.md.

## Architecture
- **Main script**: `fossibot.pl` (1,950 lines), all-in-one Perl file with embedded class `Fossibot::F1200`
- **Pure-perl BLE**: Direct L2CAP socket (`AF_BLUETOOTH / SOCK_SEQPACKET / BTPROTO_L2CAP`), no BlueZ D-Bus, no external modules needed
- **Protocol**: ATT requests over BLE → Modbus-RTU payload tunnelled in handle 0x36 writes → notifications on handle 0x38 (with CCCD subscribe at 0x39)

## Current Known Issues
- **Register `0x0029` label inconsistency in code** (still unfixed): In `fossibot_register_pretty` (~line 1557-1558) the holding register branch labels it as "Converter info", while the input register branch (~line 1648) and README correctly label it as "Active output list" with bit-parsing. The input register interpretation is correct per HA integration — the holding branch needs updating.

## Workflow for Verification Tasks
1. Use `tshark -V` or Python script for PCAPNG analysis; do NOT attempt raw block-walking
2. grep verbose output for `ATT - Handle Value Notification` or Client Characteristic Configuration descriptors (handle 0x39)
3. Cross-reference function codes and register ranges against the README decoded registers tables
4. Report PASS/FAIL per constant, flag any discrepancies with current code

## Capture Files
All `.pcapng` files are in the repository root:
| File | Frames | Size | Notes |
|------|--------|------|-------|
| `change_screen_timeout.pcapng` | 7,831 | 588 KB | Screen timeout write session |
| `new.pcapng` | 9,063 | 665 KB | Baseline session |
| `new.1.pcapng` – `new.6.pcapng` | 6,409–17,797 | ~2.8 MB total | Multiple poll/stream sessions |

## What to Verify Per Session/Task
- Modbus slave address (should be `0x11` — prior session's reported mismatch with `0xF6` was confirmed fixed in code)
- Function codes: FC03 = `f1200_send_read()` (63×), FC04 = `f1200_send_poll()` (41×), FC06 = single-register write, FC07 = diagnostics/test
- ATT write handle should be `F1200_WRITE_HANDLE` constant (0x36)
- Register read spans: app reads 0x0000..0x004F consistently per FC03/FC04
- When touching decoder logic, verify `0x0029` handling in both the holding register branch (~line 1557) and input register branch (~line 1648) are consistent

## Related Projects
The Home Assistant integration (`sydpower/modbus.py`) was used to cross-verify register mappings. Notable fixes verified there: SOC formula now ÷10, `0x0029` reclassified from "Converter power" to "Active output list", and new registers `0x0035`, `0x0037` (SOC Slave 1/2).

## Key Verification Status (from PCAPNG Report in README.md)
All constants verified as PASS against 8 captures (88,753 frames total):
- Slave address `0x11` | Write handle `0x0036` | Notify handle `0x0038` | CCCD handle `0x0039`
- Service UUID `0xA002` | FC03/FC04/FC06/FC07 | Register span 0x0000..0x004F (80 regs)
- CRC high-byte-first | Modbus payload structure | SOC ÷10 formula
