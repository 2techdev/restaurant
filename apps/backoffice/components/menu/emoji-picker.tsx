"use client";

import * as React from "react";
import { Input } from "@/components/ui/input";

const PRESETS = [
  "🍔","🍕","🍜","🍣","🥗","🍝","🌮","🥪","🍰","🍩",
  "☕","🍵","🍹","🍺","🍷","🥤","🧃","🍦","🍫","🍪",
  "🍳","🥩","🍤","🍱","🥟","🍙","🍚","🥘","🍲","🍢",
];

export function EmojiPicker({ value, onChange }: { value?: string | null; onChange: (v: string) => void }) {
  return (
    <div className="space-y-2">
      <div className="flex flex-wrap gap-1.5">
        {PRESETS.map((e) => (
          <button
            key={e}
            type="button"
            onClick={() => onChange(e)}
            className="h-8 w-8 rounded-md border border-border/40 hover:bg-accent flex items-center justify-center text-base"
          >
            {e}
          </button>
        ))}
      </div>
      <Input
        placeholder="🍔 (emoji veya icon adı)"
        value={value ?? ""}
        onChange={(e) => onChange(e.target.value)}
        maxLength={4}
      />
    </div>
  );
}
