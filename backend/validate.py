#!/usr/bin/env python3
"""
Validation script for the pupilometry pipeline.

Processes one or more videos and produces visual debug output so you can
judge whether the algorithm is finding the real pupil.

Usage:
    python validate.py /path/to/video.mp4
    python validate.py /path/to/folder_of_videos/

Output goes to  backend/validation_output/<video_name>/
    annotated_NNN.jpg   – frame with eye-ROI box + pupil contour overlay
    threshold_NNN.jpg   – binary mask the algorithm thresholds on
    diameter_plot.png   – pupil diameter time series across all frames
    results.json        – full metrics + per-frame diameter array
"""
import json
import os
import sys
from glob import glob
from pathlib import Path

import cv2
import numpy as np

from processing import process_video

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    HAS_MPL = True
except ImportError:
    HAS_MPL = False
    print("WARNING: matplotlib not installed – skipping plot generation")
    print("         pip install matplotlib  to enable plots\n")

VIDEO_EXTS = {".mp4", ".mov", ".avi", ".mkv", ".m4v"}


def validate_video(video_path: str, out_dir: str):
    """Run the pipeline in debug mode and save all visual evidence."""
    print(f"\n{'='*60}")
    print(f"Processing: {video_path}")
    print(f"{'='*60}")

    result = process_video(video_path, debug=True)

    os.makedirs(out_dir, exist_ok=True)

    # --- Save annotated frames + threshold masks ---
    debug_frames = result.pop("debug_frames", [])
    for frame_idx, annotated_bgr, thresh_mask in debug_frames:
        ann_path = os.path.join(out_dir, f"annotated_{frame_idx:03d}.jpg")
        cv2.imwrite(ann_path, annotated_bgr)

        thr_path = os.path.join(out_dir, f"threshold_{frame_idx:03d}.jpg")
        cv2.imwrite(thr_path, thresh_mask)

    # --- Diameter time-series plot ---
    diameters = result.get("diameters", [])
    fps = result.get("fps", 30.0)
    flash_onset = result.get("flash_onset_s", 1.0)
    flash_dur = result.get("flash_duration_s", 1.0)
    if diameters and HAS_MPL:
        time_s = np.arange(len(diameters)) / fps
        fig, ax = plt.subplots(figsize=(10, 4))
        ax.plot(time_s, diameters, linewidth=1.2, color="#564bf5")
        ax.set_xlabel("Time (s)")
        ax.set_ylabel("Pupil diameter (px)")
        ax.set_title(f"PLR Pupil Diameter — {Path(video_path).name}")
        ax.axhline(result["min_diameter_px"], color="green", ls="--", lw=0.8,
                    label=f"min = {result['min_diameter_px']} px")
        ax.axhline(result["max_diameter_px"], color="red", ls="--", lw=0.8,
                    label=f"max = {result['max_diameter_px']} px")
        ax.axvspan(flash_onset, flash_onset + flash_dur,
                   alpha=0.2, color="yellow", label="Flash stimulus")
        ax.axhline(result.get("baseline_diameter_px", 0), color="blue",
                   ls=":", lw=0.8, label=f"baseline = {result.get('baseline_diameter_px', 0)} px")
        ax.legend(fontsize=9)
        ax.grid(True, alpha=0.3)
        fig.tight_layout()
        fig.savefig(os.path.join(out_dir, "diameter_plot.png"), dpi=150)
        plt.close(fig)

    # --- Save results JSON (drop non-serialisable debug_frames) ---
    json_path = os.path.join(out_dir, "results.json")
    serialisable = {k: v for k, v in result.items() if k != "debug_frames"}
    with open(json_path, "w") as f:
        json.dump(serialisable, f, indent=2)

    # --- Print summary ---
    print(f"  Eye detected:    {result['eye_detected']}")
    if result.get("eye_roi"):
        print(f"  Eye ROI (x,y,w,h): {result['eye_roi']}")
    print(f"  Frames analysed: {result['frame_count']}")
    print(f"  FPS:             {result['fps']}")
    valid = [d for d in diameters if d > 0]
    print(f"  Valid measurements: {len(valid)} / {len(diameters)}")
    print(f"  Baseline diam:   {result.get('baseline_diameter_px', '?')} px")
    print(f"  Min diameter:    {result['min_diameter_px']} px")
    print(f"  Max diameter:    {result['max_diameter_px']} px")
    print(f"  Percent change:  {result['percent_change']}%")
    print(f"  Constriction:    {result.get('constriction_pct', '?')}%")
    print(f"  Latency:         {result['latency_ms']} ms")
    print(f"  Output saved to: {out_dir}")
    return result


