"use client";

/**
 * Gift card list + issuance UI.
 *
 * Talks to /api/v1/giftcards (issue + list), /bulk (bulk generate), and
 * /{code}/void. Backend enforces Swiss legal 5-year min expiry — we surface
 * it as a hint.
 */

import * as React from "react";
import { useTranslations } from "next-intl";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus, X, Copy, ListPlus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from "@/components/ui/table";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";
import { formatChf } from "@/lib/utils";

interface GiftCard {
  id: string;
  code: string;
  denomination_cents: number;
  balance_cents: number;
  status: "active" | "redeemed" | "expired" | "voided";
  issued_at: string;
  expires_at: string;
  issued_to_customer_id?: string | null;
  notes?: string | null;
}

const canEdit = (role: string) =>
  ["OWNER", "MANAGER", "HQ_ADMIN", "HQ_MANAGER"].includes(role);

export function GiftCardsClient({ userRole }: { userRole: string }) {
  const t = useTranslations("giftCards");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();
  const writable = canEdit(userRole);

  const [statusFilter, setStatusFilter] = React.useState<string>("all");
  const [issueOpen, setIssueOpen] = React.useState(false);
  const [bulkOpen, setBulkOpen] = React.useState(false);
  const [lastIssued, setLastIssued] = React.useState<GiftCard | null>(null);

  const listQ = useQuery<{ giftcards: GiftCard[] }>({
    queryKey: ["giftcards", statusFilter],
    queryFn: () => {
      const qs = statusFilter === "all" ? "" : `?status=${statusFilter}`;
      return clientFetch<{ giftcards: GiftCard[] }>({ path: `/giftcards${qs}` });
    },
  });

  const issueOne = useMutation({
    mutationFn: (body: {
      denomination_cents: number;
      issued_to_customer_id?: string | null;
      notes?: string | null;
      expires_at?: string | null;
    }) => clientFetch<GiftCard>({ path: "/giftcards", method: "POST", body }),
    onSuccess: (card) => {
      qc.invalidateQueries({ queryKey: ["giftcards"] });
      setIssueOpen(false);
      setLastIssued(card);
      toast({ title: t("issued"), description: card.code });
    },
    onError: (e: Error) =>
      toast({ title: tCommon("error"), description: e.message, variant: "destructive" }),
  });

  const issueBulk = useMutation({
    mutationFn: (body: {
      quantity: number;
      denomination_cents: number;
      notes?: string | null;
    }) =>
      clientFetch<{ giftcards: GiftCard[] }>({
        path: "/giftcards/bulk",
        method: "POST",
        body,
      }),
    onSuccess: (resp) => {
      qc.invalidateQueries({ queryKey: ["giftcards"] });
      setBulkOpen(false);
      toast({
        title: t("bulkIssued"),
        description: t("bulkIssuedDesc", { count: resp.giftcards.length }),
      });
    },
    onError: (e: Error) =>
      toast({ title: tCommon("error"), description: e.message, variant: "destructive" }),
  });

  const voidCard = useMutation({
    mutationFn: (code: string) =>
      clientFetch({ path: `/giftcards/${code}/void`, method: "PATCH" }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["giftcards"] });
      toast({ title: t("voided") });
    },
    onError: (e: Error) =>
      toast({ title: tCommon("error"), description: e.message, variant: "destructive" }),
  });

  return (
    <>
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>{t("list.title")}</CardTitle>
              <CardDescription>{t("list.subtitle")}</CardDescription>
            </div>
            <div className="flex items-center gap-2">
              <Select value={statusFilter} onValueChange={setStatusFilter}>
                <SelectTrigger className="w-40">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">{t("filter.all")}</SelectItem>
                  <SelectItem value="active">{t("status.active")}</SelectItem>
                  <SelectItem value="redeemed">{t("status.redeemed")}</SelectItem>
                  <SelectItem value="expired">{t("status.expired")}</SelectItem>
                  <SelectItem value="voided">{t("status.voided")}</SelectItem>
                </SelectContent>
              </Select>
              {writable && (
                <>
                  <Button variant="outline" size="sm" onClick={() => setBulkOpen(true)}>
                    <ListPlus className="h-4 w-4 mr-1" /> {t("bulkIssue")}
                  </Button>
                  <Button size="sm" onClick={() => setIssueOpen(true)}>
                    <Plus className="h-4 w-4 mr-1" /> {t("issueNew")}
                  </Button>
                </>
              )}
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("col.code")}</TableHead>
                <TableHead>{t("col.denomination")}</TableHead>
                <TableHead>{t("col.balance")}</TableHead>
                <TableHead>{t("col.status")}</TableHead>
                <TableHead>{t("col.expires")}</TableHead>
                <TableHead className="w-20 text-right">{tCommon("actions")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {(listQ.data?.giftcards ?? []).map((card) => (
                <TableRow key={card.id}>
                  <TableCell>
                    <button
                      className="font-mono text-xs hover:underline"
                      onClick={() => {
                        navigator.clipboard.writeText(card.code);
                        toast({ title: t("codeCopied") });
                      }}
                      title={t("copyCode")}
                    >
                      <Copy className="h-3 w-3 inline mr-1" />
                      {card.code}
                    </button>
                  </TableCell>
                  <TableCell className="font-mono">
                    {formatChf(card.denomination_cents)}
                  </TableCell>
                  <TableCell className="font-mono">
                    {formatChf(card.balance_cents / 100)}
                  </TableCell>
                  <TableCell>
                    <Badge variant={statusVariant(card.status)}>
                      {t(`status.${card.status}`)}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-xs font-mono">
                    {new Date(card.expires_at).toLocaleDateString()}
                  </TableCell>
                  <TableCell className="text-right">
                    {writable && card.status === "active" && (
                      <Button
                        variant="ghost"
                        size="icon"
                        onClick={() => {
                          if (confirm(t("voidConfirm"))) {
                            voidCard.mutate(card.code);
                          }
                        }}
                        title={t("void")}
                      >
                        <X className="h-4 w-4 text-destructive" />
                      </Button>
                    )}
                  </TableCell>
                </TableRow>
              ))}
              {!listQ.isLoading && (listQ.data?.giftcards ?? []).length === 0 && (
                <TableRow>
                  <TableCell colSpan={6} className="text-center text-sm text-muted-foreground py-6">
                    {t("empty")}
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <IssueDialog
        open={issueOpen}
        onClose={() => setIssueOpen(false)}
        onSubmit={(body) => issueOne.mutate(body)}
        saving={issueOne.isPending}
        t={t}
        tCommon={tCommon}
      />
      <BulkIssueDialog
        open={bulkOpen}
        onClose={() => setBulkOpen(false)}
        onSubmit={(body) => issueBulk.mutate(body)}
        saving={issueBulk.isPending}
        t={t}
        tCommon={tCommon}
      />
      <LastIssuedDialog
        card={lastIssued}
        onClose={() => setLastIssued(null)}
        t={t}
        tCommon={tCommon}
      />
    </>
  );
}

function statusVariant(s: GiftCard["status"]): "default" | "outline" | "secondary" {
  switch (s) {
    case "active":
      return "default";
    case "redeemed":
      return "secondary";
    case "voided":
    case "expired":
    default:
      return "outline";
  }
}

const DENOMS = [
  { cents: 2500, label: "25" },
  { cents: 5000, label: "50" },
  { cents: 10000, label: "100" },
  { cents: 20000, label: "200" },
];

function IssueDialog({
  open, onClose, onSubmit, saving, t, tCommon,
}: {
  open: boolean;
  onClose: () => void;
  onSubmit: (body: {
    denomination_cents: number;
    issued_to_customer_id?: string | null;
    notes?: string | null;
  }) => void;
  saving: boolean;
  t: (k: string) => string;
  tCommon: (k: string) => string;
}) {
  const [denomCents, setDenomCents] = React.useState(5000);
  const [custom, setCustom] = React.useState("");
  const [customerId, setCustomerId] = React.useState("");
  const [notes, setNotes] = React.useState("");

  React.useEffect(() => {
    if (open) {
      setDenomCents(5000);
      setCustom("");
      setCustomerId("");
      setNotes("");
    }
  }, [open]);

  const finalCents = custom !== "" ? Math.round(parseFloat(custom) * 100) : denomCents;

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("issueNew")}</DialogTitle>
          <DialogDescription>{t("issueHint")}</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div>
            <Label>{t("col.denomination")}</Label>
            <div className="flex gap-2 mt-1">
              {DENOMS.map((d) => (
                <Button
                  key={d.cents}
                  variant={denomCents === d.cents && custom === "" ? "default" : "outline"}
                  onClick={() => { setDenomCents(d.cents); setCustom(""); }}
                  size="sm"
                >
                  CHF {d.label}
                </Button>
              ))}
              <Input
                placeholder={t("customAmount")}
                value={custom}
                type="number"
                step="0.01"
                min="0"
                className="w-32"
                onChange={(e) => setCustom(e.target.value)}
              />
            </div>
          </div>
          <div>
            <Label>{t("issueToCustomer")}</Label>
            <Input
              placeholder={t("customerIdHint")}
              value={customerId}
              onChange={(e) => setCustomerId(e.target.value)}
            />
          </div>
          <div>
            <Label>{tCommon("notes")}</Label>
            <Input
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder={t("notesHint")}
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>{tCommon("cancel")}</Button>
          <Button
            disabled={saving || finalCents <= 0}
            onClick={() =>
              onSubmit({
                denomination_cents: finalCents,
                issued_to_customer_id: customerId || null,
                notes: notes || null,
              })
            }
          >
            {t("issue")} (CHF {(finalCents / 100).toFixed(2)})
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function BulkIssueDialog({
  open, onClose, onSubmit, saving, t, tCommon,
}: {
  open: boolean;
  onClose: () => void;
  onSubmit: (body: { quantity: number; denomination_cents: number; notes?: string | null }) => void;
  saving: boolean;
  t: (k: string) => string;
  tCommon: (k: string) => string;
}) {
  const [qty, setQty] = React.useState(10);
  const [denomCents, setDenomCents] = React.useState(5000);
  const [notes, setNotes] = React.useState("");

  React.useEffect(() => {
    if (open) {
      setQty(10);
      setDenomCents(5000);
      setNotes("");
    }
  }, [open]);

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("bulkIssue")}</DialogTitle>
          <DialogDescription>{t("bulkHint")}</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>{t("quantity")}</Label>
              <Input
                type="number"
                min="1"
                max="500"
                value={qty}
                onChange={(e) => setQty(parseInt(e.target.value, 10))}
              />
            </div>
            <div>
              <Label>{t("col.denomination")}</Label>
              <Input
                type="number"
                step="0.01"
                min="0"
                value={(denomCents / 100).toFixed(2)}
                onChange={(e) =>
                  setDenomCents(Math.round(parseFloat(e.target.value) * 100))
                }
              />
            </div>
          </div>
          <div>
            <Label>{tCommon("notes")}</Label>
            <Input
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder={t("bulkNotesHint")}
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>{tCommon("cancel")}</Button>
          <Button
            disabled={saving || qty < 1 || denomCents <= 0}
            onClick={() =>
              onSubmit({
                quantity: qty,
                denomination_cents: denomCents,
                notes: notes || null,
              })
            }
          >
            {t("issue")} ({qty} × CHF {(denomCents / 100).toFixed(2)})
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function LastIssuedDialog({
  card, onClose, t, tCommon,
}: {
  card: GiftCard | null;
  onClose: () => void;
  t: (k: string) => string;
  tCommon: (k: string) => string;
}) {
  if (!card) return null;
  return (
    <Dialog open={!!card} onOpenChange={(v) => !v && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("issued")}</DialogTitle>
        </DialogHeader>
        <div className="space-y-2 text-center py-4">
          <p className="text-xs uppercase text-muted-foreground tracking-wider">
            {t("col.code")}
          </p>
          <p className="font-mono text-2xl font-bold tracking-widest">{card.code}</p>
          <p className="text-sm text-muted-foreground">
            CHF {(card.denomination_cents / 100).toFixed(2)}
            {" · "}
            {t("expires")}: {new Date(card.expires_at).toLocaleDateString()}
          </p>
        </div>
        <DialogFooter>
          <Button
            onClick={() => {
              navigator.clipboard.writeText(card.code);
            }}
            variant="outline"
          >
            <Copy className="h-4 w-4 mr-1" /> {t("copyCode")}
          </Button>
          <Button onClick={onClose}>{tCommon("close")}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
