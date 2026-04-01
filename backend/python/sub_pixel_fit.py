"""
Sub-pixel peak fitting for correlation planes.
Adopted from prana (PIV analysis toolkit).
"""
import numpy as np


def sub_pixel_2d(plane):
    """
    Find sub-pixel peak location in a 2D correlation plane.
    Automatically finds the peak and computes sub-pixel offset.
    """
    peak_locs = np.where(plane == plane.max())
    offsets = np.array([0.0, 0.0])
    if plane.shape[0] % 2 != 0:
        offsets[0] = -0.5
    if plane.shape[1] % 2 != 0:
        offsets[1] = -0.5
    return sub_pix_2d(plane, peak_locs, offsets)


def sub_pix_2d(plane, peak_locs, offsets):
    """
    Sub-pixel peak fitting given explicit peak locations and offsets.
    Uses 3-point Gaussian fit via log interpolation.
    """
    r = peak_locs[0][0]
    c = peak_locs[1][0]

    disp = np.array([
        r - (plane.shape[0] / 2) - offsets[0],
        c - (plane.shape[1] / 2) - offsets[1],
    ])

    if 2 <= r <= plane.shape[0] - 2 and 2 <= c <= plane.shape[1] - 2:
        try:
            log_left = np.log(plane[r, c - 1])
            log_right = np.log(plane[r, c + 1])
            log_center = np.log(plane[r, c])
            denom_x = 2 * (log_left + log_right - 2 * log_center)
            if abs(denom_x) > 1e-12:
                disp[1] += (log_left - log_right) / denom_x

            log_up = np.log(plane[r - 1, c])
            log_down = np.log(plane[r + 1, c])
            denom_y = 2 * (log_up + log_down - 2 * log_center)
            if abs(denom_y) > 1e-12:
                disp[0] += (log_up - log_down) / denom_y
        except (ValueError, FloatingPointError):
            pass

    return disp


def sub_pix_3pt_fit(plane, width, height, weighting):
    """
    3-point Gaussian sub-pixel fit matching the MATLAB subpix3PtFit function.
    Returns (u, v, M, D, DX, DY).
    """
    cc_x = np.arange(-width // 2, width // 2 + (width % 2))
    cc_y = np.arange(-height // 2, height // 2 + (height % 2))

    weighted = plane * weighting
    M_val = weighted.max()

    if M_val == 0:
        return np.array([0.0]), np.array([0.0]), 0, 0, 0, 0

    I = np.argmax(weighted)
    shift_locy = I % height
    shift_locx = I // height

    shift_errx = None
    shift_erry = None
    sigma = 4.0

    if width == 1:
        shift_errx = 1.0
    elif shift_locx == 0:
        shift_errx = weighted[shift_locy, shift_locx + 1] / M_val
    elif shift_locx == width - 1:
        shift_errx = -weighted[shift_locy, shift_locx - 1] / M_val
    elif weighted[shift_locy, shift_locx + 1] == 0:
        shift_errx = -weighted[shift_locy, shift_locx - 1] / M_val
    elif weighted[shift_locy, shift_locx - 1] == 0:
        shift_errx = weighted[shift_locy, shift_locx + 1] / M_val

    if height == 1:
        shift_erry = 1.0
    elif shift_locy == 0:
        shift_erry = -weighted[shift_locy + 1, shift_locx] / M_val
    elif shift_locy == height - 1:
        shift_erry = weighted[shift_locy - 1, shift_locx] / M_val
    elif weighted[shift_locy + 1, shift_locx] == 0:
        shift_erry = weighted[shift_locy - 1, shift_locx] / M_val
    elif weighted[shift_locy - 1, shift_locx] == 0:
        shift_erry = -weighted[shift_locy + 1, shift_locx] / M_val

    dX = np.nan
    dY = np.nan

    if shift_errx is None:
        try:
            lCm1 = np.log(weighted[shift_locy, shift_locx - 1])
            lC00 = np.log(weighted[shift_locy, shift_locx])
            lCp1 = np.log(weighted[shift_locy, shift_locx + 1])
            denom = 2 * (lCm1 + lCp1 - 2 * lC00)
            if abs(denom) > 1e-12:
                shift_errx = (lCm1 - lCp1) / denom
                betax = abs(lCm1 - lC00) / ((-1 - shift_errx) ** 2 - shift_errx ** 2)
                dX = sigma / np.sqrt(2 * betax) if betax > 0 else np.nan
            else:
                shift_errx = 0.0
        except (ValueError, FloatingPointError):
            shift_errx = 0.0

    if shift_erry is None:
        try:
            lCm1 = np.log(weighted[shift_locy - 1, shift_locx])
            lC00 = np.log(weighted[shift_locy, shift_locx])
            lCp1 = np.log(weighted[shift_locy + 1, shift_locx])
            denom = 2 * (lCm1 + lCp1 - 2 * lC00)
            if abs(denom) > 1e-12:
                shift_erry = (lCm1 - lCp1) / denom
                betay = abs(lCm1 - lC00) / ((-1 - shift_erry) ** 2 - shift_erry ** 2)
                dY = sigma / np.sqrt(2 * betay) if betay > 0 else np.nan
            else:
                shift_erry = 0.0
        except (ValueError, FloatingPointError):
            shift_erry = 0.0

    u = cc_x[shift_locx] + shift_errx
    v = cc_y[shift_locy] + shift_erry

    if np.isinf(u) or np.isinf(v):
        u = 0.0
        v = 0.0

    D = np.nanmean([dX, dY])
    return np.array([u]), np.array([v]), M_val, D, dX, dY
