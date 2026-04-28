#!/usr/bin/env python3
"""Add summary field to grading.json files."""
import json
import os

WORKSPACE = os.path.dirname(os.path.abspath(__file__))

for eval_dir in sorted(os.listdir(WORKSPACE)):
    if not eval_dir.startswith("eval-"):
        continue
    for config in ["with_skill", "without_skill"]:
        path = os.path.join(WORKSPACE, eval_dir, config, "run-1", "grading.json")
        if not os.path.exists(path):
            continue
        with open(path) as f:
            data = json.load(f)

        expectations = data.get("expectations", [])
        passed = sum(1 for e in expectations if e.get("passed"))
        failed = len(expectations) - passed
        total = len(expectations)
        pass_rate = passed / total if total > 0 else 0.0

        data["summary"] = {
            "pass_rate": pass_rate,
            "passed": passed,
            "failed": failed,
            "total": total
        }

        # Add timing from sibling file
        timing_path = os.path.join(WORKSPACE, eval_dir, config, "run-1", "timing.json")
        if os.path.exists(timing_path):
            with open(timing_path) as f:
                timing = json.load(f)
            data["timing"] = timing
            data["execution_metrics"] = {
                "total_tool_calls": 0,
                "output_chars": len(str(data)),
                "errors_encountered": 0
            }

        with open(path, 'w') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print(f"Updated {eval_dir}/{config}: {passed}/{total} passed")

print("Done")
