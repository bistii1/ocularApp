#!/usr/bin/env python3
"""Quick validation harness for PLR result usability logic."""

import os
import sys

BACKEND_DIR = os.path.dirname(os.path.dirname(__file__))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

from python.plr_validation import evaluate_plr_result


def _assert(condition, message):
    if not condition:
        raise AssertionError(message)


def run_validation_checks():
    good_case = {
        "onset_time_s": 0.24,
        "peak_constriction_time_s": 0.62,
        "recovery_time_s": 1.35,
        "max_constriction_pct": 28.0,
        "quality_score": 82.0,
        "n_frames": 70,
        "baseline_stability_pct": 4.0,
        "signal_dynamic_pct": 18.0,
    }

    weak_case = {
        "onset_time_s": 0.0,
        "peak_constriction_time_s": 0.12,
        "recovery_time_s": None,
        "max_constriction_pct": 0.4,
        "quality_score": 22.0,
        "n_frames": 14,
        "baseline_stability_pct": 26.0,
        "signal_dynamic_pct": 0.2,
    }

    good_eval = evaluate_plr_result(good_case)
    bad_eval = evaluate_plr_result(weak_case)

    _assert(good_eval["is_plr_usable"], "Good case should be usable")
    _assert(good_eval["validation_score"] >= 70, "Good case should have high validation score")
    _assert(not bad_eval["is_plr_usable"], "Weak case should not be usable")
    _assert("no_reliable_constriction" in bad_eval["validation_failures"], "Weak case should fail constriction")

    print("PLR validation harness: PASS")
    print("Good case verdict:", good_eval["plr_verdict"], "score=", good_eval["validation_score"])
    print("Weak case verdict:", bad_eval["plr_verdict"], "score=", bad_eval["validation_score"])


if __name__ == "__main__":
    run_validation_checks()
