"use client";

import { useState } from "react";
import { motion } from "framer-motion";
import { Watch, Check } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAppStore } from "@/stores/useAppStore";

interface DeviceConnectionProps {
  onNext: () => void;
}

interface Device {
  id: string;
  name: string;
  icon: React.ReactNode;
}

const devices: Device[] = [
  {
    id: "apple-watch",
    name: "Apple Watch",
    icon: (
      <svg width="28" height="28" viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
        <rect x="6" y="2" width="16" height="24" rx="5" stroke="currentColor" strokeWidth="1.5" />
        <rect x="9" y="6" width="10" height="12" rx="2" stroke="currentColor" strokeWidth="1.2" />
        <path d="M10 2V0M18 2V0M10 26V28M18 26V28" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      </svg>
    ),
  },
  {
    id: "garmin",
    name: "Garmin",
    icon: <Watch size={28} strokeWidth={1.5} />,
  },
  {
    id: "oura-ring",
    name: "Oura Ring",
    icon: (
      <svg width="28" height="28" viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
        <circle cx="14" cy="14" r="10" stroke="currentColor" strokeWidth="1.5" />
        <circle cx="14" cy="14" r="6" stroke="currentColor" strokeWidth="1.2" />
      </svg>
    ),
  },
  {
    id: "fitbit",
    name: "Fitbit",
    icon: (
      <svg width="28" height="28" viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
        <rect x="7" y="3" width="14" height="22" rx="4" stroke="currentColor" strokeWidth="1.5" />
        <rect x="10" y="7" width="8" height="10" rx="1.5" stroke="currentColor" strokeWidth="1.2" />
        <circle cx="14" cy="21" r="1.2" fill="currentColor" />
      </svg>
    ),
  },
  {
    id: "samsung-galaxy-watch",
    name: "Samsung Galaxy Watch",
    icon: (
      <svg width="28" height="28" viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
        <circle cx="14" cy="14" r="11" stroke="currentColor" strokeWidth="1.5" />
        <circle cx="14" cy="14" r="8" stroke="currentColor" strokeWidth="1" />
        <path d="M14 8V14L17 17" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round" />
        <path d="M10 3V1M18 3V1M10 25V27M18 25V27" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      </svg>
    ),
  },
  {
    id: "whoop",
    name: "Whoop",
    icon: (
      <svg width="28" height="28" viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
        <rect x="4" y="8" width="20" height="12" rx="6" stroke="currentColor" strokeWidth="1.5" />
        <circle cx="10" cy="14" r="2" stroke="currentColor" strokeWidth="1.2" />
        <circle cx="18" cy="14" r="2" stroke="currentColor" strokeWidth="1.2" />
        <path d="M12 14H16" stroke="currentColor" strokeWidth="1.2" />
      </svg>
    ),
  },
];

const containerVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.08,
      delayChildren: 0.2,
    },
  },
};

const cardVariants = {
  hidden: { opacity: 0, y: 16 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.4, ease: [0.25, 0.46, 0.45, 0.94] as const },
  },
};

export default function DeviceConnection({ onNext }: DeviceConnectionProps) {
  const updateProfile = useAppStore((s) => s.updateProfile);
  const [connectedDevices, setConnectedDevices] = useState<Set<string>>(
    new Set()
  );

  const toggleDevice = (deviceId: string) => {
    setConnectedDevices((prev) => {
      const next = new Set(prev);
      if (next.has(deviceId)) {
        next.delete(deviceId);
      } else {
        next.add(deviceId);
      }
      return next;
    });
  };

  const handleContinue = () => {
    const connected = devices
      .filter((d) => connectedDevices.has(d.id))
      .map((d) => d.name);
    if (connected.length > 0) {
      updateProfile({ connectedDevices: connected });
    }
    onNext();
  };

  return (
    <div className="flex min-h-screen flex-col px-6 pb-8 pt-12">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="mb-10"
      >
        <h2 className="mb-2 text-3xl font-bold text-text-primary">
          Connect Your Devices
        </h2>
        <p className="text-text-tertiary">
          Forge uses your wearable data to personalize every workout
        </p>
      </motion.div>

      {/* Device grid */}
      <motion.div
        className="grid flex-1 grid-cols-2 gap-3 content-start"
        variants={containerVariants}
        initial="hidden"
        animate="visible"
      >
        {devices.map((device) => {
          const isConnected = connectedDevices.has(device.id);
          return (
            <motion.button
              key={device.id}
              variants={cardVariants}
              onClick={() => toggleDevice(device.id)}
              className={cn(
                "relative flex flex-col items-center justify-center gap-3 rounded-xl border p-5",
                "transition-all duration-200",
                isConnected
                  ? "border-ember bg-ember/10 shadow-[0_0_20px_rgba(255,77,0,0.1)]"
                  : "border-border bg-surface hover:border-border-light"
              )}
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.97 }}
            >
              {/* Checkmark badge */}
              {isConnected && (
                <motion.div
                  initial={{ scale: 0 }}
                  animate={{ scale: 1 }}
                  className="absolute right-2.5 top-2.5 flex h-5 w-5 items-center justify-center rounded-full bg-ember"
                >
                  <Check size={12} strokeWidth={3} className="text-white" />
                </motion.div>
              )}

              {/* Icon */}
              <div
                className={cn(
                  "transition-colors duration-200",
                  isConnected ? "text-ember" : "text-text-tertiary"
                )}
              >
                {device.icon}
              </div>

              {/* Name */}
              <span
                className={cn(
                  "text-sm font-medium transition-colors duration-200",
                  isConnected ? "text-ember" : "text-text-secondary"
                )}
              >
                {device.name}
              </span>

              {/* Status */}
              <span
                className={cn(
                  "text-xs transition-colors duration-200",
                  isConnected ? "text-ember/70" : "text-text-muted"
                )}
              >
                {isConnected ? "Connected" : "Not Connected"}
              </span>
            </motion.button>
          );
        })}
      </motion.div>

      {/* Skip note */}
      <motion.p
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 0.8 }}
        className="mb-4 text-center text-sm text-text-muted"
      >
        You can connect devices later in Settings
      </motion.p>

      {/* Continue button */}
      <motion.button
        onClick={handleContinue}
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.6 }}
        className={cn(
          "w-full rounded-xl px-8 py-4 text-lg font-semibold text-white",
          "transition-all duration-300",
          "focus:outline-none focus-visible:ring-2 focus-visible:ring-ember focus-visible:ring-offset-2 focus-visible:ring-offset-background"
        )}
        style={{
          background: "linear-gradient(135deg, #FF4D00, #FF6B2B)",
        }}
        whileHover={{ scale: 1.02, boxShadow: "0 0 30px rgba(255,77,0,0.4)" }}
        whileTap={{ scale: 0.98 }}
      >
        Continue
      </motion.button>
    </div>
  );
}
