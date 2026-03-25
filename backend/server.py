"""
FastAPI server for ocular pupilometry analysis.

Run with:
    cd backend && uvicorn server:app --host 0.0.0.0 --port 8000 --reload
"""
import os
import shutil
import tempfile
from datetime import datetime

from fastapi import FastAPI, File, Form, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from processing import process_video

app = FastAPI(title="Ocular Pupilometry API")

RECORDINGS_DIR = os.path.join(os.path.dirname(__file__), "recordings")
os.makedirs(RECORDINGS_DIR, exist_ok=True)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/analyze")
async def analyze(
    file: UploadFile = File(...),
    subject_id: str = Form(""),
    eye: str = Form("left"),
    flash_onset_s: float = Form(1.0),
    flash_duration_s: float = Form(1.0),
):
    suffix = os.path.splitext(file.filename or "video.mp4")[1] or ".mp4"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name

    # Persist a copy for offline validation
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    save_name = f"{subject_id or 'anon'}_{eye}_{timestamp}{suffix}"
    save_path = os.path.join(RECORDINGS_DIR, save_name)
    shutil.copy2(tmp_path, save_path)

    try:
        results = process_video(
            tmp_path,
            subject_id=subject_id,
            eye=eye,
            flash_onset_s=flash_onset_s,
            flash_duration_s=flash_duration_s,
        )
        results["saved_video"] = save_name
    except Exception as exc:
        results = {
            "latency_ms": 0,
            "percent_change": 0,
            "min_diameter_px": 0,
            "max_diameter_px": 0,
            "frame_count": 0,
            "fps": 0,
            "eye_detected": False,
            "subject_id": subject_id,
            "eye": eye,
            "message": f"Processing error: {exc}",
            "saved_video": save_name,
        }
    finally:
        os.unlink(tmp_path)

    return results
