import { useEffect } from 'react'
import './App.css'
import { CUSTOMER_BRAND_NAME } from './config/presentation.ts'
import { LoginPage } from './features/auth/LoginPage.tsx'
import { getStaffRedirectPath } from './features/auth/staffRoute.ts'
import { useStaffAuth } from './features/auth/useStaffAuth.ts'
import { PublicGiftPage } from './features/gifts/PublicGiftPage.tsx'
import { StaffGiftPage } from './features/gifts/StaffGiftPage.tsx'
import { getGiftTokenFromPath } from './features/gifts/giftPresentation.ts'
import { StaffRedemptionPage } from './features/rewards/StaffRedemptionPage.tsx'

function StaffApplication() {
  const auth = useStaffAuth()

  useEffect(() => {
    const targetPath = getStaffRedirectPath(window.location.pathname, auth.status)
    if (targetPath) {
      window.history.replaceState(null, '', targetPath)
    }
  }, [auth.status])

  if (auth.status === 'configuration-error') {
    return (
      <main className="state-shell">
        <section className="state-card" role="alert">
          <p className="eyebrow">{CUSTOMER_BRAND_NAME}</p>
          <h1>Chưa thể khởi động ứng dụng</h1>
          <p>{auth.configurationError}</p>
          <p className="state-note">Vui lòng kiểm tra cấu hình môi trường dành cho máy này.</p>
        </section>
      </main>
    )
  }

  if (auth.status === 'loading' || (auth.status === 'checking' && auth.email)) {
    return (
      <main className="state-shell" aria-busy="true">
        <section className="state-card state-card--centered">
          <span className="loading-dot" aria-hidden="true" />
          <h1>Đang kiểm tra phiên làm việc…</h1>
          <p>Vui lòng chờ trong giây lát.</p>
        </section>
      </main>
    )
  }

  if (auth.status === 'connection-error') {
    return (
      <main className="state-shell">
        <section className="state-card" role="alert">
          <p className="eyebrow">{CUSTOMER_BRAND_NAME}</p>
          <h1>Chưa thể kiểm tra quyền truy cập</h1>
          <p>{auth.notice}</p>
          <div className="button-row">
            <button className="button button--primary" type="button" onClick={() => void auth.retryAuthorization()}>
              Thử lại
            </button>
            <button className="button button--quiet" type="button" onClick={() => void auth.signOut()}>
              Đăng xuất
            </button>
          </div>
        </section>
      </main>
    )
  }

  if (auth.status === 'authorized' && auth.role) {
    const staffProps = {
      email: auth.email,
      role: auth.role,
      onLogout: () => auth.signOut(),
      onUnauthorized: () => auth.signOut(
        'Phiên làm việc không còn quyền Staff/Admin. Vui lòng đăng nhập lại hoặc báo quản lý.',
      ),
    }

    if (window.location.pathname === '/staff/redeem') {
      return <StaffRedemptionPage {...staffProps} />
    }

    return (
      <StaffGiftPage {...staffProps} />
    )
  }

  return (
    <LoginPage
      busy={auth.status === 'checking'}
      notice={auth.notice}
      onSubmit={auth.signIn}
    />
  )
}

function App() {
  const giftToken = getGiftTokenFromPath(window.location.pathname)

  if (giftToken !== null) {
    return <PublicGiftPage giftToken={giftToken} />
  }

  return <StaffApplication />
}

export default App
