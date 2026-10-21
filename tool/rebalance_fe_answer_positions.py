#!/usr/bin/env python3
"""Deterministically balance correct-option positions without changing answers.

Run without flags once to normalize the question bank. Use --check in CI to
ensure the saved options still match the deterministic position schedule.
"""
import argparse
import hashlib
import json
import random
from collections import Counter, defaultdict
from pathlib import Path

BANK = Path(__file__).resolve().parents[1] / "assets/questions/fe_seed.json"
SEED = 20261021
POSITION_LIMIT = 0.35


def normalize(questions):
    """Return a copy with stable, evenly distributed answer positions."""
    normalized = json.loads(json.dumps(questions, ensure_ascii=False))
    by_section = defaultdict(list)
    for question in normalized:
        if not isinstance(question, dict):
            raise ValueError("every bank entry must be an object")
        if question.get("section") not in {"A", "B"}:
            raise ValueError(f"unknown section for {question.get('id', '?')}")
        options = question.get("options")
        answer = question.get("answerIndex")
        if (not isinstance(options, list) or len(options) != 4 or
                len(set(options)) != 4 or not isinstance(answer, int) or
                not 0 <= answer < len(options)):
            raise ValueError(f"invalid answer/options for {question.get('id', '?')}")
        by_section[question["section"]].append(question)

    for section, section_questions in by_section.items():
        ids = sorted(q["id"] for q in section_questions)
        random.Random(f"{SEED}:{section}").shuffle(ids)
        target_by_id = {qid: index % 4 for index, qid in enumerate(ids)}
        for question in section_questions:
            correct = question["options"][question["answerIndex"]]
            distractors = sorted(
                option for index, option in enumerate(question["options"])
                if index != question["answerIndex"]
            )
            digest = hashlib.sha256(
                f"{SEED}:{question['id']}:distractors".encode("utf-8")
            ).digest()
            random.Random(int.from_bytes(digest[:8], "big")).shuffle(distractors)
            correct_index = target_by_id[question["id"]]
            options = list(distractors)
            options.insert(correct_index, correct)
            question["options"] = options
            question["answerIndex"] = correct_index
    return normalized


def counts(questions):
    result = {section: Counter() for section in ("A", "B")}
    for question in questions:
        result[question["section"]][question["answerIndex"]] += 1
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="fail if the bank is not in deterministic balanced order")
    args = parser.parse_args()
    source = BANK.read_text(encoding="utf-8")
    questions = json.loads(source)
    normalized = normalize(questions)
    serialized = json.dumps(normalized, ensure_ascii=False, indent=2) + "\n"
    if args.check:
        if source != serialized:
            print("Answer positions/options are not normalized; run this script to update the bank.")
            return 1
    else:
        BANK.write_text(serialized, encoding="utf-8")

    position_counts = counts(normalized)
    failed = False
    for section, section_counts in position_counts.items():
        total = sum(section_counts.values())
        shares = [section_counts[index] / total for index in range(4)] if total else [0] * 4
        print(f"Section {section}: " + ", ".join(
            f"option {index + 1}={section_counts[index]} ({shares[index]:.1%})"
            for index in range(4)
        ))
        if max(shares, default=0) > POSITION_LIMIT:
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
