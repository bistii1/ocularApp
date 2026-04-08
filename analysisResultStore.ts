import AsyncStorage from '@react-native-async-storage/async-storage';
import type { AnalysisResult } from './config';

export interface StoredAnalysisResult {
  result: AnalysisResult;
  subjectId?: string;
  eye?: string;
  savedAt: string;
}

let lastAnalysisResult: StoredAnalysisResult | null = null;
const LAST_RESULT_KEY = 'ocular:last-analysis-result';

export async function setLastAnalysisResult(payload: Omit<StoredAnalysisResult, 'savedAt'>) {
  lastAnalysisResult = {
    ...payload,
    savedAt: new Date().toISOString(),
  };

  try {
    await AsyncStorage.setItem(LAST_RESULT_KEY, JSON.stringify(lastAnalysisResult));
  } catch (error) {
    console.warn('Failed to persist analysis result:', error);
  }
}

export function getLastAnalysisResultSync() {
  return lastAnalysisResult;
}

export async function getLastAnalysisResult() {
  if (lastAnalysisResult) return lastAnalysisResult;

  try {
    const raw = await AsyncStorage.getItem(LAST_RESULT_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as StoredAnalysisResult;
    lastAnalysisResult = parsed;
    return parsed;
  } catch (error) {
    console.warn('Failed to load analysis result:', error);
    return null;
  }
}

export async function clearLastAnalysisResult() {
  lastAnalysisResult = null;
  try {
    await AsyncStorage.removeItem(LAST_RESULT_KEY);
  } catch (error) {
    console.warn('Failed to clear stored analysis result:', error);
  }
}
