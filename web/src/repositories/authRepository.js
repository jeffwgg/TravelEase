import { supabase } from '../lib/supabase'

const institutionSelect = 'id, account_user_id, name, branch, active, institution_type, official_contact, service_address, registration_document_path, verification_status, created_at, updated_at'
const institutionRegistrationFunction = 'register-institution'

function throwIfError(error) {
  if (error) throw error
}

export const authRepository = {
  async registerInstitution(form) {
    console.log('[InstitutionRegistration][Repository] Registration received', {
      formKeys: Object.keys(form),
      hasDocument: form.registrationDocument instanceof File,
      documentName: form.registrationDocument?.name,
      documentType: form.registrationDocument?.type,
      documentSize: form.registrationDocument?.size,
    })
    if (!(form.registrationDocument instanceof File)) {
      throw new Error('Registration document was not received as a browser File.')
    }

    console.log('[InstitutionRegistration][Repository] Starting File to base64 conversion')
    const documentBase64 = await fileToBase64(form.registrationDocument)
    console.log('[InstitutionRegistration][Repository] File conversion completed', {
      documentType: form.registrationDocument.type,
      base64Length: documentBase64.length,
    })

    const payload = {
      institutionName: form.institutionName.trim(),
      institutionType: form.institutionType,
      officialContact: form.officialContact.trim(),
      serviceAddress: form.serviceAddress.trim(),
      email: form.email.trim().toLowerCase(),
      password: form.password,
      document: {
        name: form.registrationDocument.name,
        type: form.registrationDocument.type,
        base64: documentBase64,
      },
    }
    console.log('[InstitutionRegistration][Repository] Invoking Edge Function', {
      functionName: institutionRegistrationFunction,
      payloadKeys: Object.keys(payload),
      documentKeys: Object.keys(payload.document),
      documentType: payload.document.type,
      base64Length: payload.document.base64.length,
    })

    const { data, error } = await supabase.functions.invoke(
      institutionRegistrationFunction,
      { body: payload },
    )
    console.log('[InstitutionRegistration][Repository] Edge Function response received', {
      data,
      error: error
        ? {
            name: error.name,
            message: error.message,
            status: error.context?.status,
          }
        : null,
    })
    if (error) {
      let message = error.message
      try {
        const payload = await error.context?.json()
        if (payload?.error) message = payload.error
      } catch {
        // Preserve the Supabase Functions error when no JSON body is available.
      }
      throw new Error(message)
    }
    if (!data?.success) throw new Error(data?.error || 'Unable to register institution.')
    return data
  },

  async signIn(email, password) {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) throw error
    return data
  },

  async signOut() {
    const { error } = await supabase.auth.signOut()
    if (error) throw error
  },

  async sendPasswordReset(email) {
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/reset-password`,
    })
    throwIfError(error)
  },

  async updatePassword(password) {
    const { data, error } = await supabase.auth.updateUser({ password })
    throwIfError(error)
    return data
  },

  async completeStaffSetup(password) {
    const { data: current, error: sessionError } = await supabase.auth.getSession()
    throwIfError(sessionError)
    if (!current.session?.user) throw new Error('The invitation session is invalid or has expired.')
    const { data: staff, error: staffError } = await supabase.from('institution_staff')
      .select('id, active, role').eq('auth_user_id', current.session.user.id).maybeSingle()
    throwIfError(staffError)
    if (!staff || staff.role !== 'staff' || !staff.active) throw new Error('This invitation is not linked to an active staff account.')
    const { data, error } = await supabase.auth.updateUser({ password })
    throwIfError(error)
    return data
  },

  async getStaffContext(userId) {
    const { data, error } = await supabase
      .from('institutions')
      .select(institutionSelect)
      .eq('account_user_id', userId)
      .maybeSingle()

    if (error) throw error
    if (data) return { institution_id: data.id, role: 'manager', institutions: data }

    const { data: staff, error: staffError } = await supabase.from('institution_staff')
      .select('id, institution_id, auth_user_id, name, email, contact_number, role, status, active')
      .eq('auth_user_id', userId).maybeSingle()
    if (staffError) throw staffError
    if (!staff || !staff.active || staff.role !== 'staff') return null

    const { data: institution, error: institutionError } = await supabase.from('institutions')
      .select(institutionSelect).eq('id', staff.institution_id).eq('active', true).maybeSingle()
    if (institutionError) throw institutionError
    if (!institution) return null
    return { institution_id: institution.id, role: 'staff', staff, institutions: institution }
  },
}

function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => {
      const base64 = String(reader.result).split(',')[1] || ''
      if (!base64) {
        console.error('[InstitutionRegistration][Repository] FileReader returned an empty base64 value')
        reject(new Error('The registration document could not be converted.'))
        return
      }
      resolve(base64)
    }
    reader.onerror = () => {
      console.error('[InstitutionRegistration][Repository] FileReader failed', reader.error)
      reject(new Error('Unable to read the registration document.'))
    }
    reader.readAsDataURL(file)
  })
}
