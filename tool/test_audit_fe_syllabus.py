import json
import sys
import unittest
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from audit_fe_syllabus import IPA, MIN_A_ITEMS, classify, summarize

BANK = Path(__file__).resolve().parents[1] / "assets/questions/fe_seed.json"


class SyllabusCoverageTests(unittest.TestCase):
    def test_all_current_items_are_mapped_and_thin_categories_are_reported(self):
        questions = json.loads(BANK.read_text(encoding="utf-8"))
        counts, unmapped = summarize(questions)
        self.assertEqual(unmapped, {})
        section_counts = Counter(q["section"] for q in questions)
        self.assertEqual(section_counts, {"A": 800, "B": 300})
        thin_a = [code for code in IPA if counts[("A", code)] < MIN_A_ITEMS]
        self.assertEqual(thin_a, [])
        self.assertEqual(counts[("A", "18")], 5)
        self.assertEqual(counts[("A", "20")], 5)
        self.assertEqual(counts[("A", "21")], 5)

    def test_new_questions_cover_hardware_ui_media_and_technology_strategy(self):
        self.assertEqual(classify({"section": "A", "subdomain": "ハードウェア（センサー）"}), "06")
        self.assertEqual(classify({"section": "A", "subdomain": "ユーザーインタフェース（アクセシビリティ）"}), "07")
        self.assertEqual(classify({"section": "A", "subdomain": "情報メディア（音声・画像）"}), "08")
        self.assertEqual(classify({"section": "A", "subdomain": "経営戦略（技術戦略）"}), "20")

    def test_section_b_uses_its_two_exam_categories(self):
        self.assertEqual(classify({"section": "B", "domain": "algorithm"}), "B-ALGORITHM")
        self.assertEqual(classify({"section": "B", "domain": "security"}), "B-SECURITY")

    def test_ipa_taxonomy_has_23_middle_classifications(self):
        self.assertEqual(len(IPA), 23)
        self.assertEqual(IPA["23"], "法務")


if __name__ == "__main__":
    unittest.main()
