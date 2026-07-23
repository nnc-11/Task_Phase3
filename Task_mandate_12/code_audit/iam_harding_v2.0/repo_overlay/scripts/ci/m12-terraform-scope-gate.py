#!/usr/bin/env python3
"""Keep IAM and Audit Foundation changes out of the normal production apply."""

import json
import sys
from pathlib import Path


AUDIT_FOUNDATION_ADDRESS_MARKERS = (
    "audit_detection_",
    "m12_audit_heartbeat",
    "m12_heartbeat",
)

# Boundary phải deny hai API này với Resource="*" vì IAM/SNS không match exact
# topic ARN cho subscription mutation. Chặn resource type tương ứng từ plan để
# normal apply không chạy một phần rồi fail, kể cả subscription ngoài audit.
BOUNDARY_GLOBAL_RESOURCE_TYPES = {
    "aws_sns_topic_subscription",
}


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: m12-terraform-scope-gate.py <tfplan.json>", file=sys.stderr)
        return 2

    plan_path = Path(sys.argv[1])
    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    violations: list[str] = []

    for change in plan.get("resource_changes", []):
        address = change.get("address", "<unknown>")
        mode = change.get("mode", "managed")
        resource_type = change.get("type", "")
        actions = change.get("change", {}).get("actions", [])
        if mode != "managed" or actions in ([], ["no-op"], ["read"]):
            continue

        if resource_type.startswith("aws_iam_"):
            violations.append(f"IAM: {address}: {','.join(actions)}")
            continue

        if resource_type in BOUNDARY_GLOBAL_RESOURCE_TYPES:
            violations.append(
                f"Boundary-global SNS subscription: {address}: {','.join(actions)}"
            )
            continue

        if any(marker in address for marker in AUDIT_FOUNDATION_ADDRESS_MARKERS):
            violations.append(
                f"Audit Foundation: {address}: {','.join(actions)}"
            )

    if violations:
        print(
            "BLOCKED: normal production plan contains boundary-protected changes.",
            file=sys.stderr,
        )
        print(
            "Move IAM changes to the reviewed bootstrap path and Audit Foundation "
            "changes to its approved maintenance path:",
            file=sys.stderr,
        )
        for violation in violations:
            print(f"  - {violation}", file=sys.stderr)
        return 1

    print("PASS: no boundary-protected changes in the normal production plan.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
