# LEVEL ME – Game Design v0.2

## Player progression
Real-life quest completion earns six attributes and overall player EXP. Next-level requirement is 100 + 25 × (current level - 1).

## Quest cadence
- One-time completion.
- Daily reset at local midnight.
- Weekly reset Monday local time.
- Repeat claims in a period are rejected by the controller.

## Combat
Each completed quest deals 1–100 HP damage, capped by total quest EXP. The initial boss has 300 HP. On defeat the boss regenerates with its defeat count incremented and grants +80 Discipline EXP. Boss victories unlock automatic achievement thresholds.

## Trophy collection
12 achievements automatically unlock based on quest clears, boss defeats, streaks, level and attribute EXP. Each catalog ID rewards only once. Users can also register manual milestones.

## Production hardening backlog
- Durable transactional event log and SQLite migrations.
- Notification schedule, backup/import/export and data recovery.
- Art direction, level-up animation, multi-boss variants, rarity and progression.
- Android signing key stored securely, Play Store release pipeline.
- STOIC SCHEDULER import via idempotent completion-event IDs.
- Improve self-reporting abuse controls; do not treat honor-system EXP as verified data.
