import { useEffect, useState } from 'react'
import { api } from '../services/api'
import { fmtDecimal, fmtInt, fmtMoney } from '../services/format'
import { useAsync } from '../services/useAsync'
import type { ProductFilters } from '../types/api'
import { EmptyState, ErrorState, Loading } from './StateMessage'

const DEFAULTS: ProductFilters = {
  page: 1, pageSize: 25, q: '', provider: '', country: '', network: '', unlimited: '',
  minPrice: '', maxPrice: '', sort: 'price', direction: 'asc',
}

const COLUMNS: { key: string; label: string; sortable?: string }[] = [
  { key: 'provider', label: 'Fournisseur', sortable: 'provider' },
  { key: 'productName', label: 'Produit', sortable: 'productName' },
  { key: 'country', label: 'Pays', sortable: 'country' },
  { key: 'data', label: 'Data', sortable: 'dataGb' },
  { key: 'validity', label: 'Validité', sortable: 'validityDays' },
  { key: 'network', label: 'Réseau' },
  { key: 'price', label: 'Prix', sortable: 'price' },
]

export function ProductsTable({ providers }: { providers: string[] }) {
  const [filters, setFilters] = useState<ProductFilters>(DEFAULTS)
  const [draftQ, setDraftQ] = useState('')
  const set = (patch: Partial<ProductFilters>) => setFilters((f) => ({ ...f, page: 1, ...patch }))

  // debounce free-text search
  useEffect(() => {
    const t = setTimeout(() => setFilters((f) => (f.q === draftQ ? f : { ...f, q: draftQ, page: 1 })), 300)
    return () => clearTimeout(t)
  }, [draftQ])

  const { data, error, loading, reload } = useAsync(() => api.products(filters), [JSON.stringify(filters)])
  const isFiltered = Boolean(filters.q || filters.provider || filters.country || filters.network || filters.unlimited || filters.minPrice || filters.maxPrice)

  const toggleSort = (key: string) =>
    setFilters((f) => ({ ...f, page: 1, sort: key, direction: f.sort === key && f.direction === 'asc' ? 'desc' : 'asc' }))

  return (
    <section className="card" aria-labelledby="catalogue-title">
      <h2 id="catalogue-title">Catalogue</h2>
      <form className="filters" onSubmit={(e) => e.preventDefault()}>
        <input type="search" placeholder="Rechercher (produit, SKU, pays)" aria-label="Rechercher" value={draftQ} onChange={(e) => setDraftQ(e.target.value)} />
        <select aria-label="Fournisseur" value={filters.provider} onChange={(e) => set({ provider: e.target.value })}>
          <option value="">Tous les fournisseurs</option>
          {providers.map((p) => <option key={p}>{p}</option>)}
        </select>
        <input className="narrow" placeholder="Pays (FR)" aria-label="Code pays" maxLength={3} value={filters.country} onChange={(e) => set({ country: e.target.value.toUpperCase() })} />
        <select aria-label="Réseau" value={filters.network} onChange={(e) => set({ network: e.target.value })}>
          <option value="">4G / 5G</option><option>4G</option><option>5G</option>
        </select>
        <select aria-label="Data" value={filters.unlimited} onChange={(e) => set({ unlimited: e.target.value as ProductFilters['unlimited'] })}>
          <option value="">Toute data</option><option value="true">Illimitée</option><option value="false">Data limitée</option>
        </select>
        <input className="narrow" type="number" min={0} placeholder="Prix min" aria-label="Prix minimum" value={filters.minPrice} onChange={(e) => set({ minPrice: e.target.value })} />
        <input className="narrow" type="number" min={0} placeholder="Prix max" aria-label="Prix maximum" value={filters.maxPrice} onChange={(e) => set({ maxPrice: e.target.value })} />
        {isFiltered && <button type="button" className="link" onClick={() => { setDraftQ(''); setFilters(DEFAULTS) }}>Réinitialiser</button>}
      </form>

      {loading && !data && <Loading />}
      {error && <ErrorState error={error} onRetry={reload} />}
      {data && (
        <>
          <div className="table-wrap" aria-busy={loading}>
            <table className="products">
              <thead>
                <tr>
                  {COLUMNS.map((c) => (
                    <th key={c.key} aria-sort={c.sortable && filters.sort === c.sortable ? (filters.direction === 'asc' ? 'ascending' : 'descending') : undefined}>
                      {c.sortable ? (
                        <button className="sort" onClick={() => toggleSort(c.sortable!)}>
                          {c.label}{filters.sort === c.sortable ? (filters.direction === 'asc' ? ' ▲' : ' ▼') : ''}
                        </button>
                      ) : c.label}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {data.items.map((p) => (
                  <tr key={p.sku}>
                    <td>{p.provider}</td>
                    <td>{p.productName}<div className="sku">{p.sku}</div></td>
                    <td>{p.countryName} <span className="muted">({p.countryCode})</span></td>
                    <td>{p.isUnlimited ? <span className="badge">Illimité</span> : `${fmtDecimal(p.dataGb, 0)} Go`}</td>
                    <td>{p.validityDays} j</td>
                    <td>{p.network}</td>
                    <td className="num">{fmtMoney(p.price, p.currency)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            {data.items.length === 0 && <EmptyState title="Aucun produit ne correspond à ces filtres." />}
          </div>
          <div className="pager">
            <span className="muted">{fmtInt(data.totalItems)} produit(s)</span>
            <div>
              <button disabled={filters.page <= 1} onClick={() => setFilters((f) => ({ ...f, page: f.page - 1 }))}>Précédent</button>
              <span className="muted"> Page {data.totalItems === 0 ? 0 : data.page} / {data.totalPages} </span>
              <button disabled={filters.page >= data.totalPages} onClick={() => setFilters((f) => ({ ...f, page: f.page + 1 }))}>Suivant</button>
            </div>
          </div>
        </>
      )}
    </section>
  )
}
