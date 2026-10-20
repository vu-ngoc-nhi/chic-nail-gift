import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import type { ChicSupabaseClient } from '../src/lib/supabase.ts'
import { getStaffRedirectPath } from '../src/features/auth/staffRoute.ts'
import {
  campaignStatusLabels,
  canEditCampaignVersion,
  createCampaignDraft,
  getCampaignInputErrors,
  getPrizeInputErrors,
  getValidationMessages,
  listAdminCampaigns,
  presentAdminError,
  publishCampaignVersion,
  saveDraftPrize,
  setCampaignLifecycle,
  AdminCampaignError,
  type CampaignDraftInput,
  type PrizeInput,
} from '../src/features/admin/adminCampaigns.ts'

const pageSource = readFileSync(new URL('../src/features/admin/AdminCampaignPage.tsx', import.meta.url), 'utf8')
const appSource = readFileSync(new URL('../src/App.tsx', import.meta.url), 'utf8')
const giftSource = readFileSync(new URL('../src/features/gifts/StaffGiftPage.tsx', import.meta.url), 'utf8')
const redemptionSource = readFileSync(new URL('../src/features/rewards/StaffRedemptionPage.tsx', import.meta.url), 'utf8')
const adapterSource = readFileSync(new URL('../src/features/admin/adminCampaigns.ts', import.meta.url), 'utf8')

function clientReturning(data: unknown, error: { code?: string; message?: string } | null = null) {
  const calls: Array<{ name: string; args: unknown }> = []
  return {
    calls,
    client: {
      rpc: async (name: string, args: unknown) => {
        calls.push({ name, args })
        return { data, error }
      },
    } as unknown as ChicSupabaseClient,
  }
}

const validCampaign: CampaignDraftInput = {
  name: 'Quà bí mật mùa thu',
  startAt: '2026-09-10T00:00:00.000Z',
  endAt: '2026-10-10T00:00:00.000Z',
  minBillVnd: 350000,
  giftOpenDeadlineHours: 72,
  headline: 'Chọn món quà dành riêng cho bạn',
  description: 'Mô tả dành cho khách.',
  terms: 'Áp dụng theo điều kiện chương trình.',
}

const validPrize: PrizeInput = {
  prizeId: null,
  name: 'Voucher 50.000đ',
  type: 'CASH_VOUCHER',
  customerDescription: 'Tặng voucher trị giá 50.000đ.',
  customerValueVnd: 50000,
  estimatedChicCostVnd: 15000,
  discountPercent: null,
  minimumSpendVnd: 0,
  applicableService: null,
  expiryDays: 30,
  weight: 5,
  maxQuantity: 100,
  isFallback: false,
  active: true,
}

test('AUI01 — Admin route is protected', () => {
  assert.equal(getStaffRedirectPath('/admin/campaigns', 'signed-out', null), '/login')
  assert.equal(getStaffRedirectPath('/admin/campaigns', 'authorized', 'ADMIN'), null)
  assert.match(appSource, /auth\.role === 'ADMIN'/)
})

test('AUI02 — Staff cannot see or use Admin controls', () => {
  assert.equal(getStaffRedirectPath('/admin/campaigns', 'authorized', 'STAFF'), '/staff')
  assert.match(giftSource, /role === 'ADMIN'.*Chương trình/)
  assert.match(redemptionSource, /role === 'ADMIN'.*Chương trình/)
})

test('AUI03 — Campaign list uses the Admin RPC and Vietnamese statuses', async () => {
  const { client, calls } = clientReturning([])
  assert.deepEqual(await listAdminCampaigns(client), [])
  assert.equal(calls[0]?.name, 'list_admin_campaigns')
  assert.equal(campaignStatusLabels.ACTIVE, 'Đang hoạt động')
  assert.match(pageSource, /Danh sách chương trình/)
})

