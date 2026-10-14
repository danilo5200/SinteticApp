// src/app/admin/layout.tsx
// Layout exclusivo de Admins de Canchas
import type { ReactNode } from 'react'

export default function AdminLayout({ children }: { children: ReactNode }) {
  return (
    <div className="admin-layout">
      {/* TODO: Sidebar y Navbar de Admin */}
      <main>{children}</main>
    </div>
  )
}
