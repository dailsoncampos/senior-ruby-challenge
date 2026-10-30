import type { Invoice, VisibleInvoice } from "../types/invoice";

export const filterDiagnostics = {
  comparisons: 0,
  computations: 0
};

export function resetFilterDiagnostics(): void {
  filterDiagnostics.comparisons = 0;
  filterDiagnostics.computations = 0;
}

export function selectVisibleInvoices(invoices: Invoice[], status: string): VisibleInvoice[] {
  filterDiagnostics.computations += 1;

  const clusterKey = (invoice: Invoice) => `${invoice.customer_name}\u0000${invoice.status}`;
  const clusterSizes = new Map<string, number>();
  for (const invoice of invoices) {
    filterDiagnostics.comparisons += 1;
    const key = clusterKey(invoice);
    clusterSizes.set(key, (clusterSizes.get(key) ?? 0) + 1);
  }

  return invoices
    .filter((invoice) => status === "all" || invoice.status === status)
    .map((invoice) => ({ ...invoice, clusterSize: clusterSizes.get(clusterKey(invoice)) ?? 0 }));
}
