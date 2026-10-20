import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { CUSTOMER_BRAND_NAME } from '../../config/presentation.ts'
import { supabase } from '../../lib/supabase.ts'
import type { StaffRole } from '../auth/useStaffAuth.ts'
import { amountDigits, formatAmountInput, formatVnd } from '../gifts/giftPresentation.ts'
import {
  AdminCampaignError,
  canEditCampaignVersion,
  campaignStatusLabels,
  createCampaignDraft,
  createNewCampaignVersion,
  deleteDraftPrize,
  getAdminCampaign,
  getCampaignInputErrors,
  getPrizeInputErrors,
  getValidationMessages,
  listAdminCampaigns,
  presentAdminError,
  prizeTypeLabels,
  publishCampaignVersion,
  saveDraftPrize,
  setCampaignLifecycle,
  updateCampaignDraft,
  validateCampaignVersion,
  type AdminCampaign,
  type AdminPrize,
  type CampaignDraftInput,
  type CampaignSummary,
  type CampaignValidation,
  type PrizeInput,
  type PrizeType,
} from './adminCampaigns.ts'

type AdminCampaignPageProps = {
  email: string | null
  role: StaffRole
  onLogout: () => Promise<void>
  onUnauthorized: () => Promise<void>
}

const prizeTypes = Object.keys(prizeTypeLabels) as PrizeType[]
const servicePrizeTypes = new Set<PrizeType>(['FREE_SERVICE', 'SERVICE_DISCOUNT', 'SERVICE_UPGRADE'])

function toDateTimeLocal(value: string) {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''
  const offset = date.getTimezoneOffset() * 60_000
  return new Date(date.getTime() - offset).toISOString().slice(0, 16)
}

function toIso(value: string) {
  return new Date(value).toISOString()
}

function dateTimeLabel(value: string) {
  return new Intl.DateTimeFormat('vi-VN', {
    dateStyle: 'short',
    timeStyle: 'short',
    timeZone: 'Asia/Ho_Chi_Minh',
  }).format(new Date(value))
}

function initialCampaignInput(): CampaignDraftInput {
  const start = new Date(Date.now() + 60 * 60 * 1000)
  const end = new Date(start.getTime() + 30 * 24 * 60 * 60 * 1000)
  return {
    name: '',
    startAt: toDateTimeLocal(start.toISOString()),
    endAt: toDateTimeLocal(end.toISOString()),
    minBillVnd: 0,
    giftOpenDeadlineHours: 72,
    headline: '',
    description: '',
    terms: '',
  }
}

function campaignInputFromDetail(campaign: AdminCampaign): CampaignDraftInput {
  const version = campaign.version
  return {
    name: campaign.name,
    startAt: toDateTimeLocal(campaign.start_at),
    endAt: toDateTimeLocal(campaign.end_at),
    minBillVnd: version?.min_bill_vnd ?? 0,
    giftOpenDeadlineHours: version?.gift_open_deadline_hours ?? 72,
    headline: version?.headline ?? '',
    description: version?.description ?? '',
    terms: version?.terms ?? '',
  }
}

function initialPrizeInput(prize?: AdminPrize): PrizeInput {
  return prize ? {
    prizeId: prize.prize_id,
    name: prize.name,
    type: prize.type,
    customerDescription: prize.customer_description,
    customerValueVnd: prize.customer_value_vnd,
    estimatedChicCostVnd: prize.estimated_chic_cost_vnd,
    discountPercent: prize.discount_percent,
    minimumSpendVnd: prize.minimum_spend_vnd,
    applicableService: prize.applicable_service,
    expiryDays: prize.expiry_days,
    weight: prize.weight,
    maxQuantity: prize.max_quantity,
    isFallback: prize.is_fallback,
    active: prize.active,
  } : {
    prizeId: null,
    name: '',
    type: 'CASH_VOUCHER',
    customerDescription: '',
    customerValueVnd: 0,
    estimatedChicCostVnd: 0,
    discountPercent: null,
    minimumSpendVnd: 0,
    applicableService: null,
    expiryDays: 30,
    weight: 1,
    maxQuantity: null,
    isFallback: false,
    active: true,
  }
}

function numberFromInput(value: string) {
  return Number(amountDigits(value) || '0')
}

