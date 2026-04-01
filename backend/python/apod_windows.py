"""
Apodization window functions for spectral analysis.
Provides 2D Gaussian and Hanning windows.
"""
import numpy as np
from scipy.signal import windows


def gauss_window(size, sigma):
    """2D Gaussian apodization window."""
    gauss_x = windows.gaussian(size[1], std=sigma * size[1], sym=True)
    gauss_y = windows.gaussian(size[0], std=sigma * size[0], sym=True)
    return np.outer(gauss_y, gauss_x)


def hanning_window(size):
    """2D Hanning apodization window."""
    hann_x = windows.hann(size[1], sym=True)
    hann_y = windows.hann(size[0], sym=True)
    return np.outer(hann_y, hann_x)


def gaussian_window_filter(dimensions, window_size, window_type='fraction'):
    """
    2D Gaussian window filter matching MATLAB gaussianWindowFilter.
    Iteratively finds the std dev so the Gaussian area equals the target window area.
    """
    if isinstance(dimensions, (int, float)):
        dimensions = (int(dimensions), int(dimensions))
    if isinstance(window_size, (int, float)):
        window_size = (window_size, window_size)

    height, width = int(dimensions[0]), int(dimensions[1])

    if window_type == 'fraction':
        win_size_x = width * window_size[1]
        win_size_y = height * window_size[0]
    else:
        win_size_x = window_size[1]
        win_size_y = window_size[0]

    sx = _find_gaussian_width(width, win_size_x)
    sy = _find_gaussian_width(height, win_size_y)

    xc = (width - 1) / 2
    yc = (height - 1) / 2
    xo, yo = np.meshgrid(np.arange(width), np.arange(height))
    x = xo - xc
    y = yo - yc

    return np.exp(-(x ** 2) / (2 * sx ** 2)) * np.exp(-(y ** 2) / (2 * sy ** 2))


def _find_gaussian_width(image_size, window_size):
    """Iteratively find Gaussian std dev matching the target effective window area."""
    std = 50 * window_size
    domain = np.arange(-image_size / 2, image_size / 2 + 1)
    gauss = np.exp(-(domain ** 2) / (2 * std ** 2))
    area = np.trapezoid(gauss, domain)

    if window_size >= area:
        return std

    smax = 100 * image_size
    smin = 0.0
    err = abs(1 - area / window_size)

    while err > 1e-5:
        if area < window_size:
            smin = smin + (smax - smin) / 2
        else:
            smax = smin + (smax - smin) / 2
        std = smin + (smax - smin) / 2
        gauss = np.exp(-(domain ** 2) / (2 * std ** 2))
        area = np.trapezoid(gauss, domain)
        err = abs(1 - area / window_size)

    return std
