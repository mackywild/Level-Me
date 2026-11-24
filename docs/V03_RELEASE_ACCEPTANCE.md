# v0.3 FOUNDATION — release candidate acceptance

## CI gates
- Strict FE bank audit and strict syllabus coverage, answer position check.
- Flutter analysis and all unit tests.
- Release APK generation, certificate verification and artifact upload.
- Verify success against the current PR head, not an earlier run.

## FE audit (2026-11-24)
Bank blob: 381417ae6b511666c234f4aead0b4992359f8ee1. CI #103 passed the data checks before failing unrelated Dart syntax.
- A 800, B 300; all labels mapped; no lexical duplicate candidates at the configured threshold.
- Correct positions A: 200 each; B: 75 each.
- B pool: 194 algorithm, 106 security. Mock selection separately uses 16/4.
- All 1,100 carry reviewed metadata, but this is not independent semantic review. Distractor rationales absent in all 1,100.
- Sample inspected (20): A-0001/0002/0003/0004/0005/0160/0273/0386/0499/0615/0728/0841; B-0067/0149/0186/0223/0260/0297/0334/0371. No obvious answer/explanation mismatch in this sample; some questions are too easy for a realistic exam (e.g. B-0149 integer division, B-0186 swap, B-0371 trivial distractors). Keep question IDs and recorded history intact; improve complexity and distractor quality in a dedicated curriculum PR. Full semantic correctness/uniqueness not certified.

## Android acceptance
Use a spare device/profile or nonessential test data for destructive/recovery tests. Do not uninstall an existing installation with valuable records.
- [ ] Compare signing certificate of existing APK with candidate. CI prints SHA-256 certificate fingerprint. This project currently generates Android scaffolding in CI and has no committed production signing setup. A certificate mismatch is an upgrade blocker, not a reason to uninstall.
- [ ] Install candidate as an update without clearing app data. Verify EXP, six stats, quests, achievements, tickets and FE answer/flag history.
- [ ] Start study and workout; pause, background, relaunch and resume. Complete once; verify history and single reward.
- [ ] Export JSON via app menu to Downloads. Record values, change player/FE history/flags, then restore. Verify all datasets revert together, including after restart.
- [ ] Cancel picker and confirmation. Reject invalid JSON or unsupported version without changes.
- [ ] Verify recovery after interrupted restore on disposable data (unit test covers journal resume).
- [ ] Verify UI, old data preservation and APK version 0.3.0+3.

Official Android signing reference: https://developer.android.com/studio/publish/app-signing

## Gate decision
Do not mark PR ready or merge while latest CI or required device acceptance is incomplete. An independent full FE content review remains open; do not market this as a verified complete exam curriculum. Stable signing/migration must be agreed if the installed certificate cannot be reused. Never store private signing keys in Git.
