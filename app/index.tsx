import { useRouter } from "expo-router";
import { useState } from "react";
import {
  StyleSheet,
  Switch,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from "react-native";

export default function Index() {
  const [isEnabled, setIsEnabled] = useState(false);
  const [subjectId, setSubjectId] = useState("");
  const toggleSwitch = () => setIsEnabled((prev) => !prev);
  const router = useRouter();

  const eye = isEnabled ? "right" : "left";

  return (
    <View style={styles.container}>
      <View style={styles.centered}>
        <TextInput
          placeholder="Subject ID"
          value={subjectId}
          onChangeText={setSubjectId}
          style={styles.input}
        />
      </View>

      <View style={styles.row}>
        <Text
          style={[
            styles.eyeLabel,
            { color: isEnabled ? "#767577" : "#564bf5" },
          ]}
        >
          Left Eye
        </Text>
        <Switch
          ios_backgroundColor="#b0afb0"
          trackColor={{ false: "#b0afb0", true: "#b0afb0" }}
          thumbColor="#564bf5"
          onValueChange={toggleSwitch}
          value={isEnabled}
          style={{ marginHorizontal: 10, marginTop: 16 }}
        />
        <Text
          style={[
            styles.eyeLabel,
            { color: isEnabled ? "#564bf5" : "#767577" },
          ]}
        >
          Right Eye
        </Text>
      </View>

      <View style={styles.centered}>
        <TouchableOpacity
          onPress={() =>
            router.push({
              pathname: "/camera",
              params: { subjectId, eye },
            })
          }
          style={styles.primaryButton}
        >
          <Text style={styles.buttonText}>Open Camera</Text>
        </TouchableOpacity>
      </View>

      <View style={[styles.centered, { marginTop: 200 }]}>
        <TouchableOpacity
          onPress={() => router.push("/testOutput")}
          style={[styles.primaryButton, { opacity: 0.5 }]}
        >
          <Text style={styles.buttonText}>Demo Results</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  centered: {
    alignItems: "center",
    justifyContent: "center",
  },
  row: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
  },
  input: {
    height: 40,
    width: 200,
    borderWidth: 1,
    borderColor: "gray",
    borderRadius: 8,
    color: "black",
    fontSize: 20,
    margin: 10,
    padding: 10,
    marginTop: 70,
  },
  eyeLabel: {
    fontSize: 20,
  },
  primaryButton: {
    marginTop: 20,
    backgroundColor: "#564bf5",
    padding: 12,
    borderRadius: 8,
    width: 200,
    alignItems: "center",
  },
  buttonText: {
    color: "white",
    fontSize: 20,
  },
});
