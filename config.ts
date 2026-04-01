/**
 * Change this to your computer's local IP if testing on a physical device.
 * Run `ifconfig | grep "inet "` on your Mac to find it.
 * Use 'localhost' only for iOS Simulator.
 */
const SERVER_IP = '10.186.191.98';

export const API_BASE_URL = `http://${SERVER_IP}:8000`;

export interface AnalysisResult {
  // Timing
  onset_time_s: number;
  peak_constriction_time_s: number;
  recovery_time_s: number | null;
  // Magnitude
  max_constriction_pct: number;
  percent_change: number;
  // Velocity
  avg_constriction_velocity: number;
  avg_dilation_velocity: number;
  // Diameter
  min_pupil_diameter_mm: number;
  max_pupil_diameter_mm: number;
  baseline_pupil_diameter_mm: number;
  // Processing info
  n_frames: number;
  fps: number;
  analysis_duration_s: number;
  // Legacy
  latency_s: number;
  // Time series
  dilation_time_series: number[];
  velocity_time_series: number[];
  time_vector: number[];
  // Metadata
  subject_id: string | null;
  eye: string | null;
  engine: string;
}

export async function analyzeVideo(
  videoUri: string,
  subjectId?: string,
  eye?: string,
  engine: string = 'python',
): Promise<AnalysisResult> {
  const formData = new FormData();

  const filename = videoUri.split('/').pop() || 'video.mp4';
  formData.append('video', {
    uri: videoUri,
    name: filename,
    type: 'video/mp4',
  } as any);

  if (subjectId) formData.append('subject_id', subjectId);
  if (eye) formData.append('eye', eye);
  formData.append('engine', engine);

  const response = await fetch(`${API_BASE_URL}/api/analyze`, {
    method: 'POST',
    body: formData,
  });

  if (!response.ok) {
    const error = await response.json().catch(() => ({ detail: 'Unknown error' }));
    throw new Error(error.detail || `Server error: ${response.status}`);
  }

  return response.json();
}
