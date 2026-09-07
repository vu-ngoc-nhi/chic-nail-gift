import { useState, type FormEvent } from 'react'

type LoginPageProps = {
  busy: boolean
  notice: string | null
  onSubmit: (email: string, password: string) => Promise<void>
}

export function LoginPage({ busy, notice, onSubmit }: LoginPageProps) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!email.trim() || !password || busy) {
      return
    }
    await onSubmit(email, password)
  }

  return (
    <main className="auth-shell">
      <section className="auth-card" aria-labelledby="login-title">
        <div className="brand-mark" aria-hidden="true">CG</div>
        <h1 id="login-title">Đăng nhập CHIC GIFT</h1>
        <p className="supporting-text">Dành cho nhân viên tạo quà sau khi kiểm tra hóa đơn trên KiotViet.</p>

        <form className="form-stack" onSubmit={handleSubmit} aria-describedby={notice ? 'login-message' : undefined}>
          <div className="field-group">
            <label htmlFor="email">Email</label>
            <input
              id="email"
              name="email"
              type="email"
              autoComplete="username"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              required
              disabled={busy}
            />
          </div>

          <div className="field-group">
            <label htmlFor="password">Mật khẩu</label>
            <input
              id="password"
              name="password"
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              required
              disabled={busy}
            />
          </div>

          {notice && (
            <p id="login-message" className="message message--error" role="alert">
              {notice}
            </p>
          )}

          <button className="button button--primary" type="submit" disabled={busy || !email.trim() || !password}>
            {busy ? 'ĐANG KIỂM TRA…' : 'ĐĂNG NHẬP'}
          </button>
        </form>
      </section>
    </main>
  )
}
