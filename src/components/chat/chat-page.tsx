"use client";

import * as React from "react";
import { useState, useRef, useEffect, useCallback } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { cn } from "@/lib/utils";
import { useAppStore } from "@/stores/useAppStore";
import { WorkoutCard } from "@/components/chat/workout-card";
import { DataInsightCard } from "@/components/chat/data-insight-card";
import { AriaOrb } from "@/components/onboarding/aria-companion";
import { useToast } from "@/stores/useToast";
import { Send, Mic, ArrowDown } from "lucide-react";
import type { ChatMessage, RichCard } from "@/types";

// ---------------------------------------------------------------------------
// Quick action definitions
// ---------------------------------------------------------------------------

const QUICK_ACTIONS = [
  "How should I train today?",
  "I'm not feeling it",
  "Explain my sleep data",
  "Adjust my plan",
  "I have an injury/pain",
] as const;

// ---------------------------------------------------------------------------
// Simulated AI response logic
// ---------------------------------------------------------------------------

function getTrainerResponse(
  text: string,
  profile: ReturnType<typeof useAppStore.getState>["userProfile"],
  readiness: ReturnType<typeof useAppStore.getState>["readiness"],
  metrics: ReturnType<typeof useAppStore.getState>["dailyMetrics"],
  sleepData: ReturnType<typeof useAppStore.getState>["sleepData"]
): { content: string; richCard?: RichCard } {
  const lower = text.toLowerCase();

  // Quick action: "How should I train today?"
  if (lower.includes("how should i train") || lower.includes("train today")) {
    const readinessLabel =
      readiness.overall >= 80
        ? "primed"
        : readiness.overall >= 60
          ? "solid"
          : "a bit low";

    return {
      content: `Your readiness is ${readinessLabel} at ${readiness.overall}/100 -- HRV is ${metrics.hrv}ms, resting HR ${metrics.restingHR}bpm. I've put together an Upper Body Power session that matches your recovery state. This one's built to push your bench and pull-up numbers. Let's get after it.`,
      richCard: {
        type: "workout-plan",
        data: {
          name: "Upper Body Power",
          duration: 55,
          exercises: [
            { name: "Barbell Bench Press", sets: 4, reps: "6-8" },
            { name: "Weighted Pull-Ups", sets: 4, reps: "6-8" },
            { name: "Overhead Press", sets: 3, reps: "8-10" },
            { name: "Barbell Rows", sets: 3, reps: "8-10" },
            { name: "Incline DB Press", sets: 3, reps: "10-12" },
            { name: "Face Pulls", sets: 3, reps: "15-20" },
          ],
        },
      },
    };
  }

  // Quick action: "I'm not feeling it"
  if (
    lower.includes("not feeling it") ||
    lower.includes("not feeling great") ||
    lower.includes("tired") ||
    lower.includes("low energy")
  ) {
    return {
      content: `Hey, I hear you -- everyone has those days. Your body might be telling you something. Instead of pushing through a heavy session, let's do something that keeps the momentum without breaking you down. I've got a lighter mobility and recovery flow that'll actually help you bounce back faster for tomorrow.`,
      richCard: {
        type: "workout-plan",
        data: {
          name: "Recovery Flow",
          duration: 30,
          exercises: [
            { name: "Foam Rolling", sets: 1, reps: "5 min" },
            { name: "World's Greatest Stretch", sets: 2, reps: "8 each side" },
            { name: "Band Pull-Aparts", sets: 3, reps: "15" },
            { name: "Goblet Squats (light)", sets: 2, reps: "10" },
            { name: "Dead Hangs", sets: 3, reps: "30 sec" },
          ],
        },
      },
    };
  }

  // Quick action: "Explain my sleep data"
  if (
    lower.includes("sleep") ||
    lower.includes("sleep data") ||
    lower.includes("how did i sleep")
  ) {
    const lastSleep = sleepData[0];
    const deepMinutes = lastSleep?.deepMinutes ?? metrics.deepSleep;
    const totalHours = lastSleep?.totalHours ?? (metrics.totalSleep / 60);
    const sleepScores = sleepData.slice(0, 7).map((s) => s.score).reverse();

    return {
      content: `Last night you logged ${totalHours.toFixed(1)} hours with ${deepMinutes} minutes of deep sleep -- that's ${deepMinutes >= 90 ? "above average" : "slightly below your best"}. Your sleep quality has been ${lastSleep && lastSleep.score >= 80 ? "trending well this week" : "a bit uneven lately"}. Deep sleep is where your muscles actually rebuild, so this directly impacts your training capacity.`,
      richCard: {
        type: "data-chart",
        data: {
          title: "Sleep Quality (7-day)",
          values: sleepScores.length > 0 ? sleepScores : [68, 74, 91, 62, 93, 80, 88],
          insight: `Your average sleep score this week is ${sleepScores.length > 0 ? Math.round(sleepScores.reduce((a, b) => a + b, 0) / sleepScores.length) : 79}. ${deepMinutes >= 90 ? "Deep sleep is solid -- your recovery should be strong." : "Try getting to bed 30 minutes earlier to boost deep sleep."}`,
          color: "#3B82F6",
        },
      },
    };
  }

  // Quick action: "Adjust my plan"
  if (
    lower.includes("adjust") ||
    lower.includes("change my plan") ||
    lower.includes("modify") ||
    lower.includes("switch")
  ) {
    return {
      content: `Absolutely -- your plan should work for you, not the other way around. I can shift today's focus in a few directions: swap to a lower-body session, dial down the intensity for an active recovery day, or pivot to a HIIT conditioning workout if you want something shorter and explosive. What sounds right?`,
    };
  }

  // Quick action: "I have an injury/pain"
  if (
    lower.includes("injury") ||
    lower.includes("pain") ||
    lower.includes("hurt") ||
    lower.includes("sore") ||
    lower.includes("tweaked")
  ) {
    return {
      content: `I want to take this seriously. Tell me more -- where exactly is the pain? Is it sharp/acute or more of a dull ache? And when did it start? In the meantime, I'm pulling your workout plan and replacing any movements that could aggravate it. We'll work around it, not through it. If this feels like more than normal soreness, please see a physio -- I can track your recovery timeline once you get a diagnosis.`,
    };
  }

  // Progress/PR related
  if (
    lower.includes("progress") ||
    lower.includes("how am i doing") ||
    lower.includes("pr") ||
    lower.includes("personal record") ||
    lower.includes("gains")
  ) {
    return {
      content: `You've been putting in the work, ${profile.name}. Over the last 4 weeks: 18 workouts completed, 3 new personal records, and your recovery consistency is up 22%. Your bench went from 205 to 225, squat hit 315, and you knocked 12 seconds off your mile. The data says you're in a growth phase -- let's keep this momentum rolling.`,
      richCard: {
        type: "data-chart",
        data: {
          title: "Strength Progress (4 weeks)",
          values: [185, 195, 205, 215, 225],
          insight: "Bench press progression: +40 lbs over 4 weeks. Current 1RM estimate: 245 lbs.",
          color: "#FF4D00",
        },
      },
    };
  }

  // Default: encouraging response
  const encouragingResponses = [
    `Good question, ${profile.name}. Based on your current metrics -- ${metrics.steps.toLocaleString()} steps today, HRV at ${metrics.hrv}ms -- you're tracking well. Keep the consistency going and the results will compound. What else can I help with?`,
    `I'm on it, ${profile.name}. Your training data shows solid progress this week. Recovery is looking ${readiness.recoveryScore >= 75 ? "strong" : "like it needs some attention"}, so let's make sure we're balancing intensity with rest. What do you want to dive into?`,
    `Here's the thing -- fitness isn't about perfect days, it's about showing up consistently. And ${profile.name}, your consistency has been on point. Your body is adapting. Let me know if you want to talk specifics about your program.`,
  ];

  return {
    content:
      encouragingResponses[Math.floor(Math.random() * encouragingResponses.length)],
  };
}

