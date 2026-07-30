"""delivery_report v2 + ADR-0004 checks."""
import json
import os
import tempfile
import unittest

from kernel.metrics.delivery_report import adr0004_gate, build_delivery_report, v2_completeness_warnings


class TestDeliveryReport(unittest.TestCase):
    def test_v2_warnings_missing_timing(self):
        w = v2_completeness_warnings({"timing": {}, "review_provenance": {"model_invocations": 1}, "loops": {"review_rounds": 0}})
        self.assertIn("timing.plan_ms", w)

    def test_adr_strict_blocks(self):
        with tempfile.TemporaryDirectory() as td:
            path = os.path.join(td, "delivery-quality.json")
            doc = {
                "schema_version": 2,
                "timing": {},
                "review_provenance": {},
                "loops": {},
                "incomplete_metrics": ["timing.plan_ms"],
            }
            json.dump(doc, open(path, "w"))
            state = os.path.join(td, "state.json")
            json.dump({"quality_policy": {"tier": "strict"}}, open(state, "w"))
            code, msgs = adr0004_gate(path, state)
            self.assertEqual(code, 2)
            self.assertTrue(msgs)

    def test_build_minimal(self):
        with tempfile.TemporaryDirectory() as td:
            handoff = os.path.join(td, "handoff")
            os.makedirs(handoff)
            for s in ("plan", "implement", "quality", "review", "complete"):
                json.dump({"stage": s, "schema_version": 1, "gate": {}}, open(os.path.join(handoff, f"{s}.json"), "w"))
            ev = os.path.join(td, "evidence")
            os.makedirs(ev)
            rep = build_delivery_report(handoff=handoff, goal_evidence=ev, repo_task=td, pipeline_id="goal-pipeline")
            self.assertEqual(rep["schema_version"], 2)
            self.assertIn("timing", rep)


if __name__ == "__main__":
    unittest.main()
