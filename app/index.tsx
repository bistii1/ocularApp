import { useState } from "react";
import { Switch, Text, TextInput, View } from "react-native";


export default function Index() {
  const [isEnabled, setIsEnabled] = useState(false);
  const toggleSwitch = () => setIsEnabled(previousState => !previousState);
  const leftEyeText = 'Left Eye';
  const rightEyeText = 'Right Eye';

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
   </View>
   
  );
}
