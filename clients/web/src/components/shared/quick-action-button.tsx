"use client";

import { motion } from "framer-motion";

interface QuickActionButtonProps {
  label: string;
  onClick: () => void;
}

export function QuickActionButton({ label, onClick }: QuickActionButtonProps) {
  return (
    <motion.button
      onClick={onClick}
      className="rounded-full border border-[#2A2A2A] px-4 py-2 text-sm text-[#A1A1AA] transition-colors hover:border-[#FF4D00] hover:text-white"
      whileTap={{ scale: 0.95 }}
      transition={{ type: "spring", stiffness: 400, damping: 17 }}
    >
      {label}
    </motion.button>
  );
}
