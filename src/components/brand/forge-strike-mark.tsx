"use client";

import { useEffect, useState } from "react";
import { FORGE_WELCOME } from "@/lib/forge-welcome";
import {
  FORGE_STRIKE_MARK,
  flameCommands,
  hammerCommands,
  isCompactStrike,
  strikePose,
  svgPath,
} from "@/lib/forge-strike-mark";
import { cn } from "@/lib/utils";

const SIDE = 100;
const PIVOT_X = FORGE_STRIKE_MARK.pivotX * SIDE;
const PIVOT_Y = FORGE_STRIKE_MARK.pivotY * SIDE;

export function ForgeStrikeMark({
  size = 160,
  labeled = true,
  className,
}: {
  size?: number;
  labeled?: boolean;
  className?: string;
}) {
  const [reduceMotion, setReduceMotion] = useState(true);

  useEffect(() => {
    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
    const sync = () => setReduceMotion(media.matches);
    sync();
    media.addEventListener("change", sync);
    return () => media.removeEventListener("change", sync);
  }, []);

  const compact = isCompactStrike(size);
  const idle = strikePose(1, true);
  const paper = `#${FORGE_STRIKE_MARK.paperHex}`;
  const ember = `#${FORGE_STRIKE_MARK.emberHex}`;
  const emberDark = `#${FORGE_STRIKE_MARK.emberDarkHex}`;
  const amber = `#${FORGE_STRIKE_MARK.amberHex}`;
  const flameFills = compact ? [paper, paper, paper] : [emberDark, ember, amber];

  return (
    <svg
      className={cn(
        "forge-strike-mark",
        compact && "is-compact",
        reduceMotion && "is-static",
        className
      )}
      width={size}
      height={size}
      viewBox={`0 0 ${SIDE} ${SIDE}`}
      role={labeled ? "img" : undefined}
      aria-label={labeled ? FORGE_WELCOME.markLabel : undefined}
      aria-hidden={labeled ? undefined : true}
    >
      {compact && (
        <rect
          x={0.5}
          y={0.5}
          width={99}
          height={99}
          rx={28}
          fill={ember}
          stroke="rgba(255,255,255,0.16)"
          strokeWidth={0.8}
        />
      )}
      <g transform={compact ? "translate(11 11) scale(0.78)" : undefined}>
        <g className="forge-strike-flame">
          {flameFills.map((fill, index) => (
            <path key={index} d={svgPath(flameCommands(index, idle.flare), SIDE)} fill={fill} />
          ))}
        </g>
        {!compact && (
          <circle className="forge-strike-glow" cx={41} cy={70} r={8} fill={ember} />
        )}
        <g className="forge-strike-hammer">
          <g transform={`translate(${PIVOT_X} ${PIVOT_Y})`}>
            <path
              d={svgPath(hammerCommands(), SIDE)}
              fill={paper}
              stroke={compact ? "none" : "rgba(255,255,255,0.16)"}
              strokeWidth={compact ? 0 : 0.7}
            />
          </g>
        </g>
        {!compact &&
          Array.from({ length: FORGE_STRIKE_MARK.sparkCount }, (_, index) => {
            const angle = ((-125 + index * 28) * Math.PI) / 180;
            const dist = 12 + (index % 3) * 5;
            return (
              <circle
                key={index}
                className="forge-strike-spark"
                cx={40}
                cy={70}
                r={0.9 + (index % 3) * 0.25}
                fill={amber}
                style={{
                  ["--spark-x" as string]: `${Math.cos(angle) * dist}px`,
                  ["--spark-y" as string]: `${Math.sin(angle) * dist}px`,
                }}
              />
            );
          })}
      </g>
    </svg>
  );
}
