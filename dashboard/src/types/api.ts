export interface Summary {
  hasData: boolean
  totalProducts: number
  productsOver100: number
  priceMin: number | null
  priceMax: number | null
  priceAvg: number | null
  dataAvgGb: number | null
  numericDataCount: number
  unlimitedCount: number
  providerCount: number
  countryCount: number
  currency: string | null
}
export interface ProviderStat {
  provider: string
  productCount: number
  sharePercent: number
  priceAvg: number
  priceMin: number
  priceMax: number
  unlimitedCount: number
}
export interface PriceBucket { label: string; min: number; max: number | null; count: number }
export interface PricesResponse { currency: string | null; buckets: PriceBucket[] }
export interface DataBucket { label: string; dataGb: number | null; isUnlimited: boolean; count: number }
export interface CountBucket { label: string; count: number }
export interface DataResponse {
  dataDistribution: DataBucket[]
  validityDistribution: CountBucket[]
  networkDistribution: CountBucket[]
}
export interface Product {
  sku: string
  provider: string
  productName: string
  countryCode: string
  countryName: string
  dataGb: number | null
  dataDisplay: string
  isUnlimited: boolean
  validityDays: number
  price: number
  currency: string
  network: string
  topUp: boolean
}
export interface ProductPage {
  items: Product[]
  page: number
  pageSize: number
  totalItems: number
  totalPages: number
}
export interface ImportRun {
  sourceFile: string
  status: 'RUNNING' | 'SUCCESS' | 'PARTIAL' | 'FAILED'
  startedAt: string
  finishedAt: string | null
  rowsRead: number
  rowsInserted: number
  rowsUpdated: number
  rowsRejected: number
  errorMessage: string | null
}
export interface LatestImport {
  hasImport: boolean
  batchId: string | null
  status: string | null
  trigger: string | null
  startedAt: string | null
  finishedAt: string | null
  filesCount: number
  rowsRead: number
  rowsInserted: number
  rowsUpdated: number
  rowsRejected: number
  runs: ImportRun[]
}
export interface ProductFilters {
  page: number
  pageSize: number
  q: string
  provider: string
  country: string
  network: string
  unlimited: '' | 'true' | 'false'
  minPrice: string
  maxPrice: string
  sort: string
  direction: 'asc' | 'desc'
}
