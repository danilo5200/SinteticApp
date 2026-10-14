import { createClient } from '@/lib/supabase/server'
import type { Complex, Court, ApiResponse } from '@/types'

/**
 * Operaciones de complejos deportivos y canchas.
 */

/** Lista todos los complejos activos */
export async function getActiveComplexes(): Promise<ApiResponse<Complex[]>> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('complexes')
    .select('*')
    .eq('is_active', true)
    .order('name')

  return { data: data as Complex[] | null, error: error?.message ?? null }
}

/** Obtiene un complejo por ID */
export async function getComplexById(id: string): Promise<ApiResponse<Complex>> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('complexes')
    .select('*')
    .eq('id', id)
    .single()

  return { data: data as Complex | null, error: error?.message ?? null }
}

/** Lista las canchas de un complejo */
export async function getCourtsByComplex(complexId: string): Promise<ApiResponse<Court[]>> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('courts')
    .select('*')
    .eq('complex_id', complexId)
    .eq('is_active', true)

  return { data: data as Court[] | null, error: error?.message ?? null }
}

/** Activa o desactiva la suscripción de un complejo (SuperAdmin) */
export async function toggleComplexSubscription(
  complexId: string,
  isActive: boolean,
  expiresAt?: string
): Promise<ApiResponse<Complex>> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('complexes')
    .update({ is_active: isActive, subscription_expires_at: expiresAt })
    .eq('id', complexId)
    .select()
    .single()

  return { data: data as Complex | null, error: error?.message ?? null }
}
