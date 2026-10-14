import { createClient } from '@/lib/supabase/server'
import type { UserProfile, UserRole } from '@/types'

/**
 * Métodos de autenticación y gestión de roles.
 */

/** Obtiene el perfil del usuario activo desde la sesión de Supabase */
export async function getCurrentUserProfile(): Promise<UserProfile | null> {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return null

  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', user.id)
    .single()

  if (error) {
    console.error('[Auth] Error fetching profile:', error.message)
    return null
  }
  return data as UserProfile
}

/** Retorna el rol del usuario actual */
export async function getUserRole(): Promise<UserRole | null> {
  const profile = await getCurrentUserProfile()
  return profile?.role ?? null
}

/** Cierra la sesión del usuario */
export async function signOut() {
  const supabase = await createClient()
  return supabase.auth.signOut()
}
