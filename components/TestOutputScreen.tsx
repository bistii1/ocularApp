import { useRouter, useLocalSearchParams } from "expo-router";
import { ScrollView, StyleSheet, Text, TouchableOpacity, View } from "react-native";

export default function TestOutputScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<{
    latency?: string;
    percentChange?: string;
    constrictionPct?: string;
    baselineDiameter?: string;
    minDiameter?: string;
    maxDiameter?: string;
    message?: string;
    eyeDetected?: string;
    validFrames?: string;
    totalFrames?: string;
  }>();

  const latency = params.latency ? parseFloat(params.latency) : null;
  const percentChange = params.percentChange
    ? parseFloat(params.percentChange)
    : null;
  const constrictionPct = params.constrictionPct
    ? parseFloat(params.constrictionPct)
    : null;
  const baselineDiameter = params.baselineDiameter
    ? parseFloat(params.baselineDiameter)
    : null;
  const minDiameter = params.minDiameter
    ? parseFloat(params.minDiameter)
    : null;
  const maxDiameter = params.maxDiameter
    ? parseFloat(params.maxDiameter)
    : null;
  const message = params.message || "";
  const eyeDetected = params.eyeDetected === "true";
  const validFrames = params.validFrames ? parseInt(params.validFrames, 10) : null;
  const totalFrames = params.totalFrames ? parseInt(params.totalFrames, 10) : null;
  const hasResults = latency !== null;

  const detectionRate =
    validFrames != null && totalFrames != null && totalFrames > 0
      ? Math.round((validFrames / totalFrames) * 100)
      : null;

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text style={styles.title}>PLR Test Results</Text>

      {message ? (
        <View style={styles.messageBanner}>
          <Text style={styles.messageText}>{message}</Text>
        </View>
      ) : null}

      {!eyeDetected && hasResults ? (
        <View style={[styles.messageBanner, styles.warningBanner]}>
          <Text style={styles.messageText}>
            Eye not auto-detected — used center-region fallback
          </Text>
        </View>
      ) : null}

      {/* Primary PLR Metrics */}
      <Text style={styles.sectionTitle}>Pupillary Light Reflex</Text>
      <View style={styles.metricsContainer}>
        <MetricRow
          label="Constriction"
          value={hasResults && constrictionPct != null ? `${constrictionPct}%` : "—"}
          highlight
        />
        <MetricRow
          label="Latency"
          value={hasResults ? `${latency} ms` : "—"}
          highlight
        />
        <MetricRow
          label="Baseline Diameter"
          value={hasResults && baselineDiameter != null ? `${baselineDiameter} px` : "—"}
        />
      </View>

      {/* Diameter Range */}
      <Text style={styles.sectionTitle}>Diameter Range</Text>
      <View style={styles.metricsContainer}>
        <MetricRow
          label="Min (5th pctl)"
          value={hasResults ? `${minDiameter} px` : "—"}
        />
        <MetricRow
          label="Max (95th pctl)"
          value={hasResults ? `${maxDiameter} px` : "—"}
        />
        <MetricRow
          label="Overall Change"
          value={hasResults ? `${percentChange}%` : "—"}
        />
      </View>

      {/* Detection Quality */}
      <Text style={styles.sectionTitle}>Detection Quality</Text>
      <View style={styles.metricsContainer}>
        <MetricRow
          label="Valid Frames"
          value={
            validFrames != null && totalFrames != null
              ? `${validFrames} / ${totalFrames}`
              : "—"
          }
        />
        <MetricRow
          label="Detection Rate"
          value={detectionRate != null ? `${detectionRate}%` : "—"}
        />
      </View>

      <View style={styles.buttonContainer}>
        <TouchableOpacity
          onPress={() => router.push("/")}
          style={styles.completeButton}
        >
          <Text style={styles.completeButtonText}>Done</Text>
        </TouchableOpacity>
        <TouchableOpacity
          onPress={() => router.push("/camera")}
          style={styles.retestButton}
        >
          <Text style={styles.retestButtonText}>Run Again</Text>
        </TouchableOpacity>
      </View>
    </ScrollView>
  );
}

function MetricRow({
  label,
  value,
  highlight = false,
}: {
  label: string;
  value: string;
  highlight?: boolean;
}) {
  return (
    <View style={styles.metricRow}>
      <Text style={styles.metricLabel}>{label}</Text>
      <Text
        style={[styles.metricValue, highlight && styles.metricValueHighlight]}
      >
        {value}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#f8f9fa",
  },
  content: {
    paddingTop: 60,
    paddingBottom: 40,
  },
  title: {
    fontSize: 24,
    fontWeight: "bold",
    textAlign: "center",
    marginBottom: 16,
    color: "#1a1a1a",
  },
  sectionTitle: {
    fontSize: 14,
    fontWeight: "600",
    color: "#888",
    textTransform: "uppercase",
    letterSpacing: 0.5,
    marginTop: 20,
    marginBottom: 8,
    marginHorizontal: 20,
  },
  messageBanner: {
    marginHorizontal: 16,
    marginBottom: 12,
    padding: 12,
    borderRadius: 8,
    backgroundColor: "#e8f5e9",
  },
  warningBanner: {
    backgroundColor: "#fff3e0",
  },
  messageText: {
    fontSize: 14,
    color: "#333",
    textAlign: "center",
  },
  metricsContainer: {
    marginHorizontal: 16,
    backgroundColor: "white",
    borderRadius: 12,
    padding: 16,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
  },
  metricRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    paddingVertical: 14,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: "#e0e0e0",
  },
  metricLabel: {
    fontSize: 16,
    color: "#555",
  },
  metricValue: {
    fontSize: 18,
    fontWeight: "600",
    color: "#1a1a1a",
  },
  metricValueHighlight: {
    color: "#564bf5",
    fontSize: 20,
  },
  buttonContainer: {
    flexDirection: "row",
    justifyContent: "center",
    gap: 16,
    marginTop: 32,
    paddingHorizontal: 16,
  },
  completeButton: {
    backgroundColor: "#0b952b",
    padding: 14,
    borderRadius: 8,
    flex: 1,
    alignItems: "center",
  },
  completeButtonText: {
    color: "white",
    fontSize: 18,
    fontWeight: "600",
  },
  retestButton: {
    backgroundColor: "#564bf5",
    padding: 14,
    borderRadius: 8,
    flex: 1,
    alignItems: "center",
  },
  retestButtonText: {
    color: "white",
    fontSize: 18,
    fontWeight: "600",
  },
});
