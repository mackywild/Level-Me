#!/usr/bin/env python3
"""Audit FE question-bank completeness and quality signals without overstating review.

The lexical similarity check finds candidates for human review; it cannot prove semantic
uniqueness. A clean audit is not a substitute for syllabus and answer review.
"""
import argparse
import json
import re
import sys
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path

BANK = Path("assets/questions/fe_seed.json")
TARGETS = {"A": 800, "B": 300}
REQUIRED_REVIEW_FIELDS = ("subdomain", "distractorRationales", "referenceUrl")


def normalize(text):
    text = unicodedata.normalize("NFKC", text).casefold()
    return "".join(ch for ch in text if not ch.isspace() and not unicodedata.category(ch)[0] in "PZ")


def trigrams(text):
    compact = normalize(text)
    if len(compact) < 3:
        return {compact} if compact else set()
    return {compact[i:i + 3] for i in range(len(compact) - 2)}


def similarity(a, b):
    left, right = trigrams(a), trigrams(b)
    if not left or not right:
        return 0.0
    return len(left & right) / len(left | right)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--strict", action="store_true",
                        help="fail unless targets and release-quality review gates are satisfied")
    parser.add_argument("--similarity-threshold", type=float, default=0.72,
                        help="Jaccard threshold for lexical duplicate candidates (default: 0.72)")
    args = parser.parse_args()

    questions = json.loads(BANK.read_text(encoding="utf-8"))
    if not isinstance(questions, list):
        raise SystemExit("Question bank root must be a JSON array")

    by_section = Counter(q.get("section") for q in questions if isinstance(q, dict))
    by_domain = defaultdict(Counter)
    by_status = Counter()
    by_syllabus = Counter()
    missing = Counter()
    blockers = []
    for q in questions:
        if not isinstance(q, dict):
            blockers.append("non-object question")
            continue
        section = q.get("section", "?")
        by_domain[section][q.get("domain", "missing")] += 1
        by_status[q.get("reviewStatus", "missing")] += 1
        by_syllabus[q.get("syllabusVersion", "missing")] += 1
        for key in REQUIRED_REVIEW_FIELDS:
            if not q.get(key):
                missing[key] += 1

    candidates = []
    stems = [(q.get("id", f"row-{i}"), q.get("stem", ""))
             for i, q in enumerate(questions) if isinstance(q, dict)]
    shingles = [(qid, stem, trigrams(stem)) for qid, stem in stems]
    for pos, (id_a, stem_a, left) in enumerate(shingles):
        for id_b, stem_b, right in shingles[pos + 1:]:
            score = len(left & right) / len(left | right) if left and right else 0.0
            if score >= args.similarity_threshold:
                candidates.append((score, id_a, id_b, stem_a, stem_b))

    print(f"Questions: {len(questions)}")
    for section in ("A", "B"):
        count = by_section[section]
        print(f"Section {section}: {count}/{TARGETS[section]} (remaining {max(0, TARGETS[section] - count)})")
        if count != TARGETS[section]:
            blockers.append(f"section {section} count is {count}, expected {TARGETS[section]}")
    print("Domain counts:")
    for section in ("A", "B"):
        print(f"  {section}: " + ", ".join(
            f"{domain}={count}" for domain, count in sorted(by_domain[section].items())))
    print("Review status: " + ", ".join(f"{key}={value}" for key, value in sorted(by_status.items())))
    print("Syllabus version: " + ", ".join(f"{key}={value}" for key, value in sorted(by_syllabus.items())))
    print("Missing release-review fields: " + ", ".join(
        f"{key}={missing[key]}" for key in REQUIRED_REVIEW_FIELDS))
    if candidates:
        print(f"Lexical duplicate candidates (Jaccard >= {args.similarity_threshold:.2f}): {len(candidates)}")
        for score, id_a, id_b, stem_a, stem_b in sorted(candidates, reverse=True)[:25]:
            print(f"  {score:.3f} {id_a} / {id_b}: {stem_a} <> {stem_b}")
        blockers.append(f"{len(candidates)} lexical duplicate candidate(s) need human adjudication")
    else:
        print("Lexical duplicate candidates: 0")

    pending = sum(value for key, value in by_status.items() if key != "reviewed")
    if pending:
        blockers.append(f"{pending} question(s) are not marked reviewed")
    for field, count in missing.items():
        if count:
            blockers.append(f"{count} question(s) are missing {field}")
    pending_syllabus = sum(value for key, value in by_syllabus.items()
                           if key in ("missing", "verification-pending"))
    if pending_syllabus:
        blockers.append(f"{pending_syllabus} question(s) lack a confirmed syllabus version")

    if blockers:
        print("Release blockers:")
        for blocker in dict.fromkeys(blockers):
            print(f"  - {blocker}")
        if args.strict:
            return 1
    else:
        print("Automated release checks passed. Human review remains required for semantic uniqueness, syllabus fit, and answer correctness.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
