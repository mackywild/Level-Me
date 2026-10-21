import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rebalance_fe_answer_positions import counts, normalize


def question(qid, section, answer):
    return {
        "id": qid,
        "section": section,
        "options": [f"{qid}-{i}" for i in range(4)],
        "answerIndex": answer,
    }


class AnswerPositionBalanceTests(unittest.TestCase):
    def test_balancing_preserves_correct_values_and_uses_each_position_equally(self):
        bank = [
            question(f"FE-{section}-{i:04d}", section, i % 4)
            for section in ("A", "B")
            for i in range(8)
        ]
        expected_answers = {
            q["id"]: q["options"][q["answerIndex"]] for q in bank
        }

        normalized = normalize(bank)

        self.assertEqual(normalize(normalized), normalized)
        self.assertEqual(counts(normalized), {
            "A": {0: 2, 1: 2, 2: 2, 3: 2},
            "B": {0: 2, 1: 2, 2: 2, 3: 2},
        })
        for q in normalized:
            self.assertEqual(q["options"][q["answerIndex"]], expected_answers[q["id"]])
            self.assertEqual(len(set(q["options"])), 4)

    def test_invalid_four_choice_question_is_rejected(self):
        invalid = [question("FE-A-0001", "A", 0)]
        invalid[0]["options"][-1] = invalid[0]["options"][0]
        with self.assertRaises(ValueError):
            normalize(invalid)


if __name__ == "__main__":
    unittest.main()
