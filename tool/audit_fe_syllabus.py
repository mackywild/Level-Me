#!/usr/bin/env python3
"""Map FE question labels to IPA FE syllabus Ver.9.2 middle classifications.

The mapping measures taxonomy coverage from editorial labels. It does not establish
that an item's wording, answer, or explanation satisfies the mapped syllabus item.
"""
import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

BANK = Path(__file__).resolve().parents[1] / "assets/questions/fe_seed.json"

# IPA Ver.9.2 中分類 (middle classifications).
IPA = {
    "01": "基礎理論", "02": "アルゴリズムとプログラミング",
    "03": "コンピュータ構成要素", "04": "システム構成要素",
    "05": "ソフトウェア", "06": "ハードウェア",
    "07": "ユーザーインタフェース", "08": "情報メディア",
    "09": "データベース", "10": "ネットワーク", "11": "セキュリティ",
    "12": "システム開発技術", "13": "ソフトウェア開発管理技術",
    "14": "プロジェクトマネジメント", "15": "サービスマネジメント",
    "16": "システム監査", "17": "システム戦略", "18": "システム企画",
    "19": "経営戦略マネジメント", "20": "技術戦略マネジメント",
    "21": "ビジネスインダストリ", "22": "企業活動", "23": "法務",
}
B_CATEGORIES = {
    "B-ALGORITHM": "科目B：擬似言語・アルゴリズム",
    "B-SECURITY": "科目B：情報セキュリティ",
}


def classify(q):
    """Return an IPA middle-classification code, B category, or None."""
    if q.get("section") == "B":
        return {"algorithm": "B-ALGORITHM", "security": "B-SECURITY"}.get(q.get("domain"))

    label = q.get("subdomain", "")
    stem = q.get("stem", "")
    if label.startswith("基礎理論") or label == "情報に関する理論・AI":
        return "01"
    if label.startswith("アルゴリズムとプログラミング"):
        return "02"
    if label.startswith("コンピュータシステム"):
        detail = label.partition("（")[2].rstrip("）")
        if any(w in detail for w in ("OS", "ファイル", "開発ツール", "OSS")):
            return "05"
        if any(w in detail for w in ("信頼性", "障害", "稼働率", "性能", "クラウド", "仮想化", "運用")):
            return "04"
        if detail in ("AI", "コンパイラ"):
            return "01"
        if any(w in detail for w in ("データベース", "データ管理")):
            return "09"
        return "03"
    if label.startswith("データベース"):
        return "09"
    if label.startswith("ネットワーク"):
        return "11" if "セキュリティ" in label else "10"
    if label.startswith(("セキュリティ", "情報セキュリティ")):
        return "11"
    if label.startswith("ソフトウェア"):
        if any(w in label for w in ("開発モデル", "開発技法", "保守")):
            return "13"
        if any(w in label for w in ("テスト", "要求", "設計", "品質", "構造")):
            return "12"
        return "05"
    if label == "プロジェクトマネジメント・サービスマネジメント":
        return "15" if any(w in stem for w in ("サービス", "インシデント", "SLA", "可用性")) else "14"
    if label.startswith("プロジェクトマネジメント"):
        return "14"
    if label.startswith("サービスマネジメント"):
        return "15"
    if label.startswith("システム監査"):
        return "16"
    if label.startswith("企業活動・経営戦略"):
        return "22" if any(w in stem for w in ("会計", "利益", "原価", "財務", "在庫")) else "19"
    if label.startswith("企業活動"):
        return "22"
    if label.startswith("法務"):
        return "23"
    if label.startswith("経営戦略"):
        if "システム企画" in label:
            return "18"
        if any(w in label for w in ("システム戦略", "業務分析", "業務改善")):
            return "17"
        if "技術" in label:
            return "20"
        if "ビジネスモデル" in label:
            return "21"
        return "19"
    return None


def summarize(questions):
    counts = Counter()
    unmapped = defaultdict(list)
    for q in questions:
        code = classify(q) if isinstance(q, dict) else None
        if code:
            counts[(q["section"], code)] += 1
        elif isinstance(q, dict):
            unmapped[(q.get("section", "?"), q.get("subdomain", "(missing)"))].append(q.get("id", "?"))
    return counts, unmapped


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--strict", action="store_true", help="fail if a label is unmapped or an A middle classification has no questions")
    args = parser.parse_args()
    questions = json.loads(BANK.read_text(encoding="utf-8"))
    counts, unmapped = summarize(questions)
    totals = Counter(q.get("section") for q in questions if isinstance(q, dict))
    print("Syllabus label coverage (taxonomy mapping only; content-level fit requires review)")
    for section in ("A", "B"):
        codes = IPA if section == "A" else B_CATEGORIES
        mapped = sum(counts[(section, code)] for code in codes)
        print(f"Section {section}: mapped={mapped}/{totals[section]}")
        for code, name in codes.items():
            print(f"  {code} {name}: {counts[(section, code)]}")
    empty_a = [code for code in IPA if counts[("A", code)] == 0]
    if empty_a:
        print("Uncovered A middle classifications: " + ", ".join(f"{code} {IPA[code]}" for code in empty_a))
    else:
        print("Uncovered A middle classifications: 0")
    if unmapped:
        print(f"Unmapped label groups: {len(unmapped)}")
        for (section, label), ids in sorted(unmapped.items()):
            print(f"  {section} {label}: {len(ids)} ({', '.join(ids[:8])})")
        return 1 if args.strict else 0
    print(f"Unmapped questions: 0/{len(questions)}")
    return 1 if args.strict and empty_a else 0


if __name__ == "__main__":
    raise SystemExit(main())
