import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import type { ChicSupabaseClient } from '../src/lib/supabase.ts'
import {
  formatRewardValue,
  isValidRewardCode,
  lookupReward,
  normalizeRewardCode,
  presentRedemptionResult,
  redeemReward,
  type StaffRewardResult,
} from '../src/features/rewards/rewardRedemption.ts'

function reward(overrides: Partial<StaffRewardResult> = {}): StaffRewardResult {
  return {
    result_code: 'REWARD_AVAILABLE',
    reward_status: 'AVAILABLE',
    reward_name: 'Chăm sóc móng thanh lịch',
    reward_description: 'Tặng một lần chăm sóc móng cơ bản.',
    reward_type: 'FREE_SERVICE',
    customer_value_vnd: 0,
    discount_percent: null,
    minimum_spend_vnd: 300000,
    applicable_service: 'Dịch vụ nail',
    reward_terms: 'Áp dụng một lần tại Chic.',
    reward_code: 'CHIC-RD4A1',
    reward_expires_at: '2026-09-30T16:59:59Z',
    redeemable: true,
    redeemed_at: null,
    redemption_bill_code: null,
    ...overrides,
  }
}

test('SUI01-SUI04: authenticated Staff route offers navigation and safe Reward lookup', async () => {
  let rpcName = ''
  let rpcArguments: unknown
  const available = reward()
  const client = {
    rpc: async (name: string, args: unknown) => {
      rpcName = name
      rpcArguments = args
      return { data: [available], error: null }
    },
  } as unknown as ChicSupabaseClient

  assert.deepEqual(await lookupReward(client, '  chic-rd4a1  '), available)
  assert.equal(rpcName, 'get_reward_for_redemption')
  assert.deepEqual(rpcArguments, { p_reward_code: 'CHIC-RD4A1' })
  assert.equal(normalizeRewardCode(' chic-rd4a1 '), 'CHIC-RD4A1')
  assert.equal(isValidRewardCode('CHIC-RD4A1'), true)

  const appSource = readFileSync(new URL('../src/App.tsx', import.meta.url), 'utf8')
  const giftPageSource = readFileSync(new URL('../src/features/gifts/StaffGiftPage.tsx', import.meta.url), 'utf8')
  const redemptionPageSource = readFileSync(new URL('../src/features/rewards/StaffRedemptionPage.tsx', import.meta.url), 'utf8')
  assert.match(appSource, /auth\.status === 'authorized'/)
  assert.match(appSource, /\/staff\/redeem/)
  assert.match(giftPageSource, />Tạo quà</)
  assert.match(giftPageSource, />Sử dụng quà</)
  assert.match(redemptionPageSource, /<h1 id="redeem-title">Sử dụng quà<\/h1>/)
})

test('SUI05-SUI08: operational conditions and unavailable states are clear', () => {
  assert.equal(presentRedemptionResult('REWARD_EXPIRED').title, 'Quà đã hết hạn sử dụng')
  assert.equal(presentRedemptionResult('ALREADY_REDEEMED').title, 'Quà đã được sử dụng')
  assert.equal(presentRedemptionResult('CANCELLED').title, 'Quà không còn hiệu lực')
  assert.equal(presentRedemptionResult('WRONG_BRANCH').message, 'Quà này không thuộc chi nhánh hiện tại.')
  assert.equal(formatRewardValue(reward()), 'Miễn phí Dịch vụ nail')

  const pageSource = readFileSync(new URL('../src/features/rewards/StaffRedemptionPage.tsx', import.meta.url), 'utf8')
  assert.match(pageSource, /Áp dụng cho/)
  assert.match(pageSource, /Bill tối thiểu/)
  assert.match(pageSource, /Điều kiện áp dụng/)
})

test('SUI09-SUI12: redemption submits only required Staff inputs and handles minimum spend safely', async () => {
  let rpcName = ''
  let rpcArguments: unknown
  const belowMinimum = reward({ result_code: 'MINIMUM_SPEND_NOT_MET', redeemable: false })
  const client = {
    rpc: async (name: string, args: unknown) => {
      rpcName = name
      rpcArguments = args
      return { data: [belowMinimum], error: null }
    },
  } as unknown as ChicSupabaseClient

  assert.deepEqual(
    await redeemReward(client, 'chic-rd4a1', ' rd4a-bill ', 299999, true),
    belowMinimum,
  )
  assert.equal(rpcName, 'redeem_reward')
  assert.deepEqual(rpcArguments, {
    p_reward_code: 'CHIC-RD4A1',
    p_redemption_bill_code: 'RD4A-BILL',
    p_redemption_bill_amount_vnd: 299999,
    p_conditions_confirmed: true,
  })
  assert.equal(presentRedemptionResult('MINIMUM_SPEND_NOT_MET').tone, 'warning')
  assert.notEqual(presentRedemptionResult('MINIMUM_SPEND_NOT_MET').title, presentRedemptionResult('REDEEMED').title)

  const pageSource = readFileSync(new URL('../src/features/rewards/StaffRedemptionPage.tsx', import.meta.url), 'utf8')
  assert.match(pageSource, /Mã bill sử dụng quà/)
  assert.match(pageSource, /Giá trị bill/)
  assert.match(pageSource, /type="checkbox"/)
  assert.match(pageSource, /Vui lòng xác nhận đã kiểm tra bill/)
})

test('SUI13-SUI15: success is final and duplicate browser submission is guarded', () => {
  assert.equal(presentRedemptionResult('REDEEMED').title, 'Đã xác nhận sử dụng quà ✓')
  const pageSource = readFileSync(new URL('../src/features/rewards/StaffRedemptionPage.tsx', import.meta.url), 'utf8')
  assert.match(pageSource, /requestLocked\.current/)
  assert.match(pageSource, /redemptionFinished/)
  assert.match(pageSource, /disabled=\{redeeming\}/)
  assert.match(pageSource, /XÁC NHẬN ĐÃ SỬ DỤNG QUÀ/)
  assert.match(pageSource, /Mã bill sử dụng/)
  assert.match(pageSource, /Thời gian xác nhận/)
})

test('SUI16-SUI18: Customer revisit shows only safe REDEEMED state', () => {
  const pageSource = readFileSync(new URL('../src/features/gifts/PublicGiftPage.tsx', import.meta.url), 'utf8')
  const customerSource = readFileSync(new URL('../src/features/gifts/customerGift.ts', import.meta.url), 'utf8')
  const combinedSource = `${pageSource}\n${customerSource}`

  assert.match(pageSource, /reward\.reward_status === 'REDEEMED'/)
  assert.match(pageSource, />Đã sử dụng</)
  assert.match(pageSource, /Phần quà này đã được sử dụng tại Chic\./)
  assert.doesNotMatch(combinedSource, /redeemed_by|redemption_bill_code|redemption_bill_amount/i)
})

test('SUI security: browser has no direct table mutation or server-owned redemption fields', () => {
  const pageSource = readFileSync(new URL('../src/features/rewards/StaffRedemptionPage.tsx', import.meta.url), 'utf8')
  const adapterSource = readFileSync(new URL('../src/features/rewards/rewardRedemption.ts', import.meta.url), 'utf8')
  const combinedSource = `${pageSource}\n${adapterSource}`

  assert.doesNotMatch(combinedSource, /\.from\s*\(/)
  assert.doesNotMatch(combinedSource, /service_role|sb_secret|estimated_chic_cost|issued_quantity|max_quantity|\bweight\b/i)
  assert.doesNotMatch(adapterSource, /p_(redeemed_by|redeemed_at|reward_status|reward_id|gift_id|prize_id|campaign_id)/)
})
