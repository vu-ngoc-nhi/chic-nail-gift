import type { StaffAuthStatus } from './useStaffAuth.ts'
import type { StaffRole } from './useStaffAuth.ts'

const STAFF_PATHS = new Set(['/staff', '/staff/redeem'])
const ADMIN_PATHS = new Set(['/admin/campaigns'])

export function getStaffRedirectPath(
  currentPath: string,
  status: StaffAuthStatus,
  role: StaffRole | null = null,
) {
  if (status === 'authorized') {
    if (ADMIN_PATHS.has(currentPath)) {
      return role === 'ADMIN' ? null : '/staff'
    }
    return STAFF_PATHS.has(currentPath) ? null : '/staff'
  }

  if (status === 'signed-out') {
    return currentPath === '/login' ? null : '/login'
  }

  return null
}
