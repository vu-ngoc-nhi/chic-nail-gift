import assert from 'node:assert/strict'
import test from 'node:test'
import type { ChicSupabaseClient } from '../src/lib/supabase.ts'
import {
  getPublicGift,
  presentPublicGift,
  type PublicGiftResult,
} from '../src/features/gifts/publicGift.ts'

function result(overrides: Partial<PublicGiftResult> = {}): PublicGiftResult {
  return {
    result_code: 'GIFT_AVAILABLE',
    valid: true,
    gift_status: 'ELIGIBLE',
    may_open: true,
    campaign_headline: 'Quà xinh dành riêng cho bạn',
    campaign_description: 'Cảm ơn bạn đã mua sắm tại CHIC GIFT.',
    campaign_terms: 'Mỗi hóa đơn nhận một lượt mở quà.',
    ...overrides,
  }
}

test('loads a public Gift through only the approved safe RPC', async () => {
  let rpcName = ''
  let rpcArguments: unknown
  const safeResult = result()
  const client = {
    rpc: async (name: string, args: unknown) => {
      rpcName = name
      rpcArguments = args
      return { data: [safeResult], error: null }
    },
  } as unknown as ChicSupabaseClient

  assert.deepEqual(await getPublicGift(client, 'opaque_token'), safeResult)
  assert.equal(rpcName, 'get_public_gift')
  assert.deepEqual(rpcArguments, { p_gift_token: 'opaque_token' })
  assert.deepEqual(Object.keys(safeResult).sort(), [
    'campaign_description',
    'campaign_headline',
    'campaign_terms',
    'gift_status',
    'may_open',
    'result_code',
    'valid',
  ])
})

test('presents only approved campaign content for an eligible Gift', () => {
  assert.deepEqual(presentPublicGift(result()), {
    tone: 'available',
    title: 'Quà của bạn đã sẵn sàng',
    message: 'Bạn đã vào đúng phần quà dành cho hóa đơn này.',
    showCampaign: true,
    showFutureAction: true,
  })
})

test('handles invalid and cancelled Gifts without internal detail', () => {
  const invalid = presentPublicGift(result({ result_code: 'INVALID_GIFT', valid: false }))
  assert.equal(invalid.title, 'Không tìm thấy phần quà này.')
  assert.equal(invalid.showCampaign, false)

  const cancelled = presentPublicGift(result({ result_code: 'GIFT_UNAVAILABLE', gift_status: 'CANCELLED' }))
  assert.equal(cancelled.title, 'Phần quà này hiện không khả dụng.')
  assert.equal(cancelled.showCampaign, false)
})

test('handles expired and opened Gifts without fabricating a Reward', () => {
  const expired = presentPublicGift(result({ result_code: 'OPEN_WINDOW_EXPIRED', may_open: false }))
  assert.equal(expired.title, 'Thời gian mở quà đã kết thúc.')
  assert.equal(expired.showFutureAction, false)

  const opened = presentPublicGift(result({ result_code: 'GIFT_OPENED', gift_status: 'OPENED', may_open: false }))
  assert.equal(opened.title, 'Phần quà này đã được mở.')
  assert.equal(opened.showFutureAction, false)
})
