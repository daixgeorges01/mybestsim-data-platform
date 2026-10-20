import { ChartCard } from '../components/ChartCard'
import { ColumnChart, HorizontalBarChart } from '../components/BarCharts'
import { ImportStatus } from '../components/ImportStatus'
import { KpiCard } from '../components/KpiCard'
import { ProductsTable } from '../components/ProductsTable'
import { EmptyState, ErrorState, Loading } from '../components/StateMessage'
import { api } from '../services/api'
import { fmtDecimal, fmtInt, fmtMoney } from '../services/format'
import { useAsync } from '../services/useAsync'

export function DashboardPage() {
  const summary = useAsync(api.summary, [])
  const latest = useAsync(api.latestImport, [])
  const providers = useAsync(api.providers, [])
  const prices = useAsync(api.prices, [])
  const dist = useAsync(api.data, [])

  const s = summary.data
  const cur = s?.currency ?? 'EUR'

  return (
    <div className="page">
      <header className="brandbar">
        <a className="brand" href="/" aria-label="MyBestSim">
          <img src="/bird.png" alt="" width={52} height={50} />
          <span>MyBestSim</span>
        </a>
        <nav aria-label="Navigation">
          <span className="navitem active">Dashboard catalogue</span>
          <a className="navitem" href="https://mybestsim.com" target="_blank" rel="noreferrer">Comparateur eSIM</a>
        </nav>
        <button className="btn-primary" onClick={() => { [summary, latest, providers, prices, dist].forEach((x) => x.reload()) }}>Actualiser</button>
      </header>

      <section className="hero">
        <div>
          <h1>Analysez <em>instantanément</em> le catalogue <em>eSIM</em></h1>
        </div>
        {s && s.hasData && (
          <ul className="checks" aria-label="Chiffres clés">
            <li><span className="check" aria-hidden>✓</span> {fmtInt(s.totalProducts)} forfaits eSIM et {s.countryCount} destinations</li>
            <li><span className="check" aria-hidden>✓</span> {s.providerCount} fournisseurs importés</li>
            <li><span className="check" aria-hidden>✓</span> Filtres performants (données, durée, prix)</li>
          </ul>
        )}
      </section>

      {latest.data && <ImportStatus latest={latest.data} />}

      {summary.loading && !s && <Loading />}
      {summary.error && <ErrorState error={summary.error} onRetry={summary.reload} />}

      {s && !s.hasData && (
        <EmptyState title="Aucune donnée disponible pour le moment.">
          La base ne contient encore aucun produit : lancez un import MuleSoft (Scheduler ou POST /api/v1/imports) pour alimenter le catalogue.
        </EmptyState>
      )}

      {s && s.hasData && (
        <>
          <section className="kpis" aria-label="Indicateurs clés">
            <KpiCard label="Cartes eSIM" value={fmtInt(s.totalProducts)} hint={`${s.providerCount} fournisseurs · ${s.countryCount} destinations`} />
            <KpiCard label="Produits à plus de 100 €" value={fmtInt(s.productsOver100)} hint={`${fmtDecimal((s.productsOver100 / s.totalProducts) * 100, 1)} % du catalogue`} />
            <KpiCard label="Fourchette de prix" value={`${fmtMoney(s.priceMin, cur)} – ${fmtMoney(s.priceMax, cur)}`} hint="du moins cher au plus cher" />
            <KpiCard label="Prix moyen" value={fmtMoney(s.priceAvg, cur)} hint="tous produits, illimités inclus" />
            <KpiCard label="Data moyenne" value={`${fmtDecimal(s.dataAvgGb, 1)} Go`} hint={`sur ${fmtInt(s.numericDataCount)} offres chiffrées (hors illimité)`} />
            <KpiCard label="Offres illimitées" value={fmtInt(s.unlimitedCount)} hint={`${fmtDecimal((s.unlimitedCount / s.totalProducts) * 100, 1)} % du catalogue`} />
          </section>

          <div className="grid">
            <ChartCard
              title="Produits par fournisseur"
              subtitle="Nombre de cartes proposées par chaque fournisseur"
              table={providers.data ? { headers: ['Fournisseur', 'Produits', 'Part', 'Prix moyen', 'Illimités'], rows: providers.data.map((p) => [p.provider, p.productCount, `${fmtDecimal(p.sharePercent, 1)} %`, fmtMoney(p.priceAvg, cur), p.unlimitedCount]) } : undefined}
            >
              {providers.loading && !providers.data && <Loading />}
              {providers.error && <ErrorState error={providers.error} onRetry={providers.reload} />}
              {providers.data && <HorizontalBarChart data={providers.data.map((p) => ({ label: p.provider, count: p.productCount }))} />}
            </ChartCard>

            <div className="stack">
              <ChartCard
                title="Distribution des prix"
                subtitle="Tranches en euros (borne haute incluse)"
                table={prices.data ? { headers: ['Tranche', 'Produits'], rows: prices.data.buckets.map((b) => [b.label, b.count]) } : undefined}
              >
                {prices.loading && !prices.data && <Loading />}
                {prices.error && <ErrorState error={prices.error} onRetry={prices.reload} />}
                {prices.data && <ColumnChart data={prices.data.buckets.map((b) => ({ label: b.label.replace(' €', ''), count: b.count }))} height={230} />}
              </ChartCard>

              <ChartCard
                title="Répartition de la data"
                subtitle="Volume de data inclus (les offres illimitées sont comptées à part)"
                table={dist.data ? { headers: ['Data', 'Produits'], rows: dist.data.dataDistribution.map((d) => [d.label, d.count]) } : undefined}
              >
                {dist.loading && !dist.data && <Loading />}
                {dist.error && <ErrorState error={dist.error} onRetry={dist.reload} />}
                {dist.data && (
                  <>
                    <ColumnChart data={dist.data.dataDistribution.map((d) => ({ label: d.label, count: d.count, highlight: d.isUnlimited }))} height={230} />
                    <ul className="legend">
                      <li><span className="swatch s1" /> Data chiffrée</li>
                      <li><span className="swatch s2" /> Illimité</li>
                    </ul>
                  </>
                )}
              </ChartCard>
            </div>
          </div>

          <div className="grid two">
            <ChartCard title="Durée de validité" table={dist.data ? { headers: ['Validité', 'Produits'], rows: dist.data.validityDistribution.map((d) => [d.label, d.count]) } : undefined}>
              {dist.data && <ColumnChart data={dist.data.validityDistribution} height={200} />}
            </ChartCard>
            <ChartCard title="Réseau" table={dist.data ? { headers: ['Réseau', 'Produits'], rows: dist.data.networkDistribution.map((d) => [d.label, d.count]) } : undefined}>
              {dist.data && <ColumnChart data={dist.data.networkDistribution} height={200} />}
            </ChartCard>
          </div>

          <ProductsTable providers={(providers.data ?? []).map((p) => p.provider).sort((a, b) => a.localeCompare(b))} />
        </>
      )}

      <footer className="muted">Chiffres calculés par l&apos;API à partir de PostgreSQL · Prix moyen = moyenne arithmétique de tous les produits · Data moyenne = offres chiffrées uniquement.</footer>
    </div>
  )
}
