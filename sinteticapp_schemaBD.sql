-- =====================================================================
-- SinteticApp - Esquema maestro definitivo (PostgreSQL / Supabase)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Extensiones
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA extensions;

-- ---------------------------------------------------------------------
-- 1. Tipo ENUM para roles (RBAC)
-- ---------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
    CREATE TYPE public.user_role AS ENUM ('superadmin', 'cancha_admin', 'cliente');
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 2. Tablas
-- ---------------------------------------------------------------------

-- 2.1 Perfiles
CREATE TABLE public.profiles (
  id          UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  role        public.user_role DEFAULT 'cliente' NOT NULL,
  full_name   TEXT,
  phone       TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- 2.2 Complejos deportivos
CREATE TABLE public.complexes (
  id                            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  owner_id                      UUID REFERENCES public.profiles(id) ON DELETE RESTRICT NOT NULL,
  nombre_complejo                 TEXT NOT NULL,
  direccion                     TEXT NOT NULL,
  ciudad                        TEXT NOT NULL,
  telefono_contacto             TEXT,
  timezone                      TEXT NOT NULL DEFAULT 'America/Bogota',
  hora_apertura                 TIME NOT NULL DEFAULT '08:00:00',
  hora_cierre                   TIME NOT NULL DEFAULT '22:00:00',
  status                        TEXT NOT NULL DEFAULT 'activo' CHECK (status IN ('activo', 'suspendido')),
  fecha_vencimiento_suscripcion DATE,
  created_at                    TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- 2.3 Canchas
CREATE TABLE public.courts (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  complex_id      UUID REFERENCES public.complexes(id) ON DELETE RESTRICT NOT NULL,
  nombre          TEXT NOT NULL,
  precio_por_hora NUMERIC(10,2) NOT NULL CHECK (precio_por_hora > 0),
  tipo_grama      TEXT,
  capacidad       INT CHECK (capacidad IS NULL OR capacidad > 0),
  estado          TEXT NOT NULL DEFAULT 'disponible' CHECK (estado IN ('disponible', 'mantenimiento', 'inactiva')),
  created_at      TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  CONSTRAINT courts_nombre_unico_por_complejo UNIQUE (complex_id, nombre)
);

-- 2.4 Reservas
CREATE TABLE public.bookings (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  court_id        UUID REFERENCES public.courts(id) ON DELETE RESTRICT NOT NULL,
  client_id       UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  inicio_reserva  TIMESTAMPTZ NOT NULL,
  fin_reserva     TIMESTAMPTZ NOT NULL,
  precio_total    NUMERIC(10,2) NOT NULL CHECK (precio_total >= 0),
  status_pago     TEXT NOT NULL DEFAULT 'pendiente' 
                  CHECK (status_pago IN ('pendiente', 'pagado_presencial', 'pagado_online', 'cancelado')),
  expira_en       TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW() NOT NULL,

  CONSTRAINT tiempo_logico CHECK (fin_reserva > inicio_reserva),
  CONSTRAINT expira_solo_pendiente CHECK (expira_en IS NULL OR status_pago = 'pendiente'),

  CONSTRAINT prevencion_doble_reserva EXCLUDE USING gist (
    court_id WITH =,
    tstzrange(inicio_reserva, fin_reserva) WITH &&
  ) WHERE (status_pago <> 'cancelado')
);

-- ---------------------------------------------------------------------
-- 3. Índices
-- ---------------------------------------------------------------------
CREATE INDEX idx_complexes_owner_id   ON public.complexes (owner_id);
CREATE INDEX idx_complexes_status     ON public.complexes (status);
CREATE INDEX idx_courts_complex_id    ON public.courts (complex_id);
CREATE INDEX idx_bookings_client_id   ON public.bookings (client_id);
CREATE INDEX idx_bookings_inicio      ON public.bookings (inicio_reserva);
CREATE INDEX idx_bookings_pendientes_expiran
  ON public.bookings (expira_en)
  WHERE status_pago = 'pendiente' AND expira_en IS NOT NULL;

-- ---------------------------------------------------------------------
-- 4. Funciones auxiliares de autorización
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS public.user_role
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT role FROM public.profiles WHERE id = (SELECT auth.uid())
$$;

CREATE OR REPLACE FUNCTION public.is_superadmin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT COALESCE(public.current_user_role() = 'superadmin', false)
$$;

CREATE OR REPLACE FUNCTION public.owns_complex(p_complex_id UUID)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT public.current_user_role() = 'cancha_admin'
     AND EXISTS (
       SELECT 1 FROM public.complexes cx
       WHERE cx.id = p_complex_id AND cx.owner_id = (SELECT auth.uid())
     )
$$;

CREATE OR REPLACE FUNCTION public.owns_court(p_court_id UUID)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT public.current_user_role() = 'cancha_admin'
     AND EXISTS (
       SELECT 1
       FROM public.courts ct
       JOIN public.complexes cx ON cx.id = ct.complex_id
       WHERE ct.id = p_court_id AND cx.owner_id = (SELECT auth.uid())
     )
$$;

CREATE OR REPLACE FUNCTION public.admin_can_see_profile(p_profile_id UUID)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT public.current_user_role() = 'cancha_admin'
     AND EXISTS (
       SELECT 1
       FROM public.bookings b
       JOIN public.courts ct    ON ct.id = b.court_id
       JOIN public.complexes cx ON cx.id = ct.complex_id
       WHERE b.client_id = p_profile_id AND cx.owner_id = (SELECT auth.uid())
     )
$$;

-- ---------------------------------------------------------------------
-- 5. Creación automática del perfil
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, phone, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'phone', ''),
    'cliente'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ---------------------------------------------------------------------
-- 6. Triggers de integridad y protección
-- ---------------------------------------------------------------------

-- 6.1 Impedir que un usuario cambie su propio rol
CREATE OR REPLACE FUNCTION public.prevent_role_change()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role
     AND auth.uid() IS NOT NULL
     AND NOT public.is_superadmin() THEN
    RAISE EXCEPTION 'No tienes permiso para cambiar el rol' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_role_change ON public.profiles;
CREATE TRIGGER trg_prevent_role_change
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.prevent_role_change();

-- 6.2 Validación de complejos
CREATE OR REPLACE FUNCTION public.validate_complex()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = NEW.timezone) THEN
    RAISE EXCEPTION 'Zona horaria inválida: %', NEW.timezone USING ERRCODE = '22023';
  END IF;

  IF TG_OP = 'INSERT' OR NEW.owner_id IS DISTINCT FROM OLD.owner_id THEN
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = NEW.owner_id AND role = 'cancha_admin') THEN
      RAISE EXCEPTION 'El dueño del complejo debe tener el rol cancha_admin' USING ERRCODE = '23514';
    END IF;
  END IF;

  IF TG_OP = 'UPDATE'
     AND auth.uid() IS NOT NULL
     AND NOT public.is_superadmin()
     AND (   NEW.owner_id IS DISTINCT FROM OLD.owner_id
          OR NEW.status IS DISTINCT FROM OLD.status
          OR NEW.fecha_vencimiento_suscripcion IS DISTINCT FROM OLD.fecha_vencimiento_suscripcion) THEN
    RAISE EXCEPTION 'Solo un superadmin puede modificar dueño, estado o suscripción' USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_complex ON public.complexes;
