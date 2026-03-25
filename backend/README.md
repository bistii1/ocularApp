# Ocular Pupilometry Backend

FastAPI server that receives eye-recording videos from the mobile app, measures pupil diameter across every frame, and returns Pupillary Light Reflex (PLR) metrics.

## How it works (high-level)

```
┌─────────────────────────────────────────────────────────────┐
│  MOBILE APP (React Native / Expo)                           │
│                                                             │
│  1. User enters subject ID, selects eye, taps "Run PLR"    │
│  2. 3-2-1 countdown (user positions eye in frame)           │
│  3. Camera records 5 seconds of video:                      │
│       [1s dark baseline] [1s bright flash] [3s dark recovery]│
│  4. Video uploaded to backend server                        │
│  5. Results displayed on screen                             │
└────────────────────┬────────────────────────────────────────┘
                     │  video file + metadata
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  BACKEND SERVER (FastAPI / Python)                           │
│                                                             │
│  1. Receive video upload, save a copy to recordings/        │
│  2. Extract all frames, pull out the red channel            │
│  3. Detect the eye region (Haar cascade)                    │
│  4. For each frame, measure pupil diameter:                 │
│       blur → find darkest point → threshold → contour      │
│  5. Compute PLR metrics using flash timing:                 │
│       baseline, constriction %, latency, diameter range     │
│  6. Return JSON results to app                              │
└────────────────────┬────────────────────────────────────────┘
                     │  (optional, manual)
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  OFFLINE VALIDATION (validate.py)                           │
│                                                             │
│  Re-process any saved recording with debug output:          │
│  → annotated frames, threshold masks, diameter plot, JSON   │
└─────────────────────────────────────────────────────────────┘
```

The phone screen itself acts as the light stimulus — it flashes bright white for 1 second to trigger the pupillary light reflex, then goes dark while the camera records the pupil constricting and recovering.

## Quick start

```bash
cd backend
pip install -r requirements.txt
uvicorn server:app --host 0.0.0.0 --port 8000 --reload
```

The server listens on port 8000. The mobile app auto-discovers the host IP via Expo, so both devices just need to be on the same network.

## API endpoints

### `GET /health`

Returns `{"status": "ok"}`. Use this to verify the server is reachable.

### `POST /analyze`

Accepts a multipart form upload and returns PLR analysis results as JSON.

**Form fields:**

| Field              | Type   | Default | Description                                         |
|--------------------|--------|---------|-----------------------------------------------------|
| `file`             | file   | —       | Video file (`.mp4`, `.mov`, etc.)                   |
| `subject_id`       | string | `""`    | Optional identifier for the subject                 |
| `eye`              | string | `"left"`| Which eye was recorded (`"left"` or `"right"`)      |
| `flash_onset_s`    | float  | `1.0`   | Seconds into the recording when the flash started   |
| `flash_duration_s` | float  | `1.0`   | Duration of the flash stimulus in seconds           |

**Response JSON:**

```json
{
  "latency_ms": 233.3,
  "percent_change": 18.45,
  "constriction_pct": 12.30,
  "baseline_diameter_px": 42.15,
  "min_diameter_px": 35.20,
  "max_diameter_px": 44.80,
  "frame_count": 150,
  "fps": 30.0,
  "eye_detected": true,
  "subject_id": "subj01",
  "eye": "left",
  "flash_onset_s": 1.0,
  "flash_duration_s": 1.0,
  "valid_frames": 138,
  "total_frames": 150,
  "message": "Analysis complete",
  "saved_video": "subj01_left_20260324_141522.mp4"
}
```

## Processing pipeline

All analysis logic lives in `processing.py`. Here is what happens when a video is submitted:

### 1. Frame extraction

`_load_frames()` opens the video with OpenCV and reads every frame into memory as BGR arrays. The video's FPS metadata is captured for time-based calculations.

### 2. Red channel extraction

`_extract_red_channel()` pulls out the red channel (index 2 of BGR) from each frame. The red channel is used instead of standard grayscale because it provides significantly better contrast between the pupil and iris, especially across different skin tones. This follows findings from the far-red spectrum pupilometry research.

