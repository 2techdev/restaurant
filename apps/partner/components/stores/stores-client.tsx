"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Plus, Edit, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from "@/components/ui/table";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription,
} from "@/components/ui/dialog";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";
import type { Brand } from "@/components/brands/brands-client";
import type { Edition } from "@/components/editions/editions-client";

export interface Store {
  id: string;
  name: string;
  store_code?: string | null;
  brand_id: string;
  brand_name?: string;
  country_code?: string | null;
  address?: string | null;
  phone?: string | null;
  email?: string | null;
  current_edition_id?: string | null;
  is_open: boolean;
  created_at: string;
  updated_at: string;
}

export function StoresClient({
  initialStores,
  brands,
  editions,
  canWrite,
}: {
  initialStores: Store[];
  brands: Brand[];
  editions: Edition[];
  canWrite: boolean;
}) {
  const t = useTranslations("stores");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();
  const [formOpen, setFormOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<Store | null>(null);

  const { data = initialStores } = useQuery({
    queryKey: ["partner-stores"],
    queryFn: async () => {
      const r = await clientFetch<{ data: Store[] }>({ path: "/stores" });
      return r?.data ?? [];
    },
    initialData: initialStores,
  });

  const refresh = () => qc.invalidateQueries({ queryKey: ["partner-stores"] });

  const deleteMut = useMutation({
    mutationFn: (id: string) =>
      clientFetch({ path: `/stores/${id}`, method: "DELETE" }),
    onSuccess: () => { toast({ title: t("deleteSuccess") }); refresh(); },
    onError: (e: Error) =>
      toast({ title: t("deleteError"), description: e.message, variant: "destructive" }),
  });

  return (
    <div className="space-y-4">
      {canWrite && (
        <div className="flex justify-end">
          <Button onClick={() => { setEditing(null); setFormOpen(true); }} className="gap-2">
            <Plus className="h-4 w-4" />
            {t("addStore")}
          </Button>
        </div>
      )}
      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("colName")}</TableHead>
              <TableHead>{t("colBrand")}</TableHead>
              <TableHead>{t("colCode")}</TableHead>
              <TableHead>{t("colCountry")}</TableHead>
              <TableHead>{t("colStatus")}</TableHead>
              {canWrite && <TableHead className="text-right">{t("colActions")}</TableHead>}
            </TableRow>
          </TableHeader>
          <TableBody>
            {data.length === 0 && (
              <TableRow>
                <TableCell colSpan={canWrite ? 6 : 5} className="text-center text-muted-foreground py-8">
                  {t("emptyState")}
                </TableCell>
              </TableRow>
            )}
            {data.map((s) => (
              <TableRow key={s.id}>
                <TableCell className="font-medium">{s.name}</TableCell>
                <TableCell className="text-sm text-muted-foreground">{s.brand_name ?? "—"}</TableCell>
                <TableCell className="font-mono text-xs">{s.store_code ?? "—"}</TableCell>
                <TableCell>{s.country_code ?? "—"}</TableCell>
                <TableCell>
                  <Badge variant={s.is_open ? "default" : "secondary"}>
                    {s.is_open ? t("statusOpen") : t("statusClosed")}
                  </Badge>
                </TableCell>
                {canWrite && (
                  <TableCell className="text-right">
                    <div className="flex justify-end gap-1">
                      <Button size="icon" variant="ghost"
                        onClick={() => { setEditing(s); setFormOpen(true); }}>
                        <Edit className="h-4 w-4" />
                      </Button>
                      <Button size="icon" variant="ghost"
                        onClick={() => {
                          if (confirm(t("deleteConfirmBody", { name: s.name }))) {
                            deleteMut.mutate(s.id);
                          }
                        }}>
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </div>
                  </TableCell>
                )}
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      <StoreFormDialog
        open={formOpen}
        initial={editing}
        brands={brands}
        editions={editions}
        onOpenChange={setFormOpen}
        onSaved={() => { setFormOpen(false); refresh(); }}
      />
    </div>
  );
}

function StoreFormDialog({
  open, initial, brands, editions, onOpenChange, onSaved,
}: {
  open: boolean;
  initial: Store | null;
  brands: Brand[];
  editions: Edition[];
  onOpenChange: (open: boolean) => void;
  onSaved: () => void;
}) {
  const t = useTranslations("stores");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const [tab, setTab] = React.useState("info");
  const [submitting, setSubmitting] = React.useState(false);

  // form state
  const [name, setName] = React.useState("");
  const [brandId, setBrandId] = React.useState("");
  const [storeCode, setStoreCode] = React.useState("");
  const [countryCode, setCountryCode] = React.useState("CH");
  const [editionId, setEditionId] = React.useState("");
  const [isOpen, setIsOpen] = React.useState(true);
  const [address, setAddress] = React.useState("");
  const [phone, setPhone] = React.useState("");
  const [email, setEmail] = React.useState("");

  React.useEffect(() => {
    if (!open) return;
    setTab("info");
    if (initial) {
      setName(initial.name);
      setBrandId(initial.brand_id);
      setStoreCode(initial.store_code ?? "");
      setCountryCode(initial.country_code ?? "CH");
      setEditionId(initial.current_edition_id ?? "");
      setIsOpen(initial.is_open);
      setAddress(initial.address ?? "");
      setPhone(initial.phone ?? "");
      setEmail(initial.email ?? "");
    } else {
      setName("");
      setBrandId(brands[0]?.id ?? "");
      setStoreCode("");
      setCountryCode("CH");
      setEditionId("");
      setIsOpen(true);
      setAddress("");
      setPhone("");
      setEmail("");
    }
  }, [open, initial, brands]);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      const body = {
        name,
        brand_id: brandId,
        store_code: storeCode || null,
        country_code: countryCode || null,
        current_edition_id: editionId || null,
        address: address || null,
        phone: phone || null,
        email: email || null,
        is_open: isOpen,
      };
      if (initial) {
        await clientFetch({ path: `/stores/${initial.id}`, method: "PUT", body });
        toast({ title: t("updateSuccess") });
      } else {
        await clientFetch({ path: "/stores", method: "POST", body });
        toast({ title: t("createSuccess") });
      }
      onSaved();
    } catch (err) {
      toast({
        title: t("saveError"),
        description: (err as Error).message,
        variant: "destructive",
      });
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <form onSubmit={onSubmit}>
          <DialogHeader>
            <DialogTitle>{initial ? t("editStore") : t("addStore")}</DialogTitle>
            <DialogDescription>
              {initial ? t("editSubtitle") : t("addSubtitle")}
            </DialogDescription>
          </DialogHeader>
          <Tabs value={tab} onValueChange={setTab} className="mt-2">
            <TabsList className="grid grid-cols-3 w-full">
              <TabsTrigger value="info">{t("tabInfo")}</TabsTrigger>
              <TabsTrigger value="contact">{t("tabContact")}</TabsTrigger>
              <TabsTrigger value="account">{t("tabAccount")}</TabsTrigger>
            </TabsList>
            <TabsContent value="info" className="space-y-3 pt-3">
              <div className="space-y-1">
                <Label>{t("colName")}</Label>
                <Input required value={name} onChange={(e) => setName(e.target.value)} />
              </div>
              <div className="space-y-1">
                <Label>{t("colBrand")}</Label>
                <Select value={brandId} onValueChange={setBrandId}>
                  <SelectTrigger><SelectValue placeholder="—" /></SelectTrigger>
                  <SelectContent>
                    {brands.map((b) => (
                      <SelectItem key={b.id} value={b.id}>{b.name}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1">
                  <Label>{t("colCode")}</Label>
                  <Input value={storeCode} onChange={(e) => setStoreCode(e.target.value)} placeholder="CH00000080" />
                </div>
                <div className="space-y-1">
                  <Label>{t("colCountry")}</Label>
                  <Input value={countryCode} onChange={(e) => setCountryCode(e.target.value.toUpperCase())} maxLength={2} />
                </div>
              </div>
              <div className="flex items-center gap-2">
                <input id="is-open" type="checkbox" className="h-4 w-4"
                  checked={isOpen} onChange={(e) => setIsOpen(e.target.checked)} />
                <Label htmlFor="is-open" className="font-normal cursor-pointer">{t("openLabel")}</Label>
              </div>
            </TabsContent>
            <TabsContent value="contact" className="space-y-3 pt-3">
              <div className="space-y-1">
                <Label>{t("colAddress")}</Label>
                <Input value={address} onChange={(e) => setAddress(e.target.value)} />
              </div>
              <div className="space-y-1">
                <Label>{t("colPhone")}</Label>
                <Input value={phone} onChange={(e) => setPhone(e.target.value)} />
              </div>
              <div className="space-y-1">
                <Label>{t("colEmail")}</Label>
                <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
              </div>
            </TabsContent>
            <TabsContent value="account" className="space-y-3 pt-3">
              <div className="space-y-1">
                <Label>{t("colEdition")}</Label>
                <Select value={editionId} onValueChange={setEditionId}>
                  <SelectTrigger><SelectValue placeholder="—" /></SelectTrigger>
                  <SelectContent>
                    {editions.map((e) => (
                      <SelectItem key={e.id} value={e.id}>
                        {e.name} · CHF {e.price_chf_month}/mo
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <p className="text-xs text-muted-foreground">{t("accountHint")}</p>
            </TabsContent>
          </Tabs>
          <DialogFooter className="mt-4">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              {tCommon("cancel")}
            </Button>
            <Button type="submit" disabled={submitting}>
              {submitting ? tCommon("loading") : tCommon("save")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
