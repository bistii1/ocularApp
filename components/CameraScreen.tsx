import { CameraType, CameraView, useCameraPermissions, useMicrophonePermissions } from 'expo-camera';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useRef, useState } from 'react';
import { ActivityIndicator, Button, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { analyzeVideo } from '../config';

export default function CameraScreen() {
  const [facing, setFacing] = useState<CameraType>('front');
  const [camPermission, requestCamPermission] = useCameraPermissions();
  const [micPermission, requestMicPermission] = useMicrophonePermissions();
  const [isRecording, setIsRecording] = useState(false);
  const [screenFlash, setScreenFlash] = useState(false);
  const [countdown, setCountdown] = useState<number | null>(null);
  const [sequenceStatus, setSequenceStatus] = useState('');
  const [isProcessing, setIsProcessing] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const cameraRef = useRef<CameraView>(null);
  const router = useRouter();
  const params = useLocalSearchParams<{ subjectId?: string; eye?: string }>();

  const isFront = facing === 'front';

  // Gate on both camera and microphone permissions
  if (!camPermission || !micPermission) return <View style={styles.container} />;

  if (!camPermission.granted || !micPermission.granted) {
    return (
      <View style={styles.permissionContainer}>
        <Text style={styles.message}>
          Camera and microphone permissions are required to record video.
        </Text>
        {!camPermission.granted && (
          <Button onPress={requestCamPermission} title="Grant Camera Permission" />
        )}
        {!micPermission.granted && (
          <View style={{ marginTop: 12 }}>
            <Button onPress={requestMicPermission} title="Grant Microphone Permission" />
          </View>
        )}
      </View>
    );
  }

  function toggleCameraFacing() {
    setFacing(current => (current === 'back' ? 'front' : 'back'));
  }

  function sleep(ms: number) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  async function runSequence() {
    setErrorMsg('');

    // Countdown
    setCountdown(2);
    await sleep(1000);
    setCountdown(1);
    await sleep(1000);
    setCountdown(null);

    // Start recording in parallel -- wrapped in try/catch so the flash
    // sequence always runs even if recording fails
    setIsRecording(true);
    let videoUri: string | undefined;
    let recordPromise: Promise<void> | null = null;

    try {
      if (cameraRef.current) {
        recordPromise = cameraRef.current
          .recordAsync()
          .then(video => {
            videoUri = video?.uri;
            console.log('Video saved to:', video?.uri);
          })
          .catch(err => {
            console.warn('recordAsync rejected:', err);
          });
      }
    } catch (err: any) {
      console.warn('recordAsync threw:', err);
    }

    // === Flash sequence (always runs) ===
    setSequenceStatus('Flash 1');
    setScreenFlash(true);
    await sleep(3000);

    setSequenceStatus('Waiting...');
    setScreenFlash(false);
    await sleep(3000);

    setSequenceStatus('Flash 2');
    setScreenFlash(true);
    await sleep(250);

    setScreenFlash(false);
    setSequenceStatus('Done');
    await sleep(1500);

    // Stop recording
    try {
      cameraRef.current?.stopRecording();
    } catch (err: any) {
      console.warn('stopRecording error:', err);
    }
    setIsRecording(false);
    setSequenceStatus('');

    // Wait for recording to finish saving
    if (recordPromise) {
      await recordPromise;
    }

    if (videoUri) {
      await processVideo(videoUri);
    } else {
      setErrorMsg('No video captured. Check camera/microphone permissions and try again.');
    }
  }

  async function processVideo(uri: string) {
    setIsProcessing(true);
    setSequenceStatus('Uploading & analyzing...');

    try {
      const result = await analyzeVideo(uri, params.subjectId, params.eye);
      router.replace({
        pathname: '/testOutput',
        params: {
          latency: String(result.latency_s),
          percentChange: String(result.percent_change),
          minDiameter: String(result.min_pupil_diameter_mm),
          maxDiameter: String(result.max_pupil_diameter_mm),
          subjectId: params.subjectId || '',
          eye: params.eye || '',
          engine: result.engine,
        },
      });
    } catch (error: any) {
      console.error('Analysis error:', error);
      setErrorMsg(`Analysis failed: ${error.message}`);
      setSequenceStatus('');
    } finally {
      setIsProcessing(false);
    }
  }

  return (
    <View style={styles.container}>
      {/* Camera -- no children allowed */}
      <CameraView
        style={styles.camera}
        facing={facing}
        ref={cameraRef}
        enableTorch={!isFront && screenFlash}
        mode="video"
      />

      {/* Screen flash stimulus (front camera only) */}
      {screenFlash && isFront && (
        <View style={styles.screenFlash} pointerEvents="none" />
      )}

      {/* Countdown */}
      {countdown !== null && (
        <View style={styles.countdownContainer} pointerEvents="none">
          <Text style={styles.countdownText}>{countdown}</Text>
        </View>
      )}

      {/* Recording indicator */}
      {isRecording && !screenFlash && (
        <View style={styles.recordingIndicator} pointerEvents="none">
          <View style={styles.recordingDot} />
          <Text style={styles.recordingText}>REC</Text>
        </View>
      )}

      {/* Processing overlay */}
      {isProcessing && (
        <View style={styles.processingOverlay}>
          <ActivityIndicator size="large" color="#564bf5" />
          <Text style={styles.processingText}>Analyzing pupil response...</Text>
        </View>
      )}

      {/* Sequence status */}
      {sequenceStatus !== '' && !isProcessing && !screenFlash && (
        <View style={styles.statusContainer} pointerEvents="none">
          <Text style={styles.statusText}>{sequenceStatus}</Text>
        </View>
      )}

      {/* Error banner */}
      {errorMsg !== '' && (
        <View style={styles.errorContainer}>
          <Text style={styles.errorText}>{errorMsg}</Text>
          <TouchableOpacity onPress={() => setErrorMsg('')}>
            <Text style={styles.errorDismiss}>Dismiss</Text>
          </TouchableOpacity>
        </View>
      )}

      {/* Controls */}
      <View style={styles.controls}>
        <TouchableOpacity
          style={[styles.captureButton, isRecording && styles.captureButtonRecording]}
          onPress={runSequence}
          disabled={isRecording || countdown !== null || isProcessing}
        >
          <View style={[styles.captureInner, isRecording && styles.captureInnerRecording]} />
        </TouchableOpacity>

        <TouchableOpacity
          style={styles.button}
          onPress={toggleCameraFacing}
          disabled={isRecording || isProcessing}
        >
          <Text style={styles.text}>{isFront ? '← Back' : 'Front →'}</Text>
        </TouchableOpacity>

        <View style={styles.button}>
          <Text style={styles.text}>{isFront ? 'Screen Flash' : 'LED Flash'}</Text>
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: 'black' },
  permissionContainer: { flex: 1, justifyContent: 'center', alignItems: 'center', padding: 20 },
  message: { textAlign: 'center', paddingBottom: 16, fontSize: 16 },
  camera: { ...StyleSheet.absoluteFillObject },
  screenFlash: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'white',
  },
  controls: {
    position: 'absolute',
    bottom: 40,
    width: '100%',
    flexDirection: 'row',
    justifyContent: 'space-around',
    alignItems: 'center',
    paddingHorizontal: 20,
  },
  button: {
    padding: 12,
    backgroundColor: 'rgba(0,0,0,0.5)',
    borderRadius: 8,
  },
  text: { color: 'white', fontSize: 14 },
  captureButton: {
    width: 70,
    height: 70,
    borderRadius: 35,
    backgroundColor: 'white',
    justifyContent: 'center',
    alignItems: 'center',
  },
  captureButtonRecording: { backgroundColor: 'red' },
  captureInner: {
    width: 60,
    height: 60,
    borderRadius: 30,
    backgroundColor: 'white',
    borderWidth: 2,
    borderColor: '#ccc',
  },
  captureInnerRecording: {
    borderRadius: 8,
    width: 30,
    height: 30,
    backgroundColor: 'white',
  },
  countdownContainer: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: 'rgba(0,0,0,0.5)',
  },
  countdownText: { fontSize: 120, fontWeight: 'bold', color: 'white' },
  recordingIndicator: {
    position: 'absolute',
    top: 60,
    left: 20,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(0,0,0,0.5)',
    padding: 8,
    borderRadius: 8,
  },
  recordingDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    backgroundColor: 'red',
    marginRight: 6,
  },
  recordingText: { color: 'white', fontWeight: 'bold' },
  statusContainer: {
    position: 'absolute',
    top: 60,
    right: 20,
    backgroundColor: 'rgba(0,0,0,0.5)',
    padding: 8,
    borderRadius: 8,
  },
  statusText: { color: 'white', fontWeight: 'bold' },
  processingOverlay: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: 'rgba(0,0,0,0.7)',
  },
  processingText: { color: 'white', fontSize: 18, marginTop: 16, fontWeight: 'bold' },
  errorContainer: {
    position: 'absolute',
    top: 100,
    left: 20,
    right: 20,
    backgroundColor: 'rgba(200,0,0,0.9)',
    padding: 16,
    borderRadius: 10,
    alignItems: 'center',
  },
  errorText: { color: 'white', fontSize: 14, textAlign: 'center', marginBottom: 8 },
  errorDismiss: { color: 'white', fontWeight: 'bold', fontSize: 16, textDecorationLine: 'underline' },
});
