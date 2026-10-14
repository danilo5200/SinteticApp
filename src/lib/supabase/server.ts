import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'

/**
 * Crea un cliente de Supabase para uso en el servidor (Server Components, Server Actions, Route Handlers).
 * Utiliza createServerClient de @supabase/ssr con manejo de cookies de Next.js.
 */
export async function createClient() {
  const cookieStore = await cookies()

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll()
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            )
          } catch {
            // El método setAll es llamado desde un Server Component.
            // Puede ignorarse si hay middleware actualizando las cookies de sesión.
          }
        },
      },
    }
  )
}
