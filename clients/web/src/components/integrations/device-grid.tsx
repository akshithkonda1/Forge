"use client";

import { motion } from "framer-motion";
import { Check, Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { WEARABLE_DEVICES, type WearableDeviceId } from "@/lib/device-connect";
import { DeviceIcon } from "@/components/integrations/device-icons";

const containerVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: { staggerChildren: 0.06 },
  },
};

const cardVariants = {
  hidden: { opacity: 0, y: 12 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.35, ease: [0.25, 0.46, 0.45, 0.94] as const },
  },
};

interface DeviceGridProps {
  isDeviceConnected: (deviceId: WearableDeviceId) => boolean;
  connectingDevice: WearableDeviceId | null;
  onConnect: (deviceId: WearableDeviceId) => void;
  compact?: boolean;
}

export function DeviceGrid({
  isDeviceConnected,
  connectingDevice,
  onConnect,
  compact = false,
}: DeviceGridProps) {
  return (
    <motion.div
      className={cn("grid gap-3", compact ? "grid-cols-2" : "grid-cols-2 content-start")}
      variants={containerVariants}
      initial="hidden"
      animate="visible"
    >
      {WEARABLE_DEVICES.map((device) => {
        const connected = isDeviceConnected(device.id);
        const connecting = connectingDevice === device.id;
        const busy = Boolean(connectingDevice) && !connecting && !connected;

        return (
          <motion.button
            key={device.id}
            type="button"
            variants={cardVariants}
            onClick={() => !connected && onConnect(device.id)}
            disabled={connected || connecting || busy}
            className={cn(
              "relative flex flex-col items-center justify-center gap-2 rounded-xl border text-left",
              compact ? "p-4" : "gap-3 p-5",
              "transition-all duration-200",
              connected
                ? "border-ember bg-ember/10"
                : "border-border bg-surface hover:border-border-light",
              busy && "opacity-60",
            )}
            whileHover={!connected && !connectingDevice ? { scale: 1.02 } : undefined}
            whileTap={!connected && !connectingDevice ? { scale: 0.97 } : undefined}
          >
            {connected && (
              <span className="absolute right-2.5 top-2.5 flex h-5 w-5 items-center justify-center rounded-full bg-ember">
                <Check size={12} strokeWidth={3} className="text-white" />
              </span>
            )}

            <div className={cn(connected ? "text-ember" : "text-text-tertiary")}>
              {connecting ? (
                <Loader2 size={compact ? 22 : 28} className="animate-spin" />
              ) : (
                <DeviceIcon deviceId={device.id} size={compact ? 22 : 28} />
              )}
            </div>

            <span
              className={cn(
                "text-center font-medium",
                compact ? "text-xs" : "text-sm",
                connected ? "text-ember" : "text-text-secondary",
              )}
            >
              {device.name}
            </span>

            <span
              className={cn(
                "text-center",
                compact ? "text-[11px]" : "text-xs",
                connected ? "text-ember/70" : "text-text-muted",
              )}
            >
              {connected ? "Connected" : connecting ? "Connecting..." : "Tap to connect"}
            </span>
          </motion.button>
        );
      })}
    </motion.div>
  );
}