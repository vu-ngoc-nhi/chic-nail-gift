import assert from 'node:assert/strict'
import test from 'node:test'
import { getStaffRedirectPath } from '../src/features/auth/staffRoute.ts'

test('keeps the requested Staff route while authentication is being restored', () => {
  assert.equal(getStaffRedirectPath('/staff/redeem', 'loading'), null)
  assert.equal(getStaffRedirectPath('/staff/redeem', 'checking'), null)
  assert.equal(getStaffRedirectPath('/staff/redeem', 'connection-error'), null)
})

test('keeps valid Staff routes after authorization', () => {
  assert.equal(getStaffRedirectPath('/staff', 'authorized'), null)
  assert.equal(getStaffRedirectPath('/staff/redeem', 'authorized'), null)
  assert.equal(getStaffRedirectPath('/login', 'authorized'), '/staff')
})

test('keeps Admin campaign route only for an authorized Admin', () => {
  assert.equal(getStaffRedirectPath('/admin/campaigns', 'authorized', 'ADMIN'), null)
  assert.equal(getStaffRedirectPath('/admin/campaigns', 'authorized', 'STAFF'), '/staff')
})

test('sends signed-out users to login', () => {
  assert.equal(getStaffRedirectPath('/staff/redeem', 'signed-out'), '/login')
  assert.equal(getStaffRedirectPath('/login', 'signed-out'), null)
})
