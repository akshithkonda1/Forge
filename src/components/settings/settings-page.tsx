"use client";

import { useState } from "react";
import { motion, type Variants } from "framer-motion";
import {
  User,
  Dumbbell,
  Watch,
  Bell,
  Shield,
  CreditCard,
  HelpCircle,
  Info,
  LogOut,
  ChevronRight,
  Plus,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useAppStore } from "@/stores/useAppStore";
import type { CoachingStyle, FitnessGoal, WorkoutType } from "@/types";

// ---------- Mappings ----------

const coachingStyleLabels: Record<CoachingStyle, string> = {
  "push-hard": "Push Me Hard",
  balanced: "Keep It Balanced",
  patient: "Be Patient With Me",
  "data-driven": "Data-Driven & Precise",
};

const coachingStyleDescriptions: Record<CoachingStyle, string> = {
  "push-hard": "Maximum intensity every session. No excuses.",
  balanced: "Smart training — push when ready, recover when needed.",
  patient: "Encouraging, supportive, and habit-focused.",
  "data-driven": "Optimized by metrics. Numbers guide everything.",
};

const fitnessGoalLabels: Record<FitnessGoal, string> = {
  "build-muscle": "Build Muscle",
  "lose-fat": "Lose Fat",
  "improve-endurance": "Improve Endurance",
  "general-fitness": "General Fitness",
  "athletic-performance": "Athletic Performance",
};

const workoutTypeLabels: Record<WorkoutType, string> = {
  strength: "Strength",
  cardio: "Cardio",
  hiit: "HIIT",
  yoga: "Yoga",
  mobility: "Mobility",
  "sport-specific": "Sport-Specific",
};

const experienceLevelLabels: Record<string, string> = {
  beginner: "Beginner",
  intermediate: "Intermediate",
  advanced: "Advanced",
  elite: "Elite",
};

const dayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

// ---------- Animation Variants ----------

const containerVariants: Variants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.06,
      delayChildren: 0.1,
    },
  },
};

const itemVariants: Variants = {
  hidden: { opacity: 0, y: 12 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.4, ease: [0.25, 0.46, 0.45, 0.94] as const },
  },
};

// ---------- Sub-components ----------

function SectionHeader({ children }: { children: React.ReactNode }) {
  return (
    <motion.h3
      variants={itemVariants}
      className="mb-2 mt-8 text-xs font-semibold uppercase tracking-wider text-text-tertiary"
    >
      {children}
    </motion.h3>
  );
}

function SectionCard({ children }: { children: React.ReactNode }) {
  return (
    <motion.div
      variants={itemVariants}
      className="divide-y divide-border overflow-hidden rounded-xl bg-surface"
    >
      {children}
    </motion.div>
  );
}

function SettingsRow({
  icon,
  iconColor,
  label,
  value,
  showChevron = false,
  rightElement,
  onClick,
}: {
  icon?: React.ReactNode;
  iconColor?: string;
  label: string;
  value?: React.ReactNode;
  showChevron?: boolean;
  rightElement?: React.ReactNode;
  onClick?: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "flex w-full items-center justify-between px-4 py-3",
        onClick && "active:bg-surface-hover transition-colors"
      )}
    >
      <div className="flex items-center gap-3">
        {icon && (
          <span className={cn("flex-shrink-0", iconColor || "text-text-secondary")}>
            {icon}
          </span>
        )}
        <span className="text-sm font-medium text-text-primary">{label}</span>
      </div>
      <div className="flex items-center gap-2">
        {value && (
          <span className="text-sm text-text-secondary">{value}</span>
        )}
        {rightElement}
        {showChevron && (
          <ChevronRight size={16} className="text-text-muted" />
        )}
      </div>
    </button>
  );
}

function ToggleSwitch({
  enabled,
  onToggle,
}: {
  enabled: boolean;
  onToggle: () => void;
}) {
  return (
    <button
      type="button"
      onClick={(e) => {
        e.stopPropagation();
        onToggle();
      }}
      className={cn(
        "relative inline-flex h-7 w-12 flex-shrink-0 items-center rounded-full transition-colors duration-200",
        enabled ? "bg-ember" : "bg-border-light"
      )}
    >
      <motion.span
        className="inline-block h-5 w-5 rounded-full bg-white shadow-md"
        animate={{ x: enabled ? 24 : 4 }}
        transition={{ type: "spring", stiffness: 500, damping: 30 }}
      />
    </button>
  );
}

