import {
  CameraType,
  CameraView,
  useCameraPermissions,
  useMicrophonePermissions,
} from "expo-camera";
import { useRouter, useLocalSearchParams } from "expo-router";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  Button,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from "react-native";
import { API_URL } from "@/config";

const BASELINE_S = 1;
const FLASH_S = 1;
const RECOVERY_S = 3;
const TOTAL_S = BASELINE_S + FLASH_S + RECOVERY_S;
const COUNTDOWN_S = 3;

type PLRPhase =
  | "idle"
  | "countdown"
  | "baseline"
  | "flash"
  | "recovery"
  | "uploading";

function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}

export default function CameraScreen() {
  const [facing, setFacing] = useState<CameraType>("front");
  const [cameraPermission, requestCameraPermission] = useCameraPermissions();
  const [micPermission, requestMicPermission] = useMicrophonePermissions();
  const [phase, setPhase] = useState<PLRPhase>("idle");
  const [countdown, setCountdown] = useState(COUNTDOWN_S);
  const [phaseTimer, setPhaseTimer] = useState(0);
  const cameraRef = useRef<CameraView>(null);
  const router = useRouter();
  const { subjectId, eye } = useLocalSearchParams<{
    subjectId: string;
    eye: string;
  }>();

  const isRunning = phase !== "idle" && phase !== "uploading";

  if (!cameraPermission || !micPermission) return <View />;

  if (!cameraPermission.granted || !micPermission.granted) {
    return (
      <View style={styles.container}>
        <Text style={styles.message}>
          Camera and microphone permissions are needed for the PLR test.
        </Text>
        <Button
          onPress={async () => {
            await requestCameraPermission();
            await requestMicPermission();
          }}
          title="Grant Permissions"
        />
      </View>
    );
  }

  async function runPLRTest() {
    if (!cameraRef.current) return;

    try {
      // --- Countdown ---
      setPhase("countdown");
      for (let i = COUNTDOWN_S; i >= 1; i--) {
        setCountdown(i);
        await sleep(1000);
      }

      // --- Start recording + run timed phases ---
      setPhase("baseline");
      setPhaseTimer(BASELINE_S);
      const recordPromise = cameraRef.current.recordAsync({
        maxDuration: TOTAL_S,
      });

      // 1 s baseline
      for (let t = BASELINE_S; t > 0; t--) {
        setPhaseTimer(t);
        await sleep(1000);
      }

      // 1 s flash stimulus
      setPhase("flash");
      for (let t = FLASH_S; t > 0; t--) {
        setPhaseTimer(t);
        await sleep(1000);
      }

      // 3 s recovery
      setPhase("recovery");
      for (let t = RECOVERY_S; t > 0; t--) {
        setPhaseTimer(t);
        await sleep(1000);
      }

      // Recording auto-stops via maxDuration; stopRecording is a safety net
      cameraRef.current?.stopRecording();

      const video = await recordPromise;
      if (video?.uri) {
        await analyzeVideo(video.uri);
      } else {
        setPhase("idle");
      }
    } catch (error) {
      console.error("PLR test failed:", error);
      Alert.alert("Error", "PLR test failed. Please try again.");
      setPhase("idle");
    }
  }

  async function analyzeVideo(uri: string) {
    setPhase("uploading");
    try {
      const formData = new FormData();
      formData.append("file", {
        uri,
        type: "video/mp4",
        name: "plr_recording.mp4",
      } as unknown as Blob);
      formData.append("subject_id", subjectId || "");
      formData.append("eye", eye || "left");
      formData.append("flash_onset_s", String(BASELINE_S));
      formData.append("flash_duration_s", String(FLASH_S));

      const response = await fetch(`${API_URL}/analyze`, {
        method: "POST",
        body: formData,
      });

      if (!response.ok) {
        throw new Error(`Server returned ${response.status}`);
      }

      const results = await response.json();

      router.replace({
        pathname: "/testOutput",
        params: {
          latency: String(results.latency_ms ?? 0),
          percentChange: String(results.percent_change ?? 0),
          constrictionPct: String(results.constriction_pct ?? 0),
          baselineDiameter: String(results.baseline_diameter_px ?? 0),
          minDiameter: String(results.min_diameter_px ?? 0),
          maxDiameter: String(results.max_diameter_px ?? 0),
          message: results.message ?? "",
          eyeDetected: String(results.eye_detected ?? false),
          validFrames: String(results.valid_frames ?? 0),
          totalFrames: String(results.total_frames ?? 0),
        },
      });
    } catch (error) {
      console.error("Analysis failed:", error);
      Alert.alert(
        "Connection Error",
        `Could not reach the server at ${API_URL}.\nMake sure the backend is running.`
      );
      setPhase("idle");
    }
  }

  // --- Uploading screen ---
  if (phase === "uploading") {
    return (
      <View style={[styles.container, styles.centerContent]}>
        <ActivityIndicator size="large" color="#564bf5" />
        <Text style={styles.uploadingTitle}>Analyzing pupil response...</Text>
        <Text style={styles.uploadingSub}>This may take a moment</Text>
      </View>
    );
  }

  // --- Overlay colour per phase ---
  const overlayStyle =
    phase === "flash"
      ? styles.overlayFlash
      : phase === "baseline" || phase === "recovery"
        ? styles.overlayDark
        : undefined;

  const phaseLabel =
    phase === "countdown"
      ? ""
      : phase === "baseline"
        ? "BASELINE"
        : phase === "flash"
          ? "STIMULUS"
          : phase === "recovery"
            ? "RECOVERY"
            : "";

  return (
    <View style={styles.container}>
      <CameraView
        style={styles.camera}
        facing={facing}
        mode="video"
        ref={cameraRef}
      >
        {/* Phase overlay — dark for baseline/recovery, bright white for flash */}
        {overlayStyle && <View style={[styles.overlayBase, overlayStyle]} />}

        {/* Countdown */}
        {phase === "countdown" && (
          <View style={[styles.overlayBase, styles.overlayCountdown]}>
            <Text style={styles.countdownNumber}>{countdown}</Text>
            <Text style={styles.countdownLabel}>
              Position eye in frame
            </Text>
          </View>
        )}

        {/* Phase indicator badge */}
        {isRunning && phase !== "countdown" && (
          <View style={styles.phaseBadge}>
            <View
              style={[
                styles.phaseDot,
                { backgroundColor: phase === "flash" ? "#ffcc00" : "#ff3b30" },
              ]}
            />
            <Text style={styles.phaseText}>
              {phaseLabel} {phaseTimer}s
            </Text>
          </View>
        )}

        {/* Controls — only visible when idle */}
        {phase === "idle" && (
          <View style={styles.controls}>
            <TouchableOpacity
              style={styles.button}
              onPress={() =>
                setFacing((f) => (f === "back" ? "front" : "back"))
              }
            >
              <Text style={styles.text}>Flip</Text>
            </TouchableOpacity>

            <TouchableOpacity style={styles.startButton} onPress={runPLRTest}>
              <Text style={styles.startButtonText}>Run PLR Test</Text>
            </TouchableOpacity>

            <View style={styles.button}>
              <Text style={styles.text}>
                {TOTAL_S}s test
              </Text>
            </View>
          </View>
        )}
      </CameraView>

      {/* Protocol description shown at top when idle */}
      {phase === "idle" && (
        <View style={styles.protocolBanner}>
          <Text style={styles.protocolText}>
            Pupillary Light Reflex Test
          </Text>
          <Text style={styles.protocolSub}>
            {BASELINE_S}s baseline → {FLASH_S}s flash stimulus → {RECOVERY_S}s
            recovery
          </Text>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, justifyContent: "center" },
  centerContent: {
    alignItems: "center",
    backgroundColor: "#f5f5f5",
  },
  message: { textAlign: "center", paddingBottom: 10, paddingHorizontal: 20 },
  camera: { flex: 1 },

  overlayBase: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: "center",
    alignItems: "center",
  },
  overlayDark: {
    backgroundColor: "rgba(0,0,0,0.15)",
  },
  overlayFlash: {
    backgroundColor: "rgba(255,255,255,0.85)",
  },
  overlayCountdown: {
    backgroundColor: "rgba(0,0,0,0.6)",
  },

  countdownNumber: {
    fontSize: 96,
    fontWeight: "bold",
    color: "white",
  },
  countdownLabel: {
    fontSize: 20,
    color: "rgba(255,255,255,0.8)",
    marginTop: 12,
  },

  phaseBadge: {
    position: "absolute",
    top: 60,
    alignSelf: "center",
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: "rgba(0,0,0,0.7)",
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 20,
  },
  phaseDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    marginRight: 8,
  },
  phaseText: {
    color: "white",
    fontSize: 16,
    fontWeight: "bold",
    letterSpacing: 1,
  },

  controls: {
    position: "absolute",
    bottom: 40,
    width: "100%",
    flexDirection: "row",
    justifyContent: "space-around",
    alignItems: "center",
    paddingHorizontal: 20,
  },
  button: {
    padding: 12,
    backgroundColor: "rgba(0,0,0,0.5)",
    borderRadius: 8,
  },
  text: { color: "white", fontSize: 16, textAlign: "center" },

  startButton: {
    paddingVertical: 16,
    paddingHorizontal: 28,
    backgroundColor: "#564bf5",
    borderRadius: 40,
  },
  startButtonText: {
    color: "white",
    fontSize: 18,
    fontWeight: "bold",
  },

  protocolBanner: {
    position: "absolute",
    top: 50,
    left: 0,
    right: 0,
    alignItems: "center",
    paddingVertical: 10,
    backgroundColor: "rgba(0,0,0,0.55)",
  },
  protocolText: {
    color: "white",
    fontSize: 18,
    fontWeight: "bold",
  },
  protocolSub: {
    color: "rgba(255,255,255,0.8)",
    fontSize: 13,
    marginTop: 4,
  },

  uploadingTitle: {
    marginTop: 20,
    fontSize: 18,
    color: "#333",
    fontWeight: "600",
  },
  uploadingSub: {
    marginTop: 8,
    fontSize: 14,
    color: "#888",
  },
});
