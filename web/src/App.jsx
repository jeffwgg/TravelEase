import { BrowserRouter, Routes, Route, NavLink, Navigate, useLocation } from 'react-router-dom'
import {
  LayoutDashboard,
  Megaphone,
  ListOrdered,
  LifeBuoy,
  MessageSquare,
  Activity,
  FileText,
  Building2,
  Bell,
  Siren,
  Users,
  UserRound,
  BarChart3
} from 'lucide-react'
import './index.css'
import './staff-workspace.css'
import LandingPage from './pages/LandingPage'
import VerifyEmailPage from './pages/VerifyEmailPage'
import AuthCallbackPage from './pages/AuthCallbackPage'
import ResetPasswordPage from './pages/ResetPasswordPage'
import ProfilePage from './pages/ProfilePage'
import AnnouncementPage from './pages/AnnouncementPage'
import CreateAnnouncementPage from './pages/CreateAnnouncementPage'
import AnnouncementDetailsPage from './pages/AnnouncementDetailsPage'
import QueueUpdatePage from './pages/QueueUpdatePage'
import AddQueueLinePage from './pages/AddQueueLinePage'
import AssistanceRequestPage from './pages/AssistanceRequestPage'
import StaffChatPage from './pages/StaffChatPage'
import AnalyticsPage from './pages/AnalyticsPage'
import ManagerDashboardPage from './pages/ManagerDashboardPage'
import UsageInsightsPage from './pages/UsageInsightsPage'
import ReportGenerationPage from './pages/ReportGenerationPage'
import SosRequestsPage from './pages/SosRequestsPage'
import StaffManagementPage from './pages/StaffManagementPage'
import StaffSetupPage from './pages/StaffSetupPage'
import StaffDashboardPage from './pages/StaffDashboardPage'
import StaffProfilePage from './pages/StaffProfilePage'
import { AuthProvider, useAuth } from './context/AuthContext'
import { NotificationProvider, useNotifications } from './context/NotificationContext'
import { WebRTCProvider } from './context/WebRTCContext'

function Sidebar() {
  const { session, staffContext, signOut } = useAuth()
  const { permission, requestBrowserPermission } = useNotifications()
  const institutionName = staffContext?.institutions?.name || 'Loading institution…'
  const institutionRole = staffContext?.role || 'Institution Admin'
  const initialsSource = staffContext?.institutions?.name || session?.user?.email || 'Institution'
  const initials = initialsSource.split(/\s|@/).filter(Boolean).slice(0, 2).map((part) => part[0]?.toUpperCase()).join('')
  const isManager = staffContext?.role === 'manager' && Boolean(staffContext?.institutions?.account_user_id)

  return (
    <aside className="sidebar">
      <div className="sidebar-logo">
        <img src="/logo.png" alt="TravelEase Logo" style={{ width: 38, height: 38, objectFit: 'contain' }} />
        <div>
          <h1>TravelEase</h1>
          <span>{staffContext?.role === 'manager' ? 'Institution Manager' : 'Staff Member'}</span>
        </div>
      </div>
      <nav className="sidebar-nav">
        <div className="sidebar-section">
          <div className="sidebar-section-title">Overview</div>
          <NavLink to="/dashboard" className={({isActive}) => `sidebar-link ${isActive ? 'active' : ''}`}>
            <span className="link-icon"><LayoutDashboard size={18} /></span> Dashboard
          </NavLink>
        </div>
        <div className="sidebar-section">
          <div className="sidebar-section-title">Communication</div>
          <NavLink to="/announcements" className={({isActive}) => `sidebar-link ${isActive ? 'active' : ''}`}>
            <span className="link-icon"><Megaphone size={18} /></span> Announcements
          </NavLink>
          <NavLink to="/queue" className={({isActive}) => `sidebar-link ${isActive ? 'active' : ''}`}>
            <span className="link-icon"><ListOrdered size={18} /></span> Queue Updates
          </NavLink>
        </div>
        <div className="sidebar-section">
          <div className="sidebar-section-title">Assistance</div>
          <NavLink to="/sos" className={({isActive}) => `sidebar-link ${isActive ? 'active' : ''}`}>
            <span className="link-icon"><Siren size={18} /></span> SOS / Emergency
          </NavLink>
          <NavLink to="/requests" className={({isActive}) => `sidebar-link ${isActive ? 'active' : ''}`}>
            <span className="link-icon"><LifeBuoy size={18} /></span> Requests
          </NavLink>
          {staffContext?.role === 'staff' && <NavLink to="/chat" className={({isActive}) => `sidebar-link ${isActive ? 'active' : ''}`}>
            <span className="link-icon"><MessageSquare size={18} /></span> Staff Chat
          </NavLink>}
          {isManager && <NavLink to="/staff" className={({isActive}) => `sidebar-link ${isActive ? 'active' : ''}`}>
            <span className="link-icon"><Users size={18} /></span> Staff Management
          </NavLink>}
        </div>
        {isManager && <>
          <div className="sidebar-section">
            <div className="sidebar-section-title">Analytics</div>
            <NavLink to="/analytics" className={({isActive}) => `sidebar-link ${isActive ? 'active' : ''}`}>
              <span className="link-icon"><BarChart3 size={18} /></span> Accessibility Analytics
            </NavLink>
            <NavLink to="/usage" className={({isActive}) => `sidebar-link ${isActive ? 'active' : ''}`}>
              <span className="link-icon"><Activity size={18} /></span> Service Analytics
            </NavLink>
            <NavLink to="/reports" className={({isActive}) => `sidebar-link ${isActive ? 'active' : ''}`}>
              <span className="link-icon"><FileText size={18} /></span> Reports
            </NavLink>
          </div>
          <div className="sidebar-section">
            <div className="sidebar-section-title">Settings</div>
            <NavLink to="/profile" className={({isActive}) => `sidebar-link ${isActive ? 'active' : ''}`}>
              <span className="link-icon"><Building2 size={18} /></span> Organization
            </NavLink>
          </div>
        </>}
        {!isManager && <div className="sidebar-section"><div className="sidebar-section-title">Account</div><NavLink to="/profile" className={({isActive}) => `sidebar-link ${isActive ? 'active' : ''}`}><span className="link-icon"><UserRound size={18} /></span> My Profile</NavLink></div>}
        {!isManager && permission === 'default' && (
          <div style={{ padding: '8px 12px', marginTop: '12px' }}>
            <button
              onClick={requestBrowserPermission}
              style={{
                width: '100%',
                background: 'rgba(59, 130, 246, 0.12)',
                border: '1px solid rgba(59, 130, 246, 0.3)',
                borderRadius: '8px',
                color: 'var(--primary)',
                padding: '8px',
                fontSize: '12px',
                fontWeight: '600',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '6px',
                cursor: 'pointer',
              }}
            >
              <Bell size={14} /> Enable Desktop Alerts
            </button>
          </div>
        )}
      </nav>
      <div className="sidebar-user">
        <div className="user-avatar">{initials || 'ST'}</div>
        <div className="user-info">
          <div className="user-name" title={institutionName}>{institutionName}</div>
          <div className="user-role">{institutionRole}</div>
        </div>
        <button className="sidebar-signout" onClick={signOut} title="Sign out">Sign out</button>
      </div>
    </aside>
  )
}

