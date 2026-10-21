# LEVEL ME — FE study and workout implementation specification

## Exam baseline
- 2026: current CBT Fundamental Information Technology Engineer Examination, Section A/B.
- 2027 syllabus draft v0.1 (IPA, 2026-09-30) is provisional; version every question against a syllabus revision.
- Source: https://www.ipa.go.jp/shiken/syllabus/henkou/2026/20260630.html
- Original authored items only. Do not claim an unverified corpus is complete.

## FE question bank acceptance criteria
- 1,100 distinct reviewed questions: 800 Section A, 300 Section B.
- Fields: immutable ID, section, syllabusVersion, domain, subdomain, difficulty, stem, options, correct answer, detailed rationale, distractor rationales, reference URL, authoring version.
- Section B supports pseudocode, tracing tables and security case studies.
- Deduplicate by normalized stem, semantic similarity, algorithmic structure, and human review. Validate exactly one answer, rationale consistency and syllabus coverage.
- Store reviewed questions as versioned offline assets. No unreviewed template permutations.

## Study session
- The daily `starter-study` quest is the entry point for FE study; its session contains the timer and access to the A/B question bank. There is no separate preview entry.
- START -> monotonic elapsed-time clock; questions can be opened while the session timer runs.
- PAUSE/RESUME/FINISH; app background/foreground reconciliation.
- Credit elapsed active seconds, not answered-question count; daily credit cap prevents idle farming.
- On finish persist session, attempts and incorrect-question IDs before issuing EXP.
- Generate a review quest from incorrect/flagged question IDs; opening it starts a timed session filtered to those questions. A review quest cannot be completed merely by creation.
- Never overwrite an incomplete session silently.

## Exam-day quest
- User chooses exam date and manually creates one-time exam quest.
- Exam attendance and official result are distinct events.
- Marking exam completed does not equal passing. User confirms passing separately.
- On confirmed pass, unlock achievement, archive FE curriculum from future routine generation, preserve question history and permit manual reactivation.
- Prevent duplicate achievement and EXP claims.

## Workout
- START/PAUSE/RESUME/FINISH elapsed-time session.
- Local MP3 picker, playlist, playback/pause/repeat, permissions scoped to selected files.
- Playback survives navigation; handle interruptions and unavailable file gracefully.
- Never bundle copyrighted tracks without redistribution rights.

## Integration and data integrity
- Session events have stable IDs and idempotent reward claims.
- Persist session/review/attempt records transactionally, with schema version and migration.
- STOIC SCHEDULER events can import using external event IDs without double-awarding.
- Time and XP calculations unit tested, including timezone changes, background, crash recovery.

## Release gates
- Flutter analyze/test; Android instrumented launch smoke test.
- Study resume, review generation, MP3 playback, pass/archive and data migration tested on physical Android.
- No user-data wipe to resolve plugin issues.
