#!/usr/bin/env python3
"""Self-contained tests for the production Terraform scope gate."""

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GATE = ROOT / "repo_overlay/scripts/ci/m12-terraform-scope-gate.py"
CASES = {
    "tfplan-no-iam.json": 0,
    "tfplan-data-iam-read.json": 0,
    "tfplan-with-iam.json": 1,
    "tfplan-with-audit.json": 1,
    "tfplan-with-sns-subscription.json": 1,
}


def main() -> int:
    failures: list[str] = []
    for fixture, expected in CASES.items():
        result = subprocess.run(
            [sys.executable, str(GATE), str(ROOT / "tests" / fixture)],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != expected:
            failures.append(
                f"{fixture}: expected {expected}, got {result.returncode}\n"
                f"stdout={result.stdout}\nstderr={result.stderr}"
            )
        else:
            print(f"PASS {fixture}: exit {result.returncode}")

    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
