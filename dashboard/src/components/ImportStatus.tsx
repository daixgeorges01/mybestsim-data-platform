import { fmtDate, fmtInt } from '../services/format'
import type { LatestImport } from '../types/api'

const LABEL: Record<string, string> = { SUCCESS: 'Réussi', PARTIAL: 'Partiel', FAILED: 'Échec', RUNNING: 'En cours' }
const ICON: Record<string, string> = { SUCCESS: '✓', PARTIAL: '!', FAILED: '✕', RUNNING: '…' }

export function ImportStatus({ latest }: { latest: LatestImport }) {
  if (!latest.hasImport) {
    return <p className="import-line muted">Aucun import n&apos;a encore été exécuté.</p>
  }
  const status = latest.status ?? 'RUNNING'
  return (
    <details className="import-line">
      <summary>
        <span className={`pill pill-${status.toLowerCase()}`}><span aria-hidden>{ICON[status]}</span> {LABEL[status] ?? status}</span>
        {' '}Dernier import : {fmtDate(latest.finishedAt ?? latest.startedAt)} · {latest.filesCount} fichier(s) ·{' '}
        {fmtInt(latest.rowsRead)} lignes lues, {fmtInt(latest.rowsInserted)} ajoutées, {fmtInt(latest.rowsUpdated)} mises à jour, {fmtInt(latest.rowsRejected)} rejetées
      </summary>
      <table>
        <thead><tr><th>Fichier</th><th>Statut</th><th>Lues</th><th>Ajoutées</th><th>MàJ</th><th>Rejetées</th><th>Message</th></tr></thead>
        <tbody>
          {latest.runs.map((r) => (
            <tr key={r.sourceFile}>
              <td>{r.sourceFile}</td><td>{LABEL[r.status]}</td><td>{r.rowsRead}</td><td>{r.rowsInserted}</td>
              <td>{r.rowsUpdated}</td><td>{r.rowsRejected}</td><td>{r.errorMessage ?? ''}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </details>
  )
}
