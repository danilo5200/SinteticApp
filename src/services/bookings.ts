import { createClient } from '@/lib/supabase/server'
import type { Booking, ApiResponse } from '@/types'

/**
 * Operaciones de reservas (bookings).
 */

/** Obtiene todas las reservas de un usuario */
export async function getUserBookings(userId: string): Promise<ApiResponse<Booking[]>> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('bookings')
    .select('*')
    .eq('user_id', userId)
    .order('date', { ascending: true })

  return { data: data as Booking[] | null, error: error?.message ?? null }
}

/** Obtiene las reservas de una cancha en una fecha dada */
export async function getCourtBookingsByDate(
  courtId: string,
  date: string
): Promise<ApiResponse<Booking[]>> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('bookings')
    .select('*')
    .eq('court_id', courtId)
    .eq('date', date)

  return { data: data as Booking[] | null, error: error?.message ?? null }
}

/** Crea una nueva reserva */
export async function createBooking(
  booking: Omit<Booking, 'id' | 'created_at'>
): Promise<ApiResponse<Booking>> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('bookings')
    .insert(booking)
    .select()
    .single()

  return { data: data as Booking | null, error: error?.message ?? null }
}

/** Cancela una reserva por ID */
export async function cancelBooking(bookingId: string): Promise<ApiResponse<Booking>> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('bookings')
    .update({ status: 'cancelada' })
    .eq('id', bookingId)
    .select()
    .single()

  return { data: data as Booking | null, error: error?.message ?? null }
}