def run_synthetic_test():
    """Generate a video with known pupil sizes and check accuracy."""
    import tempfile

    print(f"\n{'='*60}")
    print("SYNTHETIC GROUND-TRUTH TEST")
    print(f"{'='*60}")

    ground_truth_diameters = []
    w, h, fps_synth = 320, 240, 30
    tmp = tempfile.NamedTemporaryFile(suffix=".mp4", delete=False)
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(tmp.name, fourcc, float(fps_synth), (w, h))

    for i in range(90):
        frame = np.ones((h, w, 3), dtype=np.uint8) * 200
        # White "eye" background
        cv2.circle(frame, (w // 2, h // 2), 80, (255, 255, 255), -1)
        # Dark pupil with varying radius
        radius = 15 + int(15 * np.sin(i * 0.15))
        cv2.circle(frame, (w // 2, h // 2), radius, (5, 5, 5), -1)
        ground_truth_diameters.append(radius * 2)
        writer.write(frame)
    writer.release()

    result = process_video(tmp.name, debug=True)
    measured = result.get("diameters", [])
    os.unlink(tmp.name)

    gt = np.array(ground_truth_diameters, dtype=float)
    ms = np.array(measured, dtype=float)

    if len(ms) == 0 or all(m == 0 for m in ms):
        print("  FAIL: algorithm measured 0 in every frame")
        return

    paired_errors = []
    for g, m in zip(gt, ms):
        if m > 0:
            paired_errors.append(abs(m - g))

    if not paired_errors:
        print("  FAIL: no valid measurements to compare")
        return

    errors = np.array(paired_errors)
    print(f"  Frames with valid measurements: {len(errors)} / {len(gt)}")
    print(f"  Mean absolute error:  {errors.mean():.2f} px")
    print(f"  Max absolute error:   {errors.max():.2f} px")
    print(f"  Median absolute error: {np.median(errors):.2f} px")
    print(f"  Ground truth range:   {gt.min():.0f} – {gt.max():.0f} px")
    print(f"  Measured range:       {ms[ms > 0].min():.1f} – {ms[ms > 0].max():.1f} px")

    gt_min, gt_max = float(gt.min()), float(gt.max())
    ms_min = float(result["min_diameter_px"])
    ms_max = float(result["max_diameter_px"])
    print(f"\n  GT  min/max diameter: {gt_min} / {gt_max}")
    print(f"  API min/max diameter: {ms_min} / {ms_max}")
    print(f"  GT  percent change:  {((gt_max - gt_min) / gt_min) * 100:.1f}%")
    print(f"  API percent change:  {result['percent_change']}%")

    if errors.mean() < 10:
        print("\n  PASS — mean error under 10px")
    else:
        print(f"\n  NEEDS WORK — mean error is {errors.mean():.1f}px")


def main():
    if len(sys.argv) < 2:
        print("Usage: python validate.py <video_or_folder> [--synthetic]")
        print("       python validate.py --synthetic   (run only synthetic test)")
        sys.exit(1)

    target = sys.argv[1]
    base_out = os.path.join(os.path.dirname(__file__), "validation_output")

    if target == "--synthetic":
        run_synthetic_test()
        return

    # Collect video paths
    if os.path.isdir(target):
        videos = sorted(
            p for p in glob(os.path.join(target, "*"))
            if os.path.splitext(p)[1].lower() in VIDEO_EXTS
        )
    elif os.path.isfile(target):
        videos = [target]
    else:
        print(f"Not found: {target}")
        sys.exit(1)

    if not videos:
        print(f"No video files found in {target}")
        sys.exit(1)

    print(f"Found {len(videos)} video(s) to validate")

    # Always run synthetic first as a sanity check
    run_synthetic_test()

    # Process each real video
    for vpath in videos:
        name = Path(vpath).stem
        out_dir = os.path.join(base_out, name)
        validate_video(vpath, out_dir)

    print(f"\n{'='*60}")
    print(f"All output saved under: {base_out}/")
    print(f"Open the annotated_*.jpg files to see what the algorithm detected.")
    print(f"Open the threshold_*.jpg files to see the binary mask it thresholded on.")
    if HAS_MPL:
        print(f"Open diameter_plot.png to see the full diameter time-series.")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
