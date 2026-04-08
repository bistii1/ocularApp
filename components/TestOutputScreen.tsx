import { useLocalSearchParams, useRouter } from "expo-router";
import { useEffect, useMemo, useState } from "react";
import { ScrollView, StyleSheet, Text, TouchableOpacity, View } from "react-native";
import { getLastAnalysisResult, getLastAnalysisResultSync, type StoredAnalysisResult } from "../analysisResultStore";
import type { AnalysisResult } from "../config";

export default function TestOutputScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<{
    resultJson?: string;
    subjectId?: string;
    eye?: string;
  }>();

  const [stored, setStored] = useState<StoredAnalysisResult | null>(getLastAnalysisResultSync());

  useEffect(() => {
    let mounted = true;

    getLastAnalysisResult().then(value => {
      if (mounted) setStored(value);
    });

    return () => {
      mounted = false;
    };
  }, []);

  const result = useMemo<AnalysisResult | null>(() => {
    if (stored?.result) return stored.result;

    try {
      if (params.resultJson) {
        return JSON.parse(params.resultJson);
      }
    } catch {
      return null;
    }

    return null;
  }, [params.resultJson, stored]);

  const subjectId = params.subjectId || stored?.subjectId || result?.subject_id || '';
  const eye = params.eye || stored?.eye || result?.eye || '';

  const validationScore = result?.validation_score ?? 0;
  const isPlrUsable = result?.is_plr_usable ?? false;
  const plrVerdict = result?.plr_verdict ?? 'not_usable';
  const validationWarnings = result?.validation_warnings ?? [];
  const validationFailures = result?.validation_failures ?? [];

  const velocityUnits = result?.velocity_units ?? '%/fr';
  const avgConstrictionVelocityDisplay =
    result?.avg_constriction_velocity_pct_s ?? result?.avg_constriction_velocity ?? 0;
  const avgDilationVelocityDisplay =
    result?.avg_dilation_velocity_pct_s ?? result?.avg_dilation_velocity ?? 0;

  const baselineStabilityPct = result?.baseline_stability_pct ?? 0;
  const signalDynamicPct = result?.signal_dynamic_pct ?? 0;

  return (
    <View style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.title}>Pupil Analysis Results</Text>
        {(subjectId || eye) && (
          <Text style={styles.subtitle}>
            {subjectId ? `Subject: ${subjectId}` : ''}
            {subjectId && eye ? ' | ' : ''}
            {eye ? `Eye: ${eye}` : ''}
            {result ? ` | Engine: ${result.engine}` : ''}
          </Text>
        )}
      </View>

      {result ? (
        <ScrollView style={styles.scrollBody} contentContainerStyle={styles.scrollContent}>
          {/* PLR Verdict */}
          <SectionCard title="PLR Interpretation">
            <ResultRow label="Verdict" value={isPlrUsable ? 'Usable' : 'Not usable'} />
            <ResultRow label="Validation Score" value={`${validationScore.toFixed(1)} / 100`} />
            <ResultRow label="Decision" value={plrVerdict.replace(/_/g, ' ')} />
            {validationFailures.length > 0 && (
              <Text style={styles.validationFailureText}>
                Failures: {validationFailures.join(', ')}
              </Text>
            )}
            {validationWarnings.length > 0 && (
              <Text style={styles.validationWarnText}>
                Warnings: {validationWarnings.join(', ')}
              </Text>
            )}
          </SectionCard>

          {/* Timing Section */}
          <SectionCard title="Timing">
            <ResultRow label="Onset / Latency" value={`${result.onset_time_s.toFixed(3)} s`} />
            <ResultRow label="Peak Constriction Time" value={`${result.peak_constriction_time_s.toFixed(3)} s`} />
            <ResultRow
              label="Recovery Time (75%)"
              value={result.recovery_time_s != null ? `${result.recovery_time_s.toFixed(3)} s` : 'N/A'}
            />
          </SectionCard>

          {/* Constriction Section */}
          <SectionCard title="Constriction">
            <ResultRow label="Max Constriction" value={`${result.max_constriction_pct.toFixed(2)}%`} />
            <ResultRow label="Overall Change" value={`${result.percent_change.toFixed(2)}%`} />
          </SectionCard>

          {/* Velocity Section */}
          <SectionCard title="Velocity">
            <ResultRow label="Avg Constriction Vel." value={`${avgConstrictionVelocityDisplay.toFixed(3)} ${velocityUnits}`} />
            <ResultRow label="Avg Dilation Vel." value={`${avgDilationVelocityDisplay.toFixed(3)} ${velocityUnits}`} />
          </SectionCard>

          {/* Pupil Diameter Section */}
          <SectionCard title="Pupil Diameter">
            <ResultRow label="Baseline (est.)" value={`${result.baseline_pupil_diameter_mm.toFixed(1)} mm`} />
            <ResultRow label="Minimum" value={`${result.min_pupil_diameter_mm.toFixed(2)} mm`} />
            <ResultRow label="Maximum" value={`${result.max_pupil_diameter_mm.toFixed(2)} mm`} />
            <ResultRow label="Baseline Stability" value={`${baselineStabilityPct.toFixed(2)}%`} />
            <ResultRow label="Signal Dynamic Range" value={`${signalDynamicPct.toFixed(2)}%`} />
          </SectionCard>

          {/* Dilation Sparkline */}
          <SectionCard title="Dilation Ratio Over Time">
            <Sparkline
              data={result.dilation_time_series}
              times={result.time_vector}
            />
          </SectionCard>

          {/* Processing Info */}
          <SectionCard title="Processing Info">
            <ResultRow label="Frames Analyzed" value={`${result.n_frames}`} />
            <ResultRow label="Frame Rate" value={`${result.fps.toFixed(1)} fps`} />
            <ResultRow label="Duration" value={`${result.analysis_duration_s.toFixed(2)} s`} />
          </SectionCard>

          {/* Quality Section */}
          <SectionCard title="Quality">
            <ResultRow label="Confidence Score" value={`${result.quality_score.toFixed(1)} / 100`} />
            <ResultRow label="Confidence Label" value={result.quality_label} />
            <ResultRow
              label="Flags"
              value={result.quality_flags.length > 0 ? result.quality_flags.join(', ') : 'none'}
            />
            {result.quality_flags.length > 0 && (
              <Text style={styles.qualityHintText}>{qualityHintFromFlags(result.quality_flags)}</Text>
            )}
          </SectionCard>

          {/* Actions */}
          <View style={styles.actions}>
            <TouchableOpacity onPress={() => router.push('/')} style={styles.completeButton}>
              <Text style={styles.buttonText}>Complete Test</Text>
            </TouchableOpacity>
            <TouchableOpacity onPress={() => router.push('/')} style={styles.newTestButton}>
              <Text style={styles.newTestButtonText}>New Test</Text>
            </TouchableOpacity>
          </View>
        </ScrollView>
      ) : (
        <View style={styles.noResults}>
          <Text style={styles.noResultsText}>
            No results yet. Record an eye video to see analysis results here.
          </Text>
          <TouchableOpacity onPress={() => router.push('/')} style={[styles.completeButton, { marginTop: 30 }]}>
            <Text style={styles.buttonText}>Back to Home</Text>
          </TouchableOpacity>
        </View>
      )}
    </View>
  );
}

