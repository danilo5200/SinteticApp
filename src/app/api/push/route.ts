import { NextRequest, NextResponse } from 'next/server'

/**
 * POST /api/push
 * Webhook / endpoint para envío de notificaciones Web Push.
 */
export async function POST(request: NextRequest) {
  try {
    // TODO: Implementar envío de push con web-push
    const body = await request.json()
    console.log('[Push] Received payload:', body)

    return NextResponse.json({ success: true })
  } catch (error) {
    console.error('[Push] Error:', error)
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 })
  }
}
