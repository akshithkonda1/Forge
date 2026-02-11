"use client";

import * as React from "react";
import { motion } from "framer-motion";
import { cn } from "@/lib/utils";

interface AIMessageBubbleProps {
  message: string;
  isTrainer: boolean;
  timestamp: Date;
  richCard?: React.ReactNode;
}

function formatTime(date: Date): string {
  return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

export function AIMessageBubble({
  message,
  isTrainer,
  timestamp,
  richCard,
}: AIMessageBubbleProps) {
  return (
    <motion.div
      className={cn(
        "flex w-full",
        isTrainer ? "justify-start" : "justify-end"
      )}
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3, ease: "easeOut" }}
    >
      <div
        className={cn(
          "flex max-w-[85%] flex-col gap-1",
          isTrainer ? "items-start" : "items-end"
        )}
      >
        <div
          className={cn(
            "px-4 py-3 text-sm leading-relaxed",
            isTrainer
              ? "rounded-2xl rounded-bl-md bg-[#1A1A1A] text-white"
              : "rounded-2xl rounded-br-md bg-[#FF4D00]/90 text-white"
          )}
        >
          <p>{message}</p>
        </div>

        {richCard && (
          <div className={cn("mt-1 w-full", isTrainer ? "pr-4" : "pl-4")}>
            {richCard}
          </div>
        )}

        <span className="px-1 text-[10px] text-[#71717A]">
          {formatTime(timestamp)}
        </span>
      </div>
    </motion.div>
  );
}
