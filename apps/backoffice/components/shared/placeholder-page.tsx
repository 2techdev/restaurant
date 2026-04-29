import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Sparkles, Info } from "lucide-react";
import type { LucideIcon } from "lucide-react";

interface PlaceholderPageProps {
  title: string;
  hint?: string;
  bodyMessage: string;
  icon?: LucideIcon;
}

export function PlaceholderPage({ title, hint, bodyMessage, icon: Icon = Sparkles }: PlaceholderPageProps) {
  return (
    <div className="space-y-6 max-w-3xl">
      <h1 className="text-2xl font-bold tracking-tight flex items-center gap-2">
        <Icon className="h-6 w-6" />
        {title}
      </h1>
      <Card>
        <CardHeader>
          <CardTitle>{title}</CardTitle>
          {hint && <CardDescription>{hint}</CardDescription>}
        </CardHeader>
        <CardContent>
          <Alert>
            <Info className="h-4 w-4" />
            <AlertDescription>{bodyMessage}</AlertDescription>
          </Alert>
        </CardContent>
      </Card>
    </div>
  );
}
