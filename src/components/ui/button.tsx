"use client";

import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { motion, type HTMLMotionProps } from "framer-motion";
import { cn } from "@/lib/utils";

const buttonVariants = cva(
  "inline-flex items-center justify-center whitespace-nowrap rounded-lg font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#FF4D00]/50 disabled:pointer-events-none disabled:opacity-50",
  {
    variants: {
      variant: {
        default:
          "bg-[#FF4D00] text-white hover:bg-[#FF4D00]/90 shadow-[0_0_20px_rgba(255,77,0,0.3)]",
        secondary:
          "bg-[#141414] text-[#A1A1AA] hover:bg-[#1A1A1A] hover:text-white border border-[#2A2A2A]",
        ghost:
          "bg-transparent text-[#A1A1AA] hover:bg-[#141414] hover:text-white",
        outline:
          "border border-[#2A2A2A] bg-transparent text-[#A1A1AA] hover:border-[#FF4D00] hover:text-white",
      },
      size: {
        sm: "h-8 px-3 text-xs gap-1.5",
        default: "h-10 px-5 text-sm gap-2",
        lg: "h-12 px-8 text-base gap-2.5",
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
