# Fossibot Verification Agent Instructions

## Context
This workspace contains `fossibot.pl`, a Perl script that communicates with the **Fossibot F1200** portable power station via BLE using Modbus-RTU-over-BLE protocol. We have 8 `.pcapng` capture files containing actual ATT/L2CAP traffic for cross-referencing.

## Key Findings So Far
- **Slave Address Mismatch**: Script defines `0xF6`, but all captured Write Requests use slave byte `0x11` (17) → CRITICAL FIX NEEDED
- **Tooling Limitation**: tshark v4.x lacks BLE-specific `-Y` field extraction; must use verbose dump (`tshark -V`) + Python regex parsing
- **Modbus Payload Structure** (from captures, 8 bytes total): `[slave=0x11][FC][reg_hi reg_lo LE][count/value][CRC hi CRC lo LE]`
- **Handles Verified**: Write `0x36` [OK], Notify `0x38` [needs investigation - reported 0 in scan], CCCD `0x39` [OK, 20 ops]

## Workflow for Verification Tasks
1. Use `tshark -r <file> -V` piped to Python for parsing; do NOT attempt raw PCAPNG block-walking
2. grep for `ATT - Handle Value Notification` or `Attribute Type: Client Characteristic Configuration` in verbose output
3. Cross-reference all Modbus FCs and register spans against the README decoded registers table
4. Report PASS/FAIL per constant, flag any discrepancies

## Capture Files
Located in `/workspace/fossibot.git/*.pcapng`:
| File | Frames | Approx Size | Notes |
|------|--------|-------------|-------|
| `change_screen_timeout.pcapng` | 7831 | 588 KB | Screen timeout write |
| `new.pcapng` | 9063 | 665 KB | Baseline session |
| `new.1.pcapng` – `new.6.pcapng` | 6409–17797 | ~5 MB total | Multiple poll/stream sessions |

## What to Verify Per Session/Task
- Modbus slave address (expect `0x11`, flag if anything else)
- Function codes: FC03 (63), FC04 (41), FC06 (11), FC07 (2) — cross-check counts
- ATT write handle = 0x36, notify handle = 0x38, CCCD handle = 0x39
- Register read spans: should be 0x0000..0x004F (80 registers) per FC03/FC04
