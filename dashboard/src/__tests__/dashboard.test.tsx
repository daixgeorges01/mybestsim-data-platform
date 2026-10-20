import { cleanup, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { DashboardPage } from '../pages/DashboardPage'
import { fmtDecimal, fmtMoney } from '../services/format'

const json = (body: unknown, status = 200) => Promise.resolve(new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } }))

const emptySummary = {
  hasData: false, totalProducts: 0, productsOver100: 0, priceMin: null, priceMax: null, priceAvg: null, dataAvgGb: null,
  numericDataCount: 0, unlimitedCount: 0, providerCount: 0, countryCount: 0, currency: null,
}
const noImport = { hasImport: false, batchId: null, status: null, trigger: null, startedAt: null, finishedAt: null, filesCount: 0, rowsRead: 0, rowsInserted: 0, rowsUpdated: 0, rowsRejected: 0, runs: [] }

// jsdom has no ResizeObserver (needed by Recharts' ResponsiveContainer)
vi.stubGlobal('ResizeObserver', class { observe() {} unobserve() {} disconnect() {} })

afterEach(() => { cleanup(); vi.stubGlobal('fetch', undefined) })

describe('formatting', () => {
  it('shows a dash for missing values instead of inventing numbers', () => {
    expect(fmtDecimal(null)).toBe('—')
    expect(fmtMoney(undefined)).toBe('—')
  })
})

describe('DashboardPage', () => {
  it('shows an honest empty state when no import has run', async () => {
    vi.stubGlobal('fetch', (url: string) => {
      if (url.includes('/dashboard/summary')) return json(emptySummary)
      if (url.includes('/imports/latest')) return json(noImport)
      if (url.includes('/dashboard/providers')) return json({ items: [] })
      return json({})
    })
    render(<DashboardPage />)
    expect(await screen.findByText('Aucune donnée disponible pour le moment.')).toBeTruthy()
    expect(screen.getByText(/Aucun import/)).toBeTruthy()
    expect(screen.queryByText('Cartes eSIM')).toBeNull()
  })

  it('shows an error state with a retry button when the API fails', async () => {
    vi.stubGlobal('fetch', () => json({ error: { code: 'DATABASE_UNAVAILABLE', message: 'The database is currently unavailable' } }, 503))
    render(<DashboardPage />)
    await waitFor(() => expect(screen.getAllByRole('alert').length).toBeGreaterThan(0))
    expect(screen.getAllByText('The database is currently unavailable').length).toBeGreaterThan(0)
    expect(screen.getAllByText('Réessayer').length).toBeGreaterThan(0)
  })

  it('renders KPIs computed by the API', async () => {
    vi.stubGlobal('fetch', (url: string) => {
      if (url.includes('/dashboard/summary')) return json({ ...emptySummary, hasData: true, totalProducts: 10, productsOver100: 2, priceMin: 5, priceMax: 150, priceAvg: 30, dataAvgGb: 12.5, numericDataCount: 8, unlimitedCount: 2, providerCount: 3, countryCount: 4, currency: 'EUR' })
      if (url.includes('/imports/latest')) return json(noImport)
      if (url.includes('/dashboard/providers')) return json({ items: [] })
      if (url.includes('/dashboard/prices')) return json({ currency: 'EUR', buckets: [] })
      if (url.includes('/dashboard/data')) return json({ dataDistribution: [], validityDistribution: [], networkDistribution: [] })
      if (url.includes('/products')) return json({ items: [], page: 1, pageSize: 25, totalItems: 0, totalPages: 0 })
      return json({})
    })
    render(<DashboardPage />)
    expect(await screen.findByText('Cartes eSIM')).toBeTruthy()
    expect(screen.getByText('Offres illimitées')).toBeTruthy()
    expect(screen.getByText(/12,5/)).toBeTruthy()
  })
})
