"use client";

import { useEffect, useId, useState } from "react";
import { FORGE_WELCOME } from "@/lib/forge-welcome";
import {
  FORGE_STRIKE_MARK,
  flameCommands,
  flareScale,
  hammerCommands,
  hammerHighlightCommands,
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
  const uid = `fsm-${useId().replace(/:/g, "")}`;

  useEffect(() => {
    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
    const sync = () => setReduceMotion(media.matches);
    sync();
    media.addEventListener("change", sync);
    return () => media.removeEventListener("change", sync);
  }, []);

  const compact = isCompactStrike(size);
  const idle = strikePose(1, true);
  const scale = flareScale(idle.flare);
  const paper = `#${FORGE_STRIKE_MARK.paperHex}`;
  const paperShade = `#${FORGE_STRIKE_MARK.paperShadeHex}`;
  const ember = `#${FORGE_STRIKE_MARK.emberHex}`;
  const emberLight = `#${FORGE_STRIKE_MARK.emberLightHex}`;
  const emberDark = `#${FORGE_STRIKE_MARK.emberDarkHex}`;
  const amber = `#${FORGE_STRIKE_MARK.amberHex}`;
  const kernel = `#${FORGE_STRIKE_MARK.kernelHex}`; // core highlight stop

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
      <defs>
        <linearGradient id={`${uid}-hammer`} x1="18%" y1="28%" x2="88%" y2="68%">
          <stop offset="0%" stopColor={paper} />
          <stop offset="100%" stopColor={paperShade} />
        </linearGradient>
        <linearGradient id={`${uid}-envelope`} x1="30%" y1="12%" x2="42%" y2="86%">
          <stop offset="0%" stopColor={ember} />
          <stop offset="100%" stopColor={emberDark} />
        </linearGradient>
        <linearGradient id={`${uid}-body`} x1="34%" y1="18%" x2="44%" y2="82%">
          <stop offset="0%" stopColor={emberLight} />
          <stop offset="100%" stopColor={ember} />
        </linearGradient>
        <linearGradient id={`${uid}-core`} x1="38%" y1="36%" x2="43%" y2="76%">
          <stop offset="0%" stopColor={kernel} />
          <stop offset="100%" stopColor={amber} />
        </linearGradient>
        <radialGradient id={`${uid}-glow`} cx="42%" cy="58%" r="16%">
          <stop offset="0%" stopColor={ember} stopOpacity="0.42" />
          <stop offset="100%" stopColor={ember} stopOpacity="0" />
        </radialGradient>
        <radialGradient id={`${uid}-under`} cx="40%" cy="78%" r="20%">
          <stop offset="0%" stopColor={ember} stopOpacity="0.22" />
          <stop offset="100%" stopColor={ember} stopOpacity="0" />
        </radialGradient>
      </defs>
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
      <g transform={compact ? "translate(10 10) scale(0.80)" : undefined}>
        {!compact && (
          <ellipse className="forge-strike-under" cx={40} cy={78} rx={18} ry={12} fill={`url(#${uid}-under)`} />
        )}
        <g
          className="forge-strike-flame"
          style={{
            transformOrigin: `${scale.originX * SIDE}px ${scale.originY * SIDE}px`,
          }}
        >
          {(compact
            ? [paper, paper, paper]
            : [`url(#${uid}-envelope)`, `url(#${uid}-body)`, `url(#${uid}-core)`]
          ).map((fill, index) => (
            <path key={index} d={svgPath(flameCommands(index, 1), SIDE)} fill={fill} />
          ))}
        </g>
        {!compact && (
          <circle
            className="forge-strike-glow"
            cx={FORGE_STRIKE_MARK.strikeX * SIDE}
            cy={FORGE_STRIKE_MARK.strikeY * SIDE}
            r={10}
            fill={`url(#${uid}-glow)`}
          />
        )}
        <g className="forge-strike-hammer">
          <g transform={`translate(${PIVOT_X} ${PIVOT_Y})`}>
            <path
              d={svgPath(hammerCommands(), SIDE)}
              fill={compact ? paper : `url(#${uid}-hammer)`}
              fillRule="evenodd"
            />
            {!compact && (
              <path
                d={svgPath(hammerHighlightCommands(), SIDE)}
                fill="rgba(255,255,255,0.22)"
              />
            )}
          </g>
        </g>
        {!compact &&
          Array.from({ length: FORGE_STRIKE_MARK.sparkCount }, (_, index) => {
            const angle = ((-118 + index * 26) * Math.PI) / 180;
            const dist = 10 + (index % 3) * 4;
            return (
              <circle
                key={index}
                className="forge-strike-spark"
                cx={FORGE_STRIKE_MARK.strikeX * SIDE}
                cy={FORGE_STRIKE_MARK.strikeY * SIDE}
                r={0.75 + (index % 3) * 0.2}
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