// ---------------------------------------------------------------------------

function SectionCard({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <View style={styles.card}>
      <Text style={styles.cardTitle}>{title}</Text>
      {children}
    </View>
  );
}

function ResultRow({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.resultRow}>
      <Text style={styles.resultLabel}>{label}</Text>
      <Text style={styles.resultValue}>{value}</Text>
    </View>
  );
}

function Sparkline({ data, times }: { data: number[]; times: number[] }) {
  const cleanData = (data || []).filter(v => Number.isFinite(v));
  const cleanTimes = (times || []).filter(v => Number.isFinite(v));

  if (cleanData.length === 0) {
    return <Text style={styles.noResultsText}>No valid graph data from analysis.</Text>;
  }

  const min = Math.min(...cleanData);
  const max = Math.max(...cleanData);
  const range = max - min || 1;
  const barCount = Math.min(cleanData.length, 40);
  const step = Math.max(1, Math.floor(cleanData.length / barCount));
  const sampled: number[] = [];
  for (let i = 0; i < cleanData.length; i += step) {
    sampled.push(cleanData[i]);
  }

  const tStart = cleanTimes.length > 0 ? cleanTimes[0].toFixed(1) : '0';
  const tEnd = cleanTimes.length > 0 ? cleanTimes[cleanTimes.length - 1].toFixed(1) : '?';

  return (
    <View>
      <View style={styles.sparkContainer}>
        {sampled.map((v, i) => {
          const pct = ((v - min) / range) * 100;
          return (
            <View key={i} style={styles.sparkBarWrapper}>
              <View style={[styles.sparkBar, { height: `${Math.max(4, pct)}%` }]} />
            </View>
          );
        })}
      </View>
      <View style={styles.sparkLabels}>
        <Text style={styles.sparkLabel}>{tStart}s</Text>
        <Text style={styles.sparkLabel}>ratio: {min.toFixed(3)} – {max.toFixed(3)}</Text>
        <Text style={styles.sparkLabel}>{tEnd}s</Text>
      </View>
    </View>
  );
}