function CampaignFields({
  input,
  setInput,
  disabled,
}: {
  input: CampaignDraftInput
  setInput: (input: CampaignDraftInput) => void
  disabled: boolean
}) {
  return (
    <div className="admin-form-grid">
      <div className="field-group admin-field--wide">
        <label htmlFor="campaign-name">Tên chương trình</label>
        <input id="campaign-name" value={input.name} disabled={disabled}
          onChange={(event) => setInput({ ...input, name: event.target.value })} />
      </div>
      <div className="field-group">
        <label htmlFor="campaign-start">Bắt đầu</label>
        <input id="campaign-start" type="datetime-local" value={input.startAt} disabled={disabled}
          onChange={(event) => setInput({ ...input, startAt: event.target.value })} />
      </div>
      <div className="field-group">
        <label htmlFor="campaign-end">Kết thúc</label>
        <input id="campaign-end" type="datetime-local" value={input.endAt} disabled={disabled}
          onChange={(event) => setInput({ ...input, endAt: event.target.value })} />
      </div>
      <div className="field-group">
        <label htmlFor="campaign-min-bill">Bill tối thiểu</label>
        <div className="amount-field">
          <input id="campaign-min-bill" inputMode="numeric" value={formatAmountInput(String(input.minBillVnd))}
            disabled={disabled} onChange={(event) => setInput({ ...input, minBillVnd: numberFromInput(event.target.value) })} />
          <span aria-hidden="true">đ</span>
        </div>
      </div>
      <div className="field-group">
        <label htmlFor="campaign-open-hours">Hạn mở quà (giờ)</label>
        <input id="campaign-open-hours" type="number" min="1" step="1" value={input.giftOpenDeadlineHours}
          disabled={disabled} onChange={(event) => setInput({ ...input, giftOpenDeadlineHours: Number(event.target.value) })} />
      </div>
      <div className="field-group admin-field--wide">
        <label htmlFor="campaign-headline">Tiêu đề hiển thị cho khách</label>
        <input id="campaign-headline" value={input.headline} disabled={disabled}
          onChange={(event) => setInput({ ...input, headline: event.target.value })} />
      </div>
      <div className="field-group admin-field--wide">
        <label htmlFor="campaign-description">Mô tả dành cho khách</label>
        <textarea id="campaign-description" rows={3} value={input.description} disabled={disabled}
          onChange={(event) => setInput({ ...input, description: event.target.value })} />
      </div>
      <div className="field-group admin-field--wide">
        <label htmlFor="campaign-terms">Điều kiện chương trình</label>
        <textarea id="campaign-terms" rows={4} value={input.terms} disabled={disabled}
          onChange={(event) => setInput({ ...input, terms: event.target.value })} />
      </div>
    </div>
  )
}

