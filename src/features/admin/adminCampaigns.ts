import type { ChicSupabaseClient } from '../../lib/supabase.ts'

export type CampaignStatus = 'DRAFT' | 'SCHEDULED' | 'ACTIVE' | 'PAUSED' | 'ENDED' | 'ARCHIVED'
export type PrizeType =
  | 'CASH_VOUCHER'
  | 'PERCENT_DISCOUNT'
  | 'FREE_SERVICE'
  | 'SERVICE_DISCOUNT'
  | 'SERVICE_UPGRADE'
  | 'CUSTOM_REWARD'

export type CampaignSummary = {
  campaign_id: string
  campaign_name: string
  campaign_status: CampaignStatus
  start_at: string
  end_at: string
  current_version_id: string | null
  current_version_number: number | null
  minimum_bill_vnd: number | null
  published_at: string | null
  created_at: string
  updated_at: string
}

export type AdminPrize = {
  prize_id: string
  name: string
  type: PrizeType
  customer_description: string
  customer_value_vnd: number
  estimated_chic_cost_vnd: number
  discount_percent: number | null
  minimum_spend_vnd: number
  applicable_service: string | null
  expiry_days: number
  weight: number
  max_quantity: number | null
  issued_quantity: number
  is_fallback: boolean
  active: boolean
}

export type CampaignVersion = {
  campaign_version_id: string
  version_number: number
  min_bill_vnd: number
  gift_open_deadline_hours: number
  headline: string
  description: string
  terms: string
  published_at: string | null
  is_current: boolean
  prizes: AdminPrize[]
}

export type AdminCampaign = {
  campaign_id: string
  name: string
  status: CampaignStatus
  start_at: string
  end_at: string
  current_version_id: string | null
  created_at: string
  updated_at: string
  version: CampaignVersion | null
}

export type CampaignDraftInput = {
  name: string
  startAt: string
  endAt: string
  minBillVnd: number
  giftOpenDeadlineHours: number
  headline: string
  description: string
  terms: string
}

export type PrizeInput = {
  prizeId: string | null
  name: string
  type: PrizeType
  customerDescription: string
  customerValueVnd: number
  estimatedChicCostVnd: number
  discountPercent: number | null
  minimumSpendVnd: number
  applicableService: string | null
  expiryDays: number
  weight: number
  maxQuantity: number | null
  isFallback: boolean
  active: boolean
}

export type CampaignValidation = {
  valid: boolean
  issues: string[]
  prize_count: number
  normal_prize_count: number
  fallback_count: number
  fallback_valid: boolean
}

export class AdminCampaignError extends Error {
  readonly kind: 'unauthorized' | 'validation' | 'request-failed'

  constructor(kind: 'unauthorized' | 'validation' | 'request-failed', message = '') {
    super(message)
    this.name = 'AdminCampaignError'
    this.kind = kind
  }
}

function handleRpcError(error: { code?: string; message?: string } | null) {
  if (!error) return
  if (error.code === '42501') throw new AdminCampaignError('unauthorized')
  if (error.code === '23514' || error.code === '23505') {
    throw new AdminCampaignError('validation', error.message)
  }
  throw new AdminCampaignError('request-failed', error.message)
}

function unwrapObject<T>(data: unknown): T {
  const value = (Array.isArray(data) ? data[0] : data) as T | undefined
  if (!value) throw new AdminCampaignError('request-failed')
  return value
}

function campaignArguments(input: CampaignDraftInput) {
  return {
    p_name: input.name.trim(),
    p_start_at: input.startAt,
    p_end_at: input.endAt,
    p_min_bill_vnd: input.minBillVnd,
    p_gift_open_deadline_hours: input.giftOpenDeadlineHours,
    p_headline: input.headline.trim(),
    p_description: input.description.trim(),
    p_terms: input.terms.trim(),
  }
}

export async function listAdminCampaigns(client: ChicSupabaseClient) {
  const { data, error } = await client.rpc('list_admin_campaigns')
  handleRpcError(error)
  return (data ?? []) as CampaignSummary[]
}

export async function getAdminCampaign(client: ChicSupabaseClient, campaignId: string) {
  const { data, error } = await client.rpc('get_admin_campaign', { p_campaign_id: campaignId })
  handleRpcError(error)
  return unwrapObject<AdminCampaign>(data)
}

