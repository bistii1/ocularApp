"""
Pupillometry analysis pipeline.
Processes eye video recordings to measure pupil dilation response.

Modeled after reflexBetaStandAlone.m with Python implementations.
"""
import os
import logging
import cv2
import numpy as np
from numpy.fft import fft2, ifft2, fftshift
from scipy.interpolate import RegularGridInterpolator
from scipy.ndimage import median_filter

from .apod_windows import gaussian_window_filter, hanning_window
from .sub_pixel_fit import sub_pix_3pt_fit
from .coordinate_tform import log_polar_coordinates, pol2cart

logger = logging.getLogger(__name__)

CASCADE_PATH = os.path.join(
    os.path.dirname(__file__), 'cascades', 'haarcascade_eye.xml'
)


def analyze_video(video_path: str, fps_override: float = None) -> dict:
    """
    Full pupillometry pipeline: load video, register frames, detect eye,
    estimate dilation, and compute clinical metrics.

    Returns dict with:
        latency_s, percent_change, min_pupil_diameter, max_pupil_diameter,
        dilation_time_series, time_vector
    """
    logger.info("Loading video: %s", video_path)
    frames, fps = _load_and_filter_video(video_path, fps_override, max_frames=90)
    n_frames = frames.shape[3]
    logger.info("Loaded %d frames at %.1f fps", n_frames, fps)

    if n_frames < 10:
        raise ValueError(f"Too few usable frames ({n_frames}). Need at least 10.")

    rescale = 4
    gray_frames = _to_gray_rescaled(frames, rescale)

    # --- Phase 1: Image Registration ---
    logger.info("Registering frames...")
    disp_x, disp_y, scale, angle = _register_frames(gray_frames, rescale)
    frames, gray_frames, disp_x, disp_y, scale, angle = _remove_registration_outliers(
        frames, gray_frames, disp_x, disp_y, scale, angle
    )
    n_frames = frames.shape[3]
    logger.info("After outlier removal: %d frames", n_frames)

    # --- Phase 2: Eye Detection ---
    logger.info("Detecting eye...")
    scale_factor = 2
    xcent, ycent, win_size = _detect_eye(
        frames, gray_frames, disp_x, disp_y, scale, angle, rescale, scale_factor
    )
    logger.info("Eye center: (%d, %d), window: %d", xcent, ycent, win_size)

    # --- Phase 3: Register frames to memory at half-resolution ---
    logger.info("Building registered video stack...")
    registered = _build_registered_stack(
        frames, disp_x, disp_y, scale, angle, rescale, scale_factor
    )

    # --- Phase 4: Pupil Dilation Estimation ---
    logger.info("Estimating pupil dilation...")
    disp_s_inst, t_vect = _estimate_dilation(
        registered, xcent, ycent, win_size, fps
    )

    # --- Phase 5: Extract metrics ---
    logger.info("Computing metrics...")
    metrics = _compute_metrics(disp_s_inst, t_vect, win_size, fps)

    return metrics


# ============================================================================
# Video loading
# ============================================================================

def _load_and_filter_video(video_path: str, fps_override: float = None, max_frames: int = 90):
    """Load video, trim to analysis window, remove over-bright frames."""
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise FileNotFoundError(f"Cannot open video: {video_path}")

    fps = fps_override or cap.get(cv2.CAP_PROP_FPS) or 30.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    f_start = max(1, int(round(1.0 * fps)))
    f_end = min(total_frames, int(round(5.5 * fps)))

    all_frames = []
    cap.set(cv2.CAP_PROP_POS_FRAMES, f_start)
    for _ in range(f_start, f_end):
        ret, frame = cap.read()
        if not ret:
            break
        if frame.shape[0] < frame.shape[1]:
            frame = np.transpose(frame, (1, 0, 2))
        all_frames.append(frame)
    cap.release()

    if len(all_frames) < 5:
        raise ValueError("Video too short for analysis")

    video = np.stack(all_frames, axis=3)  # (H, W, 3, N)

    means = video.reshape(-1, video.shape[3]).mean(axis=0).astype(float)
    q25, q75 = np.percentile(means, 25), np.percentile(means, 75)
    iqr = q75 - q25
    good = (means >= q25 - 10 * iqr) & (means <= q75 + 10 * iqr)

    bright_idx = np.where(~good)[0]
    if len(bright_idx) > 0:
        for bi in bright_idx:
            if bi > 0:
                good[bi - 1] = False
            if bi < len(good) - 1:
                good[bi + 1] = False

    video = video[:, :, :, good]

    # Keep runtime bounded for mobile-server roundtrips by sampling frames.
    n_kept = video.shape[3]
    if n_kept > max_frames:
        idx = np.linspace(0, n_kept - 1, max_frames).astype(int)
        video = video[:, :, :, idx]

    return video, fps