CREATE TRIGGER trg_validate_complex
  BEFORE INSERT OR UPDATE ON public.complexes
  FOR EACH ROW EXECUTE FUNCTION public.validate_complex();

-- 6.3 Validación de reservas optimizada (Con v_retro y v_tarifa)
CREATE OR REPLACE FUNCTION public.validate_booking()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_court        RECORD;
  v_minutos      NUMERIC;
  v_local_start  TIMESTAMP;
  v_local_end    TIMESTAMP;
  v_dur          INTERVAL;
  v_open         TIMESTAMP;
  v_offset       INT;
  v_ok           BOOLEAN := false;
  v_retro        BOOLEAN := false;
  v_tarifa       NUMERIC;
BEGIN
  IF TG_OP = 'UPDATE'
     AND NEW.court_id = OLD.court_id
     AND NEW.inicio_reserva = OLD.inicio_reserva
     AND NEW.fin_reserva = OLD.fin_reserva THEN
    RETURN NEW;
  END IF;

  SELECT ct.precio_por_hora,
         ct.estado,
         cx.status AS complejo_status,
         cx.fecha_vencimiento_suscripcion AS vence,
         cx.hora_apertura,
         cx.hora_cierre,
         cx.timezone
    INTO v_court
    FROM public.courts ct
    JOIN public.complexes cx ON cx.id = ct.complex_id
   WHERE ct.id = NEW.court_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La cancha no existe' USING ERRCODE = '23503';
  END IF;

  -- Permite retroactividad para staff/service_role
  v_retro := NEW.inicio_reserva < now() AND (auth.uid() IS NULL OR public.is_superadmin() OR public.owns_court(NEW.court_id));

  IF NEW.inicio_reserva < now() AND NOT v_retro THEN
    RAISE EXCEPTION 'No se puede reservar ni reprogramar en el pasado' USING ERRCODE = '23514';
  END IF;

  -- Si es una reserva en tiempo presente, validamos estado actual
  IF NOT v_retro THEN
    IF v_court.estado <> 'disponible' THEN
      RAISE EXCEPTION 'La cancha no está disponible (estado: %)', v_court.estado USING ERRCODE = '23514';
    END IF;
    IF v_court.complejo_status <> 'activo' THEN
      RAISE EXCEPTION 'El complejo está suspendido' USING ERRCODE = '23514';
    END IF;
    IF v_court.vence IS NOT NULL AND v_court.vence < (now() AT TIME ZONE v_court.timezone)::date THEN
      RAISE EXCEPTION 'La suscripción del complejo está vencida' USING ERRCODE = '23514';
    END IF;
  END IF;

  v_minutos := EXTRACT(EPOCH FROM (NEW.fin_reserva - NEW.inicio_reserva)) / 60;
  IF v_minutos < 30 OR mod(v_minutos, 30) <> 0 THEN
    RAISE EXCEPTION 'La duración debe ser de al menos 30 minutos y en bloques de 30 minutos' USING ERRCODE = '23514';
  END IF;

  -- Validación de horario de operación cruzando medianoche
  v_local_start := NEW.inicio_reserva AT TIME ZONE v_court.timezone;
  v_local_end   := NEW.fin_reserva    AT TIME ZONE v_court.timezone;
  v_dur := CASE
             WHEN v_court.hora_cierre > v_court.hora_apertura THEN v_court.hora_cierre - v_court.hora_apertura
             ELSE v_court.hora_cierre - v_court.hora_apertura + INTERVAL '24 hours'
           END;

  FOR v_offset IN 0..1 LOOP
    v_open := (v_local_start::date - v_offset) + v_court.hora_apertura;
    IF v_local_start >= v_open AND v_local_end <= v_open + v_dur THEN
      v_ok := true;
      EXIT;
    END IF;
  END LOOP;

  IF NOT v_ok THEN
    RAISE EXCEPTION 'La reserva está fuera del horario de operación del complejo (% - %)',
      v_court.hora_apertura, v_court.hora_cierre USING ERRCODE = '23514';
  END IF;

  -- Conservar tarifa original en caso de reprogramación de la misma cancha
  IF TG_OP = 'UPDATE' AND NEW.court_id = OLD.court_id THEN
    v_tarifa := OLD.precio_total / (EXTRACT(EPOCH FROM (OLD.fin_reserva - OLD.inicio_reserva)) / 3600);
  ELSE
    v_tarifa := v_court.precio_por_hora;
  END IF;

  NEW.precio_total := round(v_tarifa * v_minutos / 60, 2);

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_booking ON public.bookings;
CREATE TRIGGER trg_validate_booking
  BEFORE INSERT OR UPDATE ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public.validate_booking();