export async function createCampaignDraft(client: ChicSupabaseClient, input: CampaignDraftInput) {
  const { data, error } = await client.rpc('create_campaign_draft', campaignArguments(input))
  handleRpcError(error)
  return unwrapObject<{ campaign_id: string; campaign_version_id: string }>(data)
}

export async function updateCampaignDraft(
  client: ChicSupabaseClient,
  campaignId: string,
  versionId: string,
  input: CampaignDraftInput,
) {
  const { data, error } = await client.rpc('update_campaign_draft', {
    p_campaign_id: campaignId,
    p_campaign_version_id: versionId,
    ...campaignArguments(input),
  })
  handleRpcError(error)
  return unwrapObject<{ saved: boolean }>(data)
}

export async function saveDraftPrize(
  client: ChicSupabaseClient,
  campaignId: string,
  versionId: string,
  input: PrizeInput,
) {
  const { data, error } = await client.rpc('save_draft_prize', {
    p_campaign_id: campaignId,
    p_campaign_version_id: versionId,
    p_prize_id: input.prizeId,
    p_name: input.name.trim(),
    p_type: input.type,
    p_customer_description: input.customerDescription.trim(),
    p_customer_value_vnd: input.customerValueVnd,
    p_estimated_chic_cost_vnd: input.estimatedChicCostVnd,
    p_discount_percent: input.type === 'PERCENT_DISCOUNT' ? input.discountPercent : null,
    p_minimum_spend_vnd: input.minimumSpendVnd,
    p_applicable_service: input.applicableService?.trim() || null,
    p_expiry_days: input.expiryDays,
    p_weight: input.isFallback ? 1 : input.weight,
    p_max_quantity: input.isFallback ? null : input.maxQuantity,
    p_is_fallback: input.isFallback,
    p_active: input.active,
  })
  handleRpcError(error)
  return unwrapObject<{ prize_id: string; saved: boolean }>(data)
}

export async function deleteDraftPrize(
  client: ChicSupabaseClient,
  campaignId: string,
  versionId: string,
  prizeId: string,
) {
  const { data, error } = await client.rpc('delete_draft_prize', {
    p_campaign_id: campaignId,
    p_campaign_version_id: versionId,
    p_prize_id: prizeId,
  })
  handleRpcError(error)
  return data === true
}

export async function validateCampaignVersion(
  client: ChicSupabaseClient,
  campaignId: string,
  versionId: string,
) {
  const { data, error } = await client.rpc('validate_campaign_version', {
    p_campaign_id: campaignId,
    p_campaign_version_id: versionId,
  })
  handleRpcError(error)
  return unwrapObject<CampaignValidation>(data)
}

export async function publishCampaignVersion(
  client: ChicSupabaseClient,
  campaignId: string,
  versionId: string,
) {
  const { data, error } = await client.rpc('publish_campaign_version', {
    p_campaign_id: campaignId,
    p_campaign_version_id: versionId,
  })
  handleRpcError(error)
  return unwrapObject<{ published_at: string }>(data)
}

export async function createNewCampaignVersion(client: ChicSupabaseClient, campaignId: string) {
  const { data, error } = await client.rpc('create_new_campaign_version', {
    p_campaign_id: campaignId,
  })
  handleRpcError(error)
  return unwrapObject<{ campaign_version_id: string; version_number: number }>(data)
}

export async function setCampaignLifecycle(
  client: ChicSupabaseClient,
  campaignId: string,
  action: 'ACTIVATE' | 'PAUSE' | 'RESUME' | 'END' | 'ARCHIVE',
  confirmed = false,
) {
  const { data, error } = await client.rpc('set_campaign_lifecycle', {
    p_campaign_id: campaignId,
    p_action: action,
    p_confirmed: confirmed,
  })
  handleRpcError(error)
  return unwrapObject<{ previous_status: CampaignStatus; status: CampaignStatus }>(data)
}

export const campaignStatusLabels: Record<CampaignStatus, string> = {
  DRAFT: 'Bản nháp',
  SCHEDULED: 'Đã lên lịch',
  ACTIVE: 'Đang hoạt động',
  PAUSED: 'Đang tạm dừng',
  ENDED: 'Đã kết thúc',
  ARCHIVED: 'Đã lưu trữ',
}

