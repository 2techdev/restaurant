import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { formatChf } from "@/lib/utils";
import type { TopSeller } from "@/lib/api-types";

export function TopSellersTable({ items }: { items: TopSeller[] }) {
  if (!items.length) {
    return <div className="text-sm text-muted-foreground py-8 text-center">—</div>;
  }
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Ürün</TableHead>
          <TableHead className="text-right">Adet</TableHead>
          <TableHead className="text-right">Ciro</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {items.slice(0, 8).map((it) => (
          <TableRow key={it.product_id}>
            <TableCell className="font-medium truncate max-w-[200px]">{it.product_name}</TableCell>
            <TableCell className="text-right tabular-nums">{it.quantity}</TableCell>
            <TableCell className="text-right tabular-nums">{formatChf(it.revenue)}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
