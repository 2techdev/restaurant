"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Plus, Edit, KeyRound, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from "@/components/ui/table";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription,
} from "@/components/ui/dialog";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";

export interface Employee {
  id: string;
  email: string;
  name: string;
  role: "OPERATOR" | "BD" | "MANAGER" | "EMPLOYEE";
  status: string;
  last_login_at?: string | null;
  created_at: string;
}

interface CreatedCredential {
  email: string;
  password: string;
}

const ROLES = ["OPERATOR", "BD", "MANAGER", "EMPLOYEE"] as const;

export function EmployeesClient({
  initial,
  currentUserId,
  canWrite,
}: {
  initial: Employee[];
  currentUserId: string;
  canWrite: boolean;
}) {
  const t = useTranslations("employees");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();
  const [formOpen, setFormOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<Employee | null>(null);
  const [credential, setCredential] = React.useState<CreatedCredential | null>(null);

  const { data = initial } = useQuery({
    queryKey: ["partner-employees"],
    queryFn: async () => {
      const r = await clientFetch<{ data: Employee[] }>({ path: "/employees" });
      return r?.data ?? [];
    },
    initialData: initial,
  });
  const refresh = () => qc.invalidateQueries({ queryKey: ["partner-employees"] });

  const deleteMut = useMutation({
    mutationFn: (id: string) =>
      clientFetch({ path: `/employees/${id}`, method: "DELETE" }),
    onSuccess: () => { toast({ title: t("deleteSuccess") }); refresh(); },
    onError: (e: Error) =>
      toast({ title: t("deleteError"), description: e.message, variant: "destructive" }),
  });
  const resetMut = useMutation<{ generated_password: string }, Error, Employee>({
    mutationFn: (emp) =>
      clientFetch<{ generated_password: string }>({
        path: `/employees/${emp.id}/reset-password`,
        method: "POST",
      }),
    onSuccess: (data, emp) => {
      setCredential({ email: emp.email, password: data.generated_password });
    },
    onError: (e: Error) =>
      toast({ title: t("resetError"), description: e.message, variant: "destructive" }),
  });

  return (
    <div className="space-y-4">
      {canWrite && (
        <div className="flex justify-end">
          <Button onClick={() => { setEditing(null); setFormOpen(true); }} className="gap-2">
            <Plus className="h-4 w-4" />
            {t("addEmployee")}
          </Button>
        </div>
      )}
      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("colEmail")}</TableHead>
              <TableHead>{t("colName")}</TableHead>
              <TableHead>{t("colRole")}</TableHead>
              <TableHead>{t("colStatus")}</TableHead>
              <TableHead>{t("colLastLogin")}</TableHead>
              {canWrite && <TableHead className="text-right">{t("colActions")}</TableHead>}
            </TableRow>
          </TableHeader>
          <TableBody>
            {data.map((e) => {
              const isMe = e.id === currentUserId;
              return (
                <TableRow key={e.id}>
                  <TableCell className="font-medium">
                    {e.email}
                    {isMe && <Badge variant="secondary" className="ml-2 text-xs">{t("you")}</Badge>}
                  </TableCell>
                  <TableCell>{e.name}</TableCell>
                  <TableCell><Badge>{e.role}</Badge></TableCell>
                  <TableCell>
                    <Badge variant={e.status === "active" ? "default" : "secondary"}>
                      {e.status}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-sm text-muted-foreground">
                    {e.last_login_at ? new Date(e.last_login_at).toLocaleString() : "—"}
                  </TableCell>
                  {canWrite && (
                    <TableCell className="text-right">
                      <div className="flex justify-end gap-1">
                        <Button size="icon" variant="ghost"
                          onClick={() => { setEditing(e); setFormOpen(true); }}>
                          <Edit className="h-4 w-4" />
                        </Button>
                        <Button size="icon" variant="ghost"
                          onClick={() => resetMut.mutate(e)}
                          disabled={resetMut.isPending}>
                          <KeyRound className="h-4 w-4" />
                        </Button>
                        <Button size="icon" variant="ghost" disabled={isMe}
                          onClick={() => {
                            if (confirm(t("deleteConfirmBody", { email: e.email }))) {
                              deleteMut.mutate(e.id);
                            }
                          }}>
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </div>
                    </TableCell>
                  )}
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </div>
      <EmployeeFormDialog
        open={formOpen}
        initial={editing}
        onOpenChange={setFormOpen}
        onSaved={(cred) => { setFormOpen(false); refresh(); if (cred) setCredential(cred); }}
      />
      <CredentialDialog credential={credential} onClose={() => setCredential(null)} />
    </div>
  );
}

function EmployeeFormDialog({
  open, initial, onOpenChange, onSaved,
}: {
  open: boolean;
  initial: Employee | null;
  onOpenChange: (open: boolean) => void;
  onSaved: (cred: CreatedCredential | null) => void;
}) {
  const t = useTranslations("employees");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const [email, setEmail] = React.useState("");
  const [name, setName] = React.useState("");
  const [role, setRole] = React.useState<Employee["role"]>("EMPLOYEE");
  const [password, setPassword] = React.useState("");
  const [autoGenerate, setAutoGenerate] = React.useState(true);
  const [submitting, setSubmitting] = React.useState(false);

  React.useEffect(() => {
    if (!open) return;
    if (initial) {
      setEmail(initial.email);
      setName(initial.name);
      setRole(initial.role);
    } else {
      setEmail(""); setName(""); setRole("EMPLOYEE");
    }
    setPassword(""); setAutoGenerate(true);
  }, [open, initial]);

  const isEdit = !!initial;

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      if (isEdit && initial) {
        await clientFetch({
          path: `/employees/${initial.id}`,
          method: "PUT",
          body: { name, role },
        });
        toast({ title: t("updateSuccess") });
        onSaved(null);
      } else {
        const body: Record<string, unknown> = { email, name, role };
        if (!autoGenerate && password) body.password = password;
        const res = await clientFetch<{ id: string; email: string; generated_password?: string }>({
          path: "/employees",
          method: "POST",
          body,
        });
        const cred = res.generated_password
          ? { email: res.email, password: res.generated_password }
          : null;
        onSaved(cred);
      }
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
      <DialogContent className="sm:max-w-md">
        <form onSubmit={onSubmit}>
          <DialogHeader>
            <DialogTitle>{isEdit ? t("editEmployee") : t("addEmployee")}</DialogTitle>
            <DialogDescription>
              {isEdit ? t("editSubtitle") : t("addSubtitle")}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-3 py-3">
            <div className="space-y-1">
              <Label>{t("colEmail")}</Label>
              <Input type="email" required disabled={isEdit}
                value={email} onChange={(e) => setEmail(e.target.value)} />
            </div>
            <div className="space-y-1">
              <Label>{t("colName")}</Label>
              <Input required value={name} onChange={(e) => setName(e.target.value)} />
            </div>
            <div className="space-y-1">
              <Label>{t("colRole")}</Label>
              <Select value={role} onValueChange={(v) => setRole(v as Employee["role"])}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {ROLES.map((r) => (<SelectItem key={r} value={r}>{r}</SelectItem>))}
                </SelectContent>
              </Select>
            </div>
            {!isEdit && (
              <div className="space-y-2 rounded-md border p-3">
                <div className="flex items-center gap-2">
                  <input id="auto" type="checkbox" className="h-4 w-4"
                    checked={autoGenerate}
                    onChange={(e) => setAutoGenerate(e.target.checked)} />
                  <Label htmlFor="auto" className="font-normal cursor-pointer">
                    {t("autoGenerate")}
                  </Label>
                </div>
                {!autoGenerate && (
                  <Input type="text" placeholder={t("manualPassword")}
                    value={password} onChange={(e) => setPassword(e.target.value)}
                    minLength={6} />
                )}
              </div>
            )}
          </div>
          <DialogFooter>
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

function CredentialDialog({
  credential, onClose,
}: {
  credential: CreatedCredential | null;
  onClose: () => void;
}) {
  const t = useTranslations("employees");
  const tCommon = useTranslations("common");
  return (
    <Dialog open={!!credential} onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("credentialTitle")}</DialogTitle>
          <DialogDescription>{t("credentialSubtitle")}</DialogDescription>
        </DialogHeader>
        <div className="space-y-2">
          <div className="rounded-md border bg-muted px-3 py-2 font-mono text-sm break-all">
            {credential?.email}
          </div>
          <div className="rounded-md border bg-muted px-3 py-2 font-mono text-sm break-all">
            {credential?.password}
          </div>
          <p className="text-xs text-muted-foreground">{t("credentialWarning")}</p>
        </div>
        <DialogFooter>
          <Button onClick={onClose}>{tCommon("confirm")}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
