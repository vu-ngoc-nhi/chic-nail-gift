import { useRef, useState, type FormEvent } from 'react'
import { CUSTOMER_BRAND_NAME } from '../../config/presentation.ts'
import { supabase } from '../../lib/supabase.ts'
import type { StaffRole } from '../auth/useStaffAuth.ts'
import {
  amountDigits,
  formatAmountInput,
  formatVnd,
  hasInternalWhitespace,
  normalizeBillCode,
  parseVndAmount,
} from '../gifts/giftPresentation.ts'
import {
  formatRewardValue,
  formatStaffDateTime,
  isValidRewardCode,
  lookupReward,
  normalizeRewardCode,
  presentRedemptionResult,
  redeemReward,
  RewardRedemptionError,
  type StaffRewardResult,
} from './rewardRedemption.ts'

type StaffRedemptionPageProps = {
  email: string | null
  role: StaffRole
  onLogout: () => Promise<void>
  onUnauthorized: () => Promise<void>
}

type RedemptionErrors = {
  rewardCode?: string
  billCode?: string
  billAmount?: string
  confirmation?: string
}

export function StaffRedemptionPage({
  email,
  role,
  onLogout,
  onUnauthorized,
}: StaffRedemptionPageProps) {
  const [rewardCode, setRewardCode] = useState('')
  const [billCode, setBillCode] = useState('')
  const [billAmount, setBillAmount] = useState('')
  const [conditionsConfirmed, setConditionsConfirmed] = useState(false)
  const [errors, setErrors] = useState<RedemptionErrors>({})
  const [result, setResult] = useState<StaffRewardResult | null>(null)
  const [requestError, setRequestError] = useState<string | null>(null)
  const [searching, setSearching] = useState(false)
  const [redeeming, setRedeeming] = useState(false)
  const requestLocked = useRef(false)

  const presentation = result ? presentRedemptionResult(result.result_code) : null
  const redemptionFinished = result?.result_code === 'REDEEMED'
    || result?.result_code === 'ALREADY_REDEEMED'
  const showRedemptionForm = Boolean(
    result?.reward_code
    && result.reward_status === 'AVAILABLE'
    && !redemptionFinished,
  )

  async function handleAuthorizationError(error: unknown) {
    if (error instanceof RewardRedemptionError && error.kind === 'unauthorized') {
      await onUnauthorized()
      return true
    }
    return false
  }

  async function handleLookup(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (requestLocked.current || !supabase) {
      return
    }

    const normalizedCode = normalizeRewardCode(rewardCode)
    if (!isValidRewardCode(normalizedCode)) {
      setErrors({ rewardCode: 'Vui lòng nhập mã quà hợp lệ, ví dụ CHIC-X82K9.' })
      return
    }

    requestLocked.current = true
    setSearching(true)
    setErrors({})
    setRequestError(null)
    setResult(null)
    setBillCode('')
    setBillAmount('')
    setConditionsConfirmed(false)

    try {
      const nextResult = await lookupReward(supabase, normalizedCode)
      setRewardCode(nextResult.reward_code ?? normalizedCode)
      setResult(nextResult)
    } catch (error) {
      if (await handleAuthorizationError(error)) {
        return
      }
      setRequestError('Không thể tra cứu mã quà lúc này. Vui lòng kiểm tra kết nối và thử lại.')
    } finally {
      requestLocked.current = false
      setSearching(false)
    }
  }

  function validateRedemption() {
    const nextErrors: RedemptionErrors = {}
    const normalizedBillCode = normalizeBillCode(billCode)
    const amount = parseVndAmount(billAmount)

    if (!normalizedBillCode) {
      nextErrors.billCode = 'Vui lòng nhập mã bill sử dụng quà.'
    } else if (hasInternalWhitespace(normalizedBillCode)) {
      nextErrors.billCode = 'Mã bill có khoảng trắng bất thường. Vui lòng kiểm tra lại trên KiotViet.'
    }
    if (!billAmount || amount === null) {
      nextErrors.billAmount = 'Giá trị bill phải lớn hơn 0đ.'
    }
    if (!conditionsConfirmed) {
      nextErrors.confirmation = 'Vui lòng xác nhận đã kiểm tra bill, dịch vụ và điều kiện.'
    }

    setErrors(nextErrors)
    return {
      valid: Object.keys(nextErrors).length === 0,
      normalizedBillCode,
      amount,
    }
  }

  async function handleRedeem(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (requestLocked.current || !supabase || !result?.reward_code || redemptionFinished) {
      return
    }

    const validation = validateRedemption()
    if (!validation.valid || validation.amount === null) {
      return
    }

    requestLocked.current = true
    setRedeeming(true)
    setRequestError(null)

    try {
      const nextResult = await redeemReward(
        supabase,
        result.reward_code,
        validation.normalizedBillCode,
        validation.amount,
        conditionsConfirmed,
      )
      setBillCode(nextResult.redemption_bill_code ?? validation.normalizedBillCode)
      setResult(nextResult)
    } catch (error) {
      if (await handleAuthorizationError(error)) {
        return
      }
      setRequestError('Không thể xác nhận sử dụng quà lúc này. Vui lòng kiểm tra kết nối và thử lại.')
    } finally {
      requestLocked.current = false
      setRedeeming(false)
    }
  }

  return (
    <main className="staff-shell">
      <header className="staff-header">
        <div>
          <a className="staff-brand" href="/staff" aria-label={`Trang nhân viên ${CUSTOMER_BRAND_NAME}`}>
            {CUSTOMER_BRAND_NAME}
          </a>
          <nav className="staff-navigation" aria-label="Công việc nhân viên">
            <a href="/staff">Tạo quà</a>
            <a href="/staff/redeem" aria-current="page">Sử dụng quà</a>
            {role === 'ADMIN' && <a href="/admin/campaigns">Chương trình</a>}
          </nav>
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

      <div className="staff-layout staff-layout--redemption">
        <section className="work-card" aria-labelledby="redeem-title">
          <div className="section-heading">
            <p className="step-label">KIỂM TRA TRƯỚC KHI XÁC NHẬN</p>
            <h1 id="redeem-title">Sử dụng quà</h1>
            <p>Nhập mã quà khách cung cấp để kiểm tra trạng thái và điều kiện.</p>
          </div>

          <form className="form-stack" onSubmit={handleLookup} noValidate>
            <div className="field-group">
              <label htmlFor="reward-code">Mã quà</label>
              <input
                id="reward-code"
                name="rewardCode"
                type="text"
                autoComplete="off"
                autoFocus
                value={rewardCode}
                onChange={(event) => {
                  setRewardCode(event.target.value)
                  setErrors((current) => ({ ...current, rewardCode: undefined }))
                }}
                onBlur={() => setRewardCode((current) => normalizeRewardCode(current))}
                aria-invalid={Boolean(errors.rewardCode)}
                aria-describedby={errors.rewardCode ? 'reward-code-error' : 'reward-code-help'}
                disabled={searching || redeeming || redemptionFinished}
              />
              <span id="reward-code-help" className="field-help">Ví dụ: CHIC-X82K9.</span>
              {errors.rewardCode && <span id="reward-code-error" className="field-error">{errors.rewardCode}</span>}
            </div>
            <button className="button button--primary button--large" type="submit" disabled={searching || redeeming || redemptionFinished}>
              {searching ? 'ĐANG TRA CỨU…' : 'TRA CỨU QUÀ'}
            </button>
          </form>
        </section>

        <aside className="result-column redemption-result-column" aria-live="polite">
          {!result && !requestError && (
            <div className="empty-state">
              <span className="empty-state__number">02</span>
              <h2>Sẵn sàng kiểm tra</h2>
              <p>Thông tin quà và điều kiện sử dụng sẽ xuất hiện tại đây.</p>
            </div>
          )}

          {requestError && <p className="message message--error" role="alert">{requestError}</p>}

          {result && presentation && (
            <section className={`result-card result-card--${presentation.tone}`} aria-labelledby="redemption-result-title">
              <p className="result-label">TRẠNG THÁI QUÀ</p>
              <h2 id="redemption-result-title">{presentation.title}</h2>
              <p>{presentation.message}</p>

              {result.reward_code && (
                <>
                  <dl className="gift-summary redemption-summary">
                    <div><dt>Phần quà</dt><dd>{result.reward_name}</dd></div>
                    <div><dt>Quyền lợi</dt><dd>{formatRewardValue(result)}</dd></div>
                    <div><dt>Mã quà</dt><dd>{result.reward_code}</dd></div>
                    <div><dt>Hạn sử dụng</dt><dd>{formatStaffDateTime(result.reward_expires_at)}</dd></div>
                    {result.applicable_service && <div><dt>Áp dụng cho</dt><dd>{result.applicable_service}</dd></div>}
                    {result.minimum_spend_vnd !== null && result.minimum_spend_vnd > 0 && (
                      <div><dt>Bill tối thiểu</dt><dd>{formatVnd(result.minimum_spend_vnd)}</dd></div>
                    )}
                  </dl>

                  {result.reward_description && <p>{result.reward_description}</p>}
                  {result.reward_terms && (
                    <section className="staff-terms" aria-labelledby="staff-terms-title">
                      <h3 id="staff-terms-title">Điều kiện áp dụng</h3>
                      <p>{result.reward_terms}</p>
                    </section>
                  )}
                </>
              )}

              {showRedemptionForm && (
                <form className="form-stack redemption-form" onSubmit={handleRedeem} noValidate>
                  <div className="manual-check-note" role="note">
                    <strong>Kiểm tra thủ công trên KiotViet</strong>
                    <span>Đối chiếu bill hiện tại, dịch vụ áp dụng và toàn bộ điều kiện của quà.</span>
                  </div>

                  <div className="field-group">
                    <label htmlFor="redemption-bill-code">Mã bill sử dụng quà</label>
                    <input
                      id="redemption-bill-code"
                      name="redemptionBillCode"
                      type="text"
                      autoComplete="off"
                      value={billCode}
                      onChange={(event) => {
                        setBillCode(event.target.value)
                        setErrors((current) => ({ ...current, billCode: undefined }))
                      }}
                      onBlur={() => setBillCode((current) => normalizeBillCode(current))}
                      aria-invalid={Boolean(errors.billCode)}
                      aria-describedby={errors.billCode ? 'redemption-bill-code-error' : undefined}
                      disabled={redeeming}
                    />
                    {errors.billCode && <span id="redemption-bill-code-error" className="field-error">{errors.billCode}</span>}
                  </div>

                  <div className="field-group">
                    <label htmlFor="redemption-bill-amount">Giá trị bill</label>
                    <div className="amount-field">
                      <input
                        id="redemption-bill-amount"
                        name="redemptionBillAmount"
                        type="text"
                        inputMode="numeric"
                        autoComplete="off"
                        value={formatAmountInput(billAmount)}
                        onChange={(event) => {
                          setBillAmount(amountDigits(event.target.value))
                          setErrors((current) => ({ ...current, billAmount: undefined }))
                        }}
                        aria-invalid={Boolean(errors.billAmount)}
                        aria-describedby={errors.billAmount ? 'redemption-bill-amount-error' : undefined}
                        disabled={redeeming}
                      />
                      <span aria-hidden="true">đ</span>
                    </div>
                    {errors.billAmount && <span id="redemption-bill-amount-error" className="field-error">{errors.billAmount}</span>}
                  </div>

                  <label className="confirmation-check">
                    <input
                      type="checkbox"
                      checked={conditionsConfirmed}
                      onChange={(event) => {
                        setConditionsConfirmed(event.target.checked)
                        setErrors((current) => ({ ...current, confirmation: undefined }))
                      }}
                      disabled={redeeming}
                    />
                    <span>Tôi đã kiểm tra bill, dịch vụ và điều kiện áp dụng.</span>
                  </label>
                  {errors.confirmation && <span className="field-error">{errors.confirmation}</span>}

                  <button className="button button--confirm button--large" type="submit" disabled={redeeming}>
                    {redeeming ? 'ĐANG XÁC NHẬN…' : 'XÁC NHẬN ĐÃ SỬ DỤNG QUÀ'}
                  </button>
                </form>
              )}

              {redemptionFinished && result.redemption_bill_code && (
                <dl className="gift-summary redemption-final">
                  <div><dt>Mã bill sử dụng</dt><dd>{result.redemption_bill_code}</dd></div>
                  <div><dt>Thời gian xác nhận</dt><dd>{formatStaffDateTime(result.redeemed_at)}</dd></div>
                </dl>
              )}

              {result && (
                <a className="button button--secondary result-reset navigation-button" href="/staff/redeem">
                  TRA CỨU MÃ KHÁC
                </a>
              )}
            </section>
          )}
        </aside>
      </div>
    </main>
  )
}
