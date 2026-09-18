export const portalAccessMessage = 'This account does not have access to the institution portal.'

export function validatePortalContext(context, userId) {
  const institution = context?.institutions
  const manager = context?.role === 'manager' && institution?.account_user_id === userId
  const staff = context?.role === 'staff' && context.staff?.auth_user_id === userId
    && context.staff?.role === 'staff' && context.staff?.institution_id === institution?.id
  if (!userId || !institution || (!manager && !staff)) throw new Error(portalAccessMessage)
  if (!institution.active || (staff && !context.staff.active)) throw new Error('This institution account is not active yet.')
  if (manager && institution.verification_status !== 'email_verified') throw new Error('Verify your institution email before signing in.')
  return context
}

export function validateNewPassword(password, confirmation) {
  if (password.length < 8) return 'Password must be at least 8 characters.'
  if (!/[A-Z]/.test(password) || !/[a-z]/.test(password) || !/[0-9]/.test(password)) return 'Password must include uppercase, lowercase, and a number.'
  if (password !== confirmation) return 'Passwords do not match.'
  return ''
}