// ---------------------------------------------------------------------------
// Typing indicator component
// ---------------------------------------------------------------------------

function TypingIndicator() {
  return (
    <motion.div
      className="flex justify-start"
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -5 }}
      transition={{ duration: 0.2 }}
    >
      <div className="flex max-w-[85%] flex-col items-start gap-1">
        <div className="flex items-center gap-1.5 rounded-2xl rounded-bl-sm bg-surface-elevated px-4 py-3">
          <motion.span
            className="h-1.5 w-1.5 rounded-full bg-text-tertiary"
            animate={{ opacity: [0.3, 1, 0.3] }}
            transition={{ duration: 1.2, repeat: Infinity, delay: 0 }}
          />
          <motion.span
            className="h-1.5 w-1.5 rounded-full bg-text-tertiary"
            animate={{ opacity: [0.3, 1, 0.3] }}
            transition={{ duration: 1.2, repeat: Infinity, delay: 0.2 }}
          />
          <motion.span
            className="h-1.5 w-1.5 rounded-full bg-text-tertiary"
            animate={{ opacity: [0.3, 1, 0.3] }}
            transition={{ duration: 1.2, repeat: Infinity, delay: 0.4 }}
          />
        </div>
      </div>
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// Message bubble component (inline, spec-compliant)
// ---------------------------------------------------------------------------

