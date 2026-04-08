"""Validation helpers for making PLR outputs interpretable and testable."""

from typing import Dict, List

# Paper-derived broad ranges for first-pass validation.
# These are intentionally permissive and used for warning-level checks,
# not strict clinical diagnosis.
NORMATIVE_RANGES = {
    "onset_time_s": (0.15, 0.40),
    "max_constriction_pct": (10.0, 60.0),
    "recovery_time_s": (0.50, 2.50),
}


def evaluate_plr_result(result: Dict) -> Dict:
    """Return usability metadata and validation diagnostics for PLR output."""
    warnings: List[str] = []
    failures: List[str] = []
    validation_score = 100.0

    onset = float(result.get("onset_time_s", 0.0) or 0.0)
    peak = float(result.get("peak_constriction_time_s", 0.0) or 0.0)
    recovery = result.get("recovery_time_s", None)
    constriction = float(result.get("max_constriction_pct", 0.0) or 0.0)
    quality_score = float(result.get("quality_score", 0.0) or 0.0)
    n_frames = int(result.get("n_frames", 0) or 0)
    baseline_stability_pct = float(result.get("baseline_stability_pct", 100.0) or 100.0)
    signal_dynamic_pct = float(result.get("signal_dynamic_pct", 0.0) or 0.0)

    if n_frames < 20:
        failures.append("too_few_frames_for_plr")
        validation_score -= 35

    if constriction < 2.0:
        failures.append("no_reliable_constriction")
        validation_score -= 35
    elif constriction < NORMATIVE_RANGES["max_constriction_pct"][0]:
        warnings.append("constriction_below_typical_range")
        validation_score -= 12

    if onset <= 0:
        failures.append("onset_not_detected")
        validation_score -= 25
    elif onset < 0.08 or onset > 1.20:
        warnings.append("onset_outside_expected_window")
        validation_score -= 10

    if peak <= onset and constriction >= 2.0:
        failures.append("invalid_peak_timing")
        validation_score -= 20

    if recovery is None:
        warnings.append("recovery_not_detected")
        validation_score -= 8
    else:
        recovery_val = float(recovery)
        if recovery_val <= peak:
            failures.append("invalid_recovery_timing")
            validation_score -= 15
        elif recovery_val < NORMATIVE_RANGES["recovery_time_s"][0] or recovery_val > NORMATIVE_RANGES["recovery_time_s"][1]:
            warnings.append("recovery_outside_typical_range")
            validation_score -= 6

    if baseline_stability_pct > 20.0:
        failures.append("unstable_baseline")
        validation_score -= 20
    elif baseline_stability_pct > 12.0:
        warnings.append("baseline_variability_high")
        validation_score -= 8

    if signal_dynamic_pct < 1.0:
        failures.append("insufficient_signal_dynamic_range")
        validation_score -= 20

    if quality_score < 35:
        failures.append("low_algorithm_confidence")
        validation_score -= 15
    elif quality_score < 55:
        warnings.append("algorithm_confidence_moderate")
        validation_score -= 6

    validation_score = max(0.0, min(100.0, validation_score))
    is_usable = len(failures) == 0

    if is_usable and validation_score >= 80:
        verdict = "usable_strong"
    elif is_usable:
        verdict = "usable_with_caution"
    else:
        verdict = "not_usable"

    return {
        "validation_score": round(validation_score, 1),
        "is_plr_usable": is_usable,
        "plr_verdict": verdict,
        "validation_warnings": warnings,
        "validation_failures": failures,
    }