function Pill({ children, variant = "default" }: { children: React.ReactNode; variant?: "default" | "ember" }) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full px-3 py-1 text-xs font-medium",
        variant === "ember"
          ? "bg-ember/15 text-ember"
          : "bg-surface-elevated text-text-secondary"
      )}
    >
      {children}
    </span>
  );
}

// ---------- Main Component ----------

export default function SettingsPage() {
  const { userProfile } = useAppStore();

  // Local toggle states for notification switches
  const [toggles, setToggles] = useState({
    workoutReminders: true,
    aiInsights: true,
    recoveryAlerts: true,
    weeklySummary: false,
  });

  const handleToggle = (key: keyof typeof toggles) => {
    setToggles((prev) => ({ ...prev, [key]: !prev[key] }));
  };

  // Derive initials from name
  const initials = userProfile.name
    .split(" ")
    .map((n) => n[0])
    .join("")
    .toUpperCase()
    .slice(0, 2);

  // Map weeklySchedule numbers to day labels
  const scheduleDays = userProfile.weeklySchedule
    .map((d) => dayLabels[d])
    .join(" / ");

  return (
    <motion.div
      className="min-h-screen px-4 pb-24 pt-12"
      variants={containerVariants}
      initial="hidden"
      animate="visible"
    >
      {/* Page Title */}
      <motion.h1
        variants={itemVariants}
        className="mb-6 text-2xl font-bold text-text-primary"
      >
        Settings
      </motion.h1>

      {/* ===== 1. Profile Section ===== */}
      <motion.div
        variants={itemVariants}
        className="flex flex-col items-center rounded-xl bg-surface px-4 py-6"
      >
        {/* Avatar */}
        <div
          className="flex h-20 w-20 items-center justify-center rounded-full"
          style={{
            background: "linear-gradient(135deg, #FF4D00, #FF6B2B)",
          }}
        >
          <span className="text-2xl font-bold text-white">{initials}</span>
        </div>

        {/* Name + Edit */}
        <div className="mt-4 flex items-center gap-2">
          <h2 className="text-xl font-bold text-text-primary">
            {userProfile.name}
          </h2>
          <button
            type="button"
            className="text-sm font-medium text-ember transition-colors hover:text-ember-light"
          >
            Edit
          </button>
        </div>

        {/* Experience level pill + member since */}
        <div className="mt-3 flex items-center gap-3">
          <Pill variant="ember">
            {experienceLevelLabels[userProfile.experienceLevel]}
          </Pill>
          <span className="text-xs text-text-tertiary">
            Member since Jan 2026
          </span>
        </div>
      </motion.div>

      {/* ===== 2. AI Trainer Section ===== */}
      <SectionHeader>AI Trainer</SectionHeader>
      <SectionCard>
        {/* Coaching Style */}
        <SettingsRow
          icon={<User size={18} />}
          iconColor="text-ember"
          label="Coaching Style"
          value={
            <span className="max-w-[160px] truncate text-right text-xs text-text-secondary">
              {coachingStyleLabels[userProfile.coachingStyle]}
            </span>
          }
          showChevron
        />
        {/* Style description */}
        <div className="px-4 py-2.5">
          <p className="text-xs leading-relaxed text-text-tertiary">
            {coachingStyleDescriptions[userProfile.coachingStyle]}
          </p>
        </div>
        {/* Training Goals */}
        <div className="px-4 py-3">
          <p className="mb-2 text-sm font-medium text-text-primary">
            Training Goals
          </p>
          <div className="flex flex-wrap gap-2">
            {userProfile.fitnessGoals.map((goal) => (
              <Pill key={goal} variant="ember">
                {fitnessGoalLabels[goal]}
              </Pill>
            ))}
          </div>
        </div>
      </SectionCard>

      {/* ===== 3. Connected Devices ===== */}
      <SectionHeader>Connected Devices</SectionHeader>
      <SectionCard>
        {userProfile.connectedDevices.map((device) => (
          <SettingsRow
            key={device}
            icon={<Watch size={18} />}
            iconColor="text-steel"
            label={device}
            value={
              <span className="inline-flex items-center gap-1.5 text-xs">
                <span className="inline-block h-2 w-2 rounded-full bg-success" />
                Connected
              </span>
            }
            showChevron
          />
        ))}
        {/* Add Device */}
        <button
          type="button"
          className="flex w-full items-center gap-3 px-4 py-3 transition-colors active:bg-surface-hover"
        >
          <span className="flex h-8 w-8 items-center justify-center rounded-full border border-dashed border-border-light">
            <Plus size={16} className="text-text-tertiary" />
          </span>
          <span className="text-sm font-medium text-ember">Add Device</span>
        </button>
      </SectionCard>

      {/* ===== 4. Workout Preferences ===== */}
      <SectionHeader>Workout Preferences</SectionHeader>
      <SectionCard>
        {/* Preferred workout types */}
        <div className="px-4 py-3">
          <p className="mb-2 text-sm font-medium text-text-primary">
            Preferred Types
          </p>
          <div className="flex flex-wrap gap-2">
            {userProfile.preferredWorkouts.map((type) => (
              <Pill key={type}>
                {workoutTypeLabels[type]}
              </Pill>
            ))}
          </div>
        </div>
        {/* Training schedule */}
        <SettingsRow
          icon={<Dumbbell size={18} />}
          iconColor="text-ember"
          label="Training Schedule"
          value={scheduleDays}
          showChevron
        />
        {/* Equipment */}
        <SettingsRow
          label="Equipment"
          value="Commercial Gym"
        />
      </SectionCard>

      {/* ===== 5. Notifications ===== */}
      <SectionHeader>Notifications</SectionHeader>
      <SectionCard>
        <SettingsRow
          icon={<Bell size={18} />}
          iconColor="text-ember"
          label="Workout Reminders"
          rightElement={
            <ToggleSwitch
              enabled={toggles.workoutReminders}
              onToggle={() => handleToggle("workoutReminders")}
            />
          }
        />
        <SettingsRow
          icon={<Bell size={18} />}
          iconColor="text-steel"
          label="AI Insights"
          rightElement={
            <ToggleSwitch
              enabled={toggles.aiInsights}
              onToggle={() => handleToggle("aiInsights")}
            />
          }
        />
        <SettingsRow
          icon={<Bell size={18} />}
          iconColor="text-success"
          label="Recovery Alerts"
          rightElement={
            <ToggleSwitch
              enabled={toggles.recoveryAlerts}
              onToggle={() => handleToggle("recoveryAlerts")}
            />
          }
        />
        <SettingsRow
          icon={<Bell size={18} />}
          iconColor="text-text-secondary"
          label="Weekly Summary"
          rightElement={
            <ToggleSwitch
              enabled={toggles.weeklySummary}
              onToggle={() => handleToggle("weeklySummary")}
            />
          }
        />
      </SectionCard>

      {/* ===== 6. More ===== */}
      <SectionHeader>More</SectionHeader>
      <SectionCard>
        <SettingsRow
          icon={<Shield size={18} />}
          iconColor="text-text-secondary"
          label="Data & Privacy"
          showChevron
        />
        <SettingsRow
          icon={<CreditCard size={18} />}
          iconColor="text-text-secondary"
          label="Subscription"
          showChevron
        />
        <SettingsRow
          icon={<HelpCircle size={18} />}
          iconColor="text-text-secondary"
          label="Help & Support"
          showChevron
        />
        <SettingsRow
          icon={<Info size={18} />}
          iconColor="text-text-secondary"
          label="About Forge"
          showChevron
        />
      </SectionCard>

      {/* Log Out */}
      <motion.div variants={itemVariants} className="mt-6">
        <button
          type="button"
          className="flex w-full items-center justify-center gap-2 rounded-xl bg-surface px-4 py-3.5 transition-colors active:bg-surface-hover"
        >
          <LogOut size={18} className="text-danger" />
          <span className="text-sm font-semibold text-danger">Log Out</span>
        </button>
      </motion.div>

      {/* Bottom spacer */}
      <div className="h-4" />
    </motion.div>
  );
}
