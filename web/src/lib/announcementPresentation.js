export const announcementPriorityClass = {
  low: 'muted',
  normal: 'primary',
  high: 'secondary',
  urgent: 'emergency',
}

export function announcementPriorityLabel(priority) {
  if (priority === 'high') return 'High priority'
  if (priority === 'urgent') return 'Urgent'
  if (priority === 'normal') return 'Normal'
  if (priority === 'low') return 'Low'
  return priority || 'Normal'
}
