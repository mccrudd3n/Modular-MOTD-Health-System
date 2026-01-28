# State File Format Specification

All scripts in `checks/` must output a POSIX-safe key-value file to `/run/motd-health/<pillar>.state`.

## Variables
- **STATUS**: (Required) Must be one of `PASS`, `WARN`, or `FAIL`.
- **SUMMARY**: (Required) A single concise sentence describing the state.
- **DETAIL**: (Optional) Specific technical data. Can be repeated.
- **REMEDIATE**: (Required if STATUS != PASS) Absolute path to a command or script to fix the issue.

## Example
STATUS=FAIL
SUMMARY=ZFS pool degraded
DETAIL=rpool DEGRADED (2 CKSUM)
REMEDIATE=/usr/sbin/zpool status -v
