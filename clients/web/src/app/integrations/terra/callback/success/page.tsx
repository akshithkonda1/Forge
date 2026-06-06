"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { motion } from "framer-motion";
import { Check } from "lucide-react";
import { forgeAPI } from "@/lib/forge-api";
import {
  clearConnectReturn,
  deviceName,
  providerForDevice,
  readConnectReturn,
} from "@/lib/device-connect";
import { useAppStore } from "@/stores/useAppStore";

export default function DeviceConnectSuccessPage() {
  const router = useRouter();
  const refreshProfile = useAppStore((s) => s.refreshProfileFromAPI);
  const setActiveTab = useAppStore((s) => s.setActiveTab);
  const [message, setMessage] = useState("Finishing device connection...");

  useEffect(() => {
    let cancelled = false;

    async function finalize() {
      const { returnPath, returnTab, deviceId } = readConnectReturn();
      const provider = deviceId ? providerForDevice(deviceId) : undefined;
      const label = deviceName(deviceId);

      try {
        await forgeAPI.getDeviceConnectionStatus();
        if (provider && provider !== "manual") {
          await forgeAPI.syncIntegration(provider);
        }
        await refreshProfile();
        if (!cancelled) {
          setMessage(
            label
              ? `${label} connected. Syncing your health data...`
              : "Device connected. Syncing your health data...",
          );
        }
      } catch {
        if (!cancelled) {
          setMessage(
            label
              ? `${label} linked. We'll sync your data shortly.`
              : "Device linked. We'll sync your data shortly.",
          );
        }
      }

      clearConnectReturn();

      window.setTimeout(() => {
        if (returnTab) {
          setActiveTab(returnTab);
        }
        router.replace(returnPath);
      }, 1400);
    }

    void finalize();

    return () => {
      cancelled = true;
    };
  }, [refreshProfile, router, setActiveTab]);

  return (
    <div className="flex min-h-[100dvh] flex-col items-center justify-center bg-background px-6 text-center">
      <motion.div
        initial={{ scale: 0.8, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        className="mb-6 flex h-20 w-20 items-center justify-center rounded-full bg-ember/15"
      >
        <Check size={36} className="text-ember" />
      </motion.div>
      <h1 className="mb-2 text-2xl font-bold text-text-primary">Connected</h1>
      <p className="max-w-sm text-text-tertiary">{message}</p>
    </div>
  );
}