function qualityHintFromFlags(flags: string[]) {
  const hints: string[] = [];

  if (flags.includes('flat_signal')) {
    hints.push('Use brighter, direct eye lighting and keep the eye centered/filling more of the frame.');
  }
  if (flags.includes('weak_constriction')) {
    hints.push('Increase stimulus contrast and avoid ambient light changes during recording.');
  }
  if (flags.includes('implausible_timing')) {
    hints.push('Hold the phone steady and keep eyelids open through the full flash sequence.');
  }
  if (flags.includes('low_frame_count')) {
    hints.push('Record a full-length trial and avoid early stop/cancel.');
  }
  if (flags.includes('noisy_velocity')) {
    hints.push('Reduce motion blur by stabilizing device and minimizing subject movement.');
  }

  if (hints.length === 0) {
    return 'No issues detected.';
  }
  return hints.join(' ');
}

// ---------------------------------------------------------------------------

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f5f5f5' },
  header: {
    paddingTop: 60,
    paddingHorizontal: 20,
    paddingBottom: 20,
    backgroundColor: '#564bf5',
  },
  title: { fontSize: 24, fontWeight: 'bold', color: 'white' },
  subtitle: { fontSize: 13, color: 'rgba(255,255,255,0.8)', marginTop: 4 },
  scrollBody: { flex: 1 },
  scrollContent: { paddingBottom: 40 },
  card: {
    marginHorizontal: 16,
    marginTop: 14,
    backgroundColor: 'white',
    borderRadius: 12,
    padding: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.08,
    shadowRadius: 3,
    elevation: 2,
  },
  cardTitle: {
    fontSize: 13,
    fontWeight: '700',
    color: '#888',
    textTransform: 'uppercase',
    letterSpacing: 0.8,
    marginBottom: 8,
  },
  resultRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 8,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#f0f0f0',
  },
  resultLabel: { fontSize: 15, color: '#333', flex: 1 },
  resultValue: { fontSize: 16, fontWeight: '600', color: '#564bf5' },
  sparkContainer: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    height: 80,
    marginTop: 8,
    gap: 1,
  },
  sparkBarWrapper: {
    flex: 1,
    height: '100%',
    justifyContent: 'flex-end',
  },
  sparkBar: {
    backgroundColor: '#564bf5',
    borderRadius: 1,
    minHeight: 2,
  },
  sparkLabels: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 4,
  },
  sparkLabel: { fontSize: 11, color: '#999' },
  qualityHintText: { fontSize: 12, color: '#666', marginTop: 10, lineHeight: 17 },
  validationWarnText: { fontSize: 12, color: '#7b5e00', marginTop: 8, lineHeight: 17 },
  validationFailureText: { fontSize: 12, color: '#9e1b1b', marginTop: 8, lineHeight: 17, fontWeight: '600' },
  noResults: { flex: 1, justifyContent: 'center', alignItems: 'center', paddingHorizontal: 40 },
  noResultsText: { fontSize: 16, color: '#999', textAlign: 'center' },
  actions: { alignItems: 'center', marginTop: 20, marginBottom: 20 },
  completeButton: {
    backgroundColor: '#0b952b',
    padding: 14,
    borderRadius: 8,
    width: 220,
    alignItems: 'center',
  },
  buttonText: { color: 'white', fontSize: 18, fontWeight: '600' },
  newTestButton: {
    marginTop: 12,
    padding: 14,
    borderRadius: 8,
    width: 220,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#564bf5',
  },
  newTestButtonText: { color: '#564bf5', fontSize: 18, fontWeight: '600' },
});
