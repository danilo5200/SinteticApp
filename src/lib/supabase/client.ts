import { createBrowserClient } from '@supabase/ssr'

/**
 * Crea un cliente de Supabase para uso en el navegador (Client Components).
 * Utiliza createBrowserClient de @supabase/ssr para manejo automático de cookies.
 */
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  )
}