export const prizeTypeLabels: Record<PrizeType, string> = {
  CASH_VOUCHER: 'Voucher tiền mặt',
  PERCENT_DISCOUNT: 'Giảm theo phần trăm',
  FREE_SERVICE: 'Dịch vụ miễn phí',
  SERVICE_DISCOUNT: 'Giảm giá dịch vụ',
  SERVICE_UPGRADE: 'Nâng cấp dịch vụ',
  CUSTOM_REWARD: 'Quà tùy chỉnh',
}

export function canEditCampaignVersion(status: CampaignStatus, publishedAt: string | null) {
  return !publishedAt && !['ACTIVE', 'ENDED', 'ARCHIVED'].includes(status)
}

export function getCampaignInputErrors(input: CampaignDraftInput) {
  const errors: string[] = []
  if (!input.name.trim()) errors.push('Vui lòng nhập tên chương trình.')
  if (!input.headline.trim()) errors.push('Vui lòng nhập tiêu đề hiển thị cho khách.')
  if (!input.startAt || !input.endAt || new Date(input.endAt) <= new Date(input.startAt)) {
    errors.push('Thời gian kết thúc phải sau thời gian bắt đầu.')
  }
  if (!Number.isSafeInteger(input.minBillVnd) || input.minBillVnd < 0) {
    errors.push('Bill tối thiểu phải là số nguyên VND không âm.')
  }
  if (!Number.isSafeInteger(input.giftOpenDeadlineHours) || input.giftOpenDeadlineHours <= 0) {
    errors.push('Hạn mở quà phải là số giờ nguyên dương.')
  }
  return errors
}

export function getPrizeInputErrors(input: PrizeInput) {
  const errors: string[] = []
  if (!input.name.trim()) errors.push('Vui lòng nhập tên quà.')
  if (!input.customerDescription.trim()) errors.push('Vui lòng nhập mô tả dành cho khách.')
  const moneyValues = [input.customerValueVnd, input.estimatedChicCostVnd, input.minimumSpendVnd]
  if (moneyValues.some((value) => !Number.isSafeInteger(value) || value < 0)) {
    errors.push('Các giá trị tiền phải là số nguyên VND không âm.')
  }
  if (!Number.isSafeInteger(input.expiryDays) || input.expiryDays <= 0) {
    errors.push('Hạn sử dụng phải là số ngày nguyên dương.')
  }
  if (!input.isFallback && (!Number.isSafeInteger(input.weight) || input.weight <= 0)) {
    errors.push('Trọng số phải là số nguyên dương.')
  }
  if (input.maxQuantity !== null && (!Number.isSafeInteger(input.maxQuantity) || input.maxQuantity <= 0)) {
    errors.push('Số lượng tối đa phải là số nguyên dương hoặc không giới hạn.')
  }
  if (input.type === 'PERCENT_DISCOUNT'
    && (input.discountPercent === null || input.discountPercent <= 0 || input.discountPercent > 100)) {
    errors.push('Mức giảm phải lớn hơn 0% và không quá 100%.')
  }
  return errors
}

export function getValidationMessages(validation: CampaignValidation | null) {
  if (!validation) return []
  const labels: Record<string, string> = {
    INVALID_DATES: 'Thời gian chương trình chưa hợp lệ.',
    NORMAL_PRIZE_REQUIRED: 'Cần ít nhất một quà thường đang hoạt động.',
    FALLBACK_REQUIRED: 'Chưa có quà dự phòng.',
    MULTIPLE_FALLBACKS: 'Chỉ được có một quà dự phòng.',
    FALLBACK_MUST_BE_ACTIVE_UNLIMITED: 'Quà dự phòng phải hoạt động và không giới hạn số lượng.',
  }
  return validation.issues.map((issue) => labels[issue] ?? 'Cấu hình chưa hợp lệ.')
}

export function presentAdminError(error: unknown) {
  if (error instanceof AdminCampaignError) {
    if (error.kind === 'unauthorized') return 'Phiên làm việc không còn quyền Admin.'
    if (error.message.includes('Another Campaign is already active')) {
      return 'Chi nhánh đang có một chương trình hoạt động. Hãy tạm dừng hoặc kết thúc chương trình đó trước.'
    }
    if (error.message.includes('date window')) {
      return 'Chương trình chưa nằm trong thời gian có hiệu lực.'
    }
    if (error.kind === 'validation') return 'Cấu hình chưa hợp lệ. Vui lòng kiểm tra lại các mục được đánh dấu.'
  }
  return 'Không thể hoàn tất thao tác. Vui lòng kiểm tra kết nối và thử lại.'
}
