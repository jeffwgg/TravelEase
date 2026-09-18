import { supabase } from '../lib/supabase'

export const assistanceRepository = {
  // Module 5: Assistance Requests
  async getAssistanceRequests() {
    const { data, error } = await supabase
      .from('assistance_requests')
      .select('*')
      .order('created_at', { ascending: false })

    if (error) {
      console.error('Error fetching assistance requests:', error)
      return []
    }
    return data
  },

  async createAssistanceRequest(payload) {
    const { data, error } = await supabase
      .from('assistance_requests')
      .insert([payload])
      .select()
      .single()

    if (error) {
      console.error('Error creating assistance request:', error)
      throw error
    }
    return data
  },

  async updateRequestStatus(id, status, assignedStaffName = null) {
    const updatePayload = { status, updated_at: new Date().toISOString() }
    if (assignedStaffName) {
      updatePayload.assigned_staff_name = assignedStaffName
    }
    if (status === 'resolved' || status === 'closed') {
      updatePayload.resolved_at = new Date().toISOString()
    }

    const { data, error } = await supabase
      .from('assistance_requests')
      .update(updatePayload)
      .eq('id', id)
      .select()
      .single()

    if (error) {
      console.error('Error updating assistance request status:', error)
      throw error
    }

    if ((status === 'resolved' || status === 'closed') && data.assigned_staff_id) {
      await this.freeStaffIfIdle(data.assigned_staff_id)
    }

    return data
  },

  // Institution Staff Management
  // Availability is derived from active assistance_requests AND active sos_requests
  // so that staff currently handling an SOS emergency or another assistance request
  // are marked as 'busy' and not double-assigned.
  async getInstitutionStaff(institutionId = null) {
    let query = supabase
      .from('institution_staff')
      .select('*')
      .eq('active', true)
      .order('name', { ascending: true })

    if (institutionId) {
      query = query.eq('institution_id', institutionId)
    }

    const { data, error } = await query

    if (error) {
      console.error('Error fetching institution staff:', error)
      return []
    }

    // Fetch all currently in-progress assistance requests
    const { data: activeRequests } = await supabase
      .from('assistance_requests')
      .select('assigned_staff_id')
      .eq('status', 'in_progress')

    // Fetch all active SOS requests (assigned or en_route)
    let sosQuery = supabase
      .from('sos_requests')
      .select('assigned_staff_id')
      .in('status', ['assigned', 'en_route'])

    if (institutionId) {
      sosQuery = sosQuery.eq('institution_id', institutionId)
    }
    const { data: activeSosRequests } = await sosQuery

    const busyAssistanceIds = new Set(
      (activeRequests || []).map((r) => r.assigned_staff_id).filter(Boolean)
    )
    const busySosIds = new Set(
      (activeSosRequests || []).map((r) => r.assigned_staff_id).filter(Boolean)
    )

    return data.map((staff) => {
      const isSosBusy = busySosIds.has(staff.id)
      const isAssistanceBusy = busyAssistanceIds.has(staff.id)
      const isBusy = isSosBusy || isAssistanceBusy

      return {
        ...staff,
        status: isBusy ? 'busy' : 'available',
        busyReason: isSosBusy ? 'sos' : isAssistanceBusy ? 'assistance' : null,
      }
    })
  },

  // FR-M7-08: first staff action (assignment or first staff chat message)
  // stamps acknowledged_at exactly once, even if called repeatedly.
  async maybeSetAcknowledgedAt(requestId) {
    const { error } = await supabase
      .from('assistance_requests')
      .update({ acknowledged_at: new Date().toISOString() })
      .eq('id', requestId)
      .is('acknowledged_at', null)

    if (error) {
      console.warn('Could not stamp acknowledged_at:', error.message)
    }
  },

  // Staff availability source of truth lives on institution_staff.status
  // ('free' / 'assigned'); the request page maps those to available/busy.
  async setStaffStatus(staffId, status) {
    const { error } = await supabase
      .from('institution_staff')
      .update({ status })
      .eq('id', staffId)

    if (error) {
      console.error('Error updating staff status:', error)
    }
  },

  // Helper to ensure we do not set staff to 'free' if they are still on an active SOS task
  async freeStaffIfIdle(staffId) {
    if (!staffId) return
    const { data: activeSos } = await supabase
      .from('sos_requests')
      .select('id')
      .eq('assigned_staff_id', staffId)
      .in('status', ['assigned', 'en_route'])
      .limit(1)

    if (!activeSos || activeSos.length === 0) {
      await this.setStaffStatus(staffId, 'free')
    }
  },

  async assignStaffToRequest(requestId, staffId, staffName) {
    const { data: existing } = await supabase
      .from('assistance_requests')
      .select('assigned_staff_id')
      .eq('id', requestId)
      .single()

    const updatePayload = {
      assigned_staff_id: staffId,
      assigned_staff_name: staffName,
      status: 'in_progress',
      updated_at: new Date().toISOString()
    }

    const { data, error } = await supabase
      .from('assistance_requests')
      .update(updatePayload)
      .eq('id', requestId)
      .select()
      .single()

    if (error) {
      console.error('Error assigning staff to request:', error)
      throw error
    }

    if (existing?.assigned_staff_id && existing.assigned_staff_id !== staffId) {
      await this.freeStaffIfIdle(existing.assigned_staff_id)
    }
    await this.setStaffStatus(staffId, 'assigned')

    await this.maybeSetAcknowledgedAt(requestId)

    return data
  },

  // Module 5: Chat Messages
  async getChatMessages(requestId) {
    const { data, error } = await supabase
      .from('assistance_chat_messages')
      .select('*')
      .eq('request_id', requestId)
      .order('created_at', { ascending: true })

    if (error) {
      console.error('Error fetching chat messages:', error)
      return []
    }
    return data
  },

  async sendChatMessage(payload) {
    const { data, error } = await supabase
      .from('assistance_chat_messages')
      .insert([payload])
      .select()
      .single()

    if (error) {
      console.error('Error sending chat message:', error)
      throw error
    }

    // A staff reply counts as the first response (FR-M7-08).
    if (payload.sender_type === 'staff') {
      await this.maybeSetAcknowledgedAt(payload.request_id)
    }

    return data
  },

  // Module 5 & 7: Accessibility Issue Reports
  async getAccessibilityIssueReports() {
    const { data, error } = await supabase
      .from('accessibility_issue_reports')
      .select('*')
      .order('created_at', { ascending: false })

    if (error) {
      console.error('Error fetching accessibility reports:', error)
      return []
    }
    return data
  },

  // Module 5 & 7: Update Accessibility Issue Report (status and staff admin notes / processing result)
  async updateAccessibilityReport(reportId, { status, adminNotes }) {
    const updates = {
      updated_at: new Date().toISOString()
    }
    if (status !== undefined) updates.status = status
    if (adminNotes !== undefined) updates.admin_notes = adminNotes

    const { data, error } = await supabase
      .from('accessibility_issue_reports')
      .update(updates)
      .eq('id', reportId)
      .select()
      .single()

    if (error) {
      console.error('Error updating accessibility report:', error)
      return null
    }
    return data
  },

  // Subscribe to live accessibility report updates
  subscribeToAccessibilityReports(callback) {
    const channel = supabase
      .channel('public:accessibility_issue_reports')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'accessibility_issue_reports' },
        callback
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  },

  // Module 7: Analytics Metrics
  async getAnalyticsDailyMetrics() {
    const { data, error } = await supabase
      .from('analytics_daily_metrics')
      .select('*')
      .order('metric_date', { ascending: false })

    if (error) {
      console.error('Error fetching daily metrics:', error)
      return []
    }
    return data
  },

  // Module 7: Generated Reports
  async getGeneratedReports() {
    const { data, error } = await supabase
      .from('generated_reports')
      .select('*')
      .order('created_at', { ascending: false })

    if (error) {
      console.error('Error fetching generated reports:', error)
      return []
    }
    return data
  },

  // Module 5: Upload chat media (image or video) to Supabase Storage
  async uploadChatMedia(file, requestId) {
    const ext = file.name.split('.').pop()
    const timestamp = Date.now()
    const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_')
    const path = `${requestId}/${timestamp}_${safeName}`

    const { data, error } = await supabase.storage
      .from('chat-media')
      .upload(path, file, {
        contentType: file.type,
        upsert: false,
      })

    if (error) {
      console.error('Error uploading chat media:', error)
      throw error
    }

    const { data: urlData } = supabase.storage
      .from('chat-media')
      .getPublicUrl(data.path)

    return urlData.publicUrl
  },

  // Realtime Subscriptions
  subscribeToStaff(institutionId, callback) {
    const channel = supabase
      .channel(`staff-availability-realtime:${institutionId || 'all'}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'institution_staff',
          ...(institutionId ? { filter: `institution_id=eq.${institutionId}` } : {}),
        },
        (payload) => callback(payload)
      )
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'sos_requests',
          ...(institutionId ? { filter: `institution_id=eq.${institutionId}` } : {}),
        },
        (payload) => callback(payload)
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'assistance_requests' },
        (payload) => callback(payload)
      )
      .subscribe()

    return () => supabase.removeChannel(channel)
  },

  subscribeToRequests(callback) {
    const channel = supabase
      .channel('public:assistance_requests')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'assistance_requests' },
        (payload) => callback(payload)
      )
      .subscribe()

    return () => supabase.removeChannel(channel)
  },

  subscribeToMessages(requestId, callback) {
    const channel = supabase
      .channel(`public:assistance_chat_messages:${requestId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'assistance_chat_messages',
          filter: `request_id=eq.${requestId}`
        },
        (payload) => callback(payload.new)
      )
      .subscribe()

    return () => supabase.removeChannel(channel)
  }
}
