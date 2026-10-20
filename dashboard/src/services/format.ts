const nf = (digits: number) => new Intl.NumberFormat('fr-FR', { minimumFractionDigits: digits, maximumFractionDigits: digits })

export const fmtInt = (n: number) => nf(0).format(n)
export const fmtDecimal = (n: number | null | undefined, digits = 2) => (n == null ? '—' : nf(digits).format(n))
export const fmtMoney = (n: number | null | undefined, currency: string | null = 'EUR') =>
  n == null ? '—' : new Intl.NumberFormat('fr-FR', { style: 'currency', currency: currency ?? 'EUR' }).format(n)
export const fmtDate = (iso: string | null) =>
  iso ? new Intl.DateTimeFormat('fr-FR', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(iso)) : '—'
