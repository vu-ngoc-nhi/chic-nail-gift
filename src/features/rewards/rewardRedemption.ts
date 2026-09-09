import type { ChicSupabaseClient } from '../../lib/supabase.ts'
import { formatVnd } from '../gifts/giftPresentation.ts'

export type RedemptionResultCode =
  | 'REWARD_AVAILABLE'
  | 'REWARD_NOT_FOUND'
  | 'REDEEMED'
  | 'ALREADY_REDEEMED'
  | 'REWARD_EXPIRED'
  | 'CANCELLED'
  | 'WRONG_BRANCH'
  | 'MINIMUM_SPEND_NOT_MET'
  | 'CONDITIONS_NOT_CONFIRMED'
  | 'INVALID_REDEMPTION_BILL_CODE'
  | 'INVALID_REDEMPTION_BILL_AMOUNT'

export type StaffRewardResult = {
  result_code: RedemptionResultCode
  reward_status: string | null
  reward_name: string | null
  reward_description: string | null
  reward_type: string | null
  customer_value_vnd: number | null
  discount_percent: number | null
  minimum_spend_vnd: number | null
  applicable_service: string | null
  reward_terms: string | null
  reward_code: string | null
  reward_expires_at: string | null
  redeemable: boolean
  redeemed_at: string | null
  redemption_bill_code: string | null
}

export type RedemptionPresentation = {
  tone: 'success' | 'info' | 'warning' | 'error'
  title: string
  message: string
}

export class RewardRedemptionError extends Error {
  readonly kind: 'unauthorized' | 'request-failed'

  constructor(kind: 'unauthorized' | 'request-failed') {
    super(kind)
    this.name = 'RewardRedemptionError'
    this.kind = kind
  }
}

export function normalizeRewardCode(value: string) {
  return value.trim().toUpperCase()
}

export function isValidRewardCode(value: string) {
  return /^CHIC-[A-Z0-9]{5,16}$/.test(normalizeRewardCode(value))
}

function unwrapResult(data: unknown) {
  const result = (Array.isArray(data) ? data[0] : data) as StaffRewardResult | undefined
  if (!result?.result_code) {
    throw new RewardRedemptionError('request-failed')
  }
  return result
}

function handleRpcError(error: { code?: string } | null) {
  if (error) {
    throw new RewardRedemptionError(error.code === '42501' ? 'unauthorized' : 'request-failed')
  }
}

export async function lookupReward(client: ChicSupabaseClient, rewardCode: string) {
  const { data, error } = await client.rpc('get_reward_for_redemption', {
    p_reward_code: normalizeRewardCode(rewardCode),
  })
  handleRpcError(error)
  return unwrapResult(data)
}

export async function redeemReward(
  client: ChicSupabaseClient,
  rewardCode: string,
  redemptionBillCode: string,
  redemptionBillAmountVnd: number,
  conditionsConfirmed: boolean,
) {
  const { data, error } = await client.rpc('redeem_reward', {
    p_reward_code: normalizeRewardCode(rewardCode),
    p_redemption_bill_code: redemptionBillCode.trim().toUpperCase(),
    p_redemption_bill_amount_vnd: redemptionBillAmountVnd,
    p_conditions_confirmed: conditionsConfirmed,
  })
  handleRpcError(error)
  return unwrapResult(data)
}

export function presentRedemptionResult(resultCode: RedemptionResultCode): RedemptionPresentation {
  switch (resultCode) {
    case 'REWARD_AVAILABLE':
      return {
        tone: 'info',
        title: 'Quà có thể sử dụng',
        message: 'Kiểm tra bill, dịch vụ và điều kiện trước khi xác nhận.',
      }
    case 'REDEEMED':
      return {
        tone: 'success',
        title: 'Đã xác nhận sử dụng quà ✓',
        message: 'Giao dịch đã được lưu và không thể sử dụng lại.',
      }
    case 'ALREADY_REDEEMED':
      return {
        tone: 'warning',
        title: 'Quà đã được sử dụng',
        message: 'Quà này đã được xác nhận sử dụng trước đó.',
      }
    case 'REWARD_EXPIRED':
      return {
        tone: 'warning',
        title: 'Quà đã hết hạn sử dụng',
        message: 'Không thể xác nhận sử dụng quà này.',
      }
    case 'MINIMUM_SPEND_NOT_MET':
      return {
        tone: 'warning',
        title: 'Bill chưa đủ điều kiện',
        message: 'Bill chưa đạt giá trị tối thiểu để sử dụng quà này.',
      }
    case 'WRONG_BRANCH':
      return {
        tone: 'error',
        title: 'Không đúng chi nhánh',
        message: 'Quà này không thuộc chi nhánh hiện tại.',
      }
    case 'CANCELLED':
      return {
        tone: 'warning',
        title: 'Quà không còn hiệu lực',
        message: 'Không thể xác nhận sử dụng quà này.',
      }
    case 'CONDITIONS_NOT_CONFIRMED':
      return {
        tone: 'warning',
        title: 'Chưa xác nhận điều kiện',
        message: 'Vui lòng kiểm tra bill, dịch vụ và điều kiện áp dụng.',
      }
    case 'INVALID_REDEMPTION_BILL_CODE':
      return {
        tone: 'error',
        title: 'Mã bill chưa hợp lệ',
        message: 'Kiểm tra lại mã bill trên KiotViet.',
      }
    case 'INVALID_REDEMPTION_BILL_AMOUNT':
      return {
        tone: 'error',
        title: 'Giá trị bill chưa hợp lệ',
        message: 'Giá trị bill phải là số nguyên VND lớn hơn 0.',
      }
    default:
      return {
        tone: 'error',
        title: 'Không tìm thấy mã quà',
        message: 'Vui lòng kiểm tra lại mã quà.',
      }
  }
}

export function formatStaffDateTime(value: string | null) {
  if (!value) {
    return '—'
  }
  const parsed = new Date(value)
  if (Number.isNaN(parsed.getTime())) {
    return '—'
  }
  return new Intl.DateTimeFormat('vi-VN', {
    dateStyle: 'short',
    timeStyle: 'short',
    timeZone: 'Asia/Ho_Chi_Minh',
  }).format(parsed)
}

export function formatRewardValue(result: StaffRewardResult) {
  if (result.reward_type === 'PERCENT_DISCOUNT' && result.discount_percent) {
    return `Giảm ${new Intl.NumberFormat('vi-VN', { maximumFractionDigits: 2 }).format(result.discount_percent)}%`
  }
  if (result.reward_type === 'FREE_SERVICE' && result.applicable_service?.trim()) {
    return `Miễn phí ${result.applicable_service.trim()}`
  }
  if (result.customer_value_vnd && result.customer_value_vnd > 0) {
    return formatVnd(result.customer_value_vnd)
  }
  return result.reward_description?.trim() || result.reward_name?.trim() || 'Phần quà từ CHIC GIFT'
}
