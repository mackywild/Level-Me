import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from audit_fe_syllabus import IPA, classify, summarize

BANK = Path(__file__).resolve().parents[1] / "assets/questions/fe_seed.json"


class SyllabusCoverageTests(unittest.TestCase):
    def test_all_current_items_have_a_taxonomy_mapping(self):
        questions = json.loads(BANK.read_text(encoding="utf-8"))
        _, unmapped = summarize(questions)
        self.assertEqual(unmapped, {})

    def test_section_b_uses_its_two_exam_categories(self):
        self.assertEqual(classify({"section": "B", "domain": "algorithm"}), "B-ALGORITHM")
        self.assertEqual(classify({"section": "B", "domain": "security"}), "B-SECURITY")

    def test_ipa_taxonomy_has_23_middle_classifications(self):
        self.assertEqual(len(IPA), 23)
        self.assertEqual(IPA["23"], "法務")


if __name__ == "__main__":
    unittest.main()
