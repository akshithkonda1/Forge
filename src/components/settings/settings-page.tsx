"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
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
import { useToast } from "@/stores/useToast";
import { Sheet } from "@/components/ui/sheet";
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

const DEVICE_OPTIONS = [
  "Apple Watch",
  "Garmin",
  "Oura Ring",
  "Fitbit",
  "Samsung Galaxy Watch",
  "Whoop",
];

type SettingsSheet =
  | "name"
  | "coaching"
  | "devices"
  | "schedule"
  | "privacy"
  | "subscription"
  | "help"
  | "about"
  | "logout"
  | null;

export default function SettingsPage() {
  const router = useRouter();
  const { userProfile, updateProfile, notificationPrefs, setNotificationPref, resetSession } =
    useAppStore();
  const showToast = useToast((s) => s.show);
  const [sheet, setSheet] = useState<SettingsSheet>(null);
  const [draftName, setDraftName] = useState(userProfile.name);

  const handleToggle = (key: keyof typeof notificationPrefs) => {
    setNotificationPref(key, !notificationPrefs[key]);
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
      className="px-4 pb-8 pt-4"
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
            onClick={() => {
              setDraftName(userProfile.name);
              setSheet("name");
            }}
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
      <SectionHeader>ARIA</SectionHeader>
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
          onClick={() => setSheet("coaching")}
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
            onClick={() => setSheet("devices")}
          />
        ))}
        {/* Add Device */}
        <button
          type="button"
          onClick={() => setSheet("devices")}
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
          value={scheduleDays || "Not set"}
          showChevron
          onClick={() => setSheet("schedule")}
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
              enabled={notificationPrefs.workoutReminders}
              onToggle={() => handleToggle("workoutReminders")}
            />
          }
        />
        <SettingsRow
          icon={<Bell size={18} />}
          iconColor="text-steel"
          label="ARIA Insights"
          rightElement={
            <ToggleSwitch
              enabled={notificationPrefs.aiInsights}
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
              enabled={notificationPrefs.recoveryAlerts}
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
              enabled={notificationPrefs.weeklySummary}
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
          onClick={() => setSheet("privacy")}
        />
        <SettingsRow
          icon={<CreditCard size={18} />}
          iconColor="text-text-secondary"
          label="Subscription"
          showChevron
          onClick={() => setSheet("subscription")}
        />
        <SettingsRow
          icon={<HelpCircle size={18} />}
          iconColor="text-text-secondary"
          label="Help & Support"
          showChevron
          onClick={() => setSheet("help")}
        />
        <SettingsRow
          icon={<Info size={18} />}
          iconColor="text-text-secondary"
          label="About Forge"
          showChevron
          onClick={() => setSheet("about")}
        />
      </SectionCard>

      {/* Log Out */}
      <motion.div variants={itemVariants} className="mt-6">
        <button
          type="button"
          onClick={() => setSheet("logout")}
          className="flex w-full items-center justify-center gap-2 rounded-xl bg-surface px-4 py-3.5 transition-colors active:bg-surface-hover"
        >
          <LogOut size={18} className="text-danger" />
          <span className="text-sm font-semibold text-danger">Log Out</span>
        </button>
      </motion.div>

      {/* Bottom spacer */}
      <div className="h-4" />

      <Sheet
        open={sheet === "name"}
        onClose={() => setSheet(null)}
        title="Your name"
        footer={
          <button
            type="button"
            className="w-full rounded-xl bg-ember py-3 text-sm font-semibold text-white"
            onClick={() => {
              const next = draftName.trim();
              if (!next) return;
              updateProfile({ name: next });
              setSheet(null);
              showToast("ARIA will use that name from here.");
            }}
          >
            Save
          </button>
        }
      >
        <input
          value={draftName}
          onChange={(e) => setDraftName(e.target.value)}
          className="w-full rounded-xl border border-border bg-surface-elevated px-4 py-3 text-sm text-text-primary outline-none focus:border-ember"
          placeholder="Name"
          autoFocus
        />
      </Sheet>

      <Sheet open={sheet === "coaching"} onClose={() => setSheet(null)} title="Coaching style">
        <div className="flex flex-col gap-2">
          {(Object.keys(coachingStyleLabels) as CoachingStyle[]).map((style) => (
            <button
              key={style}
              type="button"
              onClick={() => {
                updateProfile({ coachingStyle: style });
                setSheet(null);
                showToast("ARIA's voice updated.");
              }}
              className={cn(
                "rounded-xl border p-3 text-left",
                userProfile.coachingStyle === style
                  ? "border-ember bg-ember/10"
                  : "border-border bg-surface-elevated"
              )}
            >
              <p className="text-sm font-semibold text-text-primary">
                {coachingStyleLabels[style]}
              </p>
              <p className="mt-1 text-xs text-text-tertiary">
                {coachingStyleDescriptions[style]}
              </p>
            </button>
          ))}
        </div>
      </Sheet>

      <Sheet open={sheet === "devices"} onClose={() => setSheet(null)} title="Devices">
        <div className="flex flex-col gap-2">
          {DEVICE_OPTIONS.map((device) => {
            const on = userProfile.connectedDevices.includes(device);
            return (
              <button
                key={device}
                type="button"
                onClick={() => {
                  const next = on
                    ? userProfile.connectedDevices.filter((d) => d !== device)
                    : [...userProfile.connectedDevices, device];
                  updateProfile({ connectedDevices: next });
                }}
                className={cn(
                  "flex items-center justify-between rounded-xl border px-4 py-3 text-sm",
                  on ? "border-ember/50 bg-ember/10 text-ember" : "border-border text-text-secondary"
                )}
              >
                <span>{device}</span>
                <span className="text-xs">{on ? "Connected" : "Tap to add"}</span>
              </button>
            );
          })}
        </div>
      </Sheet>

      <Sheet open={sheet === "schedule"} onClose={() => setSheet(null)} title="Training schedule">
        <div className="grid grid-cols-7 gap-1.5">
          {dayLabels.map((day, index) => {
            const on = userProfile.weeklySchedule.includes(index);
            return (
              <button
                key={day}
                type="button"
                onClick={() => {
                  const next = on
                    ? userProfile.weeklySchedule.filter((d) => d !== index)
                    : [...userProfile.weeklySchedule, index].sort((a, b) => a - b);
                  updateProfile({ weeklySchedule: next });
                }}
                className={cn(
                  "rounded-lg py-3 text-xs font-semibold",
                  on ? "bg-ember text-white" : "bg-surface-elevated text-text-tertiary"
                )}
              >
                {day}
              </button>
            );
          })}
        </div>
      </Sheet>

      <Sheet open={sheet === "privacy"} onClose={() => setSheet(null)} title="Data & Privacy">
        <p className="text-sm leading-relaxed text-text-secondary">
          Forge keeps structured health signals on-device and in your account. ARIA only
          uses the domains you grant. Clinical notes and insurance coverage stay out.
        </p>
      </Sheet>

      <Sheet open={sheet === "subscription"} onClose={() => setSheet(null)} title="Subscription">
        <p className="text-sm leading-relaxed text-text-secondary">
          You&apos;re on the Forge preview. Every page here stays available — billing
          isn&apos;t wired in this build.
        </p>
      </Sheet>

      <Sheet open={sheet === "help"} onClose={() => setSheet(null)} title="Help & Support">
        <p className="text-sm leading-relaxed text-text-secondary">
          Ask ARIA from the chat tab for training and recovery. For account issues,
          use the in-app chat or email support from the iOS client.
        </p>
      </Sheet>

      <Sheet open={sheet === "about"} onClose={() => setSheet(null)} title="About Forge">
        <p className="text-sm leading-relaxed text-text-secondary">
          Forge unifies your health signals. ARIA is the intelligence layer — recovery-first
          coaching that fits the life you already have.
        </p>
      </Sheet>

      <Sheet
        open={sheet === "logout"}
        onClose={() => setSheet(null)}
        title="Log out?"
        footer={
          <div className="flex gap-2">
            <button
              type="button"
              className="flex-1 rounded-xl bg-surface-elevated py-3 text-sm font-semibold text-text-secondary"
              onClick={() => setSheet(null)}
            >
              Stay
            </button>
            <button
              type="button"
              className="flex-1 rounded-xl bg-danger/90 py-3 text-sm font-semibold text-white"
              onClick={() => {
                resetSession();
                setSheet(null);
                router.replace("/onboarding");
              }}
            >
              Log out
            </button>
          </div>
        }
      >
        <p className="text-sm leading-relaxed text-text-secondary">
          This returns you to onboarding. Your demo metrics stay on this device.
        </p>
      </Sheet>
    </motion.div>
  );
}
