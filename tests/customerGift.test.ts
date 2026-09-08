import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import type { ChicSupabaseClient } from '../src/lib/supabase.ts'
import {
  getOpeningDelay,
  isRewardResult,
  lockSecretCardSelection,
  MINIMUM_OPENING_DURATION_MS,
  openGift,
  presentOpenGiftUnavailable,
  presentReward,
  SECRET_CARD_COUNT,
  type OpenGiftResult,
} from '../src/features/gifts/customerGift.ts'

function reward(overrides: Partial<OpenGiftResult> = {}): OpenGiftResult {
  return {
    result_code: 'OPENED_NOW',
    reward_available: true,
    reward_status: 'AVAILABLE',
    reward_name: 'Chăm sóc móng thanh lịch',
    reward_description: 'Tặng bạn một buổi chăm sóc móng cơ bản.',
    reward_type: 'FREE_SERVICE',
    customer_value_vnd: 0,
    minimum_spend_vnd: 300000,
    applicable_service: 'Chăm sóc móng cơ bản',
    discount_percent: null,
    reward_terms: 'Áp dụng một lần tại Chic.',
    reward_code: 'CHIC-UAT3B1',
    reward_expires_at: '2026-09-30T16:59:59Z',
    ...overrides,
  }
}

test('UI01-UI03: exposes exactly nine cards and locks the first valid selection', () => {
  assert.equal(SECRET_CARD_COUNT, 9)
  assert.equal(lockSecretCardSelection(null, 4), 4)
  assert.equal(lockSecretCardSelection(4, 7), 4)
  assert.equal(lockSecretCardSelection(null, -1), null)
  assert.equal(lockSecretCardSelection(null, 9), null)
})

test('UI04-UI07 and INT01: open_gift receives the Gift Token and no selection data', async () => {
  let rpcName = ''
  let rpcArguments: unknown
  const safeReward = reward()
  const client = {
    rpc: async (name: string, args: unknown) => {
      rpcName = name
      rpcArguments = args
      return { data: [safeReward], error: null }
    },
  } as unknown as ChicSupabaseClient

  assert.deepEqual(await openGift(client, 'opaque_gift_token'), safeReward)
  assert.equal(rpcName, 'open_gift')
  assert.deepEqual(rpcArguments, { p_gift_token: 'opaque_gift_token' })
  assert.deepEqual(Object.keys(rpcArguments as object), ['p_gift_token'])
})

test('UI08-UI10 and INT02-INT03: both successful outcomes map to persisted Reward data', () => {
  const openedNow = reward()
  const alreadyOpened = reward({ result_code: 'ALREADY_OPENED' })

  assert.equal(isRewardResult(openedNow), true)
  assert.equal(isRewardResult(alreadyOpened), true)
  assert.deepEqual(presentReward(alreadyOpened), presentReward(openedNow))
  assert.equal(isRewardResult(reward({ reward_code: null })), false)
})

test('UI11-UI20: formats Reward benefit, expiry, conditions, and optional fields safely', () => {
  assert.deepEqual(presentReward(reward()), {
    benefit: 'Miễn phí Chăm sóc móng cơ bản',
    expiry: '30/09/2026',
    description: 'Tặng bạn một buổi chăm sóc móng cơ bản.',
    applicableService: 'Chăm sóc móng cơ bản',
    minimumSpend: 'Áp dụng cho hóa đơn từ 300.000đ',
    discountPercent: null,
    terms: 'Áp dụng một lần tại Chic.',
  })

  const percent = presentReward(reward({
    reward_type: 'PERCENT_DISCOUNT',
    discount_percent: 20,
    customer_value_vnd: 0,
    applicable_service: null,
    minimum_spend_vnd: 0,
    reward_description: null,
    reward_terms: '',
  }))
  assert.equal(percent.benefit, 'Giảm 20%')
  assert.equal(percent.discountPercent, 'Giảm 20%')
  assert.equal(percent.applicableService, null)
  assert.equal(percent.minimumSpend, null)
  assert.equal(percent.description, null)
  assert.equal(percent.terms, null)

  assert.equal(presentReward(reward({
    reward_type: 'CASH_VOUCHER',
    customer_value_vnd: 150000,
  })).benefit, '150.000đ')
})

test('UI21-UI23: unavailable open outcomes retain safe Vietnamese messages', () => {
  assert.equal(presentOpenGiftUnavailable('INVALID_GIFT').title, 'Không tìm thấy phần quà này.')
  assert.equal(presentOpenGiftUnavailable('GIFT_CANCELLED').title, 'Phần quà này hiện không khả dụng.')
  assert.equal(presentOpenGiftUnavailable('OPEN_WINDOW_EXPIRED').title, 'Thời gian mở quà đã kết thúc.')
})

test('UI24-UI26 and INT08: retry uses the same idempotent token-only operation', async () => {
  const calls: unknown[] = []
  const persisted = reward({ result_code: 'ALREADY_OPENED' })
  const client = {
    rpc: async (_name: string, args: unknown) => {
      calls.push(args)
      return calls.length === 1
        ? { data: null, error: { message: 'response lost' } }
        : { data: [persisted], error: null }
    },
  } as unknown as ChicSupabaseClient

  await assert.rejects(() => openGift(client, 'same_opaque_token'), /OPEN_GIFT_REQUEST_FAILED/)
  assert.deepEqual(await openGift(client, 'same_opaque_token'), persisted)
  assert.deepEqual(calls, [
    { p_gift_token: 'same_opaque_token' },
    { p_gift_token: 'same_opaque_token' },
  ])
})

test('UI27-UI28: opening delay is visible by default and skipped for reduced motion', () => {
  assert.equal(MINIMUM_OPENING_DURATION_MS, 900)
  assert.equal(getOpeningDelay(false, true), 900)
  assert.equal(getOpeningDelay(true, true), 0)
  assert.equal(getOpeningDelay(false, false), 0)
})

test('UI29-UI30 and INT05-INT06: frontend uses only safe RPC data and browser-safe storage', () => {
  const safeKeys = Object.keys(reward()).sort()
  assert.deepEqual(safeKeys, [
    'applicable_service',
    'customer_value_vnd',
    'discount_percent',
    'minimum_spend_vnd',
    'result_code',
    'reward_available',
    'reward_code',
    'reward_description',
    'reward_expires_at',
    'reward_name',
    'reward_status',
    'reward_terms',
    'reward_type',
  ])

  const pageSource = readFileSync(new URL('../src/features/gifts/PublicGiftPage.tsx', import.meta.url), 'utf8')
  const clientSource = readFileSync(new URL('../src/features/gifts/customerGift.ts', import.meta.url), 'utf8')
  const cssSource = readFileSync(new URL('../src/App.css', import.meta.url), 'utf8')
  const combinedSource = `${pageSource}\n${clientSource}`

  assert.doesNotMatch(combinedSource, /Math\.random|localStorage|sessionStorage|service_role|sb_secret/i)
  assert.doesNotMatch(combinedSource, /estimated_chic_cost|issued_quantity|max_quantity|\bweight\b|bill_code|staff_profile/i)
  assert.doesNotMatch(combinedSource, /supabase\.from\s*\(/)
  assert.match(pageSource, /<button[\s\S]*?className={`secret-card/)
  assert.match(pageSource, /aria-pressed=/)
  assert.match(pageSource, /aria-live="polite"/)
  assert.match(cssSource, /@media \(prefers-reduced-motion: reduce\)/)
})
