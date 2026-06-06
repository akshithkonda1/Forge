import { Watch } from "lucide-react";
import type { WearableDeviceId } from "@/lib/device-connect";

export function DeviceIcon({
  deviceId,
  size = 28,
}: {
  deviceId: WearableDeviceId;
  size?: number;
}) {
  switch (deviceId) {
    case "apple-watch":
      return (
        <svg width={size} height={size} viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
          <rect x="6" y="2" width="16" height="24" rx="5" stroke="currentColor" strokeWidth="1.5" />
          <rect x="9" y="6" width="10" height="12" rx="2" stroke="currentColor" strokeWidth="1.2" />
          <path d="M10 2V0M18 2V0M10 26V28M18 26V28" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
        </svg>
      );
    case "garmin":
      return <Watch size={size} strokeWidth={1.5} />;
    case "oura-ring":
      return (
        <svg width={size} height={size} viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
          <circle cx="14" cy="14" r="10" stroke="currentColor" strokeWidth="1.5" />
          <circle cx="14" cy="14" r="6" stroke="currentColor" strokeWidth="1.2" />
        </svg>
      );
    case "fitbit":
      return (
        <svg width={size} height={size} viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
          <rect x="7" y="3" width="14" height="22" rx="4" stroke="currentColor" strokeWidth="1.5" />
          <rect x="10" y="7" width="8" height="10" rx="1.5" stroke="currentColor" strokeWidth="1.2" />
          <circle cx="14" cy="21" r="1.2" fill="currentColor" />
        </svg>
      );
    case "samsung-galaxy-watch":
      return (
        <svg width={size} height={size} viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
          <circle cx="14" cy="14" r="11" stroke="currentColor" strokeWidth="1.5" />
          <circle cx="14" cy="14" r="8" stroke="currentColor" strokeWidth="1" />
          <path d="M14 8V14L17 17" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round" />
          <path d="M10 3V1M18 3V1M10 25V27M18 25V27" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
        </svg>
      );
    case "whoop":
      return (
        <svg width={size} height={size} viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
          <rect x="4" y="8" width="20" height="12" rx="6" stroke="currentColor" strokeWidth="1.5" />
          <circle cx="10" cy="14" r="2" stroke="currentColor" strokeWidth="1.2" />
          <circle cx="18" cy="14" r="2" stroke="currentColor" strokeWidth="1.2" />
          <path d="M12 14H16" stroke="currentColor" strokeWidth="1.2" />
        </svg>
      );
    case "strava":
      return (
        <svg width={size} height={size} viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M6 20L14 6L18 14L22 10V20H6Z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
        </svg>
      );
    default:
      return <Watch size={size} strokeWidth={1.5} />;
  }
}