### 3. Eye region detection

`_detect_eye_region()` runs OpenCV's Haar cascade classifier (`haarcascade_eye.xml`) on up to 12 evenly-spaced frames from the video, trying three progressively looser configurations (varying `scaleFactor`, `minNeighbors`, and `minSize`). It returns the bounding box `(x, y, w, h)` of the first detected eye. If no eye is found in any frame, the pipeline falls back to using the center 50% of the frame.

### 4. Per-frame pupil measurement

`_measure_pupil_diameter()` runs on the red-channel ROI of every frame:

1. **Heavy Gaussian blur** — kernel size scales with ROI dimensions (`max(15, min_dim // 6)`). This eliminates fine texture like eyelashes and skin pores so only the broad dark region of the pupil remains.

2. **Darkest-point detection** — `cv2.minMaxLoc` on the blurred image finds the single darkest pixel, which is assumed to be the pupil center. If it isn't substantially darker than the image median (ratio > 0.75), the frame is marked as no-detection (flash-washed or closed eye).

3. **Local thresholding** — a threshold is set at `min_val + 0.35 * (median_val - min_val)`, which captures the pupil disc without bleeding into the surrounding iris.

4. **Morphological cleanup** — elliptical OPEN then CLOSE operations remove small noise blobs and fill holes in the threshold mask.

5. **Contour scoring** — each contour from the threshold mask is evaluated by:
   - Area bounds (0.1%–15% of the ROI area)
   - Circularity (must be > 0.25, where 1.0 = perfect circle)
   - Whether it contains the darkest point (+5.0 bonus to score)
   - Distance from the darkest point (penalised)

   The highest-scoring contour is selected and its diameter is computed as `2 * sqrt(area / pi)`.

### 5. Metric computation

After measuring all frames, the pipeline computes PLR-specific metrics using the flash timing parameters sent by the app:

- **Baseline diameter** — median of all valid diameter measurements from frames *before* `flash_onset_s`. This represents the resting pupil size.

- **Constriction %** — `(baseline - post_flash_minimum) / baseline * 100`. The post-flash minimum uses the 5th percentile of valid diameters after the flash ends, which gives the peak constriction while rejecting single-frame outliers.

- **Latency** — time in milliseconds from flash onset to the first frame showing sustained pupil change. "Sustained" means a sliding window of frames (approximately 100 ms worth) all deviate from baseline by more than 5%. This prevents momentary noise from triggering a false latency reading.

- **Min/Max diameter** — 5th and 95th percentiles of all valid diameter measurements across the full video. Using percentiles instead of raw min/max avoids flash artifacts or blink frames from skewing the range.

- **Percent change** — `(max - min) / min * 100` using the percentile-based diameters above.

- **Detection quality** — `valid_frames / total_frames` ratio, so the app can display how many frames had a successful pupil measurement.

## Video saving

Every video uploaded through `/analyze` is saved to `backend/recordings/` with the naming pattern `{subject_id}_{eye}_{YYYYMMDD_HHMMSS}.mp4`. This allows offline re-validation of any recording using `validate.py`.

## Offline validation

`validate.py` processes videos locally with full debug output:

```bash
# Run on a single video
python validate.py recordings/subj01_left_20260324_141522.mp4

# Run on a folder of videos
python validate.py ../p01/

# Run only the synthetic ground-truth test
python validate.py --synthetic
```

For each video it produces a folder under `validation_output/` containing:

| File                   | Description                                                           |
|------------------------|-----------------------------------------------------------------------|
| `annotated_NNN.jpg`    | Sample frames with green eye-ROI box and cyan pupil contour overlay   |
| `threshold_NNN.jpg`    | Binary mask showing what the thresholding step captured               |
| `diameter_plot.png`    | Full time-series plot of pupil diameter with flash region highlighted |
| `results.json`         | Complete metrics including per-frame diameter array                   |

The synthetic test generates a video with known pupil diameters (sinusoidal variation, 30 px range) and reports mean/max/median absolute error as a pipeline sanity check.

