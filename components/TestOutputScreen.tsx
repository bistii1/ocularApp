import { useRouter } from "expo-router";
import { Image, StyleSheet, Text, TouchableOpacity, View } from "react-native";

export default function TestOutputScreen() {
  const latency = 'Latency:';
  const percentChange = 'Percent Change:';
  const minDiameter = 'Minimum Pupil Diameter:';
  const maxDiameter = 'Maximum Pupil Diameter:';
  const router = useRouter();

  return (
    <View>
      <View style={{ alignItems: 'center', justifyContent: 'center' }}>
        <Image
          source={require('../assets/images/react-logo.png')}
          style={{ width: 300, height: 300, marginTop: 50 }}
        />
      </View>

      <View style={{ marginTop: 20, marginLeft: 16 }}>
        <Text style={{ fontSize: 20, marginBottom: 10 }}>{latency}</Text>
        <Text style={{ fontSize: 20, marginBottom: 10 }}>{percentChange}</Text>
        <Text style={{ fontSize: 20, marginBottom: 10 }}>{minDiameter}</Text>
        <Text style={{ fontSize: 20, marginBottom: 10 }}>{maxDiameter}</Text>
      </View>

      <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'center' }}>
        {/* Complete Test Button */}
        <TouchableOpacity
          onPress={() => router.push('/')}
          style={{
            marginTop: 20,
            backgroundColor: '#0b952b',
            padding: 12,
            borderRadius: 8,
            width: 200,
            alignItems: 'center',
          }}
        >
          <Text style={{ color: 'white', fontSize: 20 }}>Complete Test</Text>
        </TouchableOpacity>
      </View>

    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    marginHorizontal: 16,
  },
  title: {
    textAlign: 'center',
    marginVertical: 8,
  },
  button: {
    justifyContent: 'center',
    marginTop: 16,
  },
  separator: {
    marginVertical: 8,
    borderBottomColor: '#737373',
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
});