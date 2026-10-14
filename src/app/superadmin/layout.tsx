// src/app/superadmin/layout.tsx
// Layout exclusivo de SuperAdmin
import type { ReactNode } from 'react'

export default function SuperAdminLayout({ children }: { children: ReactNode }) {
  return (
    <div className="superadmin-layout">
      {/* TODO: Sidebar y Navbar de SuperAdmin */}
      <main>{children}</main>
    </div>
  )
}
