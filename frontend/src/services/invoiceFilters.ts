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

  // Build cluster map in O(n)
  const clusterMap = new Map<string, number>();
  for (const invoice of invoices) {
    filterDiagnostics.comparisons += 1;
    const key = `${invoice.customer_name}|${invoice.status}`;
    clusterMap.set(key, (clusterMap.get(key) ?? 0) + 1);
  }

  // Map and filter in O(n)
  return invoices
    .map((invoice) => ({
      ...invoice,
      clusterSize: clusterMap.get(`${invoice.customer_name}|${invoice.status}`) ?? 0
    }))
    .filter((invoice) => status === "all" || invoice.status === status);
}
