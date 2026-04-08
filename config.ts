import Constants from 'expo-constants';
import { Platform } from 'react-native';

/**
 * Configure API URL in this order:
 * 1) EXPO_PUBLIC_API_BASE_URL (recommended)
 * 2) Expo debugger host (for LAN testing)
 * 3) Emulator/simulator sensible defaults
 */
function resolveApiBaseUrl() {
  const envUrl = process.env.EXPO_PUBLIC_API_BASE_URL?.trim();
  if (envUrl) return envUrl.replace(/\/$/, '');

  const hostUri =
    (Constants.expoConfig as any)?.hostUri ||
    (Constants.manifest2 as any)?.extra?.expoGo?.debuggerHost ||
    (Constants.manifest as any)?.debuggerHost ||
    '';

  if (typeof hostUri === 'string' && hostUri.length > 0) {
    const host = hostUri.split(':')[0];
    if (host) return `http://${host}:8000`;
  }

  if (Platform.OS === 'android') return 'http://10.0.2.2:8000';
  return 'http://localhost:8000';
}

export const API_BASE_URL = resolveApiBaseUrl();

async function fetchWithTimeout(url: string, options: RequestInit, timeoutMs: number) {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  try {
    return await fetch(url, {
      ...options,
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timeoutId);
  }
}

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
  avg_constriction_velocity_pct_s: number;
  avg_dilation_velocity_pct_s: number;
  velocity_units: string;
  // Diameter
  min_pupil_diameter_mm: number;
  max_pupil_diameter_mm: number;
  baseline_pupil_diameter_mm: number;
  baseline_stability_pct: number;
  signal_dynamic_pct: number;
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
  // Quality
  quality_score: number;
  quality_label: string;
  quality_flags: string[];
  validation_score: number;
  is_plr_usable: boolean;
  plr_verdict: string;
  validation_warnings: string[];
  validation_failures: string[];
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

  // Quick preflight to surface unreachable backend errors early.
  try {
    await fetchWithTimeout(`${API_BASE_URL}/api/health`, { method: 'GET' }, 5000);
  } catch {
    throw new Error(
      `Cannot reach backend at ${API_BASE_URL}. Start the backend and set EXPO_PUBLIC_API_BASE_URL if needed.`
    );
  }

  let response: Response;
  try {
    response = await fetchWithTimeout(
      `${API_BASE_URL}/api/analyze`,
      {
        method: 'POST',
        body: formData,
      },
      240000,
    );
  } catch (error: any) {
    if (error?.name === 'AbortError') {
      throw new Error('Analysis timed out after 240s. Try a shorter/clearer recording.');
    }
    throw new Error(`Network request failed to ${API_BASE_URL}: ${error?.message || 'Unknown error'}`);
  }

  if (!response.ok) {
    const error = await response.json().catch(() => ({ detail: 'Unknown error' }));
    throw new Error(error.detail || `Server error: ${response.status}`);
  }

  return response.json();
}
