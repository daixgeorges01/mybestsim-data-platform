import { Bar, BarChart, CartesianGrid, Cell, LabelList, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { fmtInt } from '../services/format'

interface Datum { label: string; count: number; highlight?: boolean }

const axis = { fontSize: 12, fill: 'var(--text-secondary)' }

function Tip({ active, payload, suffix }: { active?: boolean; payload?: { payload: Datum }[]; suffix: string }) {
  if (!active || !payload?.length) return null
  const d = payload[0].payload
  return (
    <div className="tooltip">
      <div className="tooltip-title">{d.label}</div>
      <div>{fmtInt(d.count)} {suffix}</div>
    </div>
  )
}

const labelStyle = { fontSize: 11, fill: 'var(--text-secondary)' }
const fmtLabel = (v: unknown) => fmtInt(Number(v))

/** Vertical columns: distributions (price buckets, data allowance, validity, network). */
export function ColumnChart({ data, suffix = 'produits', height = 260 }: { data: Datum[]; suffix?: string; height?: number }) {
  return (
    <ResponsiveContainer width="100%" height={height}>
      <BarChart data={data} margin={{ top: 18, right: 8, bottom: 0, left: 0 }} barCategoryGap="22%">
        <CartesianGrid stroke="var(--grid)" vertical={false} />
        <XAxis dataKey="label" tick={axis} tickLine={false} axisLine={{ stroke: 'var(--axis)' }} interval={0} />
        <YAxis tick={axis} tickLine={false} axisLine={false} width={44} tickFormatter={fmtInt} />
        <Tooltip content={<Tip suffix={suffix} />} cursor={{ fill: 'var(--hover)' }} />
        <Bar dataKey="count" radius={[4, 4, 0, 0]} isAnimationActive={false}>
          {data.map((d) => <Cell key={d.label} fill={d.highlight ? 'var(--series-2)' : 'var(--series-1)'} />)}
          <LabelList dataKey="count" position="top" formatter={fmtLabel} style={labelStyle} />
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  )
}

/** Horizontal bars: one row per provider, sorted by size. */
export function HorizontalBarChart({ data, suffix = 'produits' }: { data: Datum[]; suffix?: string }) {
  const height = Math.max(180, data.length * 28 + 20)
  return (
    <ResponsiveContainer width="100%" height={height}>
      <BarChart data={data} layout="vertical" margin={{ top: 0, right: 44, bottom: 0, left: 0 }} barCategoryGap="22%">
        <CartesianGrid stroke="var(--grid)" horizontal={false} />
        <XAxis type="number" tick={axis} tickLine={false} axisLine={false} tickFormatter={fmtInt} />
        <YAxis type="category" dataKey="label" tick={axis} tickLine={false} axisLine={false} width={96} interval={0} />
        <Tooltip content={<Tip suffix={suffix} />} cursor={{ fill: 'var(--hover)' }} />
        <Bar dataKey="count" radius={[0, 4, 4, 0]} fill="var(--series-1)" isAnimationActive={false}>
          <LabelList dataKey="count" position="right" formatter={fmtLabel} style={labelStyle} />
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  )
}
