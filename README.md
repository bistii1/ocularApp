# Ocular Pupillometry App

Mobile app for measuring pupil dilation response using visible light stimulation. The app records an eye video with a controlled flash sequence, uploads it to a Python analysis server, and displays results (latency, percent change, min/max pupil diameter).

## Architecture

- **Frontend**: Expo (React Native) app with camera recording and results display
- **Backend**: FastAPI server wrapping a Python pupillometry pipeline (FFT-based image registration + Fourier-Mellin correlation for dilation estimation)
- **MATLAB reference**: `backend/reflexBetaStandAlone.m` contains the original MATLAB implementation

## Quick Start

### 1. Start the backend server

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python3 -m uvicorn server:app --host 0.0.0.0 --port 8000 --reload
```

The API will be available at `http://localhost:8000`. Visit `http://localhost:8000/docs` for interactive API docs.

### 2. Start the mobile app

```bash
npm install
npx expo start
```

Open in Expo Go, iOS Simulator, or Android Emulator.

### 3. Usage

1. Enter a Subject ID and select Left/Right eye on the home screen
2. Tap **Open Camera** and press the record button
3. The app runs an automated flash sequence (3s on, 3s off, 0.25s on, off)
4. After recording, the video is uploaded to the backend for analysis
5. Results appear on the output screen: latency, percent change, min/max pupil diameter

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/health` | Health check |
| POST | `/api/analyze` | Upload video for analysis (multipart form: `video`, `subject_id`, `eye`, `engine`) |

## Backend Python Package

The analysis pipeline lives in `backend/python/`:

| Module | Purpose |
|--------|---------|
| `pipeline.py` | Main analysis pipeline (`analyze_video()`) |
| `apod_windows.py` | 2D Gaussian and Hanning apodization windows |
| `sub_pixel_fit.py` | Sub-pixel peak fitting for correlation planes |
| `coordinate_tform.py` | Coordinate transforms, log-polar grids, image warping |
| `correlation.py` | SCC (translation) and FMC (scale) correlation functions |

## Learn more

- [Expo documentation](https://docs.expo.dev/)
- [FastAPI documentation](https://fastapi.tiangolo.com/)
