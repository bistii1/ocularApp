import { useRouter } from "expo-router";
import { useState } from "react";
import { Switch, Text, TextInput, TouchableOpacity, View } from "react-native";


export default function Index() {
  const [isEnabled, setIsEnabled] = useState(false);
  const toggleSwitch = () => setIsEnabled(previousState => !previousState);
  const leftEyeText = 'Left Eye';
  const rightEyeText = 'Right Eye';
  const router = useRouter();

  return (
    <View>
      <TextInput
        placeholder="User ID"
        style={{
          height: 40,
          width: 200,
          borderWidth: 1,
          borderColor: 'gray',
          margin: 10,
          padding: 10,
        }}
      />
      <Text style={isEnabled ? { color: '#767577' } : { color: 'black' }}>{leftEyeText}</Text>
      <Switch
          ios_backgroundColor="#b0afb0"
          trackColor={{false: '#b0afb0', true: '#b0afb0'}}
          thumbColor={isEnabled ? '#564bf5' : '#564bf5'}
          onValueChange={toggleSwitch}
          value={isEnabled}
        />
      <Text style={isEnabled ? { color: 'black' } : { color: '#767577' }}>{rightEyeText}</Text>

      {/* Camera Button */}
      <TouchableOpacity
        onPress={() => router.push('/camera')}
        style={{
          marginTop: 20,
          marginLeft: 10,
          backgroundColor: '#564bf5',
          padding: 12,
          borderRadius: 8,
          width: 200,
          alignItems: 'center',
        }}
      >
        <Text style={{ color: 'white', fontSize: 16 }}>Open Camera</Text>
      </TouchableOpacity>
   </View>
   
  );
}
