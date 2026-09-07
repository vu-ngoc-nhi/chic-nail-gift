import type { ChicSupabaseClient } from '../../lib/supabase.ts'
import { CUSTOMER_BRAND_NAME } from '../../config/presentation.ts'

export type PublicGiftResult = {
  result_code: string
  valid: boolean
  gift_status: string | null
  may_open: boolean
  campaign_headline: string | null
  campaign_description: string | null
  campaign_terms: string | null
}

export type PublicGiftPresentation = {
  tone: 'available' | 'neutral' | 'unavailable'
  title: string
  message: string
  showCampaign: boolean
  showFutureAction: boolean
}

export async function getPublicGift(client: ChicSupabaseClient, giftToken: string) {
  const { data, error } = await client.rpc('get_public_gift', {
    p_gift_token: giftToken,
  })

  if (error) {
    throw new Error('PUBLIC_GIFT_REQUEST_FAILED')
  }

  const result = (Array.isArray(data) ? data[0] : data) as PublicGiftResult | undefined
  if (!result?.result_code) {
    throw new Error('PUBLIC_GIFT_REQUEST_FAILED')
  }

  return result
}

export function presentPublicGift(result: PublicGiftResult): PublicGiftPresentation {
  if (!result.valid || result.result_code === 'INVALID_GIFT') {
    return {
      tone: 'unavailable',
      title: 'Không tìm thấy phần quà này.',
      message: `Vui lòng kiểm tra lại mã QR hoặc liên hệ nhân viên ${CUSTOMER_BRAND_NAME} để được hỗ trợ.`,
      showCampaign: false,
      showFutureAction: false,
    }
  }

  if (result.result_code === 'GIFT_UNAVAILABLE' || result.gift_status === 'CANCELLED') {
    return {
      tone: 'unavailable',
      title: 'Phần quà này hiện không khả dụng.',
      message: `Vui lòng liên hệ nhân viên ${CUSTOMER_BRAND_NAME} để được hỗ trợ.`,
      showCampaign: false,
      showFutureAction: false,
    }
  }

  if (result.result_code === 'OPEN_WINDOW_EXPIRED') {
    return {
      tone: 'unavailable',
      title: 'Thời gian mở quà đã kết thúc.',
      message: `Cảm ơn bạn đã tham gia chương trình của ${CUSTOMER_BRAND_NAME}.`,
      showCampaign: true,
      showFutureAction: false,
    }
  }

  if (result.result_code === 'GIFT_OPENED') {
    return {
      tone: 'neutral',
      title: 'Phần quà này đã được mở.',
      message: 'Thông tin quà sẽ được hiển thị ở bước tiếp theo.',
      showCampaign: true,
      showFutureAction: false,
    }
  }

  if (result.result_code === 'GIFT_AVAILABLE' && result.may_open) {
    return {
      tone: 'available',
      title: 'Quà của bạn đã sẵn sàng',
      message: 'Bạn đã vào đúng phần quà dành cho hóa đơn này.',
      showCampaign: true,
      showFutureAction: true,
    }
  }

  return {
    tone: 'unavailable',
    title: 'Phần quà này hiện không khả dụng.',
    message: `Vui lòng liên hệ nhân viên ${CUSTOMER_BRAND_NAME} để được hỗ trợ.`,
    showCampaign: false,
    showFutureAction: false,
  }
}
