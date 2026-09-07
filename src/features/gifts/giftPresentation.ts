export type CreateGiftResultCode =
  | 'CREATED_GIFT'
  | 'EXISTING_GIFT'
  | 'AMOUNT_MISMATCH'
  | 'BILL_BELOW_MINIMUM'
  | 'NO_ACTIVE_CAMPAIGN'
  | 'INVALID_BILL_CODE'
  | 'INVALID_BILL_AMOUNT'

export type CreateGiftResult = {
  result_code: CreateGiftResultCode
  bill_code: string | null
  bill_amount_vnd: number | null
  gift_status: string | null
  gift_token: string | null
  created_at: string | null
  is_new: boolean
  minimum_bill_vnd: number | null
}

export type GiftResultPresentation = {
  tone: 'success' | 'info' | 'warning' | 'error'
  title: string
  message: string
  showsGift: boolean
}

export function normalizeBillCode(value: string) {
  return value.trim().toUpperCase()
}

export function hasInternalWhitespace(value: string) {
  return /\s/.test(normalizeBillCode(value))
}

export function amountDigits(value: string) {
  return value.replace(/\D/g, '').slice(0, 15)
}

export function parseVndAmount(value: string) {
  if (!value) {
    return null
  }

  const amount = Number(value)
  return Number.isSafeInteger(amount) && amount > 0 ? amount : null
}

export function formatVnd(value: number | string) {
  const amount = typeof value === 'number' ? value : Number(value)
  return Number.isSafeInteger(amount)
    ? `${new Intl.NumberFormat('vi-VN').format(amount)}đ`
    : ''
}

export function formatAmountInput(value: string) {
  return value ? new Intl.NumberFormat('vi-VN').format(Number(value)) : ''
}

export function buildPublicGiftUrl(baseUrl: string, giftToken: string) {
  return `${baseUrl.replace(/\/+$/, '')}/g/${encodeURIComponent(giftToken)}`
}

export function getGiftTokenFromPath(pathname: string) {
  if (pathname === '/g' || pathname === '/g/') {
    return ''
  }

  const match = /^\/g\/([^/]+)\/?$/.exec(pathname)
  if (!match) {
    return null
  }

  try {
    return decodeURIComponent(match[1])
  } catch {
    return ''
  }
}

export function presentGiftResult(result: CreateGiftResult): GiftResultPresentation {
  switch (result.result_code) {
    case 'CREATED_GIFT':
      return {
        tone: 'success',
        title: 'Quà đã sẵn sàng 🎁',
        message: 'Mời khách quét mã để tiếp tục nhận quà.',
        showsGift: true,
      }
    case 'EXISTING_GIFT':
      return {
        tone: 'info',
        title: 'Bill này đã được tạo quà trước đó.',
        message: 'Mời khách sử dụng lại mã QR bên dưới.',
        showsGift: true,
      }
    case 'AMOUNT_MISMATCH':
      return {
        tone: 'warning',
        title: 'Giá trị hóa đơn không khớp',
        message: 'Mã bill này đã tồn tại nhưng giá trị không khớp. Vui lòng kiểm tra lại hóa đơn trên KiotViet.',
        showsGift: false,
      }
    case 'BILL_BELOW_MINIMUM':
      return {
        tone: 'warning',
        title: 'Bill chưa đủ điều kiện nhận quà',
        message: result.minimum_bill_vnd === null
          ? 'Vui lòng kiểm tra điều kiện của chương trình hiện tại.'
          : `Giá trị tối thiểu hiện tại là ${formatVnd(result.minimum_bill_vnd)}.`,
        showsGift: false,
      }
    case 'NO_ACTIVE_CAMPAIGN':
      return {
        tone: 'warning',
        title: 'Chưa có chương trình đang hoạt động',
        message: 'Hiện chưa có chương trình quà tặng đang hoạt động. Vui lòng báo quản lý.',
        showsGift: false,
      }
    case 'INVALID_BILL_CODE':
      return {
        tone: 'error',
        title: 'Mã bill không hợp lệ',
        message: 'Vui lòng kiểm tra lại mã hóa đơn trên KiotViet.',
        showsGift: false,
      }
    case 'INVALID_BILL_AMOUNT':
      return {
        tone: 'error',
        title: 'Giá trị hóa đơn không hợp lệ',
        message: 'Vui lòng nhập giá trị lớn hơn 0đ.',
        showsGift: false,
      }
    default:
      return {
        tone: 'error',
        title: 'Không thể tạo quà',
        message: 'Vui lòng thử lại hoặc báo quản lý nếu lỗi tiếp tục xảy ra.',
        showsGift: false,
      }
  }
}