## File overview

| File                         | Purpose                                                          |
|------------------------------|------------------------------------------------------------------|
| `server.py`                  | FastAPI app with `/health` and `/analyze` endpoints              |
| `processing.py`              | Video analysis pipeline (eye detection, pupil measurement, PLR metrics) |
| `validate.py`                | Offline debug/validation tool for videos                         |
| `requirements.txt`           | Python dependencies                                              |
| `apodWindows.py`             | Gaussian and Hanning 2D window functions (for future FFT work)   |
| `coordinateTform.py`         | Cartesian/polar coordinate transforms and log-polar grid (for future FMC registration) |
| `correlationSubFunctions.py` | Spectral Cross-Correlation, Fourier-Mellin, and Log-Polar Correlation functions (for future sub-pixel registration) |
| `subPixelFit.py`             | Log-parabolic sub-pixel peak fitting (used by correlation functions) |
| `reflexPython.py`            | Original standalone reflex analysis script (reference, not used by server) |

The files `apodWindows.py`, `coordinateTform.py`, `correlationSubFunctions.py`, `subPixelFit.py`, and `reflexPython.py` are legacy utility modules from earlier research work. They are not currently called by the server pipeline but are preserved for future integration of FFT-based sub-pixel registration and advanced correlation analysis.


## Annotated image overlays

Each `annotated_NNN.jpg` is a raw frame with three things drawn on top:

- **Green rectangle** — the eye region of interest (ROI) found by a Haar cascade detector (a machine learning-based object detection algorithm commonly used for real-time face and eye detection). This ROI is detected once and reused across all frames.
- **Cyan contour** — the shape the algorithm identified as the pupil within the ROI.
- **Green text label** — e.g. `Frame 92: d=122.2px` means the algorithm measured a pupil diameter of 122.2 pixels for this frame (or `no detect` when it fails).

The corresponding `threshold_NNN.jpg` files show the raw binary mask — white pixels survived the thresholding step, black pixels were rejected. This shows exactly what the algorithm "sees" before contour selection.

## results.json field reference

| Field | Example value | Meaning |
|---|---|---|
| `eye_detected` | `true` | Whether the Haar cascade found an eye (`false` = fell back to center-crop of the frame) |
| `eye_roi` | `[119, 560, 484, 484]` | `[x, y, width, height]` of the detected eye bounding box in pixel coordinates |
| `frame_count` | `184` | Total number of frames in the video |
| `fps` | `27.9` | Video framerate (read from file metadata) |
| `baseline_diameter_px` | `113.5` | Median pupil diameter from frames before the flash onset — the resting pupil size |
| `min_diameter_px` | `87.8` | 5th percentile of all valid (non-zero) diameter measurements |
| `max_diameter_px` | `125.4` | 95th percentile of all valid diameter measurements |
| `percent_change` | `42.82` | `(max - min) / min * 100` — overall range of pupil size variation |
| `constriction_pct` | `12.3` | `(baseline - post_flash_min) / baseline * 100` — how much the pupil contracted after the flash |
| `latency_ms` | `358.6` | Time in milliseconds from flash onset to first sustained diameter change |
| `flash_onset_s` | `1.0` | When the flash stimulus started (seconds into the recording) |
| `flash_duration_s` | `1.0` | How long the flash lasted (seconds) |
| `valid_frames` | `152` | Number of frames where the pupil was successfully detected |
| `total_frames` | `184` | Same as `frame_count` |
| `subject_id` | `""` | Subject identifier passed from the app |
| `eye` | `"left"` | Which eye was recorded |
| `message` | `"Analysis complete"` | Status message or error description |
| `diameters` | `[115.28, 106.73, ...]` | Array with one diameter value per frame (see below) |

### Understanding the `diameters` array

Each entry in the `diameters` array is the measured pupil diameter in pixels for that frame index. The value `0.0` means the algorithm could not find the pupil in that frame (blink, flash washout, closed eye, or no contour passed the filters).

Typical diameter ranges and what they indicate:

