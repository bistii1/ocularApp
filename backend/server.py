"""
FastAPI server for the ocular pupillometry analysis backend.
Accepts video uploads, runs the analysis pipeline, and returns results.
"""
import os
import sys
import uuid
import shutil
import logging
import tempfile
import asyncio
import time
import math

from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel, Field
from typing import Optional, List

sys.path.insert(0, os.path.dirname(__file__))
from python.pipeline import analyze_video

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

app = FastAPI(title="Ocular Pupillometry API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class AnalysisResult(BaseModel):
    # Timing
    onset_time_s: float
    peak_constriction_time_s: float
    recovery_time_s: Optional[float] = None
    # Magnitude
    max_constriction_pct: float
    percent_change: float
    # Velocity
    avg_constriction_velocity: float
    avg_dilation_velocity: float
    # Diameter
    min_pupil_diameter_mm: float
    max_pupil_diameter_mm: float
    baseline_pupil_diameter_mm: float
    # Processing info
    n_frames: int
    fps: float
    analysis_duration_s: float
    # Legacy
    latency_s: float
    # Time series
    dilation_time_series: List[float]
    velocity_time_series: List[float]
    time_vector: List[float]
    # Metadata
    subject_id: Optional[str] = None
    eye: Optional[str] = None
    engine: str = "python"
    quality_score: float = 0.0
    quality_label: str = "unreliable"
    quality_flags: List[str] = Field(default_factory=list)


def _validate_analysis_payload(result: dict):
    required_series = ["dilation_time_series", "velocity_time_series", "time_vector"]
    for key in required_series:
        values = result.get(key)
        if not isinstance(values, list) or len(values) == 0:
            raise ValueError(f"Invalid analysis output: '{key}' is empty")
        finite_values = [v for v in values if isinstance(v, (int, float)) and math.isfinite(v)]
        if len(finite_values) == 0:
            raise ValueError(f"Invalid analysis output: '{key}' has no finite values")

    n = len(result.get("time_vector", []))
    if len(result.get("dilation_time_series", [])) != n:
        raise ValueError("Invalid analysis output: dilation/time vector length mismatch")
    if len(result.get("velocity_time_series", [])) != n:
        raise ValueError("Invalid analysis output: velocity/time vector length mismatch")


@app.get("/api/health")
async def health():
    return {"status": "ok", "engine": "python"}


@app.post("/api/analyze", response_model=AnalysisResult)
async def analyze(
    video: UploadFile = File(...),
    subject_id: Optional[str] = Form(None),
    eye: Optional[str] = Form(None),
    engine: Optional[str] = Form("python"),
):
    """
    Upload an eye video recording for pupillometry analysis.
    Returns dilation metrics and time series data.
    """
    tmp_dir = tempfile.mkdtemp(prefix="ocular_")
    ext = os.path.splitext(video.filename or "video.mp4")[1] or ".mp4"
    tmp_path = os.path.join(tmp_dir, f"{uuid.uuid4()}{ext}")
    start_time = time.perf_counter()

    try:
        with open(tmp_path, "wb") as f:
            shutil.copyfileobj(video.file, f)

        logger.info("Received video: %s (%s, subject=%s, eye=%s)",
                     video.filename, engine, subject_id, eye)

        if engine == "matlab":
            raise HTTPException(
                status_code=501,
                detail="MATLAB engine not yet implemented. Use engine=python."
            )

        try:
            result = await asyncio.wait_for(
                run_in_threadpool(analyze_video, tmp_path),
                timeout=180,
            )
        except asyncio.TimeoutError:
            raise HTTPException(
                status_code=504,
                detail="Analysis timed out on the server (180s). Try a shorter recording."
            )

        result["subject_id"] = subject_id
        result["eye"] = eye
        result["engine"] = engine
        _validate_analysis_payload(result)

        elapsed = time.perf_counter() - start_time
        logger.info(
            "Analysis completed in %.2fs (frames=%s, series_len=%s)",
            elapsed,
            result.get("n_frames"),
            len(result.get("time_vector", [])),
        )

        return AnalysisResult(**result)

    except FileNotFoundError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    except Exception as e:
        logger.exception("Analysis failed")
        raise HTTPException(status_code=500, detail=f"Analysis failed: {str(e)}")
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("server:app", host="0.0.0.0", port=8000, reload=True)
