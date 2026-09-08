import type { ChicSupabaseClient } from '../../lib/supabase.ts'
import { formatVnd } from './giftPresentation.ts'

export const SECRET_CARD_COUNT = 9
export const MINIMUM_OPENING_DURATION_MS = 900

export function lockSecretCardSelection(currentSelection: number | null, requestedCard: number) {
  if (
    currentSelection !== null
    || !Number.isInteger(requestedCard)
    || requestedCard < 0
    || requestedCard >= SECRET_CARD_COUNT
  ) {
    return currentSelection
  }

  return requestedCard
}

export function getOpeningDelay(reduceMotion: boolean, withOpeningMoment: boolean) {
  return reduceMotion || !withOpeningMoment ? 0 : MINIMUM_OPENING_DURATION_MS
}

export type OpenGiftResult = {
  result_code: string
  reward_available: boolean
  reward_status: string | null
  reward_name: string | null
  reward_description: string | null
  reward_type: string | null
  customer_value_vnd: number | null
  minimum_spend_vnd: number | null
  applicable_service: string | null
  discount_percent: number | null
  reward_terms: string | null
  reward_code: string | null
  reward_expires_at: string | null
}

export type RewardPresentation = {
  benefit: string
  expiry: string
  description: string | null
  applicableService: string | null
  minimumSpend: string | null
  discountPercent: string | null
  terms: string | null
}

export type UnavailableGiftPresentation = {
  title: string
  message: string
}

export async function openGift(client: ChicSupabaseClient, giftToken: string) {
  const { data, error } = await client.rpc('open_gift', {
    p_gift_token: giftToken,
  })

  if (error) {
    throw new Error('OPEN_GIFT_REQUEST_FAILED')
  }

  const result = (Array.isArray(data) ? data[0] : data) as OpenGiftResult | undefined
  if (!result?.result_code) {
    throw new Error('OPEN_GIFT_REQUEST_FAILED')
  }

  return result
}

export function isRewardResult(result: OpenGiftResult) {
  return (
    (result.result_code === 'OPENED_NOW' || result.result_code === 'ALREADY_OPENED')
    && result.reward_available
    && Boolean(result.reward_name?.trim())
    && Boolean(result.reward_code?.trim())
    && Boolean(result.reward_expires_at)
  )
}

function formatPercent(value: number) {
  return new Intl.NumberFormat('vi-VN', { maximumFractionDigits: 2 }).format(value)
}

export function formatRewardBenefit(result: OpenGiftResult) {
  if (result.reward_type === 'PERCENT_DISCOUNT' && result.discount_percent) {
    return `Giảm ${formatPercent(result.discount_percent)}%`
  }

  if (result.reward_type === 'FREE_SERVICE') {
    return result.applicable_service?.trim()
      ? `Miễn phí ${result.applicable_service.trim()}`
      : result.reward_name?.trim() || 'Dịch vụ miễn phí'
  }

  if (result.customer_value_vnd && result.customer_value_vnd > 0) {
    return formatVnd(result.customer_value_vnd)
  }

  return result.reward_description?.trim() || result.reward_name?.trim() || 'Phần quà từ CHIC GIFT'
}

export function formatRewardExpiry(value: string) {
  const parsed = new Date(value)
  if (Number.isNaN(parsed.getTime())) {
    return ''
  }

  return new Intl.DateTimeFormat('vi-VN', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    timeZone: 'Asia/Ho_Chi_Minh',
  }).format(parsed)
}

export function presentReward(result: OpenGiftResult): RewardPresentation {
  return {
    benefit: formatRewardBenefit(result),
    expiry: result.reward_expires_at ? formatRewardExpiry(result.reward_expires_at) : '',
    description: result.reward_description?.trim() || null,
    applicableService: result.applicable_service?.trim() || null,
    minimumSpend: result.minimum_spend_vnd && result.minimum_spend_vnd > 0
      ? `Áp dụng cho hóa đơn từ ${formatVnd(result.minimum_spend_vnd)}`
      : null,
    discountPercent: result.discount_percent && result.discount_percent > 0
      ? `Giảm ${formatPercent(result.discount_percent)}%`
      : null,
    terms: result.reward_terms?.trim() || null,
  }
}

export function presentOpenGiftUnavailable(resultCode: string): UnavailableGiftPresentation {
  if (resultCode === 'INVALID_GIFT') {
    return {
      title: 'Không tìm thấy phần quà này.',
      message: 'Vui lòng kiểm tra lại mã QR hoặc liên hệ nhân viên để được hỗ trợ.',
    }
  }

  if (resultCode === 'OPEN_WINDOW_EXPIRED') {
    return {
      title: 'Thời gian mở quà đã kết thúc.',
      message: 'Cảm ơn bạn đã tham gia chương trình.',
    }
  }

  return {
    title: 'Phần quà này hiện không khả dụng.',
    message: 'Vui lòng liên hệ nhân viên để được hỗ trợ.',
  }
}
