#!/usr/bin/env python3
"""Validate the offline FE question bank before every APK build."""
import json
import re
import sys
from collections import Counter
from pathlib import Path

path = Path("assets/questions/fe_seed.json")
questions = json.loads(path.read_text(encoding="utf-8"))
errors = []
ids = set()
stems = set()
def norm(value):
    return re.sub(r"\s+", "", value).casefold()

if not isinstance(questions, list):
    errors.append("Question bank must be a list")
    questions = []

for i, q in enumerate(questions, 1):
    prefix = f"question {i}"
    if not isinstance(q, dict):
        errors.append(f"{prefix}: not an object")
        continue
    for key in ("id", "section", "domain", "stem", "options", "answerIndex", "explanation"):
        if key not in q:
            errors.append(f"{prefix}: missing {key}")
    if any(key not in q for key in ("id", "section", "domain", "stem", "options", "answerIndex", "explanation")):
        continue
    qid = q["id"]
    if not isinstance(qid, str) or not re.fullmatch(r"FE-[AB]-\d{4,}", qid):
        errors.append(f"{prefix}: invalid id")
    elif qid in ids:
        errors.append(f"{prefix}: duplicate id {qid}")
    ids.add(qid)
    if q["section"] not in ("A", "B"):
        errors.append(f"{prefix}: invalid section")
    elif isinstance(qid, str) and not qid.startswith("FE-" + q["section"] + "-"):
        errors.append(f"{prefix}: id/section mismatch")
    if not isinstance(q["domain"], str) or not q["domain"].strip():
        errors.append(f"{prefix}: missing domain")
    stem = q["stem"]
    if not isinstance(stem, str) or len(stem.strip()) < 12:
        errors.append(f"{prefix}: question too short")
    else:
        normalized = norm(stem)
        if normalized in stems:
            errors.append(f"{prefix}: duplicate stem")
        stems.add(normalized)
    options = q["options"]
    if not isinstance(options, list) or len(options) != 4 or any(not isinstance(o, str) or not o.strip() for o in options):
        errors.append(f"{prefix}: requires four nonempty options")
    elif len({norm(o) for o in options}) != 4:
        errors.append(f"{prefix}: duplicate options")
    answer = q["answerIndex"]
    if type(answer) is not int or not 0 <= answer < 4:
        errors.append(f"{prefix}: invalid answerIndex")
    if not isinstance(q["explanation"], str) or len(q["explanation"].strip()) < 6:
        errors.append(f"{prefix}: explanation too short")
    if q.get("reviewStatus") not in ("initial-draft", "reviewed"):
        errors.append(f"{prefix}: invalid reviewStatus")
    if not isinstance(q.get("syllabusVersion"), str) or not q["syllabusVersion"].strip():
        errors.append(f"{prefix}: missing syllabusVersion")

counts = Counter(q.get("section") for q in questions if isinstance(q, dict))
print(f"FE questions: total={len(questions)} A={counts['A']} B={counts['B']}")
print(f"Reviewed: {sum(q.get('reviewStatus') == 'reviewed' for q in questions if isinstance(q, dict))}")
if errors:
    print("\n".join("ERROR: " + e for e in errors))
    sys.exit(1)
print("Structural validation passed. Semantic similarity, answer correctness, and syllabus compliance still require expert review.")
