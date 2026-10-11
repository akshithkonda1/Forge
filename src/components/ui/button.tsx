"use client";

import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { motion, type HTMLMotionProps } from "framer-motion";
import { cn } from "@/lib/utils";

const buttonVariants = cva(
  "inline-flex items-center justify-center whitespace-nowrap rounded-xl font-semibold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ember/60 disabled:pointer-events-none disabled:opacity-50",
  {
    variants: {
      variant: {
        default:
          "bg-ember text-text-primary hover:bg-ember/90 glow-ember",
        secondary:
          "bg-surface text-text-secondary hover:bg-surface-elevated hover:text-text-primary border border-border",
        ghost:
          "bg-transparent text-text-secondary hover:bg-surface hover:text-text-primary",
        outline:
          "border border-border bg-transparent text-text-secondary hover:border-ember hover:text-text-primary",
      },
      size: {
        sm: "h-9 px-3 text-xs gap-1.5",
        default: "h-11 px-5 text-sm gap-2",
        lg: "h-12 px-6 text-base gap-2.5",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
);

export interface ButtonProps
  extends Omit<HTMLMotionProps<"button">, "color">,
    VariantProps<typeof buttonVariants> {}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, ...props }, ref) => {
    return (
      <motion.button
        className={cn(buttonVariants({ variant, size, className }))}
        ref={ref}
        whileTap={{ scale: 0.97 }}
        whileHover={{ scale: 1.02 }}
        transition={{ type: "spring", stiffness: 400, damping: 17 }}
        {...props}
      />
    );
  }
);
Button.displayName = "Button";

export { Button, buttonVariants };