| Diameter range | Interpretation |
|---|---|
| **0.0** | No detection — the pupil was not visible (blink, flash washout, or closed eye) |
| **< 50 px** | Likely a mis-detection or partial occlusion — the contour probably captured only a fragment of the pupil or a non-pupil feature |
| **~80–100 px** | Constricted pupil — typically seen shortly after a bright flash stimulus |
| **~100–130 px** | Normal / dilated pupil — typical resting diameter in a close-up phone recording |
| **> 140 px** | Likely an artifact — the contour probably bled into the iris or eyelid shadow |

These ranges are approximate and depend on recording distance, camera zoom, and resolution. What matters clinically is the *relative* change (constriction %) rather than the absolute pixel values.

## References

Several design decisions in this pipeline are informed by the following research:

### [1] McAnany et al. — "Racially fair pupillometry measurements for RGB smartphone cameras using the far red spectrum"

This paper demonstrated that standard RGB pupilometry has a racial bias: the pupil-iris contrast is much lower in darkly pigmented eyes under visible light, causing detection algorithms to fail or lose accuracy. The authors showed that using the far-red / near-infrared spectrum (>700 nm) dramatically improves contrast across all skin tones.

What we adopted from this paper:

- **Red channel processing** (Section 2, Processing pipeline step 2) — Instead of converting frames to grayscale (which mixes all three channels), we extract only the red channel. The red channel is the closest approximation to far-red that a standard phone camera sensor provides without hardware modifications. This improves pupil-iris contrast, especially for darker eye colors.
- **PLR test protocol structure** (Section 1, How it works) — The paper describes a Pupillary Light Reflex protocol with a defined baseline period, a controlled light stimulus, and a recovery period. Our protocol (1s baseline → 1s flash → 3s recovery) follows this structure. The paper used a 1-second white-light stimulus delivered via the phone screen, which is the same approach we use.
- **Screen-based stimulus** — The paper validated that the phone's own screen can serve as a sufficient light source to trigger a measurable PLR, which is why we use a bright white overlay during the flash phase rather than requiring external hardware.
- **Constriction % as primary metric** — The paper reports pupil constriction as a percentage of baseline diameter, which is the clinically meaningful measure. We compute this the same way: `(baseline - minimum) / baseline * 100`.

### [2] Fuhl et al. — "Improving real-time CNN-based pupil detection through domain-specific data augmentation"

This paper showed that convolutional neural networks significantly outperform traditional image processing for pupil detection, and that domain-specific data augmentation (simulating reflections, eyelid occlusion, and varying illumination) can dramatically reduce the amount of hand-labeled training data needed.

What we adopted from this paper:

- **Nothing yet in the current pipeline** — the current implementation uses classical computer vision (Haar cascade + thresholding + contour analysis) as an MVP baseline. However, this paper informs the planned Phase 2 upgrade.
- **Future work: CNN pupil detector** — the paper's approach of training a lightweight CNN on augmented eye images is the intended replacement for the current darkest-point detection method. The irregular contours visible in current annotated outputs (e.g., eyelash shadows being mistaken for pupil edges) are exactly the failure mode that CNN-based detection resolves.
- **Future work: domain-specific augmentation** — rather than manually labeling thousands of frames, the paper's augmentation strategy (synthetic reflections, blur, gaze variation) would let us bootstrap a training set from a small number of hand-labeled examples.

### Techniques not from papers

The following techniques in the pipeline are standard computer vision approaches, not derived from either paper:

- **Haar cascade eye detection** — OpenCV's built-in `haarcascade_eye.xml` classifier, based on Viola & Jones (2001).
- **Darkest-point seeded pupil detection** — custom approach developed iteratively for this project. Uses heavy Gaussian blur + `minMaxLoc` + local thresholding + contour scoring. This is a heuristic method that works reasonably well on close-up eye videos but has known limitations with eyelash shadows and uneven lighting.
- **Robust statistics for metrics** — using percentiles (5th/95th) instead of raw min/max, and median instead of mean, to resist outliers from flash artifacts and blink frames. This is standard practice in noisy signal analysis.