// ============================================================
//  SinteticApp — Definiciones de tipos globales TypeScript
// ============================================================

// ----------------------------------------------------------
// Roles de usuario
// ----------------------------------------------------------
export type UserRole = 'superadmin' | 'admin' | 'cliente'

// ----------------------------------------------------------
// Usuario / Perfil
// ----------------------------------------------------------
export interface UserProfile {
  id: string
  email: string
  full_name: string
  avatar_url?: string
  role: UserRole
  created_at: string
}

// ----------------------------------------------------------
// Complejo deportivo
// ----------------------------------------------------------
export interface Complex {
  id: string
  name: string
  address: string
  city: string
  phone?: string
  image_url?: string
  admin_id: string
  is_active: boolean
  subscription_expires_at?: string
  created_at: string
}

// ----------------------------------------------------------
// Cancha
// ----------------------------------------------------------
export type CourtSurface = 'cesped' | 'cemento' | 'sintético' | 'madera'
export type CourtSport = 'futbol' | 'tenis' | 'padel' | 'basquet' | 'voley'

export interface Court {
  id: string
  complex_id: string
  name: string
  sport: CourtSport
  surface: CourtSurface
  price_per_hour: number
  image_url?: string
  is_active: boolean
  created_at: string
}

// ----------------------------------------------------------
// Reserva
// ----------------------------------------------------------
export type BookingStatus = 'pendiente' | 'confirmada' | 'cancelada' | 'completada'

export interface Booking {
  id: string
  court_id: string
  user_id: string
  date: string          // ISO date string: 'YYYY-MM-DD'
  start_time: string    // 'HH:mm'
  end_time: string      // 'HH:mm'
  status: BookingStatus
  total_price: number
  notes?: string
  created_at: string
}

// ----------------------------------------------------------
// Horario disponible
// ----------------------------------------------------------
export interface Schedule {
  id: string
  court_id: string
  day_of_week: number   // 0=Domingo … 6=Sábado
  open_time: string     // 'HH:mm'
  close_time: string    // 'HH:mm'
  slot_duration: number // minutos (ej: 60, 90)
}

// ----------------------------------------------------------
// Notificación Push
// ----------------------------------------------------------
export interface PushSubscriptionPayload {
  endpoint: string
  keys: {
    p256dh: string
    auth: string
  }
}

// ----------------------------------------------------------
// API responses
// ----------------------------------------------------------
export interface ApiResponse<T = unknown> {
  data: T | null
  error: string | null
}
