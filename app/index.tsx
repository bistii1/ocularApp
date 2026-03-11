import React, { useState } from "react";
import { Button, StyleSheet, Switch, Text, TextInput, View } from "react-native";


export default function Index() {
  const [isEnabled, setIsEnabled] = useState(false);
  const toggleSwitch = () => setIsEnabled(previousState => !previousState);
  const leftEyeText = 'Left Eye';
  const rightEyeText = 'Right Eye';
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
    fontSize: 28,
  },
  separator: {
    marginVertical: 8,
    borderBottomColor: '#737373',
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
});


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
      <View style={styles.button}>
        <Button
          color='#564bf5'
          title="Start Test"
          onPress={() => console.log('Button pressed')}
        />
      </View>
   </View>

  );

}