-- ---------------------------------------------------------------------
-- 7. Funciones RPC
-- ---------------------------------------------------------------------

-- 7.1 Crear reserva (Incluye soporte para estado de pago inicial)
CREATE OR REPLACE FUNCTION public.create_booking(
  p_court_id    UUID,
  p_inicio      TIMESTAMPTZ,
  p_fin         TIMESTAMPTZ,
  p_client_id   UUID DEFAULT NULL,
  p_status_pago TEXT DEFAULT 'pendiente'
)
RETURNS public.bookings
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid       UUID := auth.uid();
  v_client    UUID;
  v_por_staff BOOLEAN := false;
  v_booking   public.bookings;
BEGIN
  IF v_uid IS NULL THEN
    v_por_staff := true;
  END IF;

  v_client := COALESCE(p_client_id, v_uid);

  IF v_uid IS NOT NULL AND (public.is_superadmin() OR public.owns_court(p_court_id)) THEN
    v_por_staff := true;
  END IF;

  IF v_client IS DISTINCT FROM v_uid AND NOT v_por_staff THEN
    RAISE EXCEPTION 'No tienes permiso para reservar a nombre de otro usuario' USING ERRCODE = '42501';
  END IF;

  IF v_client IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_client) THEN
    RAISE EXCEPTION 'El cliente indicado no existe' USING ERRCODE = '23503';
  END IF;

  IF p_status_pago <> 'pendiente' AND NOT v_por_staff THEN
    RAISE EXCEPTION 'No tienes permiso para establecer estados de pago iniciales' USING ERRCODE = '42501';
  END IF;

  UPDATE public.bookings
     SET status_pago = 'cancelado', expira_en = NULL
   WHERE court_id = p_court_id
     AND status_pago = 'pendiente'
     AND expira_en IS NOT NULL
     AND expira_en < now()
     AND tstzrange(inicio_reserva, fin_reserva) && tstzrange(p_inicio, p_fin);

  INSERT INTO public.bookings (
    court_id, client_id, inicio_reserva, fin_reserva, precio_total, status_pago, expira_en
  )
  VALUES (
    p_court_id, v_client, p_inicio, p_fin, 0, p_status_pago,
    CASE WHEN v_por_staff OR p_status_pago <> 'pendiente' THEN NULL ELSE now() + INTERVAL '30 minutes' END
  )
  RETURNING * INTO v_booking;

  RETURN v_booking;
