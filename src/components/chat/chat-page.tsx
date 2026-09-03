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
import type { ChatMessage } from "@/types";
import { coachReply } from "@/lib/aria-coach";

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

function getTrainerResponse(
  text: string,
  profile: ReturnType<typeof useAppStore.getState>["userProfile"],
  readiness: ReturnType<typeof useAppStore.getState>["readiness"],
  metrics: ReturnType<typeof useAppStore.getState>["dailyMetrics"],
  sleepData: ReturnType<typeof useAppStore.getState>["sleepData"]
) {
  return coachReply(text, profile, readiness, metrics, sleepData);
}

function TypingIndicator() {
  return (
    <div className="flex justify-start">
      <div className="flex items-center gap-1.5 rounded-2xl rounded-bl-sm bg-surface-elevated px-4 py-3">
        <span className="h-1.5 w-1.5 rounded-full bg-text-tertiary aria-orb-glow" />
        <span className="h-1.5 w-1.5 rounded-full bg-text-tertiary aria-orb-glow" />
        <span className="h-1.5 w-1.5 rounded-full bg-text-tertiary aria-orb-glow" />
      </div>
    </div>
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
    <div className={cn("flex w-full", isTrainer ? "justify-start" : "justify-end")}>
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
    </div>
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

      window.setTimeout(() => {
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
      }, 280);
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
          {chatMessages.length === 0 && !isTyping && (
            <div className="mx-auto mt-10 max-w-xs text-center">
              <AriaOrb mood="focused" size={56} />
              <p className="mt-4 text-sm leading-relaxed text-text-secondary">
                I already have the context we built in onboarding. Ask about today, last night, or what&apos;s in the way.
              </p>
            </div>
          )}
          {chatMessages.map((msg) => (
            <MessageBubble
              key={msg.id}
              message={msg}
              onStartWorkout={handleStartWorkout}
            />
          ))}

          {isTyping && <TypingIndicator />}

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
