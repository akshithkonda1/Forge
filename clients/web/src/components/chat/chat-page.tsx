"use client";

import * as React from "react";
import { useState, useRef, useEffect, useCallback } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { cn } from "@/lib/utils";
import { isDemoFallbackAllowed } from "@/lib/auth-config";
import { useAppStore } from "@/stores/useAppStore";
import { WorkoutCard } from "@/components/chat/workout-card";
import { DataInsightCard } from "@/components/chat/data-insight-card";
import { Send, Mic, ArrowDown } from "lucide-react";
import type { ChatMessage, RichCard } from "@/types";

const QUICK_ACTIONS = [
  "How should I train today?",
  "I'm not feeling it",
  "Explain my sleep data",
  "Adjust my plan",
  "I have an injury/pain",
] as const;

function ChatWelcome({ name }: { name: string }) {
  const displayName = name.trim() || "there";
  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      className="mx-auto flex max-w-sm flex-col items-center px-4 py-10 text-center"
    >
      <div className="mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-ember/15">
        <span className="text-xl font-bold text-ember">F</span>
      </div>
      <h2 className="text-lg font-semibold text-text-primary">
        Hey {displayName}, I&apos;m ARIA
      </h2>
      <p className="mt-2 text-sm leading-relaxed text-text-secondary">
        Your AI trainer with full context on your sleep, recovery, and training history.
        Ask anything — or tap a quick prompt below.
      </p>
    </motion.div>
  );
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

function MessageBubble({ message }: { message: ChatMessage }) {
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
              : "rounded-2xl rounded-br-sm bg-ember/90 text-white"
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
  const chatMessages = useAppStore((s) => s.chatMessages);
  const sendChatMessage = useAppStore((s) => s.sendChatMessage);
  const isGeneratingResponse = useAppStore((s) => s.isGeneratingResponse);
  const userProfile = useAppStore((s) => s.userProfile);
  const dataLoadState = useAppStore((s) => s.dataLoadState);

  const [inputValue, setInputValue] = useState("");
  const [showScrollButton, setShowScrollButton] = useState(false);
  const isTyping = isGeneratingResponse;

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
    scrollToBottom();
  }, [chatMessages, isTyping, scrollToBottom]);

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
      setInputValue("");
      void sendChatMessage(trimmed);
    },
    [isTyping, sendChatMessage]
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

  return (
    <div className="flex h-full flex-col bg-background">
      {/* ---- Header ---- */}
      <header className="glass sticky top-0 z-30 border-b border-border px-4 py-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            {/* AI Avatar */}
            <div className="relative flex h-9 w-9 items-center justify-center rounded-full bg-ember/15">
              <svg
                width="18"
                height="18"
                viewBox="0 0 24 24"
                fill="none"
                className="text-ember"
              >
                <path
                  d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                />
              </svg>
              {/* Online indicator */}
              <span className="absolute -bottom-0.5 -right-0.5 flex h-3 w-3 items-center justify-center rounded-full border-2 border-background bg-success">
                <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-success" />
              </span>
            </div>

            <div>
              <h1 className="text-base font-semibold text-text-primary">
                Forge AI
              </h1>
              <div className="flex items-center gap-1.5">
                <span
                  className={cn(
                    "h-1.5 w-1.5 rounded-full",
                    dataLoadState === "offline" || dataLoadState === "error"
                      ? "bg-warning"
                      : "bg-success",
                  )}
                />
                <span className="text-xs text-text-tertiary">
                  {dataLoadState === "offline"
                    ? isDemoFallbackAllowed()
                      ? "Demo mode"
                      : "Offline"
                    : dataLoadState === "error"
                      ? "Reconnecting"
                      : "Live"}
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
            <ChatWelcome name={userProfile.name} />
          )}
          <AnimatePresence initial={false}>
            {chatMessages.map((msg) => (
              <MessageBubble key={msg.id} message={msg} />
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
              className="absolute bottom-4 left-1/2 z-10 flex h-8 w-8 -translate-x-1/2 items-center justify-center rounded-full bg-surface-elevated shadow-lg shadow-black/30 border border-border"
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
      <div className="glass border-t border-border pb-[env(safe-area-inset-bottom,0px)]">
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
              placeholder="Message your trainer..."
              disabled={isTyping}
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