def _to_gray_rescaled(video, rescale):
    """Convert NHWC video to grayscale and downscale."""
    n = video.shape[3]
    h, w = video.shape[0] // rescale, video.shape[1] // rescale
    gray = np.zeros((h, w, n), dtype=np.float64)
    for i in range(n):
        frame = video[:, :, :, i]
        g = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray[:, :, i] = cv2.resize(g, (w, h), interpolation=cv2.INTER_NEAREST).astype(np.float64)
    return gray


# ============================================================================
# Image Registration (matches MATLAB statisticalRegister)
# ============================================================================

def _register_frames(gray_frames, rescale):
    """Register all frames to reference using FFT + FMC."""
    n = gray_frames.shape[2]
    h, w = gray_frames.shape[:2]

    ref_img = gray_frames[:, :, 0]
    max_rad = min(h, w) / 2
    min_rad = 2
    n_wedges = 180

    spt_window = gaussian_window_filter((h, w), (0.5, 0.5), 'fraction')
    fmc_window = gaussian_window_filter((n_wedges, w), (0.5, 0.5), 'fraction')

    x_sub, y_sub = np.meshgrid(
        np.arange(-w / 2, w / 2),
        np.arange(-h / 2, h / 2)
    )
    x_lp, y_lp = log_polar_coordinates((h, w), n_wedges, w, min_rad, max_rad, 2 * np.pi)

    disp_x = np.zeros(n)
    disp_y = np.zeros(n)
    disp_s = np.zeros(n)
    disp_a = np.zeros(n)

    for k in range(n):
        cur_img = gray_frames[:, :, k]
        dx, dy, ds, da, _ = _statistical_register(
            ref_img, cur_img, spt_window, fmc_window,
            h, w, min_rad, max_rad, x_lp, y_lp, 1e-4, 60
        )
        disp_x[k] = dx
        disp_y[k] = dy
        disp_s[k] = ds
        disp_a[k] = da

        if (k + 1) % 10 == 0:
            logger.info("  Registered %d/%d", k + 1, n)

    scale = (max_rad / min_rad) ** (-disp_s / w)
    angle = 2 * np.pi * disp_a / x_lp.shape[0]

    return disp_x, disp_y, scale, angle


