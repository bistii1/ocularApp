import { useLocalSearchParams, useRouter } from "expo-router";
import { ScrollView, StyleSheet, Text, TouchableOpacity, View } from "react-native";
import type { AnalysisResult } from "../config";

export default function TestOutputScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<{
    resultJson?: string;
    subjectId?: string;
    eye?: string;
  }>();

  let result: AnalysisResult | null = null;
  try {
    if (params.resultJson) {
      result = JSON.parse(params.resultJson);
    }
  } catch {
    result = null;
  }

  return (
    <View style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.title}>Pupil Analysis Results</Text>
        {(params.subjectId || params.eye) && (
          <Text style={styles.subtitle}>
            {params.subjectId ? `Subject: ${params.subjectId}` : ''}
            {params.subjectId && params.eye ? ' | ' : ''}
            {params.eye ? `Eye: ${params.eye}` : ''}
            {result ? ` | Engine: ${result.engine}` : ''}
          </Text>
        )}
      </View>

      {result ? (
        <ScrollView style={styles.scrollBody} contentContainerStyle={styles.scrollContent}>
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
            <ResultRow label="Avg Constriction Vel." value={`${result.avg_constriction_velocity.toFixed(3)} %/fr`} />
            <ResultRow label="Avg Dilation Vel." value={`${result.avg_dilation_velocity.toFixed(3)} %/fr`} />
          </SectionCard>

          {/* Pupil Diameter Section */}
          <SectionCard title="Pupil Diameter">
            <ResultRow label="Baseline (est.)" value={`${result.baseline_pupil_diameter_mm.toFixed(1)} mm`} />
            <ResultRow label="Minimum" value={`${result.min_pupil_diameter_mm.toFixed(2)} mm`} />
            <ResultRow label="Maximum" value={`${result.max_pupil_diameter_mm.toFixed(2)} mm`} />
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
  if (!data || data.length === 0) return <Text style={styles.noResultsText}>No data</Text>;

  const min = Math.min(...data);
  const max = Math.max(...data);
  const range = max - min || 1;
  const barCount = Math.min(data.length, 40);
  const step = Math.max(1, Math.floor(data.length / barCount));
  const sampled: number[] = [];
  for (let i = 0; i < data.length; i += step) {
    sampled.push(data[i]);
  }

  const tStart = times.length > 0 ? times[0].toFixed(1) : '0';
  const tEnd = times.length > 0 ? times[times.length - 1].toFixed(1) : '?';

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