test('AUI04 — Create Campaign Draft submits one Campaign and Version payload', async () => {
  const { client, calls } = clientReturning({ campaign_id: 'campaign', campaign_version_id: 'version' })
  await createCampaignDraft(client, validCampaign)
  assert.equal(calls[0]?.name, 'create_campaign_draft')
  assert.deepEqual(calls[0]?.args, {
    p_name: validCampaign.name,
    p_start_at: validCampaign.startAt,
    p_end_at: validCampaign.endAt,
    p_min_bill_vnd: 350000,
    p_gift_open_deadline_hours: 72,
    p_headline: validCampaign.headline,
    p_description: validCampaign.description,
    p_terms: validCampaign.terms,
  })
})

test('AUI05 — Required Campaign fields and date order are validated', () => {
  const errors = getCampaignInputErrors({ ...validCampaign, name: '', headline: '', endAt: validCampaign.startAt })
  assert.equal(errors.length, 3)
})

test('AUI06 — VND inputs require safe integers and use formatted controls', () => {
  assert.ok(getCampaignInputErrors({ ...validCampaign, minBillVnd: 1.5 }).length > 0)
  assert.match(pageSource, /formatAmountInput/)
  assert.doesNotMatch(pageSource, /200000|200\.000/)
})

test('AUI07 — Prize type-specific fields render only when appropriate', () => {
  assert.match(pageSource, /input\.type === 'PERCENT_DISCOUNT'/)
  assert.match(pageSource, /servicePrizeTypes\.has\(input\.type\)/)
  assert.equal(getPrizeInputErrors({ ...validPrize, type: 'PERCENT_DISCOUNT', discountPercent: null }).length, 1)
})

test('AUI08 — A normal Prize can be added through the safe RPC', async () => {
  const { client, calls } = clientReturning({ prize_id: 'prize', saved: true })
  await saveDraftPrize(client, 'campaign', 'version', validPrize)
  assert.equal(calls[0]?.name, 'save_draft_prize')
  const args = calls[0]!.args as { p_is_fallback: boolean; p_weight: number }
  assert.equal(args.p_is_fallback, false)
  assert.equal(args.p_weight, 5)
})

test('AUI09 — Fallback configuration is active and maps to unlimited inventory', async () => {
  const { client, calls } = clientReturning({ prize_id: 'fallback', saved: true })
  await saveDraftPrize(client, 'campaign', 'version', { ...validPrize, isFallback: true, maxQuantity: 4 })
  const args = calls[0]!.args as { p_is_fallback: boolean; p_max_quantity: number | null; p_weight: number }
  assert.equal(args.p_is_fallback, true)
  assert.equal(args.p_max_quantity, null)
  assert.equal(args.p_weight, 1)
})

test('AUI10 — Fallback validation is displayed clearly', () => {
  const messages = getValidationMessages({ valid: false, issues: ['FALLBACK_REQUIRED'], prize_count: 1, normal_prize_count: 1, fallback_count: 0, fallback_valid: false })
  assert.deepEqual(messages, ['Chưa có quà dự phòng.'])
  assert.match(pageSource, /Có đúng 1 quà dự phòng/)
  assert.match(pageSource, /Quà dự phòng không giới hạn số lượng/)
})

test('AUI11 — Weights are relative and never required to total 100', () => {
  assert.deepEqual(getPrizeInputErrors({ ...validPrize, weight: 7 }), [])
  assert.match(pageSource, /Không cần cộng đủ 100/)
  assert.doesNotMatch(adapterSource, /weight.*===?\s*100|reduce\([^)]*weight/)
})

test('AUI12 — Unlimited inventory is represented by null', async () => {
  const { client, calls } = clientReturning({ prize_id: 'prize', saved: true })
  await saveDraftPrize(client, 'campaign', 'version', { ...validPrize, maxQuantity: null })
  assert.equal((calls[0]!.args as { p_max_quantity: number | null }).p_max_quantity, null)
  assert.match(pageSource, /Không giới hạn số lượng/)
})

