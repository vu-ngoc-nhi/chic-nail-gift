import type { StaffAuthStatus } from './useStaffAuth.ts'

const STAFF_PATHS = new Set(['/staff', '/staff/redeem'])

export function getStaffRedirectPath(currentPath: string, status: StaffAuthStatus) {
  if (status === 'authorized') {
    return STAFF_PATHS.has(currentPath) ? null : '/staff'
  }

  if (status === 'signed-out') {
    return currentPath === '/login' ? null : '/login'
  }

  return null
}