function PrizeForm({
  prize,
  busy,
  onCancel,
  onSave,
}: {
  prize?: AdminPrize
  busy: boolean
  onCancel: () => void
  onSave: (input: PrizeInput) => Promise<void>
}) {
  const [input, setInput] = useState(() => initialPrizeInput(prize))
  const [errors, setErrors] = useState<string[]>([])
  const unlimited = input.maxQuantity === null
  const showService = servicePrizeTypes.has(input.type)

  async function submit(event: FormEvent) {
    event.preventDefault()
    const nextErrors = getPrizeInputErrors(input)
    setErrors(nextErrors)
    if (nextErrors.length === 0) await onSave(input)
  }

  return (
    <form className="admin-panel admin-prize-form" onSubmit={submit} noValidate>
      <div className="admin-section-title">
        <div><p className="step-label">CẤU HÌNH QUÀ</p><h3>{prize ? 'Chỉnh sửa quà' : 'Thêm quà'}</h3></div>
        <button className="button button--quiet" type="button" onClick={onCancel}>Hủy</button>
      </div>
      <div className="admin-form-grid">
        <div className="field-group">
          <label htmlFor="prize-name">Tên quà</label>
          <input id="prize-name" value={input.name} disabled={busy}
            onChange={(event) => setInput({ ...input, name: event.target.value })} />
        </div>
        <div className="field-group">
          <label htmlFor="prize-type">Loại quà</label>
          <select id="prize-type" value={input.type} disabled={busy}
            onChange={(event) => setInput({ ...input, type: event.target.value as PrizeType, discountPercent: null })}>
            {prizeTypes.map((type) => <option key={type} value={type}>{prizeTypeLabels[type]}</option>)}
          </select>
        </div>
        <div className="field-group admin-field--wide">
          <label htmlFor="prize-description">Mô tả dành cho khách</label>
          <textarea id="prize-description" rows={3} value={input.customerDescription} disabled={busy}
            onChange={(event) => setInput({ ...input, customerDescription: event.target.value })} />
        </div>
        <div className="field-group">
          <label htmlFor="prize-customer-value">Giá trị khách nhận</label>
          <div className="amount-field"><input id="prize-customer-value" inputMode="numeric"
            value={formatAmountInput(String(input.customerValueVnd))} disabled={busy}
            onChange={(event) => setInput({ ...input, customerValueVnd: numberFromInput(event.target.value) })} /><span>đ</span></div>
        </div>
        <div className="field-group">
          <label htmlFor="prize-chic-cost">Chi phí dự kiến của Chic</label>
          <div className="amount-field"><input id="prize-chic-cost" inputMode="numeric"
            value={formatAmountInput(String(input.estimatedChicCostVnd))} disabled={busy}
            onChange={(event) => setInput({ ...input, estimatedChicCostVnd: numberFromInput(event.target.value) })} /><span>đ</span></div>
          <span className="field-help">Thông tin nội bộ, chỉ Admin thấy.</span>
        </div>
        {input.type === 'PERCENT_DISCOUNT' && (
          <div className="field-group">
            <label htmlFor="prize-percent">Mức giảm (%)</label>
            <input id="prize-percent" type="number" min="0.01" max="100" step="0.01"
              value={input.discountPercent ?? ''} disabled={busy}
              onChange={(event) => setInput({ ...input, discountPercent: Number(event.target.value) })} />
          </div>
        )}
        {showService && (
          <div className="field-group">
            <label htmlFor="prize-service">Dịch vụ áp dụng</label>
            <input id="prize-service" value={input.applicableService ?? ''} disabled={busy}
              onChange={(event) => setInput({ ...input, applicableService: event.target.value })} />
          </div>
        )}
        <div className="field-group">
          <label htmlFor="prize-minimum">Bill tối thiểu khi sử dụng</label>
          <div className="amount-field"><input id="prize-minimum" inputMode="numeric"
            value={formatAmountInput(String(input.minimumSpendVnd))} disabled={busy}
            onChange={(event) => setInput({ ...input, minimumSpendVnd: numberFromInput(event.target.value) })} /><span>đ</span></div>
        </div>
        <div className="field-group">
          <label htmlFor="prize-expiry">Hạn sử dụng (ngày)</label>
          <input id="prize-expiry" type="number" min="1" step="1" value={input.expiryDays} disabled={busy}
            onChange={(event) => setInput({ ...input, expiryDays: Number(event.target.value) })} />
        </div>
        {!input.isFallback && (
          <div className="field-group">
            <label htmlFor="prize-weight">Trọng số</label>
            <input id="prize-weight" type="number" min="1" step="1" value={input.weight} disabled={busy}
              onChange={(event) => setInput({ ...input, weight: Number(event.target.value) })} />
            <span className="field-help">Trọng số xác định tỷ lệ tương đối. Không cần cộng đủ 100.</span>
          </div>
        )}
        <div className="field-group admin-field--wide admin-check-row">
          <label className="confirmation-check"><input type="checkbox" checked={input.isFallback} disabled={busy}
            onChange={(event) => setInput({ ...input, isFallback: event.target.checked, maxQuantity: event.target.checked ? null : input.maxQuantity })} />
            <span>Đây là quà dự phòng</span></label>
          <span className="field-help">Quà dự phòng chỉ dùng khi các quà thường không còn khả dụng và phải không giới hạn.</span>
        </div>
        {!input.isFallback && (
          <div className="field-group admin-field--wide admin-inventory-row">
            <label className="confirmation-check"><input type="checkbox" checked={unlimited} disabled={busy}
              onChange={(event) => setInput({ ...input, maxQuantity: event.target.checked ? null : 1 })} />
              <span>Không giới hạn số lượng</span></label>
            {!unlimited && <input aria-label="Số lượng tối đa" type="number" min="1" step="1" value={input.maxQuantity ?? 1}
              disabled={busy} onChange={(event) => setInput({ ...input, maxQuantity: Number(event.target.value) })} />}
          </div>
        )}
        <div className="field-group admin-field--wide">
          <label className="confirmation-check"><input type="checkbox" checked={input.active} disabled={busy}
            onChange={(event) => setInput({ ...input, active: event.target.checked })} />
            <span>Quà đang hoạt động</span></label>
        </div>
      </div>
      {errors.length > 0 && <ul className="admin-error-list" role="alert">{errors.map((error) => <li key={error}>{error}</li>)}</ul>}
      <button className="button button--primary" type="submit" disabled={busy}>{busy ? 'ĐANG LƯU…' : 'LƯU QUÀ'}</button>
    </form>
  )
}