test('AUI13 — Review section summarizes dates, limits, headline, counts and fallback', () => {
  assert.match(pageSource, /03 · RÀ SOÁT/)
  assert.match(pageSource, /Bill tối thiểu/)
  assert.match(pageSource, /Hạn mở quà/)
  assert.match(pageSource, /Tổng số quà/)
  assert.match(pageSource, /Quà thường hoạt động/)
})

test('AUI14 — Invalid configuration cannot be published', () => {
  assert.match(pageSource, /disabled=\{busy \|\| !validation\?\.valid\}/)
})

test('AUI15 — Valid configuration publishes through a dedicated RPC', async () => {
  const { client, calls } = clientReturning({ published_at: '2026-09-09T00:00:00Z' })
  await publishCampaignVersion(client, 'campaign', 'version')
  assert.equal(calls[0]?.name, 'publish_campaign_version')
  assert.deepEqual(calls[0]?.args, { p_campaign_id: 'campaign', p_campaign_version_id: 'version' })
})

test('AUI16 — Published configuration becomes read-only', () => {
  assert.equal(canEditCampaignVersion('DRAFT', null), true)
  assert.equal(canEditCampaignVersion('DRAFT', '2026-09-09T00:00:00Z'), false)
  assert.match(pageSource, /Đã xuất bản, chỉ đọc/)
})

test('AUI17 — Activation requires an explicit confirmation and server action', async () => {
  const { client, calls } = clientReturning({ previous_status: 'DRAFT', status: 'ACTIVE' })
  await setCampaignLifecycle(client, 'campaign', 'ACTIVATE', true)
  assert.deepEqual(calls[0]?.args, { p_campaign_id: 'campaign', p_action: 'ACTIVATE', p_confirmed: true })
  assert.match(pageSource, /ACTIVATE: 'Kích hoạt chương trình/)
  assert.match(pageSource, /window\.confirm\(confirmations\[action\]\)/)
})

test('AUI18 — Active conflict has a safe operational message', () => {
  const message = presentAdminError(new AdminCampaignError('validation', 'Another Campaign is already active for this branch'))
  assert.equal(message, 'Chi nhánh đang có một chương trình hoạt động. Hãy tạm dừng hoặc kết thúc chương trình đó trước.')
})

test('AUI19 — Pause and resume states and actions are clear', () => {
  assert.equal(campaignStatusLabels.PAUSED, 'Đang tạm dừng')
  assert.match(pageSource, /lifecycle\('PAUSE'\)/)
  assert.match(pageSource, /lifecycle\('RESUME'\)/)
})

test('AUI20 — End and archive states and actions are clear', () => {
  assert.equal(campaignStatusLabels.ENDED, 'Đã kết thúc')
  assert.equal(campaignStatusLabels.ARCHIVED, 'Đã lưu trữ')
  assert.match(pageSource, /lifecycle\('END'\)/)
  assert.match(pageSource, /lifecycle\('ARCHIVE'\)/)
})

test('AUI21 — Internal Chic cost is visible only in the Admin feature', () => {
  const customerSource = readFileSync(new URL('../src/features/gifts/customerGift.ts', import.meta.url), 'utf8')
  const publicPageSource = readFileSync(new URL('../src/features/gifts/PublicGiftPage.tsx', import.meta.url), 'utf8')
  assert.match(pageSource, /Chi phí dự kiến của Chic/)
  assert.doesNotMatch(`${customerSource}\n${publicPageSource}`, /estimated_chic_cost|Chi phí dự kiến của Chic/i)
})

test('AUI22 — Internal UUIDs are not displayed or labelled in the Admin UI', () => {
  assert.doesNotMatch(pageSource, />\s*(Campaign|Version|Prize)?\s*(UUID|ID)\s*</i)
  assert.doesNotMatch(pageSource, /<d[dt]>\{[^}]*(_id|Id)\}/)
})

test('Admin UI security — browser uses RPC only and has no privileged credential', () => {
  assert.doesNotMatch(`${pageSource}\n${adapterSource}`, /\.from\s*\(/)
  assert.doesNotMatch(`${pageSource}\n${adapterSource}`, /service_role|sb_secret|password|legacy jwt/i)
})
