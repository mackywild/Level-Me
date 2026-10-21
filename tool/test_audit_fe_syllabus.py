import json
import sys
import unittest
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from audit_fe_syllabus import IPA, classify, summarize

BANK = Path(__file__).resolve().parents[1] / "assets/questions/fe_seed.json"


class SyllabusCoverageTests(unittest.TestCase):
    def test_all_current_items_are_mapped_and_known_gaps_are_reported(self):
        questions = json.loads(BANK.read_text(encoding="utf-8"))
        counts, unmapped = summarize(questions)
        self.assertEqual(unmapped, {})
        section_counts = Counter(q["section"] for q in questions)
        self.assertEqual(section_counts, {"A": 800, "B": 300})
        missing_a = [code for code in IPA if counts[("A", code)] == 0]
        self.assertEqual(missing_a, ["06", "07", "08", "20"])

    def test_section_b_uses_its_two_exam_categories(self):
        self.assertEqual(classify({"section": "B", "domain": "algorithm"}), "B-ALGORITHM")
        self.assertEqual(classify({"section": "B", "domain": "security"}), "B-SECURITY")

    def test_ipa_taxonomy_has_23_middle_classifications(self):
        self.assertEqual(len(IPA), 23)
        self.assertEqual(IPA["23"], "法務")


if __name__ == "__main__":
    unittest.main()
