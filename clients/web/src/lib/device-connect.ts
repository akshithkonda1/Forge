import { forgeAPI, ForgeAPIError } from "@/lib/forge-api";
import type { IntegrationConnection } from "@/types";

export const RETURN_PATH_KEY = "forge:device:returnPath";
export const RETURN_TAB_KEY = "forge:device:returnTab";
export const DEVICE_INTENT_KEY = "forge:device:intent";
export const ONBOARDING_DRAFT_KEY = "forge:onboarding:draft";

export interface OnboardingDraft {
  step: number;
  profile: {
    name?: string;
    fitnessGoals?: string[];
    experienceLevel?: string;
    preferredWorkouts?: string[];
    coachingStyle?: string;
    connectedDevices?: string[];
    weeklySchedule?: number[];
  };
}

export type WearableDeviceId =
  | "apple-watch"
  | "garmin"
  | "oura-ring"
  | "fitbit"
  | "samsung-galaxy-watch"
  | "whoop"
  | "strava";

export const WEARABLE_DEVICES: Array<{
  id: WearableDeviceId;
  name: string;
  provider: string;
}> = [
  { id: "apple-watch", name: "Apple Watch", provider: "apple-health" },
  { id: "garmin", name: "Garmin", provider: "garmin" },
  { id: "oura-ring", name: "Oura Ring", provider: "oura" },
  { id: "fitbit", name: "Fitbit", provider: "manual" },
  { id: "samsung-galaxy-watch", name: "Samsung Galaxy Watch", provider: "manual" },
  { id: "whoop", name: "Whoop", provider: "whoop" },
  { id: "strava", name: "Strava", provider: "strava" },
];

export function widgetCallbackUrls(origin: string) {
  return {
    successRedirectUrl: `${origin}/integrations/terra/callback/success`,
    failureRedirectUrl: `${origin}/integrations/terra/callback/failure`,
  };
}

export function rememberConnectReturn(options: {
  returnPath: string;
  returnTab?: string;
  deviceId?: WearableDeviceId;
}) {
  if (typeof window === "undefined") return;
  sessionStorage.setItem(RETURN_PATH_KEY, options.returnPath);
  if (options.returnTab) {
    sessionStorage.setItem(RETURN_TAB_KEY, options.returnTab);
  } else {
    sessionStorage.removeItem(RETURN_TAB_KEY);
  }
  if (options.deviceId) {
    sessionStorage.setItem(DEVICE_INTENT_KEY, options.deviceId);
  } else {
    sessionStorage.removeItem(DEVICE_INTENT_KEY);
  }
}

export function readConnectReturn() {
  if (typeof window === "undefined") {
    return { returnPath: "/", returnTab: undefined, deviceId: undefined };
  }
  const deviceId = sessionStorage.getItem(DEVICE_INTENT_KEY) as WearableDeviceId | null;
  return {
    returnPath: sessionStorage.getItem(RETURN_PATH_KEY) ?? "/",
    returnTab: sessionStorage.getItem(RETURN_TAB_KEY) ?? undefined,
    deviceId: deviceId ?? undefined,
  };
}

export function clearConnectReturn() {
  if (typeof window === "undefined") return;
  sessionStorage.removeItem(RETURN_PATH_KEY);
  sessionStorage.removeItem(RETURN_TAB_KEY);
  sessionStorage.removeItem(DEVICE_INTENT_KEY);
}

export function saveOnboardingDraft(draft: OnboardingDraft) {
  if (typeof window === "undefined") return;
  sessionStorage.setItem(ONBOARDING_DRAFT_KEY, JSON.stringify(draft));
}

export function readOnboardingDraft(): OnboardingDraft | null {
  if (typeof window === "undefined") return null;
  const raw = sessionStorage.getItem(ONBOARDING_DRAFT_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as OnboardingDraft;
  } catch {
    return null;
  }
}

export function clearOnboardingDraft() {
  if (typeof window === "undefined") return;
  sessionStorage.removeItem(ONBOARDING_DRAFT_KEY);
}

export function deviceById(deviceId: WearableDeviceId) {
  return WEARABLE_DEVICES.find((device) => device.id === deviceId);
}

export function providerForDevice(deviceId: WearableDeviceId): string | undefined {
  return deviceById(deviceId)?.provider;
}

export function deviceName(deviceId: WearableDeviceId | undefined): string | undefined {
  if (!deviceId) return undefined;
  return deviceById(deviceId)?.name;
}

export function connectionForDevice(
  deviceId: WearableDeviceId,
  connections: IntegrationConnection[],
): IntegrationConnection | undefined {
  const device = deviceById(deviceId);
  if (!device) return undefined;

  return connections.find((connection) => {
    if (connection.displayName.toLowerCase() === device.name.toLowerCase()) {
      return true;
    }
    if (device.provider !== "manual" && connection.provider === device.provider) {
      return true;
    }
    return false;
  });
}

export function isDeviceConnected(
  deviceId: WearableDeviceId,
  connections: IntegrationConnection[],
): boolean {
  const connection = connectionForDevice(deviceId, connections);
  return connection?.status === "connected" || connection?.status === "syncing";
}

export async function startDeviceConnect(options?: {
  returnPath?: string;
  returnTab?: string;
  deviceId?: WearableDeviceId;
}) {
  const origin = window.location.origin;
  rememberConnectReturn({
    returnPath: options?.returnPath ?? window.location.pathname,
    returnTab: options?.returnTab,
    deviceId: options?.deviceId,
  });

  const session = await forgeAPI.createWearableWidgetSession({
    ...widgetCallbackUrls(origin),
    language: "en",
  });

  if (!session.url) {
    throw new ForgeAPIError("Device connection session did not return a URL.", 502);
  }

  window.location.assign(session.url);
}