EXCEPTION
  WHEN exclusion_violation THEN
    RAISE EXCEPTION 'Ese horario ya está reservado' USING ERRCODE = '23P01';
END;
$$;

-- 7.2 Cancelar reserva
CREATE OR REPLACE FUNCTION public.cancel_booking(p_booking_id UUID)
RETURNS public.bookings
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid             UUID := auth.uid();
  v_booking         public.bookings;
  v_min_anticipacion INTERVAL := INTERVAL '2 hours';
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Debes iniciar sesión' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_booking FROM public.bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reserva no encontrada' USING ERRCODE = 'P0002';
  END IF;

  IF v_booking.status_pago = 'cancelado' THEN
    RAISE EXCEPTION 'La reserva ya está cancelada' USING ERRCODE = '23514';
  END IF;

  IF NOT (public.is_superadmin() OR public.owns_court(v_booking.court_id)) THEN
    IF v_booking.client_id IS DISTINCT FROM v_uid THEN
      RAISE EXCEPTION 'Reserva no encontrada' USING ERRCODE = 'P0002';
    END IF;
    IF v_booking.inicio_reserva < now() + v_min_anticipacion THEN
      RAISE EXCEPTION 'Solo puedes cancelar con al menos % de anticipación', v_min_anticipacion
        USING ERRCODE = '23514';
    END IF;
  END IF;

  UPDATE public.bookings
     SET status_pago = 'cancelado', expira_en = NULL
   WHERE id = p_booking_id
  RETURNING * INTO v_booking;

  RETURN v_booking;
