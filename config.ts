import Constants from "expo-constants";

function getApiUrl(): string {
  const hostUri = Constants.expoConfig?.hostUri;
  if (hostUri) {
    const ip = hostUri.split(":")[0];
    return `http://${ip}:8000`;
  }
  return "http://localhost:8000";
}

export const API_URL = getApiUrl();
