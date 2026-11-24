import { cn } from "@/lib/utils";

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