export function AdminCampaignPage({ email, role, onLogout, onUnauthorized }: AdminCampaignPageProps) {
  const [campaigns, setCampaigns] = useState<CampaignSummary[]>([])
  const [detail, setDetail] = useState<AdminCampaign | null>(null)
  const [campaignInput, setCampaignInput] = useState<CampaignDraftInput>(initialCampaignInput)
  const [validation, setValidation] = useState<CampaignValidation | null>(null)
  const [creating, setCreating] = useState(false)
  const [editingPrize, setEditingPrize] = useState<AdminPrize | null | undefined>(undefined)
  const [busy, setBusy] = useState(false)
  const [notice, setNotice] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const handleError = useCallback(async (caught: unknown) => {
    if (caught instanceof AdminCampaignError && caught.kind === 'unauthorized') {
      await onUnauthorized()
      return
    }
    setError(presentAdminError(caught))
  }, [onUnauthorized])

  const loadDetail = useCallback(async (campaignId: string) => {
    if (!supabase) return
    const nextDetail = await getAdminCampaign(supabase, campaignId)
    setDetail(nextDetail)
    setCampaignInput(campaignInputFromDetail(nextDetail))
    setEditingPrize(undefined)
    if (nextDetail.version) {
      setValidation(await validateCampaignVersion(supabase, campaignId, nextDetail.version.campaign_version_id))
    } else {
      setValidation(null)
    }
  }, [])

  const refreshCampaigns = useCallback(async (selectedId?: string) => {
    if (!supabase) return
    const rows = await listAdminCampaigns(supabase)
    setCampaigns(rows)
    if (selectedId) await loadDetail(selectedId)
  }, [loadDetail])

  useEffect(() => {
    if (!supabase) return
    let active = true
    void listAdminCampaigns(supabase).then(
      (rows) => { if (active) setCampaigns(rows) },
      (caught) => { if (active) void handleError(caught) },
    )
    return () => { active = false }
  }, [handleError])

  async function run(action: () => Promise<void>) {
    if (busy) return
    setBusy(true)
    setError(null)
    setNotice(null)
    try {
      await action()
    } catch (caught) {
      await handleError(caught)
    } finally {
      setBusy(false)
    }
  }

  async function submitCampaign(event: FormEvent) {
    event.preventDefault()
    const issues = getCampaignInputErrors(campaignInput)
    if (issues.length > 0) {
      setError(issues.join(' '))
      return
    }
    const normalized = { ...campaignInput, startAt: toIso(campaignInput.startAt), endAt: toIso(campaignInput.endAt) }
    await run(async () => {
      if (creating) {
        const created = await createCampaignDraft(supabase!, normalized)
        setCreating(false)
        await refreshCampaigns(created.campaign_id)
        setNotice('Đã tạo bản nháp. Tiếp tục cấu hình phần quà.')
      } else if (detail?.version) {
        await updateCampaignDraft(supabase!, detail.campaign_id, detail.version.campaign_version_id, normalized)
        await refreshCampaigns(detail.campaign_id)
        setNotice('Đã lưu cấu hình chương trình.')
      }
    })
  }

  async function submitPrize(input: PrizeInput) {
    if (!detail?.version) return
    await run(async () => {
      await saveDraftPrize(supabase!, detail.campaign_id, detail.version!.campaign_version_id, input)
      await refreshCampaigns(detail.campaign_id)
      setNotice('Đã lưu phần quà.')
    })
  }

  async function removePrize(prize: AdminPrize) {
    if (!detail?.version || !window.confirm(`Xóa quà nháp “${prize.name}”?`)) return
    await run(async () => {
      await deleteDraftPrize(supabase!, detail.campaign_id, detail.version!.campaign_version_id, prize.prize_id)
      await refreshCampaigns(detail.campaign_id)
      setNotice('Đã xóa phần quà khỏi bản nháp.')
    })
  }

  async function publish() {
    if (!detail?.version || !validation?.valid || !window.confirm('Xuất bản phiên bản này? Sau khi xuất bản, cấu hình và phần quà sẽ không thể sửa.')) return
    await run(async () => {
      await publishCampaignVersion(supabase!, detail.campaign_id, detail.version!.campaign_version_id)
      await refreshCampaigns(detail.campaign_id)
      setNotice('Đã xuất bản phiên bản. Chương trình chưa được kích hoạt.')
    })
  }

  async function cloneVersion() {
    if (!detail || !window.confirm('Tạo phiên bản nháp mới từ cấu hình đã xuất bản?')) return
    await run(async () => {
      await createNewCampaignVersion(supabase!, detail.campaign_id)
      await refreshCampaigns(detail.campaign_id)
      setNotice('Đã tạo phiên bản mới. Bản đã xuất bản trước đó vẫn được giữ nguyên.')
    })
  }

  async function lifecycle(action: 'ACTIVATE' | 'PAUSE' | 'RESUME' | 'END' | 'ARCHIVE') {
    if (!detail) return
    const confirmations: Partial<Record<typeof action, string>> = {
      ACTIVATE: 'Kích hoạt chương trình này để Staff bắt đầu tạo quà?',
      END: 'Kết thúc chương trình? Quà đã cấp vẫn được giữ nguyên.',
      ARCHIVE: 'Lưu trữ chương trình đã kết thúc? Lịch sử vẫn được giữ nguyên.',
    }
    const confirmed = confirmations[action] ? window.confirm(confirmations[action]) : false
    if (confirmations[action] && !confirmed) return
    await run(async () => {
      await setCampaignLifecycle(supabase!, detail.campaign_id, action, confirmed)
      await refreshCampaigns(detail.campaign_id)
      setNotice('Đã cập nhật trạng thái chương trình.')
    })
  }

  const version = detail?.version
  const published = Boolean(version?.published_at)
  const editable = Boolean(version && detail && canEditCampaignVersion(detail.status, version.published_at))
  const validationMessages = getValidationMessages(validation)

  return (
    <main className="staff-shell admin-shell">
      <header className="staff-header">
        <div>
          <a className="staff-brand" href="/staff">{CUSTOMER_BRAND_NAME}</a>
          <nav className="staff-navigation" aria-label="Khu vực vận hành">
            <a href="/staff">Tạo quà</a><a href="/staff/redeem">Sử dụng quà</a>
            <a href="/admin/campaigns" aria-current="page">Chương trình</a>
          </nav>
        </div>
        <div className="account-actions"><div className="account-summary"><span className="role-badge">{role}</span>
          {email && <span className="account-email">{email}</span>}</div>
          <button className="button button--quiet" onClick={() => void onLogout()}>Đăng xuất</button></div>
      </header>

      <div className="admin-layout">
        <aside className="admin-campaign-list" aria-label="Danh sách chương trình">
          <div className="admin-section-title"><div><p className="step-label">QUẢN LÝ</p><h1>Chương trình</h1></div>
            <button className="button button--primary" type="button" onClick={() => {
              setCreating(true); setDetail(null); setCampaignInput(initialCampaignInput()); setValidation(null); setError(null)
            }}>TẠO CHƯƠNG TRÌNH</button></div>
          {campaigns.length === 0 && <p className="admin-empty">Chưa có chương trình nào.</p>}
          <div className="admin-campaign-items">
            {campaigns.map((campaign) => (
              <button key={campaign.campaign_id} type="button"
                className={detail?.campaign_id === campaign.campaign_id ? 'admin-campaign-item admin-campaign-item--active' : 'admin-campaign-item'}
                onClick={() => void run(() => loadDetail(campaign.campaign_id))}>
                <strong>{campaign.campaign_name}</strong>
                <span className={`status-pill status-pill--${campaign.campaign_status.toLowerCase()}`}>{campaignStatusLabels[campaign.campaign_status]}</span>
                <span>{dateTimeLabel(campaign.start_at)} – {dateTimeLabel(campaign.end_at)}</span>
                <span>Phiên bản hiện tại: {campaign.current_version_number ?? 'Chưa xuất bản'}</span>
                <span>Bill tối thiểu: {campaign.minimum_bill_vnd === null ? '—' : formatVnd(campaign.minimum_bill_vnd)}</span>
              </button>
            ))}
          </div>
        </aside>

        <section className="admin-workspace">
          {error && <p className="message message--error" role="alert">{error}</p>}
          {notice && <p className="message message--success" role="status">{notice}</p>}
          {!creating && !detail && <div className="empty-state"><span className="empty-state__number">05</span>
            <h2>Chọn một chương trình</h2><p>Xem cấu hình hiện tại hoặc tạo chương trình mới.</p></div>}

          {(creating || detail) && (
            <>
              <form className="admin-panel" onSubmit={submitCampaign} noValidate>
                <div className="admin-section-title"><div><p className="step-label">01 · CẤU HÌNH</p>
                  <h2>{creating ? 'Tạo chương trình nháp' : detail?.name}</h2></div>
                  {detail && <span className={`status-pill status-pill--${detail.status.toLowerCase()}`}>{campaignStatusLabels[detail.status]}</span>}
                </div>
                {version && <p className="admin-version-label">Phiên bản chương trình {version.version_number} · {published ? 'Đã xuất bản, chỉ đọc' : 'Bản nháp có thể chỉnh sửa'}</p>}
                <CampaignFields input={campaignInput} setInput={setCampaignInput} disabled={busy || (!creating && !editable)} />
                {(creating || editable) && <button className="button button--primary" type="submit" disabled={busy}>{busy ? 'ĐANG LƯU…' : creating ? 'TẠO BẢN NHÁP' : 'LƯU CẤU HÌNH'}</button>}
              </form>

              {detail && version && (
                <section className="admin-panel">
                  <div className="admin-section-title"><div><p className="step-label">02 · PHẦN QUÀ</p><h2>Cấu hình quà</h2></div>
                    {editable && editingPrize === undefined && <button className="button button--secondary" onClick={() => setEditingPrize(null)}>THÊM QUÀ</button>}
                  </div>
                  <p className="admin-helper">Quà thường dùng trọng số tương đối; không cần cộng đủ 100. Quà dự phòng không thuộc phép chọn trọng số thông thường.</p>
                  <div className="admin-prize-list">
                    {version.prizes.map((prize) => <article className={prize.is_fallback ? 'admin-prize admin-prize--fallback' : 'admin-prize'} key={prize.prize_id}>
                      <div><span className="prize-kind">{prize.is_fallback ? 'QUÀ DỰ PHÒNG' : prizeTypeLabels[prize.type]}</span><h3>{prize.name}</h3><p>{prize.customer_description}</p></div>
                      <dl><div><dt>Giá trị khách nhận</dt><dd>{formatVnd(prize.customer_value_vnd)}</dd></div>
                        <div><dt>Chi phí dự kiến của Chic</dt><dd>{formatVnd(prize.estimated_chic_cost_vnd)}</dd></div>
                        {!prize.is_fallback && <div><dt>Trọng số</dt><dd>{prize.weight}</dd></div>}
                        <div><dt>Số lượng</dt><dd>{prize.max_quantity === null ? 'Không giới hạn' : `${prize.issued_quantity}/${prize.max_quantity}`}</dd></div>
                        <div><dt>Trạng thái</dt><dd>{prize.active ? 'Hoạt động' : 'Tạm tắt'}</dd></div></dl>
                      {editable && <div className="button-row"><button className="button button--quiet" onClick={() => setEditingPrize(prize)}>SỬA</button>
                        <button className="button button--quiet" onClick={() => void removePrize(prize)}>XÓA</button></div>}
                    </article>)}
                  </div>
                  {version.prizes.length === 0 && <p className="admin-empty">Chưa có phần quà. Thêm ít nhất một quà thường và một quà dự phòng.</p>}
                </section>
              )}

              {detail && version && editable && editingPrize !== undefined && (
                <PrizeForm key={editingPrize?.prize_id ?? 'new'} prize={editingPrize ?? undefined} busy={busy}
                  onCancel={() => setEditingPrize(undefined)} onSave={submitPrize} />
              )}

              {detail && version && (
                <section className="admin-panel admin-review">
                  <div className="admin-section-title"><div><p className="step-label">03 · RÀ SOÁT</p><h2>Sẵn sàng xuất bản</h2></div>
                    <span className={validation?.valid ? 'review-badge review-badge--pass' : 'review-badge'}>{validation?.valid ? 'ĐỦ ĐIỀU KIỆN' : 'CHƯA ĐỦ'}</span></div>
                  <dl className="admin-review-grid"><div><dt>Thời gian</dt><dd>{dateTimeLabel(detail.start_at)} – {dateTimeLabel(detail.end_at)}</dd></div>
                    <div><dt>Bill tối thiểu</dt><dd>{formatVnd(version.min_bill_vnd)}</dd></div>
                    <div><dt>Hạn mở quà</dt><dd>{version.gift_open_deadline_hours} giờ</dd></div>
                    <div><dt>Tiêu đề</dt><dd>{version.headline}</dd></div>
                    <div><dt>Tổng số quà</dt><dd>{validation?.prize_count ?? 0}</dd></div>
                    <div><dt>Quà thường hoạt động</dt><dd>{validation?.normal_prize_count ?? 0}</dd></div></dl>
                  <ul className="fallback-checks">
                    <li className={validation?.fallback_count === 1 ? 'check-pass' : ''}>Có đúng 1 quà dự phòng</li>
                    <li className={validation?.fallback_valid ? 'check-pass' : ''}>Quà dự phòng đang hoạt động</li>
                    <li className={validation?.fallback_valid ? 'check-pass' : ''}>Quà dự phòng không giới hạn số lượng</li>
                  </ul>
                  {validationMessages.length > 0 && <ul className="admin-error-list">{validationMessages.map((message) => <li key={message}>{message}</li>)}</ul>}
                  {!published && <button className="button button--primary" disabled={busy || !validation?.valid} onClick={() => void publish()}>XUẤT BẢN PHIÊN BẢN</button>}
                  {published && detail.status !== 'ACTIVE' && !['ENDED', 'ARCHIVED'].includes(detail.status) && (
                    <button className="button button--secondary" disabled={busy} onClick={() => void cloneVersion()}>TẠO PHIÊN BẢN MỚI</button>
                  )}
                  {published && detail.status === 'ACTIVE' && <p className="admin-helper">Tạm dừng chương trình trước khi tạo phiên bản mới.</p>}
                </section>
              )}

              {detail && version?.published_at && version.is_current && (
                <section className="admin-panel">
                  <div className="admin-section-title"><div><p className="step-label">04 · VẬN HÀNH</p><h2>Trạng thái chương trình</h2></div></div>
                  <p className="admin-helper">Mỗi chi nhánh chỉ có một chương trình hoạt động. Hệ thống không tự tắt chương trình khác.</p>
                  <div className="button-row lifecycle-actions">
                    {['DRAFT', 'SCHEDULED'].includes(detail.status) && <button className="button button--confirm" disabled={busy} onClick={() => void lifecycle('ACTIVATE')}>KÍCH HOẠT CHƯƠNG TRÌNH</button>}
                    {detail.status === 'ACTIVE' && <button className="button button--secondary" disabled={busy} onClick={() => void lifecycle('PAUSE')}>TẠM DỪNG</button>}
                    {detail.status === 'PAUSED' && <button className="button button--confirm" disabled={busy} onClick={() => void lifecycle('RESUME')}>TIẾP TỤC</button>}
                    {!['ENDED', 'ARCHIVED'].includes(detail.status) && <button className="button button--quiet" disabled={busy} onClick={() => void lifecycle('END')}>KẾT THÚC</button>}
                    {detail.status === 'ENDED' && <button className="button button--quiet" disabled={busy} onClick={() => void lifecycle('ARCHIVE')}>LƯU TRỮ</button>}
                  </div>
                </section>
              )}
            </>
          )}
        </section>
      </div>
    </main>
  )
}

export function AdminUnauthorizedState() {
  return <main className="state-shell"><section className="state-card" role="alert"><p className="eyebrow">{CUSTOMER_BRAND_NAME}</p>
    <h1>Không có quyền truy cập</h1><p>Khu vực Chương trình chỉ dành cho Admin đang hoạt động.</p>
    <a className="button button--secondary navigation-button" href="/staff">Về trang nhân viên</a></section></main>
}
