import type { PushSubscriptionPayload } from '@/types'

/**
 * Lógica para Notificaciones Web Push.
 * Requiere la librería `web-push` instalada en el servidor.
 *
 * TODO: npm install web-push && npm install -D @types/web-push
 */

// const webpush = require('web-push') — descomenta al instalar web-push

/**
 * Configura las claves VAPID (llamar una vez al inicializar el servidor)
 */
export function configureWebPush() {
  // webpush.setVapidDetails(
  //   process.env.VAPID_SUBJECT!,
  //   process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY!,
  //   process.env.VAPID_PRIVATE_KEY!
  // )
  console.warn('[Push] web-push not yet configured. Install web-push package first.')
}

/**
 * Envía una notificación push a una suscripción dada
 */
export async function sendPushNotification(
  subscription: PushSubscriptionPayload,
  payload: { title: string; body: string; url?: string }
) {
  try {
    // await webpush.sendNotification(subscription, JSON.stringify(payload))
    console.log('[Push] Would send notification:', payload)
    return { success: true }
  } catch (error) {
    console.error('[Push] Error sending notification:', error)
    return { success: false, error }
  }
}