function formatTime(date: Date): string {
  return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function MessageBubble({
  message,
  onStartWorkout,
}: {
  message: ChatMessage;
  onStartWorkout?: () => void;
}) {
  const isTrainer = message.role === "trainer";

  const richCardNode = React.useMemo(() => {
    if (!message.richCard) return null;

    if (message.richCard.type === "workout-plan") {
      const d = message.richCard.data as {
        name: string;
        duration: number;
        exercises: { name: string; sets: number; reps: string | number }[];
      };
      return (
        <WorkoutCard
          name={d.name}
          duration={d.duration}
          exercises={d.exercises}
          onStart={onStartWorkout}
        />
      );
    }

    if (message.richCard.type === "data-chart") {
      const d = message.richCard.data as {
        title: string;
        values: number[];
        insight: string;
        color?: string;
      };
      return (
        <DataInsightCard
          title={d.title}
          values={d.values}
          insight={d.insight}
          color={d.color}
        />
      );
    }

    return null;
  }, [message.richCard]);

  return (
    <motion.div
      className={cn("flex w-full", isTrainer ? "justify-start" : "justify-end")}
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3, ease: "easeOut" }}
    >
      <div
        className={cn(
          "flex flex-col gap-1",
          isTrainer ? "max-w-[85%] items-start" : "max-w-[75%] items-end"
        )}
      >
        {/* Bubble */}
        <div
          className={cn(
            "px-4 py-3 text-sm leading-relaxed",
            isTrainer
              ? "rounded-2xl rounded-bl-sm bg-surface-elevated text-white"
              : "rounded-2xl rounded-br-sm bg-ember text-white"
          )}
        >
          <p className="whitespace-pre-wrap">{message.content}</p>
        </div>

        {/* Rich card */}
        {richCardNode && (
          <div className={cn("mt-1.5 w-full", isTrainer ? "pr-2" : "pl-2")}>
            {richCardNode}
          </div>
        )}

        {/* Timestamp */}
        <span className="px-1 text-[10px] text-text-tertiary">
          {formatTime(message.timestamp)}
        </span>
      </div>
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// Main Chat Page
// ---------------------------------------------------------------------------

export function ChatPage() {
  const {
    chatMessages,
    addMessage,
    userProfile,
    readiness,
    dailyMetrics,
    sleepData,
    startWorkout,
    setActiveTab,
  } = useAppStore();
  const showToast = useToast((s) => s.show);

  const [inputValue, setInputValue] = useState("");
  const [isTyping, setIsTyping] = useState(false);
  const [showScrollButton, setShowScrollButton] = useState(false);

  const scrollAreaRef = useRef<HTMLDivElement>(null);
  const bottomRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // -----------------------------------------------------------------------
  // Auto-scroll to bottom on new messages
  // -----------------------------------------------------------------------

  const scrollToBottom = useCallback((behavior: ScrollBehavior = "smooth") => {
    bottomRef.current?.scrollIntoView({ behavior });
  }, []);

  useEffect(() => {
    if (!showScrollButton) {
      scrollToBottom();
    }
  }, [chatMessages, isTyping, scrollToBottom, showScrollButton]);

  // -----------------------------------------------------------------------
  // Show / hide scroll-to-bottom button
  // -----------------------------------------------------------------------

  const handleScroll = useCallback(() => {
    const el = scrollAreaRef.current;
    if (!el) return;
    const distanceFromBottom = el.scrollHeight - el.scrollTop - el.clientHeight;
    setShowScrollButton(distanceFromBottom > 120);
  }, []);

  // -----------------------------------------------------------------------
  // Send a message
  // -----------------------------------------------------------------------

  const sendMessage = useCallback(
    (text: string) => {
      const trimmed = text.trim();
      if (!trimmed || isTyping) return;

      // Add user message
      const userMsg: ChatMessage = {
        id: `user-${Date.now()}`,
        role: "user",
        content: trimmed,
        timestamp: new Date(),
      };
      addMessage(userMsg);
      setInputValue("");

      // Show typing indicator, then respond
      setIsTyping(true);

      const delay = 1200 + Math.random() * 800; // 1.2 - 2.0 seconds
      setTimeout(() => {
        const { content, richCard } = getTrainerResponse(
          trimmed,
          userProfile,
          readiness,
          dailyMetrics,
          sleepData
        );

        const trainerMsg: ChatMessage = {
          id: `trainer-${Date.now()}`,
          role: "trainer",
          content,
          timestamp: new Date(),
          richCard,
        };
        addMessage(trainerMsg);
        setIsTyping(false);
      }, delay);
    },
    [addMessage, isTyping, userProfile, readiness, dailyMetrics, sleepData]
  );

  // -----------------------------------------------------------------------
  // Handlers
  // -----------------------------------------------------------------------

  const handleSend = () => {
    sendMessage(inputValue);
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  const handleQuickAction = (action: string) => {
    sendMessage(action);
  };

  // -----------------------------------------------------------------------
  // Render
  // -----------------------------------------------------------------------

  const handleStartWorkout = () => {
    startWorkout();
    setActiveTab("workout");
  };

  return (
    <div className="flex h-full min-h-0 flex-col bg-background">
      {/* ---- Header ---- */}
      <header className="glass z-30 shrink-0 border-b border-border px-4 py-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="relative">
              <AriaOrb mood="focused" size={36} speaking={isTyping} />
              <span className="absolute -bottom-0.5 -right-0.5 flex h-3 w-3 items-center justify-center rounded-full border-2 border-background bg-success">
                <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-success" />
              </span>
            </div>

            <div>
              <h1 className="text-base font-semibold text-text-primary">ARIA</h1>
              <div className="flex items-center gap-1.5">
                <span className="h-1.5 w-1.5 rounded-full bg-ember" />
                <span className="text-xs text-text-tertiary">
                  {isTyping ? "Reading your signals…" : "Online · recovery-first"}
                </span>
              </div>
            </div>
          </div>
        </div>
      </header>

      {/* ---- Messages area ---- */}
      <div
        ref={scrollAreaRef}
        onScroll={handleScroll}
        className="relative flex-1 overflow-y-auto px-4 py-4"
      >
        <div className="flex flex-col gap-4">
          <AnimatePresence initial={false}>
            {chatMessages.map((msg) => (
              <MessageBubble
                key={msg.id}
                message={msg}
                onStartWorkout={handleStartWorkout}
              />
            ))}
          </AnimatePresence>

          {/* Typing indicator */}
          <AnimatePresence>{isTyping && <TypingIndicator />}</AnimatePresence>

          <div ref={bottomRef} />
        </div>

        {/* Scroll to bottom button */}
        <AnimatePresence>
          {showScrollButton && (
            <motion.button
              type="button"
              aria-label="Scroll to latest message"
              className="absolute bottom-4 left-1/2 z-10 flex h-8 w-8 -translate-x-1/2 items-center justify-center rounded-full border border-border bg-surface-elevated shadow-lg shadow-black/30"
              onClick={() => scrollToBottom()}
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: 10 }}
              transition={{ duration: 0.2 }}
              whileTap={{ scale: 0.9 }}
            >
              <ArrowDown className="h-4 w-4 text-text-secondary" />
            </motion.button>
          )}
        </AnimatePresence>
      </div>

      {/* ---- Bottom input area ---- */}
      <div className="glass shrink-0 border-t border-border">
        {/* Quick actions - horizontally scrollable */}
        <div className="no-scrollbar flex gap-2 overflow-x-auto px-4 pt-3 pb-2">
          {QUICK_ACTIONS.map((action) => (
            <motion.button
              key={action}
              onClick={() => handleQuickAction(action)}
              disabled={isTyping}
              className={cn(
                "flex-shrink-0 rounded-full border border-border px-4 py-2 text-xs text-text-secondary transition-colors",
                "hover:border-ember/50 hover:text-text-primary",
                "disabled:opacity-40 disabled:pointer-events-none"
              )}
              whileTap={{ scale: 0.95 }}
              transition={{ type: "spring", stiffness: 400, damping: 17 }}
            >
              {action}
            </motion.button>
          ))}
        </div>

        {/* Input row */}
        <div className="flex items-end gap-2 px-4 pb-4 pt-1">
          {/* Mic button */}
          <motion.button
            type="button"
            aria-label="Voice input coming soon"
            onClick={() =>
              showToast("Voice is on the way — type ARIA for now.")
            }
            className="flex h-11 w-11 flex-shrink-0 items-center justify-center rounded-2xl bg-surface-elevated text-text-tertiary transition-colors hover:text-text-secondary"
            whileTap={{ scale: 0.92 }}
            transition={{ type: "spring", stiffness: 400, damping: 17 }}
          >
            <Mic className="h-5 w-5" />
          </motion.button>

          {/* Text input */}
          <div className="relative flex-1">
            <input
              ref={inputRef}
              type="text"
              value={inputValue}
              onChange={(e) => setInputValue(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="Message ARIA…"
              aria-label="Message ARIA"
              disabled={isTyping}
              autoComplete="off"
              className={cn(
                "h-11 w-full rounded-2xl border border-border bg-surface-elevated px-4 pr-12 text-sm text-text-primary placeholder:text-text-muted",
                "outline-none transition-colors",
                "focus:border-ember/50 focus:ring-1 focus:ring-ember/20",
                "disabled:opacity-50"
              )}
            />

            {/* Send button (inside input) */}
            <motion.button
              onClick={handleSend}
              disabled={!inputValue.trim() || isTyping}
              className={cn(
                "absolute right-1.5 top-1/2 -translate-y-1/2 flex h-8 w-8 items-center justify-center rounded-xl transition-colors",
                inputValue.trim() && !isTyping
                  ? "bg-ember text-white shadow-[0_0_12px_rgba(255,77,0,0.3)]"
                  : "bg-transparent text-text-muted"
              )}
              whileTap={inputValue.trim() && !isTyping ? { scale: 0.9 } : {}}
              transition={{ type: "spring", stiffness: 400, damping: 17 }}
            >
              <Send className="h-4 w-4" />
            </motion.button>
          </div>
        </div>
      </div>
    </div>
  );
}
