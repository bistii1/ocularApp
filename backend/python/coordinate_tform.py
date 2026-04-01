"""
Coordinate transformations: Cartesian/Polar conversions,
log-polar grids, and image warping.
"""
import numpy as np
import scipy.ndimage
from scipy.interpolate import RegularGridInterpolator


def cart2pol(x, y):
    rho = np.sqrt(x ** 2 + y ** 2)
    phi = np.arctan2(y, x)
    return rho, phi


def pol2cart(rho, phi):
    x = rho * np.cos(phi)
    y = rho * np.sin(phi)
    return x, y


def log_polar_grid(nx, ny, rmin, rmax, nwedges, nrings):
    """Build log-polar sampling grid (matches Python-style LPGrid)."""
    x_zero = (nx + 0.5) / 2
    y_zero = (ny + 0.5) / 2
    rv = np.exp(np.linspace(np.log(rmin), np.log(rmax), nrings))
    thv = np.linspace(0, 2 * np.pi * (1 - 1 / nwedges), nwedges)
    r, th = np.meshgrid(rv, thv)
    x, y = pol2cart(r, th)
    return x + x_zero, y + y_zero


def log_polar_coordinates(image_size, num_wedges, num_rings, rmin, rmax, max_angle):
    """
    Log-polar coordinate grid matching MATLAB LogPolarCoordinates.
    Returns (XLP, YLP).
    """
    h, w = image_size
    x_zero = (w + 1) / 2
    y_zero = (h + 1) / 2
    log_r = np.linspace(np.log(rmin), np.log(rmax), num_rings)
    rv = np.exp(log_r)
    th_max = max_angle * (1 - 1 / num_wedges)
    thv = np.linspace(0, th_max, num_wedges)
    r, th = np.meshgrid(rv, thv)
    x, y = pol2cart(r, th)
    return x + x_zero, y + y_zero


def make_interpolator(x_grid, y_grid, image):
    """
    Build a scipy interpolator mimicking MATLAB griddedInterpolant.
    x_grid and y_grid are 2D meshgrid arrays; image is the 2D data.
    """
    x_1d = x_grid[0, :]
    y_1d = y_grid[:, 0]
    return RegularGridInterpolator(
        (x_1d, y_1d), image.T,
        method='linear', bounds_error=False, fill_value=np.nan
    )


def tform_image(x, y, M, size, interp_func):
    """
    Map image from reference to current coordinates via affine transform.
    
    Args:
        x, y: meshgrid coordinate arrays
        M: 3x3 affine transform matrix
        size: (height, width) tuple
        interp_func: RegularGridInterpolator or similar callable
    """
    ones = np.ones_like(x.ravel())
    coords = np.vstack([x.ravel(), y.ravel(), ones])
    interp_points = np.linalg.solve(M, coords)

    xi = interp_points[0, :].reshape(size)
    yi = interp_points[1, :].reshape(size)

    pts = np.column_stack([xi.ravel(), yi.ravel()])
    result = interp_func(pts).reshape(size)
    return result


def tform_lp(img, x_lp, y_lp):
    """Sample image at log-polar coordinates via map_coordinates."""
    result = np.empty_like(x_lp)
    scipy.ndimage.map_coordinates(
        img, [y_lp, x_lp],
        output=result, order=1, mode='constant', cval=0.0, prefilter=True
    )
    return result
