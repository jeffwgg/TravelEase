import React from 'react'
import StaffAccountManager from '../components/StaffAccountManager'

export default function StaffManagementPage() {
  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Staff Management</h2>
          <div className="header-subtitle">Invite and manage staff accounts for your institution.</div>
        </div>
      </div>
      <div className="page-body">
        <StaffAccountManager />
      </div>
    </div>
  )
}

