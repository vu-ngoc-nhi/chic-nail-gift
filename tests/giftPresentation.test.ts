import assert from 'node:assert/strict'
import test from 'node:test'
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
} from '../src/features/gifts/giftPresentation.ts'

function result(overrides: Partial<CreateGiftResult>): CreateGiftResult {
  return {
    result_code: 'CREATED_GIFT',
    bill_code: 'HD00123',
    bill_amount_vnd: 385000,
    gift_status: 'ELIGIBLE',
    gift_token: 'a'.repeat(64),
    created_at: '2026-09-06T00:00:00Z',
    is_new: true,
    minimum_bill_vnd: 200000,
    ...overrides,
  }
}

test('normalizes Bill Code for display and rejects internal whitespace', () => {
  assert.equal(normalizeBillCode('  hd00123  '), 'HD00123')
  assert.equal(hasInternalWhitespace('HD 00123'), true)
  assert.equal(hasInternalWhitespace(' HD00123 '), false)
})

test('keeps VND input integer-only and formats it naturally', () => {
  assert.equal(amountDigits('385.000đ'), '385000')
  assert.equal(formatAmountInput('385000'), '385.000')
  assert.equal(parseVndAmount('385000'), 385000)
  assert.equal(parseVndAmount('0'), null)
  assert.equal(formatVnd(385000), '385.000đ')
})

test('builds the future customer URL from one centralized helper', () => {
  assert.equal(
    buildPublicGiftUrl('https://gift.chic.test/', 'token_123'),
    'https://gift.chic.test/g/token_123',
  )
})

test('presents new and existing Gifts as recoverable results', () => {
  assert.deepEqual(presentGiftResult(result({})), {
    tone: 'success',
    title: 'Quà đã sẵn sàng 🎁',
    message: 'Gửi đường dẫn bên dưới để khách mở quà.',
    showsGift: true,
  })
  assert.equal(
    presentGiftResult(result({ result_code: 'EXISTING_GIFT', is_new: false })).showsGift,
    true,
  )
})

test('presents mismatch, minimum, campaign, and invalid results safely', () => {
  assert.equal(presentGiftResult(result({ result_code: 'AMOUNT_MISMATCH' })).showsGift, false)
  assert.match(
    presentGiftResult(result({ result_code: 'BILL_BELOW_MINIMUM' })).message,
    /200\.000đ/,
  )
  assert.match(
    presentGiftResult(result({ result_code: 'NO_ACTIVE_CAMPAIGN' })).message,
    /báo quản lý/,
  )
  assert.equal(presentGiftResult(result({ result_code: 'INVALID_BILL_CODE' })).tone, 'error')
  assert.equal(presentGiftResult(result({ result_code: 'INVALID_BILL_AMOUNT' })).tone, 'error')
})
