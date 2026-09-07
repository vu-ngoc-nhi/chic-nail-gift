import { useCallback, useEffect, useRef, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase, supabaseConfigurationError } from '../../lib/supabase.ts'

export type StaffRole = 'STAFF' | 'ADMIN'
export type StaffAuthStatus =
  | 'loading'
  | 'signed-out'
  | 'checking'
  | 'authorized'
  | 'connection-error'
  | 'configuration-error'

type StaffAccessRow = {
  authorized: boolean
  staff_role: StaffRole
}

const INVALID_LOGIN_MESSAGE = 'Email hoặc mật khẩu không đúng. Vui lòng thử lại.'
const UNAUTHORIZED_MESSAGE =
  'Tài khoản này chưa được cấp quyền Staff/Admin hoặc đã ngừng hoạt động. Vui lòng báo quản lý.'
const CONNECTION_MESSAGE =
  'Không thể kiểm tra quyền truy cập. Vui lòng kiểm tra kết nối và thử lại.'

export function useStaffAuth() {
  const [status, setStatus] = useState<StaffAuthStatus>(
    supabaseConfigurationError ? 'configuration-error' : 'loading',
  )
  const [role, setRole] = useState<StaffRole | null>(null)
  const [email, setEmail] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const requestId = useRef(0)

  const clearSession = useCallback(async (message: string | null = null) => {
    requestId.current += 1
    setRole(null)
    setEmail(null)
    setNotice(message)
    setStatus('signed-out')
    if (supabase) {
      await supabase.auth.signOut({ scope: 'local' })
    }
  }, [])

  const verifySession = useCallback(async (session: Session | null) => {
    if (!supabase || !session) {
      await clearSession()
      return
    }

    const currentRequest = ++requestId.current
    setStatus('checking')
    setNotice(null)

    const { data, error } = await supabase.rpc('get_staff_access')
    if (currentRequest !== requestId.current) {
      return
    }

    if (error) {
      setRole(null)
      setEmail(session.user.email ?? null)
      setNotice(CONNECTION_MESSAGE)
      setStatus('connection-error')
      return
    }

    const access = (Array.isArray(data) ? data[0] : data) as StaffAccessRow | undefined
    if (!access?.authorized || !['STAFF', 'ADMIN'].includes(access.staff_role)) {
      await clearSession(UNAUTHORIZED_MESSAGE)
      return
    }

    setRole(access.staff_role)
    setEmail(session.user.email ?? null)
    setStatus('authorized')
  }, [clearSession])

  useEffect(() => {
    if (!supabase) {
      return
    }

    let active = true
    void supabase.auth.getSession().then(({ data, error }) => {
      if (!active) {
        return
      }
      if (error) {
        setNotice(CONNECTION_MESSAGE)
        setStatus('connection-error')
        return
      }
      void verifySession(data.session)
    })

    const { data } = supabase.auth.onAuthStateChange((event, session) => {
      if (!active) {
        return
      }
      if (event === 'SIGNED_OUT') {
        requestId.current += 1
        setRole(null)
        setEmail(null)
        setStatus('signed-out')
      } else if (event === 'TOKEN_REFRESHED') {
        window.setTimeout(() => void verifySession(session), 0)
      }
    })

    return () => {
      active = false
      data.subscription.unsubscribe()
    }
  }, [verifySession])

  const signIn = useCallback(async (loginEmail: string, password: string) => {
    if (!supabase) {
      setStatus('configuration-error')
      return
    }

    setNotice(null)
    setStatus('checking')
    const { data, error } = await supabase.auth.signInWithPassword({
      email: loginEmail.trim(),
      password,
    })

    if (error || !data.session) {
      setStatus('signed-out')
      setNotice(INVALID_LOGIN_MESSAGE)
      return
    }

    await verifySession(data.session)
  }, [verifySession])

  const retryAuthorization = useCallback(async () => {
    if (!supabase) {
      return
    }
    const { data, error } = await supabase.auth.getSession()
    if (error) {
      setNotice(CONNECTION_MESSAGE)
      setStatus('connection-error')
      return
    }
    await verifySession(data.session)
  }, [verifySession])

  return {
    status,
    role,
    email,
    notice,
    configurationError: supabaseConfigurationError,
    signIn,
    signOut: clearSession,
    retryAuthorization,
  }
}
