import { createClient } from '@supabase/supabase-js'

function isValidProjectUrl(value: string) {
  try {
    const url = new URL(value)
    return url.protocol === 'https:' || url.hostname === 'localhost' || url.hostname === '127.0.0.1'
  } catch {
    return false
  }
}

function isBrowserSafeKey(value: string, projectUrl: string) {
  if (value.startsWith('sb_publishable_')) {
    return true
  }

  if (value.startsWith('sb_secret_')) {
    return false
  }

  const payload = value.split('.')[1]
  if (!payload) {
    const hostname = new URL(projectUrl).hostname
    return hostname === 'localhost' || hostname === '127.0.0.1'
  }

  try {
    const normalized = payload.replace(/-/g, '+').replace(/_/g, '/')
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=')
    const parsed = JSON.parse(atob(padded)) as { role?: string }
    return parsed.role === 'anon'
  } catch {
    return false
  }
}

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL?.trim() ?? ''
const publishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim() ?? ''

export const supabaseConfigurationError = (() => {
  if (!supabaseUrl || !publishableKey) {
    return 'Ứng dụng chưa được cấu hình kết nối Supabase.'
  }

  if (!isValidProjectUrl(supabaseUrl)) {
    return 'Địa chỉ Supabase không hợp lệ.'
  }

  if (!isBrowserSafeKey(publishableKey, supabaseUrl)) {
    return 'Ứng dụng đang dùng khóa không an toàn cho trình duyệt.'
  }

  return null
})()

export const supabase = supabaseConfigurationError
  ? null
  : createClient(supabaseUrl, publishableKey, {
      db: { schema: 'api' },
      auth: {
        autoRefreshToken: true,
        detectSessionInUrl: false,
        persistSession: true,
      },
    })

export type ChicSupabaseClient = NonNullable<typeof supabase>

export function getPublicAppUrl() {
  const configuredUrl = import.meta.env.VITE_PUBLIC_APP_URL?.trim()
  return (configuredUrl || window.location.origin).replace(/\/+$/, '')
}
