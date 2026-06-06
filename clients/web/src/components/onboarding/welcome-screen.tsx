"use client";

import { motion } from "framer-motion";
import { cn } from "@/lib/utils";

interface WelcomeScreenProps {
  onNext: () => void;
}

const containerVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.2,
      delayChildren: 0.3,
    },
  },
};

const itemVariants = {
  hidden: { opacity: 0, y: 20 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.6, ease: [0.25, 0.46, 0.45, 0.94] as const },
  },
};

function ForgeFlameIcon() {
  return (
    <motion.svg
      width="80"
      height="80"
      viewBox="0 0 80 80"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      initial={{ scale: 0.8, opacity: 0 }}
      animate={{ scale: 1, opacity: 1 }}
      transition={{ duration: 0.8, ease: "easeOut" }}
    >
      {/* Outer flame */}
      <motion.path
        d="M40 8C40 8 18 28 18 48C18 60.15 27.85 70 40 70C52.15 70 62 60.15 62 48C62 28 40 8 40 8Z"
        fill="url(#flame-gradient-outer)"
        initial={{ pathLength: 0 }}
        animate={{ pathLength: 1 }}
        transition={{ duration: 1.2, ease: "easeInOut" }}
      />
      {/* Inner flame */}
      <motion.path
        d="M40 24C40 24 28 38 28 50C28 56.63 33.37 62 40 62C46.63 62 52 56.63 52 50C52 38 40 24 40 24Z"
        fill="url(#flame-gradient-inner)"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ duration: 0.8, delay: 0.4 }}
      />
      {/* Core glow */}
      <motion.ellipse
        cx="40"
        cy="52"
        rx="6"
        ry="8"
        fill="#FFF"
        opacity="0.3"
        initial={{ opacity: 0 }}
        animate={{ opacity: 0.3 }}
        transition={{ duration: 0.6, delay: 0.8 }}
      />
      <defs>
        <linearGradient id="flame-gradient-outer" x1="40" y1="8" x2="40" y2="70" gradientUnits="userSpaceOnUse">
          <stop stopColor="#FF6B2B" />
          <stop offset="1" stopColor="#FF4D00" />
        </linearGradient>
        <linearGradient id="flame-gradient-inner" x1="40" y1="24" x2="40" y2="62" gradientUnits="userSpaceOnUse">
          <stop stopColor="#FFAD73" />
          <stop offset="1" stopColor="#FF6B2B" />
        </linearGradient>
      </defs>
    </motion.svg>
  );
}

export default function WelcomeScreen({ onNext }: WelcomeScreenProps) {
  return (
    <div className="flex min-h-[100dvh] flex-col items-center justify-center px-6">
      {/* Background ambient glow */}
      <div
        className="pointer-events-none fixed inset-0"
        style={{
          background:
            "radial-gradient(ellipse 50% 40% at 50% 40%, rgba(255,77,0,0.08) 0%, transparent 70%)",
        }}
      />

      <motion.div
        className="relative z-10 flex w-full max-w-md flex-col items-center text-center"
        variants={containerVariants}
        initial="hidden"
        animate="visible"
      >
        {/* Flame icon */}
        <motion.div variants={itemVariants} className="mb-8">
          <div className="relative">
            <ForgeFlameIcon />
            {/* Glow behind icon */}
            <div
              className="absolute inset-0 -z-10 blur-2xl"
              style={{
                background: "radial-gradient(circle, rgba(255,77,0,0.3) 0%, transparent 70%)",
              }}
            />
          </div>
        </motion.div>

        {/* Logo text */}
        <motion.h1
          variants={itemVariants}
          className="text-gradient-ember mb-3 text-6xl font-black tracking-[0.2em]"
          style={{
            fontFamily: "var(--font-display)",
          }}
        >
          FORGE
        </motion.h1>

        {/* Tagline */}
        <motion.p
          variants={itemVariants}
          className="mb-8 text-lg font-medium text-text-secondary"
        >
          Your AI Training Partner
        </motion.p>

        {/* Divider */}
        <motion.div
          variants={itemVariants}
          className="mb-8 h-px w-16"
          style={{
            background: "linear-gradient(90deg, transparent, #FF4D00, transparent)",
          }}
        />

        {/* Description */}
        <motion.p
          variants={itemVariants}
          className="mb-16 max-w-sm text-base leading-relaxed text-text-tertiary"
        >
          An AI coach that knows your body, adapts to your life, and pushes you
          to be your best.
        </motion.p>

        {/* Get Started button */}
        <motion.div variants={itemVariants} className="w-full">
          <motion.button
            onClick={onNext}
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
            Get Started
          </motion.button>
        </motion.div>
      </motion.div>
    </div>
  );
}
