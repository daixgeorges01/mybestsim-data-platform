import type { ReactNode } from 'react'

interface Props {
  title: string
  subtitle?: string
  children: ReactNode
  table?: { headers: string[]; rows: (string | number)[][] }
}

/** Card with a title, the chart and an accessible table view of the same data. */
export function ChartCard({ title, subtitle, children, table }: Props) {
  return (
    <section className="card">
      <h2>{title}</h2>
      {subtitle && <p className="muted">{subtitle}</p>}
      <div className="chart">{children}</div>
      {table && (
        <details className="table-view">
          <summary>Afficher les données</summary>
          <table>
            <thead><tr>{table.headers.map((h) => <th key={h}>{h}</th>)}</tr></thead>
            <tbody>
              {table.rows.map((r, i) => <tr key={i}>{r.map((c, j) => <td key={j}>{c}</td>)}</tr>)}
            </tbody>
          </table>
        </details>
      )}
    </section>
  )
}
