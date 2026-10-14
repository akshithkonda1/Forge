import * as React from "react";
import { cn } from "@/lib/utils";

type CardTone = "default" | "outlined" | "inset";

const toneClass: Record<CardTone, string> = {
  default: "surface-card",
  outlined: "surface-outlined p-5",
  inset: "surface-inset p-4",
};

interface CardProps extends React.HTMLAttributes<HTMLElement> {
  tone?: CardTone;
  as?: "div" | "section" | "article";
}

/** The one Forge container. Default = Home card; inset nests inside it. */
export const Card = React.forwardRef<HTMLElement, CardProps>(function Card(
  { tone = "default", as: Tag = "div", className, ...props },
  ref
) {
  return (
    <Tag
      ref={ref as React.Ref<HTMLDivElement>}
      className={cn(toneClass[tone], className)}
      {...props}
    />
  );
});

/** Uppercase label that opens a card or a page section. */
export function SectionLabel({
  className,
  ...props
}: React.HTMLAttributes<HTMLParagraphElement>) {
  return <p className={cn("type-eyebrow", className)} {...props} />;
}

interface PageHeaderProps {
  title: string;
  subtitle?: string;
  className?: string;
}

/** Shared page title block: one size, one weight, one spacing. */
export function PageHeader({ title, subtitle, className }: PageHeaderProps) {
  return (
    <header className={cn("flex flex-col gap-1", className)}>
      <h1 className="type-page-title text-text-primary">{title}</h1>
      {subtitle && <p className="type-body text-text-tertiary">{subtitle}</p>}
    </header>
  );
}
