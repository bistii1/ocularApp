import { useLocalSearchParams, useRouter } from "expo-router";
import { StyleSheet, Text, TouchableOpacity, View } from "react-native";

export default function TestOutputScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<{
    latency?: string;
    percentChange?: string;
    minDiameter?: string;
    maxDiameter?: string;
    subjectId?: string;
    eye?: string;
    engine?: string;
  }>();

  const hasResults = params.latency !== undefined;

  const latency = params.latency ? parseFloat(params.latency) : null;
  const percentChange = params.percentChange ? parseFloat(params.percentChange) : null;
  const minDiameter = params.minDiameter ? parseFloat(params.minDiameter) : null;
  const maxDiameter = params.maxDiameter ? parseFloat(params.maxDiameter) : null;

  return (
    <View style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.title}>Pupil Analysis Results</Text>
        {params.subjectId ? (
          <Text style={styles.subtitle}>
            Subject: {params.subjectId} | Eye: {params.eye || 'N/A'} | Engine: {params.engine || 'python'}
          </Text>
        ) : null}
      </View>

      {/* Results */}
      <View style={styles.resultsCard}>
        <ResultRow
          label="Latency"
          value={latency !== null ? `${latency.toFixed(3)} s` : '--'}
        />
        <View style={styles.divider} />
        <ResultRow
          label="Percent Change"
          value={percentChange !== null ? `${percentChange.toFixed(2)}%` : '--'}
        />
        <View style={styles.divider} />
        <ResultRow
          label="Min Pupil Diameter"
          value={minDiameter !== null ? `${minDiameter.toFixed(2)} mm` : '--'}
        />
        <View style={styles.divider} />
        <ResultRow
          label="Max Pupil Diameter"
          value={maxDiameter !== null ? `${maxDiameter.toFixed(2)} mm` : '--'}
        />
      </View>

      {!hasResults && (
        <View style={styles.noResults}>
          <Text style={styles.noResultsText}>
            No results yet. Record an eye video to see analysis results here.
          </Text>
        </View>
      )}

      {/* Actions */}
      <View style={styles.actions}>
        <TouchableOpacity
          onPress={() => router.push('/')}
          style={styles.completeButton}
        >
          <Text style={styles.buttonText}>
            {hasResults ? 'Complete Test' : 'Back to Home'}
          </Text>
        </TouchableOpacity>

        {hasResults && (
          <TouchableOpacity
            onPress={() => router.push('/')}
            style={styles.newTestButton}
          >
            <Text style={styles.newTestButtonText}>New Test</Text>
          </TouchableOpacity>
        )}
      </View>
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

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  header: {
    paddingTop: 60,
    paddingHorizontal: 20,
    paddingBottom: 20,
    backgroundColor: '#564bf5',
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    color: 'white',
  },
  subtitle: {
    fontSize: 14,
    color: 'rgba(255,255,255,0.8)',
    marginTop: 4,
  },
  resultsCard: {
    margin: 20,
    backgroundColor: 'white',
    borderRadius: 12,
    padding: 20,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  resultRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 12,
  },
  resultLabel: {
    fontSize: 16,
    color: '#333',
  },
  resultValue: {
    fontSize: 18,
    fontWeight: '600',
    color: '#564bf5',
  },
  divider: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: '#e0e0e0',
  },
  noResults: {
    paddingHorizontal: 40,
    alignItems: 'center',
  },
  noResultsText: {
    fontSize: 16,
    color: '#999',
    textAlign: 'center',
  },
  actions: {
    alignItems: 'center',
    marginTop: 20,
  },
  completeButton: {
    backgroundColor: '#0b952b',
    padding: 14,
    borderRadius: 8,
    width: 220,
    alignItems: 'center',
  },
  buttonText: {
    color: 'white',
    fontSize: 18,
    fontWeight: '600',
  },
  newTestButton: {
    marginTop: 12,
    padding: 14,
    borderRadius: 8,
    width: 220,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#564bf5',
  },
  newTestButtonText: {
    color: '#564bf5',
    fontSize: 18,
    fontWeight: '600',
  },
});