def _statistical_register(ref_img, cur_img, spt_window, fmc_window,
                          height, width, min_rad, max_rad,
                          x_lp, y_lp, err_thresh, iter_thresh):
    """Iterative FFT phase correlation + FMC for single frame pair."""
    err = np.inf
    iteration = 0
    dx = dy = ds = da = 0.0
    t_rev = np.eye(3)
    t_for = np.eye(3)

    while err >= err_thresh and iteration < iter_thresh:
        fr01 = _warp_frame(cur_img, t_for, height, width)
        fr02 = _warp_frame(ref_img, t_rev, height, width)

        fft01 = fft2(spt_window * (fr01 - fr01.mean()))
        fft02 = fft2(spt_window * (fr02 - fr02.mean()))

        mag01 = fftshift(spt_window * np.abs(fft01))
        mag02 = fftshift(spt_window * np.abs(fft02))

        if width % 2 == 0:
            fmc01 = fft2(fmc_window * _interp2(mag01, x_lp + 0.5, y_lp + 0.5))
            fmc02 = fft2(fmc_window * _interp2(mag02, x_lp + 0.5, y_lp + 0.5))
        else:
            fmc01 = fft2(fmc_window * _interp2(mag01, x_lp, y_lp + 0.5))
            fmc02 = fft2(fmc_window * _interp2(mag02, x_lp, y_lp + 0.5))

        disp_spectral = fft01 * np.conj(fft02)
        disp_plane = np.abs(fftshift(ifft2(disp_spectral)))
        ones_w = np.ones_like(disp_plane)
        pl_x, pl_y, _, _, _, _ = sub_pix_3pt_fit(disp_plane, width, height, ones_w)

        dx -= pl_x[0]
        dy -= pl_y[0]

        fmc_spectral = fmc01 * np.conj(fmc02)
        fmc_plane = np.abs(fftshift(ifft2(fmc_spectral)))
        ones_fmc = np.ones_like(fmc_plane)
        fmc_x, fmc_y, _, _, _, _ = sub_pix_3pt_fit(
            fmc_plane, fmc_plane.shape[1], fmc_plane.shape[0], ones_fmc
        )

        ds -= fmc_x[0]
        da -= fmc_y[0]

        s = (max_rad / min_rad) ** (-ds / width)
        a = 2 * np.pi * da / x_lp.shape[0]

        err = max(np.sqrt(pl_x[0] ** 2 + pl_y[0] ** 2), abs(fmc_x[0]))
        iteration += 1

        cos_a = np.cos(a / 2)
        sin_a = np.sin(a / 2)
        t_rev[0, 0] = np.sqrt(1 / s) * cos_a
        t_rev[1, 1] = np.sqrt(1 / s) * cos_a
        t_rev[0, 1] = np.sqrt(1 / s) * sin_a
        t_rev[1, 0] = -np.sqrt(1 / s) * sin_a
        t_rev[0, 2] = -dx / 2
        t_rev[1, 2] = -dy / 2

        t_for[0, 0] = np.sqrt(s) * cos_a
        t_for[1, 1] = np.sqrt(s) * cos_a
        t_for[0, 1] = np.sqrt(s) * (-sin_a)
        t_for[1, 0] = np.sqrt(s) * sin_a
        t_for[0, 2] = dx / 2
        t_for[1, 2] = dy / 2

    return dx, dy, ds, da, iteration


def _warp_frame(img, T, h, w):
    """Apply affine warp via cv2."""
    warped = cv2.warpAffine(
        img.astype(np.float64), T[:2, :], (w, h),
        flags=cv2.INTER_LINEAR | cv2.WARP_FILL_OUTLIERS
    )
    return np.nan_to_num(warped)


def _interp2(img, x_coords, y_coords):
    """Bilinear interpolation at arbitrary coordinates (like MATLAB interp2)."""
    from scipy.ndimage import map_coordinates
    result = map_coordinates(img, [y_coords, x_coords], order=1, mode='constant', cval=0.0)
    return result


# ============================================================================
# Outlier removal
# ============================================================================

def _remove_registration_outliers(frames, gray_frames, disp_x, disp_y, scale, angle):
    """Remove frames with extreme registration values."""
    good = np.ones(len(scale), dtype=bool)
    good[scale < 0.5] = False
    good[scale > 2.0] = False

    q25, q75 = np.percentile(disp_x[good], [25, 75])
    iqr = q75 - q25
    good[(disp_x < q25 - 3 * iqr) | (disp_x > q75 + 3 * iqr)] = False

    return (
        frames[:, :, :, good],
        gray_frames[:, :, good],
        disp_x[good], disp_y[good], scale[good], angle[good],
    )


# ============================================================================
# Eye Detection
# ============================================================================

