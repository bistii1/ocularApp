import { Text, TextInput, View } from "react-native";

export default function Index() {
  return (
      <View
        style={{
          flex: 1,
          justifyContent: "center",
          alignItems: "center",
        }}
      >
        <Text>Edit app/index.tsx to edit this screen.</Text>
      </View>
      <TextInput
        placeholder="User ID"
        style={{
          height: 40,
          width: 200,
          borderWidth: 1,
          borderColor: 'gray',
          margin: 10,
        }}
      />
   
  );
}
