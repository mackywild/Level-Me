# PR #30 review response — v0.4 WORLD AWAKENING

| ID | Change |
|---|---|
| RV-001 | Persist sub-interval natural recovery at battle start and restore it at battle end. No natural recovery during combat. |
| RV-002 | Legacy boss gives 80 G; former creativity EXP gacha outcome gives 50 G; boss trophies give no ability EXP. Existing earned EXP and ticket counts remain. |
| RV-003 | Additional same-day timed sessions restore energy without repeat EXP. Study 15/25 min, workout 15/30 min; 120-min per-session input cap. Session ID guards against replays and stale checkpoints. |
| RV-004 | JSON encounter master validation, stable padded stage IDs and runtime loading before save validation. |
| RV-005 | App version 0.4.0+4; independent v2 player save and portable backup format v2. Read legacy v1 on first migration, do not overwrite it. Accept v1 backup imports explicitly. |

## Compatibility
Existing v0.3 player file remains unchanged; v0.4 writes v2. Downgrade is unsupported: v0.3 would use the old snapshot and share FE files, so changes made after downgrade are not merged back. v0.3 cannot import v2 external backups. Do not uninstall or downgrade to resolve APK signing issues. Explicitly restoring an old v1 backup replaces current data including WORLD progress; confirmation is required. Keep a current external backup before restore.

## Verification
Added nine regression tests (recovery, stage IDs, invalid master, additional study/workout, legacy EXP, migration, v1 import, active battle backup). CI must pass on the current PR head. Android upgrade, signing compatibility, UI and forced-exit tests remain device acceptance requirements.