def _detect_eye(frames, gray_frames, disp_x, disp_y, scale, angle,
                rescale, scale_factor):
    """Use Haar cascade to find eye position across registered frames."""
    if not os.path.exists(CASCADE_PATH):
        logger.warning("Haar cascade not found at %s, using center fallback", CASCADE_PATH)
        h, w = frames.shape[:2]
        return w // (2 * scale_factor), h // (2 * scale_factor), min(h, w) // (4 * scale_factor)

    eye_cascade = cv2.CascadeClassifier(CASCADE_PATH)
    n = frames.shape[3]
    h_small = frames.shape[0] // rescale
    w_small = frames.shape[1] // rescale
    min_dim = min(h_small, w_small)

    store_eye = []

    for k in range(n):
        cur = cv2.resize(frames[:, :, :, k], (w_small, h_small), interpolation=cv2.INTER_NEAREST)

        T = np.array([
            [scale[k] * np.cos(angle[k]), -scale[k] * np.sin(angle[k]), disp_x[k]],
            [scale[k] * np.sin(angle[k]),  scale[k] * np.cos(angle[k]), disp_y[k]],
        ], dtype=np.float64)
        cur = cv2.warpAffine(cur, T, (w_small, h_small),
                             flags=cv2.INTER_LINEAR | cv2.WARP_FILL_OUTLIERS)
        cur[np.isnan(cur.astype(float))] = 0

        eyes = eye_cascade.detectMultiScale(
            cur, scaleFactor=1.1, minNeighbors=5, minSize=(min_dim // 4, min_dim // 4)
        )
        if len(eyes) > 0:
            eyes = sorted(eyes, key=lambda e: e[2] * e[3], reverse=True)
            ex, ey, ew, eh = eyes[0]
            store_eye.append((ex + ew / 2, ey + eh / 2, ew / 2, eh / 2))

    if not store_eye:
        h, w = frames.shape[:2]
        return w // (2 * scale_factor), h // (2 * scale_factor), min(h, w) // (4 * scale_factor)

    arr = np.array(store_eye)
    xcent = int(round(rescale / scale_factor * np.nanmedian(arr[:, 0])))
    ycent = int(round(rescale / scale_factor * np.nanmedian(arr[:, 1])))
    win_size = int(np.ceil(rescale / scale_factor * np.nanmedian(np.nanmedian(arr[:, 2:4], axis=1))))

    if win_size % 2 != 0:
        win_size += 1
    win_size = max(win_size, 32)

    return xcent, ycent, win_size


# ============================================================================
# Build registered stack
# ============================================================================

def _build_registered_stack(frames, disp_x, disp_y, scale, angle, rescale, scale_factor):
    """Warp all frames to the reference coordinate system at half-resolution."""
    n = frames.shape[3]
    sample = cv2.resize(frames[:, :, :, 0], None,
                        fx=1 / scale_factor, fy=1 / scale_factor,
                        interpolation=cv2.INTER_NEAREST)
    h, w = sample.shape[:2]

    disp_x_scaled = disp_x * rescale / scale_factor
    disp_y_scaled = disp_y * rescale / scale_factor

    registered = np.zeros((h, w, 3, n), dtype=np.uint8)

    for k in range(n):
        current = cv2.resize(frames[:, :, :, k], (w, h), interpolation=cv2.INTER_NEAREST).astype(np.float64)
        T = np.array([
            [scale[k] * np.cos(angle[k]), -scale[k] * np.sin(angle[k]), disp_x_scaled[k]],
            [scale[k] * np.sin(angle[k]),  scale[k] * np.cos(angle[k]), disp_y_scaled[k]],
        ], dtype=np.float64)
        warped = cv2.warpAffine(current, T, (w, h),
                                flags=cv2.INTER_LINEAR | cv2.WARP_FILL_OUTLIERS)
        warped = np.nan_to_num(warped)
        warped = np.clip(warped, 0, 255)
        registered[:, :, :, k] = warped.astype(np.uint8)

    return registered


# ============================================================================
# Pupil Dilation Estimation
# ============================================================================

def _estimate_dilation(registered, xcent, ycent, win_size, fps):
    """
    Estimate instantaneous pupil dilation rate via frame-to-frame
    Fourier-Mellin correlation on cropped eye ROIs.
    """
    n = registered.shape[3]
    h, w = registered.shape[:2]

    half = win_size // 2
    y_lo = max(0, ycent - half)
    y_hi = min(h, ycent + half)
    x_lo = max(0, xcent - half)
    x_hi = min(w, xcent + half)

    actual_h = y_hi - y_lo
    actual_w = x_hi - x_lo
    if actual_h < 16 or actual_w < 16:
        raise ValueError("Eye ROI too small for dilation analysis")

    dilate_min_rad = 1
    dilate_max_rad = min(actual_h, actual_w) / 2
    n_wedges = min(360, actual_h * 2)

    spt_win = gaussian_window_filter(
        (actual_h, actual_w), (0.5, 0.5), 'fraction'
    )
    fmc_win = gaussian_window_filter(
        (n_wedges, actual_w), (0.5, 0.5), 'fraction'
    )
    x_lp, y_lp = log_polar_coordinates(
        (actual_h, actual_w), n_wedges, actual_w,
        dilate_min_rad, dilate_max_rad, 2 * np.pi
    )

    disp_s = np.zeros(n)

    for k in range(1, n - 1):
        ref_roi = registered[y_lo:y_hi, x_lo:x_hi, :, k - 1]
        cur_roi = registered[y_lo:y_hi, x_lo:x_hi, :, k + 1]

        ref_proc = _preprocess_roi(ref_roi)
        cur_proc = _preprocess_roi(cur_roi)

        ds = _dilation_correlate(
            ref_proc, cur_proc, spt_win, fmc_win,
            x_lp, y_lp, dilate_min_rad, dilate_max_rad,
            actual_w, 1e-5, 80
        )
        disp_s[k] = ds / 2.0  # pair-wise: divide by 2 frame steps

    t_vect = np.arange(n) / fps

    return disp_s, t_vect


def _preprocess_roi(roi):
    """Convert ROI to grayscale with histogram equalization and complement."""
    if roi.ndim == 3:
        lab = cv2.cvtColor(roi, cv2.COLOR_BGR2Lab)
        eq = cv2.equalizeHist(lab[:, :, 0])
        gray = cv2.bitwise_not(eq).astype(np.float64)
    else:
        gray = roi.astype(np.float64)
    return gray


def _dilation_correlate(ref, cur, spt_win, fmc_win, x_lp, y_lp,
                        min_rad, max_rad, width, err_thresh, iter_thresh):
    """Iterative FMC for dilation between a reference and current ROI."""
    err = np.inf
    iteration = 0
    ds = 0.0
    h, w = ref.shape[:2]

    t_rev = np.eye(3)
    t_for = np.eye(3)

    while err >= err_thresh and iteration < iter_thresh:
        fr01 = _warp_frame(ref, t_for, h, w)
        fr02 = _warp_frame(cur, t_rev, h, w)

        fr01 = spt_win * (fr01 - fr01.mean())
        fr02 = spt_win * (fr02 - fr02.mean())

        fft01 = fftshift(fft2(fr01))
        fft02 = fftshift(fft2(fr02))

        if w % 2 == 0:
            fmc01 = fft2(fmc_win * _interp2(np.abs(fft01), x_lp + 0.5, y_lp + 0.5))
            fmc02 = fft2(fmc_win * _interp2(np.abs(fft02), x_lp + 0.5, y_lp + 0.5))
        else:
            fmc01 = fft2(fmc_win * _interp2(np.abs(fft01), x_lp, y_lp + 0.5))
            fmc02 = fft2(fmc_win * _interp2(np.abs(fft02), x_lp, y_lp + 0.5))

        fmc_spectral = fmc01 * np.conj(fmc02)
        fmc_plane = np.abs(fftshift(ifft2(fmc_spectral)))
        ones_w = np.ones_like(fmc_plane)
        fmc_x, _, _, _, _, _ = sub_pix_3pt_fit(
            fmc_plane, fmc_plane.shape[1], fmc_plane.shape[0], ones_w
        )

        ds -= fmc_x[0]
        err = abs(fmc_x[0])
        iteration += 1

        s = (max_rad / min_rad) ** (-ds / width)
        t_rev[0, 0] = np.sqrt(1 / s)
        t_rev[1, 1] = np.sqrt(1 / s)
        t_for[0, 0] = np.sqrt(s)
        t_for[1, 1] = np.sqrt(s)

    return ds


# ============================================================================
# Metrics Extraction
# ============================================================================

def _compute_metrics(disp_s_inst, t_vect, win_size, fps):
    """
    Extract full set of pupillometry metrics matching MATLAB output:
      - Onset / latency
      - Peak constriction time and magnitude
      - Recovery time (75% recovery)
      - Average constriction and dilation velocities
      - Pupil diameter estimates
      - Full time series
    """
    filtered = median_filter(disp_s_inst, size=5)

    dilate_max_rad = win_size / 2
    dilate_min_rad = 1

    dilation_vel = np.interp(
        np.linspace(t_vect[0], t_vect[-1], len(t_vect)),
        t_vect, filtered
    )

    dilation_ratio = (dilate_max_rad / dilate_min_rad) ** (
        -np.cumsum(dilation_vel) / (win_size / 2)
    )
    dilation_ratio = np.clip(dilation_ratio, 0.01, 10.0)

    # Velocity as percent change per frame
    velocity_pct = (1 - (dilate_max_rad / dilate_min_rad) ** (
        (-dilation_vel * 2) / win_size
    )) * 100

    approx_pupil_mm = 4.0

    # --- Onset detection ---
    onset_idx = _find_onset(dilation_vel, fps)
    onset_time = float(t_vect[onset_idx]) if onset_idx is not None else 0.0

    # --- Peak constriction (minimum dilation ratio within first 2.5s) ---
    search_end = min(len(dilation_ratio), int(2.5 * fps))
    if search_end < 2:
        search_end = len(dilation_ratio)
    constrict_idx = int(np.argmin(dilation_ratio[:search_end]))
    peak_constriction_time = float(t_vect[constrict_idx])
    max_constriction_ratio = abs(1.0 - float(dilation_ratio[constrict_idx])) * 100

    # --- Recovery time (75% return from constriction) ---
    recovery_time = None
    if onset_idx is not None and constrict_idx > 0:
        baseline = float(dilation_ratio[max(0, onset_idx - 1)]) if onset_idx > 0 else 1.0
        trough = float(dilation_ratio[constrict_idx])
        recovery_threshold = trough + 0.75 * abs(baseline - trough)
        for ri in range(constrict_idx, len(dilation_ratio)):
            if dilation_ratio[ri] >= recovery_threshold:
                recovery_time = float(t_vect[ri])
                break
    if recovery_time is None and len(t_vect) > constrict_idx:
        post_peak = dilation_ratio[constrict_idx:]
        recovery_time = float(t_vect[constrict_idx + int(np.argmax(post_peak))])

    # --- Average velocities ---
    start = onset_idx if onset_idx is not None else 0
    avg_constriction_vel = float(np.mean(velocity_pct[start:constrict_idx + 1])) if constrict_idx > start else 0.0
    recovery_end = min(len(velocity_pct), int(recovery_time * fps)) if recovery_time else len(velocity_pct)
    avg_dilation_vel = float(np.mean(velocity_pct[constrict_idx + 1:recovery_end])) if recovery_end > constrict_idx + 1 else 0.0

    # --- Diameter estimates ---
    min_ratio = float(np.nanmin(dilation_ratio))
    max_ratio = float(np.nanmax(dilation_ratio))
    min_diameter = min_ratio * approx_pupil_mm
    max_diameter = max_ratio * approx_pupil_mm

    quality_score, quality_label, quality_flags = _compute_quality(
        dilation_ratio=dilation_ratio,
        velocity_pct=velocity_pct,
        t_vect=t_vect,
        onset_time=onset_time,
        peak_constriction_time=peak_constriction_time,
        max_constriction_ratio=max_constriction_ratio,
    )

    return {
        # Timing metrics
        "onset_time_s": round(onset_time, 3),
        "peak_constriction_time_s": round(peak_constriction_time, 3),
        "recovery_time_s": round(recovery_time, 3) if recovery_time else None,
        # Magnitude metrics
        "max_constriction_pct": round(max_constriction_ratio, 2),
        "percent_change": round(abs(1 - min_ratio) * 100, 2),
        # Velocity metrics
        "avg_constriction_velocity": round(avg_constriction_vel, 3),
        "avg_dilation_velocity": round(avg_dilation_vel, 3),
        # Diameter estimates
        "min_pupil_diameter_mm": round(min_diameter, 2),
        "max_pupil_diameter_mm": round(max_diameter, 2),
        "baseline_pupil_diameter_mm": approx_pupil_mm,
        # Processing info
        "n_frames": len(t_vect),
        "fps": round(fps, 1),
        "analysis_duration_s": round(float(t_vect[-1] - t_vect[0]), 2),
        # Legacy (kept for backward compat)
        "latency_s": round(onset_time, 3),
        # Time series
        "dilation_time_series": dilation_ratio.tolist(),
        "velocity_time_series": velocity_pct.tolist(),
        "time_vector": t_vect.tolist(),
        # Quality
        "quality_score": quality_score,
        "quality_label": quality_label,
        "quality_flags": quality_flags,
    }


def _compute_quality(dilation_ratio, velocity_pct, t_vect,
                     onset_time, peak_constriction_time, max_constriction_ratio):
    """Derive a heuristic quality/confidence score from signal and timing behavior."""
    score = 100.0
    flags = []

    if len(t_vect) < 25:
        score -= 25
        flags.append("low_frame_count")

    finite_ratio = np.asarray(dilation_ratio, dtype=float)
    finite_vel = np.asarray(velocity_pct, dtype=float)

    if not np.all(np.isfinite(finite_ratio)) or not np.all(np.isfinite(finite_vel)):
        score -= 40
        flags.append("non_finite_signal")

    ratio_std = float(np.nanstd(finite_ratio)) if finite_ratio.size else 0.0
    if ratio_std < 0.003:
        score -= 20
        flags.append("flat_signal")

    if max_constriction_ratio < 0.75:
        score -= 15
        flags.append("weak_constriction")

    vel_noise = float(np.nanmedian(np.abs(np.diff(finite_vel)))) if finite_vel.size > 1 else 0.0
    if vel_noise > 1.5:
        score -= 20
        flags.append("noisy_velocity")

    # Timing is only meaningful if there is visible constriction and non-flat signal.
    has_meaningful_response = max_constriction_ratio >= 0.75 and ratio_std >= 0.003
    if has_meaningful_response and peak_constriction_time <= onset_time:
        score -= 20
        flags.append("implausible_timing")

    score = float(np.clip(score, 0.0, 100.0))
    if score >= 85:
        label = "excellent"
    elif score >= 70:
        label = "good"
    elif score >= 50:
        label = "fair"
    elif score >= 30:
        label = "poor"
    else:
        label = "unreliable"

    return round(score, 1), label, flags


def _find_onset(dilation_vel, fps):
    """Find the onset index where dilation velocity first exceeds threshold."""
    threshold = np.std(dilation_vel[:max(5, int(0.5 * fps))]) * 2
    if threshold < 1e-6:
        threshold = 0.01

    for i in range(len(dilation_vel)):
        if abs(dilation_vel[i]) > threshold:
            return max(0, i - 1)
    return None
