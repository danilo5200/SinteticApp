// src/app/(cliente)/layout.tsx
// Layout para clientes / jugadores
import type { ReactNode } from 'react'

export default function ClienteLayout({ children }: { children: ReactNode }) {
  return (
    <div className="cliente-layout">
      {/* TODO: Navbar de Cliente */}
      <main>{children}</main>
    </div>
  )
}