END;
$$;

-- 7.3 Cambiar estado de pago
CREATE OR REPLACE FUNCTION public.set_booking_payment_status(p_booking_id UUID, p_status TEXT)
RETURNS public.bookings
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_booking public.bookings;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Debes iniciar sesión' USING ERRCODE = '28000';
  END IF;

  IF p_status NOT IN ('pendiente', 'pagado_presencial', 'pagado_online') THEN
    RAISE EXCEPTION 'Estado de pago inválido' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_booking FROM public.bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND OR NOT (public.is_superadmin() OR public.owns_court(v_booking.court_id)) THEN
    RAISE EXCEPTION 'Reserva no encontrada' USING ERRCODE = 'P0002';
  END IF;

  IF v_booking.status_pago = 'cancelado' THEN
    RAISE EXCEPTION 'No se puede modificar una reserva cancelada' USING ERRCODE = '23514';
  END IF;

  UPDATE public.bookings
     SET status_pago = p_status, expira_en = NULL
   WHERE id = p_booking_id
  RETURNING * INTO v_booking;

  RETURN v_booking;
END;
$$;

-- 7.4 Disponibilidad pública de una cancha
CREATE OR REPLACE FUNCTION public.get_court_availability(
  p_court_id UUID,
  p_desde    TIMESTAMPTZ,
  p_hasta    TIMESTAMPTZ
)
RETURNS TABLE (inicio_reserva TIMESTAMPTZ, fin_reserva TIMESTAMPTZ)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT b.inicio_reserva, b.fin_reserva
  FROM public.bookings b
  JOIN public.courts ct    ON ct.id = b.court_id
  JOIN public.complexes cx ON cx.id = ct.complex_id
  WHERE b.court_id = p_court_id
    AND cx.status = 'activo'
    AND b.status_pago <> 'cancelado'
    AND NOT (b.status_pago = 'pendiente' AND b.expira_en IS NOT NULL AND b.expira_en < now())
    AND tstzrange(b.inicio_reserva, b.fin_reserva) && tstzrange(p_desde, p_hasta)
  ORDER BY b.inicio_reserva
$$;

-- ---------------------------------------------------------------------
-- 8. Funciones de mantenimiento (cron)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expire_pending_bookings()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE public.bookings
     SET status_pago = 'cancelado', expira_en = NULL
   WHERE status_pago = 'pendiente'
     AND expira_en IS NOT NULL
     AND expira_en < now();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.suspend_expired_complexes()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE public.complexes
     SET status = 'suspendido'
   WHERE status = 'activo'
     AND fecha_vencimiento_suscripcion IS NOT NULL
     AND fecha_vencimiento_suscripcion < (now() AT TIME ZONE timezone)::date;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- ---------------------------------------------------------------------
-- 9. Permisos de ejecución
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION
  public.handle_new_user(),
  public.prevent_role_change(),
  public.validate_complex(),
  public.validate_booking(),
  public.expire_pending_bookings(),
  public.suspend_expired_complexes()
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION
  public.current_user_role(),
  public.is_superadmin(),
  public.owns_complex(UUID),
  public.owns_court(UUID),
  public.admin_can_see_profile(UUID),
  public.create_booking(UUID, TIMESTAMPTZ, TIMESTAMPTZ, UUID, TEXT),
  public.cancel_booking(UUID),
  public.set_booking_payment_status(UUID, TEXT),
  public.get_court_availability(UUID, TIMESTAMPTZ, TIMESTAMPTZ)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
  public.current_user_role(),
  public.is_superadmin(),
  public.owns_complex(UUID),
  public.owns_court(UUID),
  public.admin_can_see_profile(UUID),
  public.create_booking(UUID, TIMESTAMPTZ, TIMESTAMPTZ, UUID, TEXT),
  public.cancel_booking(UUID),
  public.set_booking_payment_status(UUID, TEXT)
TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_court_availability(UUID, TIMESTAMPTZ, TIMESTAMPTZ)
TO anon, authenticated;

-- ---------------------------------------------------------------------
-- 10. Row Level Security
-- ---------------------------------------------------------------------
ALTER TABLE public.profiles   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.complexes  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courts     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookings   ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles: ver el propio" ON public.profiles FOR SELECT TO authenticated USING (id = (SELECT auth.uid()));
CREATE POLICY "profiles: superadmin ve todos" ON public.profiles FOR SELECT TO authenticated USING (public.is_superadmin());
CREATE POLICY "profiles: admin ve a los clientes de sus canchas" ON public.profiles FOR SELECT TO authenticated USING (public.admin_can_see_profile(id));
CREATE POLICY "profiles: editar el propio" ON public.profiles FOR UPDATE TO authenticated USING (id = (SELECT auth.uid())) WITH CHECK (id = (SELECT auth.uid()));
CREATE POLICY "profiles: superadmin edita todos" ON public.profiles FOR UPDATE TO authenticated USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());

CREATE POLICY "complexes: lectura pública de activos" ON public.complexes FOR SELECT TO anon, authenticated USING (status = 'activo');
CREATE POLICY "complexes: dueño y superadmin ven los suyos" ON public.complexes FOR SELECT TO authenticated USING (public.is_superadmin() OR public.owns_complex(id));
CREATE POLICY "complexes: solo superadmin crea" ON public.complexes FOR INSERT TO authenticated WITH CHECK (public.is_superadmin());
CREATE POLICY "complexes: dueño o superadmin actualizan" ON public.complexes FOR UPDATE TO authenticated USING (public.is_superadmin() OR public.owns_complex(id)) WITH CHECK (public.is_superadmin() OR public.owns_complex(id));
CREATE POLICY "complexes: solo superadmin elimina" ON public.complexes FOR DELETE TO authenticated USING (public.is_superadmin());

CREATE POLICY "courts: lectura pública (no inactivas, complejo activo)" ON public.courts FOR SELECT TO anon, authenticated USING (estado <> 'inactiva' AND EXISTS (SELECT 1 FROM public.complexes cx WHERE cx.id = courts.complex_id AND cx.status = 'activo'));
CREATE POLICY "courts: dueño y superadmin ven todas las suyas" ON public.courts FOR SELECT TO authenticated USING (public.is_superadmin() OR public.owns_complex(complex_id));
CREATE POLICY "courts: dueño o superadmin crean" ON public.courts FOR INSERT TO authenticated WITH CHECK (public.is_superadmin() OR public.owns_complex(complex_id));
CREATE POLICY "courts: dueño o superadmin actualizan" ON public.courts FOR UPDATE TO authenticated USING (public.is_superadmin() OR public.owns_complex(complex_id)) WITH CHECK (public.is_superadmin() OR public.owns_complex(complex_id));
CREATE POLICY "courts: dueño o superadmin eliminan" ON public.courts FOR DELETE TO authenticated USING (public.is_superadmin() OR public.owns_complex(complex_id));

CREATE POLICY "bookings: cliente ve las suyas" ON public.bookings FOR SELECT TO authenticated USING (client_id = (SELECT auth.uid()));
CREATE POLICY "bookings: admin ve las de sus canchas, superadmin todas" ON public.bookings FOR SELECT TO authenticated USING (public.is_superadmin() OR public.owns_court(court_id));

-- ---------------------------------------------------------------------
-- 11. Jobs programados (pg_cron)
-- ---------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule('expirar-reservas-pendientes', '* * * * *',
                          'SELECT public.expire_pending_bookings()');
    PERFORM cron.schedule('suspender-complejos-vencidos', '5 0 * * *',
                          'SELECT public.suspend_expired_complexes()');
  ELSE
    RAISE NOTICE 'pg_cron no está activo. Habilítalo en el Dashboard si deseas usar tareas programadas.';
  END IF;
END $$;
-- =====================================================================