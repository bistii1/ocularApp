"""
Correlation sub-functions for image registration and dilation estimation.
SCC: Spectral Cross-Correlation for translation.
FMC: Fourier-Mellin Correlation for scale.
"""
import numpy as np
from numpy.fft import fft2, ifft2, fftshift

from .apod_windows import hanning_window
from .sub_pixel_fit import sub_pix_2d
from .coordinate_tform import log_polar_grid, tform_lp


def SCC(fr01, fr02):
    """Spectral cross-correlation for translation estimation."""
    win2d = hanning_window(fr02.shape[:2])
    cc_spectral = np.zeros(fr01.shape[:2], dtype=complex)

    if fr01.ndim == 2:
        fft01 = fft2(win2d * (fr01 - fr01.mean()))
        fft02 = fft2(win2d * (fr02 - fr02.mean()))
        cc_spectral += fft01 * np.conj(fft02)
    else:
        for i in range(fr01.shape[2]):
            fft01 = fft2(win2d * (fr01[:, :, i] - fr01[:, :, i].mean()))
            fft02 = fft2(win2d * (fr02[:, :, i] - fr02[:, :, i].mean()))
            cc_spectral += fft01 * np.conj(fft02)

    cc_spatial = np.abs(fftshift(ifft2(cc_spectral)))
    peak_locs = np.where(cc_spatial == cc_spatial.max())
    disp = sub_pix_2d(cc_spatial, peak_locs, np.array([0.0, 0.0]))
    return disp[1], disp[0]


def FMC(fr01, fr02, min_rad, max_rad, n_wedges, n_rings, sdx):
    """Fourier-Mellin correlation for scale estimation."""
    ny, nx = fr01.shape[:2]
    xlp, ylp = log_polar_grid(nx, ny, min_rad, max_rad, n_wedges, n_rings)
    win_lp = hanning_window(xlp.shape)
    win2d = hanning_window(fr02.shape[:2])
    cc_spectral = np.zeros(xlp.shape, dtype=complex)

    if fr01.ndim == 2:
        mfft01 = np.abs(fftshift(fft2(win2d * (fr01 - fr01.mean()))))
        mfft02 = np.abs(fftshift(fft2(win2d * (fr02 - fr02.mean()))))
        lp01 = np.abs(tform_lp(mfft01, xlp, ylp))
        lp02 = np.abs(tform_lp(mfft02, xlp, ylp))
        f01 = fft2(win_lp * lp01)
        f02 = fft2(win_lp * lp02)
        cc_spectral = f01 * np.conj(f02)
    else:
        for i in range(fr01.shape[2]):
            ch1, ch2 = fr01[:, :, i], fr02[:, :, i]
            mfft01 = np.abs(fftshift(fft2(win2d * (ch1 - ch1.mean()))))
            mfft02 = np.abs(fftshift(fft2(win2d * (ch2 - ch2.mean()))))
            lp01 = np.abs(tform_lp(mfft01, xlp, ylp))
            lp02 = np.abs(tform_lp(mfft02, xlp, ylp))
            f01 = fft2(win_lp * lp01)
            f02 = fft2(win_lp * lp02)
            cc_spectral += f01 * np.conj(f02)

    cc_spatial = np.abs(fftshift(ifft2(cc_spectral)))
    peak_locs = np.where(cc_spatial == cc_spatial.max())
    offsets = np.array([0.0, 0.0])
    if cc_spatial.shape[0] % 2 != 0:
        offsets[0] = -0.5
    if cc_spatial.shape[1] % 2 != 0:
        offsets[1] = -0.5
    disp = sub_pix_2d(cc_spatial, peak_locs, offsets)

    sdx -= disp[1]
    scale = np.exp(np.log(max_rad / min_rad) * sdx / (nx - 1))
    return scale, sdx, disp[1]
