"use client";

import { cn } from "@/lib/utils";
import { Input } from "@/components/ui/input";
import { Check } from "lucide-react";

const PRESET_COLORS = [
  "#EF4444", "#F97316", "#F59E0B", "#EAB308", "#10B981",
  "#06B6D4", "#3B82F6", "#6366F1", "#8B5CF6", "#EC4899",
];

export function ColorPicker({
  value,
  onChange,
}: {
  value?: string | null;
  onChange: (v: string) => void;
}) {
  return (
    <div className="space-y-2">
      <div className="flex flex-wrap gap-2">
        {PRESET_COLORS.map((c) => (
          <button
            key={c}
            type="button"
            onClick={() => onChange(c)}
            className={cn(
              "h-7 w-7 rounded-md border border-border/40 flex items-center justify-center transition-transform hover:scale-110",
              value?.toLowerCase() === c.toLowerCase() && "ring-2 ring-ring ring-offset-2 ring-offset-background"
            )}
            style={{ backgroundColor: c }}
            aria-label={c}
          >
            {value?.toLowerCase() === c.toLowerCase() && (
              <Check className="h-3.5 w-3.5 text-white drop-shadow" />
            )}
          </button>
        ))}
      </div>
      <Input
        type="text"
        placeholder="#RRGGBB"
        value={value ?? ""}
        onChange={(e) => onChange(e.target.value)}
        className="font-mono text-xs"
      />
    </div>
  );
}
