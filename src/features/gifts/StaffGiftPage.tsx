import { useRef, useState, type FormEvent } from 'react'
import { QRCodeSVG } from 'qrcode.react'
import { CUSTOMER_BRAND_NAME } from '../../config/presentation.ts'
import type { StaffRole } from '../auth/useStaffAuth.ts'
import { getPublicGiftBaseUrl, supabase } from '../../lib/supabase.ts'
import { createGift, GiftOperationError } from './giftOperations.ts'
import {
  amountDigits,
  buildPublicGiftUrl,
  formatAmountInput,
  formatVnd,
  hasInternalWhitespace,
  normalizeBillCode,
  parseVndAmount,
  presentGiftResult,
  type CreateGiftResult,
} from './giftPresentation.ts'

type StaffGiftPageProps = {
  email: string | null
  role: StaffRole
  onLogout: () => Promise<void>
  onUnauthorized: () => Promise<void>
}

type FormErrors = {
  billCode?: string
  billAmount?: string
}

export function StaffGiftPage({ email, role, onLogout, onUnauthorized }: StaffGiftPageProps) {
  const [billCode, setBillCode] = useState('')
  const [billAmount, setBillAmount] = useState('')
  const [errors, setErrors] = useState<FormErrors>({})
  const [result, setResult] = useState<CreateGiftResult | null>(null)
  const [requestError, setRequestError] = useState<string | null>(null)
  const [copyStatus, setCopyStatus] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const billInput = useRef<HTMLInputElement>(null)

  const presentation = result ? presentGiftResult(result) : null
  const publicGiftLink = result?.gift_token
    ? buildPublicGiftUrl(getPublicGiftBaseUrl(), result.gift_token)
    : null

  function validateForm() {
    const nextErrors: FormErrors = {}
    const normalizedCode = normalizeBillCode(billCode)
    const amount = parseVndAmount(billAmount)

    if (!normalizedCode) {
      nextErrors.billCode = 'Vui lòng nhập mã hóa đơn.'
    } else if (hasInternalWhitespace(normalizedCode)) {
      nextErrors.billCode = 'Mã bill có khoảng trắng bất thường. Vui lòng kiểm tra lại trên KiotViet.'
    }

    if (!billAmount) {
      nextErrors.billAmount = 'Vui lòng nhập giá trị hóa đơn.'
    } else if (amount === null) {
      nextErrors.billAmount = 'Giá trị hóa đơn phải lớn hơn 0đ.'
    }

    setErrors(nextErrors)
    return { valid: Object.keys(nextErrors).length === 0, normalizedCode, amount }
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (submitting || !supabase) {
      return
    }

    const validation = validateForm()
    if (!validation.valid || validation.amount === null) {
      return
    }

    setSubmitting(true)
    setRequestError(null)
    setCopyStatus(null)
    setResult(null)

    try {
      const gift = await createGift(supabase, validation.normalizedCode, validation.amount)
      setBillCode(gift.bill_code ?? validation.normalizedCode)
      setResult(gift)
    } catch (error) {
      if (error instanceof GiftOperationError && error.kind === 'unauthorized') {
        await onUnauthorized()
        return
      }
      setRequestError('Không thể tạo quà lúc này. Vui lòng kiểm tra kết nối và thử lại.')
    } finally {
      setSubmitting(false)
    }
  }

  async function copyGiftLink() {
    if (!publicGiftLink) {
      return
    }

    try {
      await navigator.clipboard.writeText(publicGiftLink)
      setCopyStatus('Đã sao chép link quà.')
    } catch {
      setCopyStatus('Không thể sao chép tự động. Vui lòng sao chép link thủ công.')
    }
  }

  function resetForNextBill() {
    setBillCode('')
    setBillAmount('')
    setErrors({})
    setResult(null)
    setRequestError(null)
    setCopyStatus(null)
    window.requestAnimationFrame(() => billInput.current?.focus())
  }

  return (
    <main className="staff-shell">
      <header className="staff-header">
        <div>
          <a className="staff-brand" href="/staff" aria-label={`Trang tạo quà ${CUSTOMER_BRAND_NAME}`}>
            {CUSTOMER_BRAND_NAME}
          </a>
        </div>
        <div className="account-actions">
          <div className="account-summary">
            <span className="role-badge">{role}</span>
            {email && <span className="account-email">{email}</span>}
          </div>
          <button className="button button--quiet" type="button" onClick={() => void onLogout()}>
            Đăng xuất
          </button>
        </div>
      </header>

      <div className="staff-layout">
        <section className="work-card" aria-labelledby="create-gift-title">
          <div className="section-heading">
            <p className="step-label">TẠO QUÀ SAU THANH TOÁN</p>
            <h1 id="create-gift-title">Tạo quà cho khách</h1>
            <p>Kiểm tra hóa đơn trên KiotViet trước khi nhập thông tin.</p>
          </div>

          <form className="form-stack" onSubmit={handleSubmit} noValidate>
            <div className="field-group">
              <label htmlFor="bill-code">Mã hóa đơn</label>
              <input
                ref={billInput}
                id="bill-code"
                name="billCode"
                type="text"
                autoComplete="off"
                autoFocus
                value={billCode}
                onChange={(event) => {
                  setBillCode(event.target.value)
                  setErrors((current) => ({ ...current, billCode: undefined }))
                }}
                onBlur={() => setBillCode((current) => normalizeBillCode(current))}
                aria-invalid={Boolean(errors.billCode)}
                aria-describedby={errors.billCode ? 'bill-code-error' : 'bill-code-help'}
                disabled={submitting}
              />
              <span id="bill-code-help" className="field-help">Viết hoa tự động khi rời ô nhập.</span>
              {errors.billCode && <span id="bill-code-error" className="field-error">{errors.billCode}</span>}
            </div>

            <div className="field-group">
              <label htmlFor="bill-amount">Giá trị hóa đơn</label>
              <div className="amount-field">
                <input
                  id="bill-amount"
                  name="billAmount"
                  type="text"
                  inputMode="numeric"
                  autoComplete="off"
                  value={formatAmountInput(billAmount)}
                  onChange={(event) => {
                    setBillAmount(amountDigits(event.target.value))
                    setErrors((current) => ({ ...current, billAmount: undefined }))
                  }}
                  aria-invalid={Boolean(errors.billAmount)}
                  aria-describedby={errors.billAmount ? 'bill-amount-error' : 'bill-amount-help'}
                  disabled={submitting}
                />
                <span aria-hidden="true">đ</span>
              </div>
              <span id="bill-amount-help" className="field-help">Chỉ nhập số, ví dụ 385000.</span>
              {errors.billAmount && <span id="bill-amount-error" className="field-error">{errors.billAmount}</span>}
            </div>

            {requestError && <p className="message message--error" role="alert">{requestError}</p>}

            <button className="button button--primary button--large" type="submit" disabled={submitting}>
              {submitting ? 'ĐANG TẠO QUÀ…' : 'TẠO QUÀ'}
            </button>
          </form>
        </section>

        <aside className="result-column" aria-live="polite">
          {!result && !requestError && (
            <div className="empty-state">
              <span className="empty-state__number">01</span>
              <h2>Sẵn sàng phục vụ</h2>
              <p>Kết quả tạo quà và đường dẫn gửi khách sẽ xuất hiện tại đây.</p>
            </div>
          )}

          {result && presentation && (
            <section className={`result-card result-card--${presentation.tone}`} aria-labelledby="gift-result-title">
              <p className="result-label">KẾT QUẢ</p>
              <h2 id="gift-result-title">{presentation.title}</h2>
              <p>{presentation.message}</p>

              {presentation.showsGift && publicGiftLink && (
                <>
                  <div className="qr-handoff">
                    <div className="qr-frame">
                      <QRCodeSVG
                        value={publicGiftLink}
                        size={256}
                        level="M"
                        marginSize={4}
                        bgColor="#ffffff"
                        fgColor="#111111"
                        title={`Mã QR mở quà ${CUSTOMER_BRAND_NAME}`}
                      />
                    </div>
                  </div>
                  <dl className="gift-summary">
                    <div><dt>Mã hóa đơn</dt><dd>{result.bill_code}</dd></div>
                    <div><dt>Giá trị</dt><dd>{result.bill_amount_vnd === null ? '—' : formatVnd(result.bill_amount_vnd)}</dd></div>
                    <div><dt>Trạng thái</dt><dd>{result.gift_status === 'ELIGIBLE' ? 'Đủ điều kiện' : result.gift_status}</dd></div>
                  </dl>
                  <div className="link-block">
                    <label htmlFor="public-gift-link">Đường dẫn mở quà</label>
                    <input id="public-gift-link" type="text" readOnly value={publicGiftLink} onFocus={(event) => event.currentTarget.select()} />
                    <button className="button button--secondary" type="button" onClick={() => void copyGiftLink()}>
                      SAO CHÉP LINK
                    </button>
                    {copyStatus && <span className="copy-status" role="status">{copyStatus}</span>}
                  </div>
                </>
              )}

              <button className="button button--quiet result-reset" type="button" onClick={resetForNextBill}>
                TẠO BILL TIẾP THEO
              </button>
            </section>
          )}
        </aside>
      </div>
    </main>
  )
}
