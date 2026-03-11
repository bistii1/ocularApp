import { useRouter } from "expo-router";
import { useState } from "react";
import { StyleSheet, Switch, Text, TextInput, TouchableOpacity, View } from "react-native";

export default function Index() {
  const [isEnabled, setIsEnabled] = useState(false);
  const toggleSwitch = () => setIsEnabled(previousState => !previousState);
  const leftEyeText = 'Left Eye';
  const rightEyeText = 'Right Eye';
  const router = useRouter();

  return (
    <View>
      <View style={{ alignItems: 'center', justifyContent: 'center' }}>
        <TextInput
          placeholder="Subject ID"
          style={{
            height: 40,
            width: 200,
            borderWidth: 1,
            borderColor: 'gray',
            borderRadius: 8,
            color: 'black',
            fontSize: 20,
            margin: 10,
            padding: 10,
            marginTop: 70,
          }}
        />
      </View>

      <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'center' }}>
        <Text style={isEnabled ? { color: '#767577', fontSize: 20 } : { color: '#564bf5', fontSize: 20 }}>{leftEyeText}</Text>
        <Switch
            ios_backgroundColor="#b0afb0"
            trackColor={{false: '#b0afb0', true: '#b0afb0'}}
            thumbColor={isEnabled ? '#564bf5' : '#564bf5'}
            onValueChange={toggleSwitch}
            value={isEnabled}
            style={{marginHorizontal: 10, marginTop: 16}}
          />
        <Text style={isEnabled ? { color: '#564bf5', fontSize: 20 } : { color: '#767577', fontSize: 20 }}>{rightEyeText}</Text>
      </View>

      <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'center' }}>
        {/* Camera Button */}
        <TouchableOpacity
          onPress={() => router.push('/camera')}
          style={{
            marginTop: 20,
            backgroundColor: '#564bf5',
            padding: 12,
            borderRadius: 8,
            width: 200,
            alignItems: 'center',
          }}
        >
          <Text style={{ color: 'white', fontSize: 20 }}>Open Camera</Text>
        </TouchableOpacity>
      </View>

      <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'center', marginTop: 300 }}>
        {/* Temporary Button */}
        <TouchableOpacity
          onPress={() => router.push('/testOutput')}
          style={{
            marginTop: 20,
            backgroundColor: '#564bf5',
            padding: 12,
            borderRadius: 8,
            width: 200,
            alignItems: 'center',
          }}
        >
          <Text style={{ color: 'white', fontSize: 20 }}>Temporary</Text>
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