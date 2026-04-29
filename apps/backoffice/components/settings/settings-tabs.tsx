"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Info } from "lucide-react";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";
import type { AdminUser } from "@/lib/api-types";

export function SettingsTabs({ initialUser }: { initialUser: AdminUser }) {
  const t = useTranslations("settings");

  return (
    <Tabs defaultValue="profile">
      <TabsList className="flex flex-wrap h-auto">
        <TabsTrigger value="profile">{t("tabProfile")}</TabsTrigger>
        <TabsTrigger value="password">{t("tabPassword")}</TabsTrigger>
        <TabsTrigger value="organization">{t("tabOrganization")}</TabsTrigger>
        <TabsTrigger value="notifications">{t("tabNotifications")}</TabsTrigger>
        <TabsTrigger value="apikeys">{t("tabApiKeys")}</TabsTrigger>
        <TabsTrigger value="audit">{t("tabAuditLog")}</TabsTrigger>
      </TabsList>

      <TabsContent value="profile" className="mt-4">
        <ProfileTab initialUser={initialUser} />
      </TabsContent>
      <TabsContent value="password" className="mt-4">
        <PasswordTab />
      </TabsContent>
      <TabsContent value="organization" className="mt-4">
        <ComingSoon title={t("tabOrganization")} body={t("comingSoon")} />
      </TabsContent>
      <TabsContent value="notifications" className="mt-4">
        <ComingSoon title={t("tabNotifications")} body={t("comingSoon")} />
      </TabsContent>
      <TabsContent value="apikeys" className="mt-4">
        <ComingSoon title={t("tabApiKeys")} body={t("comingSoon")} />
      </TabsContent>
      <TabsContent value="audit" className="mt-4">
        <ComingSoon title={t("tabAuditLog")} body={t("comingSoon")} />
      </TabsContent>
    </Tabs>
  );
}

function ProfileTab({ initialUser }: { initialUser: AdminUser }) {
  const t = useTranslations("settings");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const [name, setName] = React.useState(initialUser.name);
  const [submitting, setSubmitting] = React.useState(false);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      await clientFetch({
        path: "/me/profile",
        method: "PUT",
        body: { name },
      });
      toast({ title: t("profileSaved") });
    } catch (err) {
      toast({
        title: tCommon("error"),
        description: (err as Error).message,
        variant: "destructive",
      });
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("profileTitle")}</CardTitle>
      </CardHeader>
      <CardContent>
        <form onSubmit={onSubmit} className="space-y-4">
          <div className="space-y-1">
            <Label htmlFor="profile-email">{t("profileEmail")}</Label>
            <Input id="profile-email" value={initialUser.email} disabled />
          </div>
          <div className="space-y-1">
            <Label htmlFor="profile-name">{t("profileName")}</Label>
            <Input
              id="profile-name"
              required
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </div>
          <div className="flex justify-end">
            <Button type="submit" disabled={submitting}>
              {submitting ? tCommon("loading") : tCommon("save")}
            </Button>
          </div>
        </form>
      </CardContent>
    </Card>
  );
}

function PasswordTab() {
  const t = useTranslations("settings");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const [current, setCurrent] = React.useState("");
  const [next, setNext] = React.useState("");
  const [confirm, setConfirm] = React.useState("");
  const [submitting, setSubmitting] = React.useState(false);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (next !== confirm) {
      toast({ title: t("passwordMismatch"), variant: "destructive" });
      return;
    }
    setSubmitting(true);
    try {
      await clientFetch({
        path: "/me/password",
        method: "PUT",
        body: { current_password: current, new_password: next },
      });
      toast({ title: t("passwordChanged") });
      setCurrent("");
      setNext("");
      setConfirm("");
    } catch (err) {
      toast({
        title: t("passwordChangeError"),
        description: (err as Error).message,
        variant: "destructive",
      });
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("passwordTitle")}</CardTitle>
      </CardHeader>
      <CardContent>
        <form onSubmit={onSubmit} className="space-y-4 max-w-md">
          <div className="space-y-1">
            <Label htmlFor="cur-pwd">{t("currentPassword")}</Label>
            <Input
              id="cur-pwd"
              type="password"
              required
              autoComplete="current-password"
              value={current}
              onChange={(e) => setCurrent(e.target.value)}
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor="new-pwd">{t("newPassword")}</Label>
            <Input
              id="new-pwd"
              type="password"
              required
              minLength={6}
              autoComplete="new-password"
              value={next}
              onChange={(e) => setNext(e.target.value)}
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor="cnf-pwd">{t("confirmPassword")}</Label>
            <Input
              id="cnf-pwd"
              type="password"
              required
              minLength={6}
              autoComplete="new-password"
              value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
            />
          </div>
          <div className="flex justify-end">
            <Button type="submit" disabled={submitting}>
              {submitting ? tCommon("loading") : tCommon("save")}
            </Button>
          </div>
        </form>
      </CardContent>
    </Card>
  );
}

function ComingSoon({ title, body }: { title: string; body: string }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{body}</CardDescription>
      </CardHeader>
      <CardContent>
        <Alert>
          <Info className="h-4 w-4" />
          <AlertDescription>{body}</AlertDescription>
        </Alert>
      </CardContent>
    </Card>
  );
}
