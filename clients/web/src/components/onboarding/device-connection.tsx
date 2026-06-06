"use client";

import { useEffect } from "react";
import { motion } from "framer-motion";
import { cn } from "@/lib/utils";
import { useAppStore } from "@/stores/useAppStore";
import { useDeviceConnections } from "@/hooks/useDeviceConnections";
import {
  saveOnboardingDraft,
  WEARABLE_DEVICES,
  type WearableDeviceId,
} from "@/lib/device-connect";
import { DeviceGrid } from "@/components/integrations/device-grid";

interface DeviceConnectionProps {
  onNext: () => void;
}

export default function DeviceConnection({ onNext }: DeviceConnectionProps) {
  const connections = useAppStore((s) => s.connections);
  const userProfile = useAppStore((s) => s.userProfile);
  const onboardingStep = useAppStore((s) => s.onboardingStep);
  const updateProfile = useAppStore((s) => s.updateProfile);
  const refreshProfileFromAPI = useAppStore((s) => s.refreshProfileFromAPI);
  const {
    status,
    loadingStatus,
    connectingDevice,
    error,
    isDeviceConnected,
    connectDevice,
  } = useDeviceConnections(connections, { refreshProfile: refreshProfileFromAPI });

  useEffect(() => {
    void refreshProfileFromAPI();
  }, [refreshProfileFromAPI]);

  const handleConnect = (deviceId: WearableDeviceId) => {
    saveOnboardingDraft({
      step: onboardingStep,
      profile: userProfile,
    });
    void connectDevice({
      deviceId,
      returnPath: "/onboarding",
    });
  };

  const handleContinue = () => {
    const connected = WEARABLE_DEVICES.filter((device) => isDeviceConnected(device.id)).map(
      (device) => device.name,
    );
    if (connected.length > 0) {
      updateProfile({ connectedDevices: connected });
    }
    onNext();
  };

  const connectedCount = WEARABLE_DEVICES.filter((device) =>
    isDeviceConnected(device.id),
  ).length;

  return (
    <div className="flex min-h-[100dvh] flex-col px-6 pb-8 pt-12">
      <motion.div
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="mb-8"
      >
        <h2 className="mb-2 text-3xl font-bold text-text-primary">Connect Your Devices</h2>
        <p className="text-text-tertiary">
          Link your wearables to personalize every workout with real health data
        </p>
        {connectedCount > 0 && (
          <p className="mt-3 text-sm text-ember">
            {connectedCount} device{connectedCount === 1 ? "" : "s"} connected
          </p>
        )}
      </motion.div>

      {!loadingStatus && status && !status.configured && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          className="mb-4 rounded-xl border border-border bg-surface px-4 py-3 text-sm text-text-tertiary"
        >
          Device connections are not configured on this backend yet. You can skip for now and
          connect later in Settings.
        </motion.div>
      )}

      {error && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          className="mb-4 rounded-xl border border-danger/30 bg-danger/10 px-4 py-3 text-sm text-danger"
        >
          {error}
        </motion.div>
      )}

      <div className="flex-1">
        <DeviceGrid
          isDeviceConnected={isDeviceConnected}
          connectingDevice={connectingDevice}
          onConnect={handleConnect}
        />
      </div>

      <motion.p
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 0.5 }}
        className="mb-4 text-center text-sm text-text-muted"
      >
        You can connect devices later in Settings
      </motion.p>

      <motion.button
        onClick={handleContinue}
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.4 }}
        className={cn(
          "w-full rounded-xl px-8 py-4 text-lg font-semibold text-white",
          "transition-all duration-300",
          "focus:outline-none focus-visible:ring-2 focus-visible:ring-ember focus-visible:ring-offset-2 focus-visible:ring-offset-background",
        )}
        style={{
          background: "linear-gradient(135deg, #FF4D00, #FF6B2B)",
        }}
        whileHover={{ scale: 1.02, boxShadow: "0 0 30px rgba(255,77,0,0.4)" }}
        whileTap={{ scale: 0.98 }}
      >
        {connectedCount > 0 ? "Continue" : "Skip for now"}
      </motion.button>
    </div>
  );
}