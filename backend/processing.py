"""
Pupilometry video processing pipeline.

Uses the red channel of the video frames for better pupil–iris contrast
(per the far-red spectrum research), and accepts PLR flash timing to
compute latency relative to the known stimulus onset.
"""
import cv2
import numpy as np
from numpy import sqrt


def _hanning_window(shape):
    """Build 2D Hanning window matching the given (rows, cols) shape."""
    win_y = np.hanning(shape[0]).reshape(-1, 1)
    win_x = np.hanning(shape[1]).reshape(1, -1)
    return win_y @ win_x


def _detect_eye_region(frames_single, width, height):
    """Try Haar-cascade eye detection on several frames, return best ROI."""
    cascade_path = cv2.data.haarcascades + "haarcascade_eye.xml"
    eye_cascade = cv2.CascadeClassifier(cascade_path)

    min_dim = min(width, height)
    configs = [
        {"scaleFactor": 1.1, "minNeighbors": 5, "minSize": (min_dim // 6, min_dim // 6)},
        {"scaleFactor": 1.05, "minNeighbors": 3, "minSize": (min_dim // 8, min_dim // 8)},
        {"scaleFactor": 1.05, "minNeighbors": 2, "minSize": (min_dim // 10, min_dim // 10)},
    ]

    indices_to_try = _spread_indices(len(frames_single), 12)

    for cfg in configs:
        for idx in indices_to_try:
            eyes = eye_cascade.detectMultiScale(frames_single[idx], **cfg)
            if len(eyes) > 0:
                ex, ey, ew, eh = eyes[0]
                return ex, ey, ew, eh
    return None


def _spread_indices(n, count):
    """Return up to *count* evenly-spaced indices across [0, n)."""
    if n <= count:
        return list(range(n))
    step = max(1, n // count)
    return list(range(0, n, step))[:count]


def _measure_pupil_diameter(roi_single):
    """Detect pupil by finding the darkest circular region after heavy blur.

    Works on a single-channel ROI (red channel preferred for better
    pupil–iris contrast).

    Returns (diameter, contour_in_roi_coords, debug_mask).
    """
    h, w = roi_single.shape[:2]
    min_dim = min(h, w)

    ksize = max(15, (min_dim // 6) | 1)
    blurred = cv2.GaussianBlur(roi_single, (ksize, ksize), 0)

    min_val, _, min_loc, _ = cv2.minMaxLoc(blurred)
    median_val = float(np.median(blurred))

    if min_val > median_val * 0.75:
        debug_mask = np.zeros_like(roi_single)
        return 0.0, None, debug_mask

    local_thresh = int(min_val + (median_val - min_val) * 0.35)
    _, thresh = cv2.threshold(blurred, local_thresh, 255, cv2.THRESH_BINARY_INV)

    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    thresh = cv2.morphologyEx(thresh, cv2.MORPH_OPEN, kernel)
    thresh = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, kernel)

    contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return 0.0, None, thresh

    px, py = float(min_loc[0]), float(min_loc[1])
    roi_area = h * w

    candidates = []
    for c in contours:
        area = cv2.contourArea(c)
        if area < roi_area * 0.001 or area > roi_area * 0.15:
            continue
        perimeter = cv2.arcLength(c, True)
        if perimeter == 0:
            continue
        circularity = 4 * np.pi * area / (perimeter * perimeter)
        if circularity < 0.25:
            continue
        dist = abs(cv2.pointPolygonTest(c, (px, py), True))
        contains = cv2.pointPolygonTest(c, (px, py), False) >= 0
        score = circularity + (5.0 if contains else 0.0) - dist / min_dim
        diameter = float(2 * sqrt(area / np.pi))
        candidates.append((score, diameter, c))

    if not candidates:
        return 0.0, None, thresh

    candidates.sort(key=lambda t: t[0], reverse=True)
    _, diameter, contour = candidates[0]
    return diameter, contour, thresh


def _load_frames(video_path):
    """Read all frames from a video file. Returns (frames_bgr, fps)."""
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise ValueError(f"Cannot open video: {video_path}")
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    frames = []
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        frames.append(frame)
    cap.release()
    return frames, fps


def _extract_red_channel(frames_bgr):
    """Extract the red channel from BGR frames as single-channel images.

    The red channel provides better pupil–iris contrast than luminance
    (grayscale), especially across different skin tones.
    """
    return [f[:, :, 2] for f in frames_bgr]


def process_video(video_path: str, subject_id: str = "", eye: str = "left",
                  flash_onset_s: float = 1.0, flash_duration_s: float = 1.0,
                  debug: bool = False) -> dict:
    """
    Analyse a pupillometry video and return key metrics.

    flash_onset_s / flash_duration_s describe the PLR protocol timing so
    that latency is computed relative to the known stimulus onset.

    When debug=True, extra keys are included:
        diameters       – list of per-frame diameter measurements
        eye_roi         – [x, y, w, h] of detected eye region
        debug_frames    – list of (frame_idx, annotated_bgr, thresh_mask)
    """
    frames_bgr, fps = _load_frames(video_path)

    if len(frames_bgr) < 3:
        result = _empty_result(len(frames_bgr), fps, "Video too short (need >= 3 frames)")
        if debug:
            result.update(diameters=[], eye_roi=None, debug_frames=[])
        return result

    height, width = frames_bgr[0].shape[:2]
    frames_red = _extract_red_channel(frames_bgr)

    # Eye detection uses the red channel (single-channel, works with Haar)
    eye_roi = _detect_eye_region(frames_red, width, height)
    eye_detected = eye_roi is not None

    if eye_roi is None:
        ex, ey = width // 4, height // 4
        ew, eh = width // 2, height // 2
    else:
        ex, ey, ew, eh = eye_roi

    diameters = []
    contours_per_frame = []
    thresholds_per_frame = []
    for red in frames_red:
        roi = red[ey : ey + eh, ex : ex + ew]
        d, contour, thresh = _measure_pupil_diameter(roi)
        diameters.append(d)
        contours_per_frame.append(contour)
        thresholds_per_frame.append(thresh)

    valid = np.array([d for d in diameters if d > 0], dtype=float)
    if len(valid) == 0:
        result = _empty_result(len(frames_bgr), fps, "Could not measure pupil in any frame")
        if debug:
            result.update(diameters=diameters, eye_roi=[ex, ey, ew, eh], debug_frames=[])
        return result

    min_d = float(np.percentile(valid, 5))
    max_d = float(np.percentile(valid, 95))
    percent_change = ((max_d - min_d) / min_d) * 100 if min_d > 0 else 0.0

    # --- PLR-aware latency computation ---
    # Baseline: frames before the flash onset
    flash_onset_frame = int(flash_onset_s * fps)
    flash_end_frame = int((flash_onset_s + flash_duration_s) * fps)

    baseline_diameters = [d for d in diameters[:flash_onset_frame] if d > 0]
    if len(baseline_diameters) >= 2:
        baseline = float(np.median(baseline_diameters))
    else:
        baseline_n = max(3, len(valid) // 5)
        baseline = float(np.median(valid[:baseline_n]))

    # Latency: first frame *after flash onset* with sustained constriction
    change_threshold = baseline * 0.05
    sustain_frames = max(2, int(fps * 0.1))
    latency_frame = None

    for idx in range(flash_onset_frame, len(diameters) - sustain_frames):
        segment = np.array(diameters[idx : idx + sustain_frames])
        segment_valid = segment[segment > 0]
        if len(segment_valid) < sustain_frames // 2:
            continue
        if np.all(np.abs(segment_valid - baseline) > change_threshold):
            latency_frame = idx
            break

    if latency_frame is not None:
        latency_ms = ((latency_frame - flash_onset_frame) / fps) * 1000
    else:
        latency_ms = 0.0

    # Constriction amplitude: baseline minus post-flash minimum
    post_flash_valid = [d for d in diameters[flash_end_frame:] if d > 0]
    if post_flash_valid:
        constriction_min = float(np.percentile(post_flash_valid, 5))
        constriction_pct = ((baseline - constriction_min) / baseline) * 100 if baseline > 0 else 0.0
    else:
        constriction_min = 0.0
        constriction_pct = 0.0

    result = {
        "latency_ms": round(latency_ms, 1),
        "percent_change": round(percent_change, 2),
        "constriction_pct": round(constriction_pct, 2),
        "baseline_diameter_px": round(baseline, 2),
        "min_diameter_px": round(min_d, 2),
        "max_diameter_px": round(max_d, 2),
        "frame_count": len(frames_bgr),
        "fps": round(fps, 1),
        "eye_detected": eye_detected,
        "subject_id": subject_id,
        "eye": eye,
        "flash_onset_s": flash_onset_s,
        "flash_duration_s": flash_duration_s,
        "valid_frames": int(len(valid)),
        "total_frames": len(frames_bgr),
        "message": "Analysis complete",
    }

    if debug:
        sample_indices = _spread_indices(len(frames_bgr), 8)
        debug_frames = []
        for fi in sample_indices:
            annotated = frames_bgr[fi].copy()
            cv2.rectangle(annotated, (ex, ey), (ex + ew, ey + eh), (0, 255, 0), 3)
            if contours_per_frame[fi] is not None:
                shifted = contours_per_frame[fi].copy()
                shifted[:, :, 0] += ex
                shifted[:, :, 1] += ey
                cv2.drawContours(annotated, [shifted], -1, (255, 255, 0), 2)
            label = f"d={diameters[fi]:.1f}px" if diameters[fi] > 0 else "no detect"
            cv2.putText(annotated, f"Frame {fi}: {label}",
                        (ex, max(ey - 10, 25)),
                        cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 255, 0), 2)
            debug_frames.append((fi, annotated, thresholds_per_frame[fi]))

        result["diameters"] = [round(d, 2) for d in diameters]
        result["eye_roi"] = [int(ex), int(ey), int(ew), int(eh)]
        result["debug_frames"] = debug_frames

    return result


def _empty_result(frame_count, fps, message):
    return {
        "latency_ms": 0,
        "percent_change": 0,
        "constriction_pct": 0,
        "baseline_diameter_px": 0,
        "min_diameter_px": 0,
        "max_diameter_px": 0,
        "frame_count": frame_count,
        "fps": round(fps, 1),
        "eye_detected": False,
        "subject_id": "",
        "eye": "",
        "flash_onset_s": 0,
        "flash_duration_s": 0,
        "valid_frames": 0,
        "total_frames": frame_count,
        "message": message,
    }
