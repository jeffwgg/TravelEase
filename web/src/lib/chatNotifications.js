/**
 * Determines whether the current web client should display and sound a notification
 * for an incoming assistance chat message.
 *
 * Rules:
 * 1. Only logged-in users with the 'staff' role receive chat notifications (managers never receive them).
 * 2. The staff member must have a valid staff ID.
 * 3. Only traveler messages (sender_type === 'traveler') notify staff.
 * 4. Suppress notifications if staff currently has this exact conversation open in view.
 * 5. Only the specific staff member ASSIGNED to this assistance request (requestAssignedStaffId === currentStaffId) receives the notification.
 *
 * @param {Object} params
 * @param {string|null} params.role - User role ('manager' | 'staff' | null)
 * @param {string|null} params.currentStaffId - Current logged-in staff ID
 * @param {string|null} params.activeRequestId - Request ID currently open in chat view (if any)
 * @param {string|null} params.messageSenderType - Sender type ('traveler' | 'staff')
 * @param {string|null} params.messageRequestId - Target request ID of the message
 * @param {string|null} params.requestAssignedStaffId - Assigned staff ID for the request
 * @returns {boolean}
 */
export function shouldNotifyChatMessage({
  role,
  currentStaffId,
  activeRequestId,
  messageSenderType,
  messageRequestId,
  requestAssignedStaffId,
}) {
  if (role !== 'staff' || !currentStaffId) {
    return false
  }

  if (messageSenderType !== 'traveler') {
    return false
  }

  if (!messageRequestId) {
    return false
  }

  if (activeRequestId && activeRequestId === messageRequestId) {
    return false
  }

  if (!requestAssignedStaffId || requestAssignedStaffId !== currentStaffId) {
    return false
  }

  return true
}

/**
 * Determines whether the current web client should accept and ring for an incoming
 * WebRTC call offer.
 *
 * Rules:
 * 1. Only logged-in users with the 'staff' role can receive call offers.
 * 2. The staff member must have a valid staff ID.
 * 3. The caller must be from mobile (callerSide !== 'web').
 * 4. The request must be assigned to the current staff member (requestAssignedStaffId === currentStaffId).
 *
 * @param {Object} params
 * @param {string|null} params.role
 * @param {string|null} params.currentStaffId
 * @param {string|null} params.callerSide
 * @param {string|null} params.requestAssignedStaffId
 * @returns {boolean}
 */
export function shouldAcceptCallOffer({
  role,
  currentStaffId,
  callerSide,
  requestAssignedStaffId,
  activeRequestId,
  targetRequestId,
}) {
  if (role !== 'staff' || !currentStaffId) {
    return false
  }

  if (callerSide === 'web') {
    return false
  }

  const isAssigned = Boolean(requestAssignedStaffId && requestAssignedStaffId === currentStaffId)
  const isViewing = Boolean(activeRequestId && targetRequestId && activeRequestId === targetRequestId)

  if (!isAssigned && !isViewing) {
    return false
  }

  return true
}
