"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Card, CardContent } from "@/components/ui/card";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";

const DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;
type Day = (typeof DAYS)[number];

interface DayHours {
  open: boolean;
  morning_open: string; // "HH:MM"
  morning_close: string;
  afternoon_open: string;
  afternoon_close: string;
}

type Hours = Record<Day, DayHours>;

const DEFAULT_DAY: DayHours = {
  open: true,
  morning_open: "11:00",
  morning_close: "14:00",
  afternoon_open: "18:00",
  afternoon_close: "23:00",
};

export function OpeningHoursClient() {
  const t = useTranslations("openingHours");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();

  const query = useQuery<Hours | null>({
    queryKey: ["opening-hours"],
    queryFn: async () => {
      try {
        return await clientFetch<Hours>({ path: "/restaurant/opening-hours" });
      } catch {
        return null;
      }
    },
  });

  const initial: Hours =
    query.data ??
    DAYS.reduce((acc, d) => {
      acc[d] = { ...DEFAULT_DAY, open: d !== "sun" };
      return acc;
    }, {} as Hours);

  const [hours, setHours] = React.useState<Hours>(initial);

  React.useEffect(() => {
    if (query.data) setHours(query.data);
  }, [query.data]);

  const save = useMutation({
    mutationFn: async () =>
      clientFetch({ path: "/restaurant/opening-hours", method: "PUT", body: hours }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["opening-hours"] });
      toast({ title: tCommon("success") });
    },
    onError: (e) =>
      toast({
        title: tCommon("error"),
        description: e instanceof Error ? e.message : String(e),
        variant: "destructive",
      }),
  });

  function update(day: Day, patch: Partial<DayHours>) {
    setHours((h) => ({ ...h, [day]: { ...h[day], ...patch } }));
  }

  return (
    <Card>
      <CardContent className="p-6 space-y-3">
        {DAYS.map((d) => {
          const h = hours[d];
          return (
            <div key={d} className="grid grid-cols-12 gap-3 items-center py-2 border-b last:border-0">
              <div className="col-span-2 font-medium">{t(d)}</div>
              <div className="col-span-2 flex items-center gap-2">
                <Switch checked={h.open} onCheckedChange={(v) => update(d, { open: v })} id={`open-${d}`} />
                <Label htmlFor={`open-${d}`} className="text-sm text-muted-foreground">
                  {h.open ? tCommon("active") : tCommon("inactive")}
                </Label>
              </div>
              {h.open ? (
                <>
                  <div className="col-span-4 flex gap-2 items-center">
                    <Input
                      type="time"
                      value={h.morning_open}
                      onChange={(e) => update(d, { morning_open: e.target.value })}
                      className="w-[100px]"
                    />
                    <span className="text-muted-foreground">–</span>
                    <Input
                      type="time"
                      value={h.morning_close}
                      onChange={(e) => update(d, { morning_close: e.target.value })}
                      className="w-[100px]"
                    />
                  </div>
                  <div className="col-span-4 flex gap-2 items-center">
                    <Input
                      type="time"
                      value={h.afternoon_open}
                      onChange={(e) => update(d, { afternoon_open: e.target.value })}
                      className="w-[100px]"
                    />
                    <span className="text-muted-foreground">–</span>
                    <Input
                      type="time"
                      value={h.afternoon_close}
                      onChange={(e) => update(d, { afternoon_close: e.target.value })}
                      className="w-[100px]"
                    />
                  </div>
                </>
              ) : (
                <div className="col-span-8 text-sm text-muted-foreground italic">{t("closed")}</div>
              )}
            </div>
          );
        })}
        <div className="flex justify-end pt-3">
          <Button onClick={() => save.mutate()} disabled={save.isPending}>
            {save.isPending ? tCommon("loading") : tCommon("save")}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