function DashboardLayout({ children }) {
  return (
    <div className="app-layout">
      <Sidebar />
      <main className="main-content">
        {children}
      </main>
    </div>
  )
}

function AppRoutes() {
  const location = useLocation()
  const { session, staffContext, loading } = useAuth()
  const publicAuthRoutes = new Set(['/', '/auth', '/verify-email', '/auth/callback', '/reset-password', '/staff/setup'])
  const isPublicAuthRoute = publicAuthRoutes.has(location.pathname)

  if (loading) return <div className="app-loading">Connecting to TravelEase…</div>

  if (isPublicAuthRoute) {
    if ((location.pathname === '/' || location.pathname === '/auth') && session && staffContext) {
      return <Navigate to="/dashboard" replace />
    }
    return (
      <Routes>
        <Route path="/" element={<LandingPage defaultModalOpen={false} />} />
        <Route path="/auth" element={<LandingPage defaultModalOpen={true} />} />
        <Route path="/verify-email" element={<VerifyEmailPage />} />
        <Route path="/auth/callback" element={<AuthCallbackPage />} />
        <Route path="/reset-password" element={<ResetPasswordPage />} />
        <Route path="/staff/setup" element={<StaffSetupPage />} />
      </Routes>
    )
  }

  if (!session || !staffContext) return <Navigate to="/auth" replace state={{ from: location.pathname }} />
  const isManager = staffContext?.role === 'manager' && Boolean(staffContext?.institutions?.account_user_id)

  return (
    <DashboardLayout>
      <Routes>
        <Route path="/" element={<Navigate to="/dashboard" replace />} />
        <Route path="/dashboard" element={staffContext?.role === 'staff' ? <StaffDashboardPage /> : <ManagerDashboardPage />} />
        <Route path="/profile" element={isManager ? <ProfilePage /> : <StaffProfilePage />} />
        <Route path="/announcements" element={<AnnouncementPage />} />
        <Route path="/announcements/create" element={<CreateAnnouncementPage />} />
        <Route path="/announcements/:id" element={<AnnouncementDetailsPage />} />
        <Route path="/announcements/:id/edit" element={<CreateAnnouncementPage />} />
        <Route path="/queue" element={<QueueUpdatePage />} />
        <Route path="/queue/add" element={<AddQueueLinePage />} />
        <Route path="/requests" element={<AssistanceRequestPage staffOnly={staffContext?.role === 'staff'} />} />
        <Route path="/sos" element={<SosRequestsPage />} />
        <Route path="/chat" element={staffContext?.role === 'staff' ? <StaffChatPage /> : <Navigate to="/dashboard" replace />} />
        <Route path="/staff" element={isManager ? <StaffManagementPage /> : <Navigate to="/dashboard" replace />} />
        {/* Accessibility analytics (barriers & hotspots); the dashboard is now an operations hub. */}
        <Route path="/analytics" element={isManager ? <AnalyticsPage /> : <Navigate to="/dashboard" replace />} />
        <Route path="/usage" element={isManager ? <UsageInsightsPage /> : <Navigate to="/dashboard" replace />} />
        {/* Legacy deep-link alias: service performance is now a tab of the consolidated analytics page. */}
        <Route path="/performance" element={<Navigate to="/usage" replace />} />
        <Route path="/reports" element={isManager ? <ReportGenerationPage /> : <Navigate to="/dashboard" replace />} />
      </Routes>
    </DashboardLayout>
  )
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <NotificationProvider>
          <WebRTCProvider>
            <AppRoutes />
          </WebRTCProvider>
        </NotificationProvider>
      </AuthProvider>
    </BrowserRouter>
  )
}
