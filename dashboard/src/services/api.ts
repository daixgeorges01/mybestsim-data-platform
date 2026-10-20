import type { DataResponse, LatestImport, PricesResponse, ProductFilters, ProductPage, ProviderStat, Summary } from '../types/api'

export const API_BASE_URL = (import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:8081/api/v1').replace(/\/$/, '')

export class ApiError extends Error {
  constructor(message: string, public readonly status: number) {
    super(message)
  }
}

async function get<T>(path: string, params?: Record<string, string | number>): Promise<T> {
  const url = new URL(API_BASE_URL + path, window.location.origin)
  Object.entries(params ?? {}).forEach(([k, v]) => {
    if (v !== '' && v !== undefined) url.searchParams.set(k, String(v))
  })
  let response: Response
  try {
    response = await fetch(url.toString(), { headers: { Accept: 'application/json' } })
  } catch {
    throw new ApiError("L'API est injoignable.", 0)
  }
  if (!response.ok) {
    let message = `Erreur ${response.status}`
    try {
      message = (await response.json())?.error?.message ?? message
    } catch { /* body is not JSON */ }
    throw new ApiError(message, response.status)
  }
  return response.json() as Promise<T>
}

export const api = {
  summary: () => get<Summary>('/dashboard/summary'),
  providers: () => get<{ items: ProviderStat[] }>('/dashboard/providers').then((r) => r.items),
  prices: () => get<PricesResponse>('/dashboard/prices'),
  data: () => get<DataResponse>('/dashboard/data'),
  latestImport: () => get<LatestImport>('/imports/latest'),
  products: (f: ProductFilters) =>
    get<ProductPage>('/products', {
      page: f.page, pageSize: f.pageSize, q: f.q.trim(), provider: f.provider, country: f.country,
      network: f.network, unlimited: f.unlimited, minPrice: f.minPrice, maxPrice: f.maxPrice,
      sort: f.sort, direction: f.direction,
    }),
}
