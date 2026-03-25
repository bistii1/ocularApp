import { CameraType, CameraView, useCameraPermissions } from 'expo-camera';
import { useRef, useState } from 'react';
import { Button, StyleSheet, Text, TouchableOpacity, View } from 'react-native';

export default function CameraScreen() {
  const [facing, setFacing] = useState<CameraType>('back');
  const [flash, setFlash] = useState<'off' | 'on' | 'auto'>('off');
  const [permission, requestPermission] = useCameraPermissions();
  const [isRecording, setIsRecording] = useState(false);
  const [torchOn, setTorchOn] = useState(false);
  const [countdown, setCountdown] = useState<number | null>(null);
  const [sequenceStatus, setSequenceStatus] = useState<string>('');
  const cameraRef = useRef<CameraView>(null);

  if (!permission) return <View />;

  if (!permission.granted) {
    return (
      <View style={styles.container}>
        <Text style={styles.message}>
          We need camera permission to continue.
        </Text>
        <Button onPress={requestPermission} title="Grant Permission" />
      </View>
    );
  }

  function toggleCameraFacing() {
    setFacing(current => (current === 'back' ? 'front' : 'back'));
  }

  function sleep(ms: number) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  function toggleFlash() {
    setFlash(current => {
      if (current === 'off') return 'on';
      if (current === 'on') return 'auto';
      return 'off';
    });
  }

  async function runSequence() {
    // Countdown: 2 seconds
    setCountdown(2);
    await sleep(1000);
    setCountdown(1);
    await sleep(1000);
    setCountdown(null);

    // Start recording
    setIsRecording(true);
    if (cameraRef.current) {
      cameraRef.current.recordAsync().then(video => {
        console.log('Video saved to:', video?.uri);
      });
    }

    // Step 1: Flash ON for 3 seconds
    setSequenceStatus('Flash 1');
    setTorchOn(true);
    await sleep(3000);

    // Step 2: Flash OFF for 3 seconds
    setSequenceStatus('Waiting...');
    setTorchOn(false);
    await sleep(3000);

    // Step 3: Flash ON for 0.25 seconds
    setSequenceStatus('Flash 2');
    setTorchOn(true);
    await sleep(250);

    // Step 4: Flash OFF
    setTorchOn(false);
    setSequenceStatus('Done');

    // Stop recording
    if (cameraRef.current) {
      cameraRef.current.stopRecording();
    }
    setIsRecording(false);
    setSequenceStatus('');
  }

  return (
    <View style={styles.container}>
      <CameraView
        style={styles.camera}
        facing={facing}
        flash={flash}
        ref={cameraRef}
        enableTorch={torchOn}
        mode="video"
      >
        {/* Countdown overlay */}
        {countdown !== null && (
          <View style={styles.countdownContainer}>
            <Text style={styles.countdownText}>{countdown}</Text>
          </View>
        )}

        {/* Recording indicator */}
        {isRecording && (
          <View style={styles.recordingIndicator}>
            <View style={styles.recordingDot} />
            <Text style={styles.recordingText}>REC</Text>
          </View>
        )}

        {/* Sequence status */}
        {sequenceStatus !== '' && (
          <View style={styles.statusContainer}>
            <Text style={styles.statusText}>{sequenceStatus}</Text>
          </View>
        )}

        <View style={styles.controls}>
          {/* Start button */}
          <TouchableOpacity
            style={[styles.captureButton, isRecording && styles.captureButtonRecording]}
            onPress={runSequence}
            disabled={isRecording || countdown !== null}
          >
            <View style={[styles.captureInner, isRecording && styles.captureInnerRecording]} />
          </TouchableOpacity>

          {/* Flip camera */}
          <TouchableOpacity style={styles.button} onPress={toggleCameraFacing}>
            <Text style={styles.text}>Flip</Text>
          </TouchableOpacity>

          {/* Placeholder to balance layout */}
          <View style={styles.button} />
        </View>
      </CameraView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, justifyContent: 'center' },
  message: { textAlign: 'center', paddingBottom: 10 },
  camera: { flex: 1 },
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
  text: { color: 'white', fontSize: 16 },
  captureButton: {
    width: 70,
    height: 70,
    borderRadius: 35,
    backgroundColor: 'white',
    justifyContent: 'center',
    alignItems: 'center',
  },
  captureButtonRecording: {
    backgroundColor: 'red',
  },
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
    position: 'absolute',
    top: 0, left: 0, right: 0, bottom: 0,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: 'rgba(0,0,0,0.5)',
  },
  countdownText: {
    fontSize: 120,
    fontWeight: 'bold',
    color: 'white',
  },
  recordingIndicator: {
    position: 'absolute',
    top: 40,
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
    top: 40,
    right: 20,
    backgroundColor: 'rgba(0,0,0,0.5)',
    padding: 8,
    borderRadius: 8,
  },
  statusText: { color: 'white', fontWeight: 'bold' },
});