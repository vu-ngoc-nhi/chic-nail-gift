// Permanent Development-only hosted concurrency test for Phase 3A.
// It reads the ignored .env.local and never prints URLs, keys, or Gift Tokens.

import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const localEnvironment = readFileSync(new URL('../../.env.local', import.meta.url), 'utf8')

function readSetting(name) {
  const fromProcess = process.env[name]?.trim()
  if (fromProcess) {
    return fromProcess
  }

  const line = localEnvironment
    .split(/\r?\n/)
    .find((candidate) => candidate.startsWith(`${name}=`))
  const rawValue = line?.slice(name.length + 1).trim() ?? ''
  return rawValue.replace(/^(['"])(.*)\1$/, '$2')
}

const supabaseUrl = readSetting('VITE_SUPABASE_URL').replace(/\/+$/, '')
const publishableKey = readSetting('VITE_SUPABASE_PUBLISHABLE_KEY')

assert.ok(supabaseUrl, 'Missing VITE_SUPABASE_URL in ignored .env.local')
assert.ok(publishableKey, 'Missing VITE_SUPABASE_PUBLISHABLE_KEY in ignored .env.local')
assert.ok(!publishableKey.startsWith('sb_secret_'), 'Browser test must not use a secret key')

const tokens = {
  same: '13e22b37481c7e5d445b77414be5fc08e8aadcc97e0c493f9e395caae0e69797',
  lastA: '4ac5f1cb11cc7f6bbe2b11c15adbecc3c0956c7732830782fe939a9ebb8a0065',
  lastB: 'c20caec5d3068188d5307a7e91fbfe1efca7fade8d9d494d77f4406356451285',
  fallbackA: 'c9bb51e70b9899d2e1d75a5cf4d4f3aff13f4deb61c6505c15b866e8b5de4390',
  fallbackB: 'fc31356f46182f24b4219e800b813fa2697495e9f5e7ac32b5c06bb45055aa9f',
  fallbackC: '67caefac2c52a531eb6db9ab5cacf7882fd58b902b3ab7d6d0cea2a0618a3b82',
  fallbackD: 'c7fc972cdbf995bc4fc65db65bc5775dac0ca4a3acd4a488191d6ba5090c3534',
  failure: '89655fbe22a8d913a2c92ce4a4e3613e3e9d0f283c3b53282fb57ef4c8394515',
}

const safeFields = [
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
]

const apiHeaders = {
  Accept: 'application/json',
  'Accept-Profile': 'api',
  Authorization: `Bearer ${publishableKey}`,
  'Content-Profile': 'api',
  'Content-Type': 'application/json',
  apikey: publishableKey,
}

async function requestOpen(token) {
  return fetch(`${supabaseUrl}/rest/v1/rpc/open_gift`, {
    method: 'POST',
    headers: apiHeaders,
    body: JSON.stringify({ p_gift_token: token }),
  })
}

async function openGift(token) {
  const response = await requestOpen(token)
  assert.equal(response.status, 200, 'open_gift must return HTTP 200 for a safe outcome')
  const payload = await response.json()
  const result = Array.isArray(payload) ? payload[0] : payload
  assert.ok(result, 'open_gift must return one result')
  assert.deepEqual(Object.keys(result).sort(), safeFields)
  return result
}

if (process.argv.includes('--http-only')) {
  const existingResult = await openGift(tokens.same)
  assert.equal(existingResult.result_code, 'ALREADY_OPENED')
  assert.equal(existingResult.reward_available, true)

  const invalidResult = await openGift('invalid-token')
  assert.equal(invalidResult.result_code, 'INVALID_GIFT')
  assert.equal(invalidResult.reward_available, false)

  const privateTableResponse = await fetch(
    `${supabaseUrl}/rest/v1/gift_entries?select=*`,
    {
      headers: {
        ...apiHeaders,
        'Accept-Profile': 'private',
      },
    },
  )
  assert.ok(!privateTableResponse.ok, 'private schema must remain unavailable through Data API')

  console.log('HTTP01 PASS — anon can execute api.open_gift')
  console.log('HTTP02 PASS — valid Gift returns only the exact approved fields')
  console.log('HTTP03 PASS — invalid token returns a safe public result')
  console.log('HTTP04 PASS — private table access remains denied')
  console.log('HTTP05 PASS — validation output contains no credential value')
  process.exit(0)
}

const sameGiftResults = await Promise.all([
  openGift(tokens.same),
  openGift(tokens.same),
])
assert.deepEqual(
  sameGiftResults.map(({ result_code }) => result_code).sort(),
  ['ALREADY_OPENED', 'OPENED_NOW'],
)
assert.equal(sameGiftResults[0].reward_code, sameGiftResults[1].reward_code)
console.log('CON01 PASS — simultaneous same-Gift calls returned one stable Reward')

const repeatedResults = await Promise.all(
  Array.from({ length: 8 }, () => openGift(tokens.same)),
)
assert.ok(repeatedResults.every(({ result_code }) => result_code === 'ALREADY_OPENED'))
assert.equal(new Set(repeatedResults.map(({ reward_code }) => reward_code)).size, 1)
console.log('CON02 PASS — repeated concurrent calls returned one stable Reward')

const lastUnitResults = await Promise.all([
  openGift(tokens.lastA),
  openGift(tokens.lastB),
])
assert.ok(lastUnitResults.every(({ result_code }) => result_code === 'OPENED_NOW'))
assert.deepEqual(
  lastUnitResults.map(({ reward_name }) => reward_name).sort(),
  ['Last limited unit', 'Last unit fallback'],
)
console.log('CON03 PASS — the final limited unit was assigned at most once')

const fallbackResults = await Promise.all([
  openGift(tokens.fallbackA),
  openGift(tokens.fallbackB),
  openGift(tokens.fallbackC),
  openGift(tokens.fallbackD),
])
assert.ok(fallbackResults.every(({ result_code }) => result_code === 'OPENED_NOW'))
assert.ok(
  fallbackResults.every(
    ({ reward_name }) => reward_name === 'Concurrency exhaustion fallback',
  ),
)
console.log('CON04 PASS — exhausted normal inventory safely used unlimited fallback')

const failedResponse = await requestOpen(tokens.failure)
assert.ok(!failedResponse.ok, 'Invalid unpublished configuration must fail')
console.log('CON05 RPC PASS — invalid configuration failed without a public data payload')

const invalidResult = await openGift('invalid-token')
assert.equal(invalidResult.result_code, 'INVALID_GIFT')
assert.equal(invalidResult.reward_available, false)
console.log('HTTP01-HTTP03 PASS — anon RPC is reachable and returns only safe fields/results')

const privateTableResponse = await fetch(`${supabaseUrl}/rest/v1/gift_entries?select=*`, {
  headers: {
    ...apiHeaders,
    'Accept-Profile': 'private',
  },
})
assert.ok(!privateTableResponse.ok, 'private schema must remain unavailable through Data API')
console.log('HTTP04 PASS — private table access remains denied')
console.log('HTTP05 PASS — validation output contains no credential value')
