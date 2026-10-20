import type { ReactNode } from 'react'

export function Loading({ label = 'Chargement…' }: { label?: string }) {
  return <div className="state" role="status" aria-live="polite"><span className="spinner" aria-hidden />{label}</div>
}

export function ErrorState({ error, onRetry }: { error: Error; onRetry: () => void }) {
  return (
    <div className="state state-error" role="alert">
      <strong>Impossible de charger les données.</strong>
      <span>{error.message}</span>
      <button onClick={onRetry}>Réessayer</button>
    </div>
  )
}

export function EmptyState({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="state state-empty">
      <strong>{title}</strong>
      {children && <span>{children}</span>}
    </div>
  )
}
