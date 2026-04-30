"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Star, MessageSquare, CheckCircle2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";
import { formatDateTime } from "@/lib/utils";

interface FeedbackItem {
  id: string;
  customer_name?: string | null;
  rating: number;
  comment?: string | null;
  resolved: boolean;
  reply?: string | null;
  created_at: string;
}

function Stars({ value }: { value: number }) {
  return (
    <span className="inline-flex items-center" aria-label={`${value} / 5`}>
      {[1, 2, 3, 4, 5].map((i) => (
        <Star
          key={i}
          className={`h-4 w-4 ${i <= value ? "fill-yellow-500 text-yellow-500" : "text-muted-foreground/30"}`}
        />
      ))}
    </span>
  );
}

export function FeedbackClient() {
  const t = useTranslations("feedback");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();
  const [ratingFilter, setRatingFilter] = React.useState<string>("all");
  const [pendingOnly, setPendingOnly] = React.useState<boolean>(false);
  const [replyOpen, setReplyOpen] = React.useState<FeedbackItem | null>(null);
  const [replyText, setReplyText] = React.useState("");

  const query = useQuery<FeedbackItem[]>({
    queryKey: ["feedback"],
    queryFn: async () => {
      try {
        const data = await clientFetch<{ items?: FeedbackItem[] } | FeedbackItem[]>({
          path: "/feedback",
        });
        if (Array.isArray(data)) return data;
        return data.items ?? [];
      } catch {
        return [];
      }
    },
  });

  const items = (query.data ?? []).filter((it) => {
    if (ratingFilter !== "all" && String(it.rating) !== ratingFilter) return false;
    if (pendingOnly && it.resolved) return false;
    return true;
  });

  const reply = useMutation({
    mutationFn: async (input: { id: string; reply: string }) =>
      clientFetch({
        path: `/feedback/${input.id}/reply`,
        method: "POST",
        body: { reply: input.reply },
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["feedback"] });
      toast({ title: tCommon("success") });
      setReplyOpen(null);
      setReplyText("");
    },
    onError: (e) =>
      toast({
        title: tCommon("error"),
        description: e instanceof Error ? e.message : String(e),
        variant: "destructive",
      }),
  });

  const resolve = useMutation({
    mutationFn: async (id: string) =>
      clientFetch({ path: `/feedback/${id}/resolve`, method: "POST" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["feedback"] }),
  });

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <Select value={ratingFilter} onValueChange={setRatingFilter}>
          <SelectTrigger className="w-[160px]">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">{tCommon("all")}</SelectItem>
            {[1, 2, 3, 4, 5].map((r) => (
              <SelectItem key={r} value={String(r)}>
                {r} {t("stars")}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Button
          variant={pendingOnly ? "default" : "outline"}
          size="sm"
          onClick={() => setPendingOnly((v) => !v)}
        >
          {t("pendingOnly")}
        </Button>
      </div>

      {query.isLoading ? (
        <Card>
          <CardContent className="p-6 text-sm text-muted-foreground">{tCommon("loading")}</CardContent>
        </Card>
      ) : items.length === 0 ? (
        <Card>
          <CardContent className="p-6 text-sm text-muted-foreground text-center">
            {tCommon("noData")}
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-3">
          {items.map((it) => (
            <Card key={it.id}>
              <CardContent className="p-4 space-y-2">
                <div className="flex items-center gap-3 flex-wrap">
                  <Stars value={it.rating} />
                  <span className="text-sm font-medium">{it.customer_name || t("anonymous")}</span>
                  <span className="text-xs text-muted-foreground">{formatDateTime(it.created_at)}</span>
                  {it.resolved ? (
                    <Badge variant="secondary" className="ml-auto">
                      <CheckCircle2 className="h-3 w-3 mr-1" /> {t("resolved")}
                    </Badge>
                  ) : (
                    <Badge variant="outline" className="ml-auto">{t("pending")}</Badge>
                  )}
                </div>
                {it.comment ? <p className="text-sm">{it.comment}</p> : null}
                {it.reply ? (
                  <div className="bg-muted/40 rounded p-2 text-sm">
                    <span className="font-medium">{t("yourReply")}:</span> {it.reply}
                  </div>
                ) : null}
                <div className="flex gap-2 pt-1">
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() => {
                      setReplyOpen(it);
                      setReplyText(it.reply ?? "");
                    }}
                  >
                    <MessageSquare className="h-4 w-4 mr-2" />
                    {t("reply")}
                  </Button>
                  {!it.resolved && (
                    <Button size="sm" variant="ghost" onClick={() => resolve.mutate(it.id)}>
                      <CheckCircle2 className="h-4 w-4 mr-2" />
                      {t("markResolved")}
                    </Button>
                  )}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      <Dialog open={!!replyOpen} onOpenChange={(o) => !o && setReplyOpen(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t("reply")}</DialogTitle>
          </DialogHeader>
          <Input
            value={replyText}
            onChange={(e) => setReplyText(e.target.value)}
            placeholder={t("replyPlaceholder")}
          />
          <DialogFooter>
            <Button variant="outline" onClick={() => setReplyOpen(null)}>
              {tCommon("cancel")}
            </Button>
            <Button
              onClick={() => {
                if (replyOpen && replyText.trim()) {
                  reply.mutate({ id: replyOpen.id, reply: replyText.trim() });
                }
              }}
              disabled={!replyText.trim() || reply.isPending}
            >
              {tCommon("save")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
