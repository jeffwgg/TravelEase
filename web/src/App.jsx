import { BrowserRouter, Routes, Route, NavLink, Navigate, useLocation } from 'react-router-dom'
import {
  LayoutDashboard,
  Megaphone,
  ListOrdered,
  LifeBuoy,
  MessageSquare,
  BarChart3,
  Zap,
  FileText,
  Hand,
  MessageCircle,
  Building2
} from 'lucide-react'
import './index.css'
import AuthPage from './pages/AuthPage'
import VerifyEmailPage from './pages/VerifyEmailPage'
import AuthCallbackPage from './pages/AuthCallbackPage'
import ResetPasswordPage from './pages/ResetPasswordPage'
import ProfilePage from './pages/ProfilePage'
import AnnouncementPage from './pages/AnnouncementPage'
import CreateAnnouncementPage from './pages/CreateAnnouncementPage'
import QueueUpdatePage from './pages/QueueUpdatePage'
import AddQueueLinePage from './pages/AddQueueLinePage'
import AssistanceRequestPage from './pages/AssistanceRequestPage'
import StaffChatPage from './pages/StaffChatPage'
import AnalyticsPage from './pages/AnalyticsPage'
import ServicePerformancePage from './pages/ServicePerformancePage'
import ReportGenerationPage from './pages/ReportGenerationPage'
import SignDictionaryMgmtPage from './pages/SignDictionaryMgmtPage'
import SignFeedbackPage from './pages/SignFeedbackPage'
import { AuthProvider, useAuth } from './context/AuthContext'

function Sidebar() {
  const { session, signOut } = useAuth()
  const displayName = session?.user?.user_metadata?.full_name || session?.user?.email || 'Staff User'
  const initials = displayName.split(/\s|@/).filter(Boolean).slice(0, 2).map((part) => part[0]?.toUpperCase()).join('')

  return (
    <aside className="sidebar">
      <div className="sidebar-logo">
        <img src="/logo.png" alt="TravelEase Logo" style={{ width: 38, height: 38, borderRadius: 10, objectFit: 'cover' }} />
        <div>
          <h1>TravelEase</h1>
          <span>Staff Dashboard</span>
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
          <NavLink to="/requests" className={({isActive}) => `sidebar-link ${isActive ? 'active' : ''}`}>
            <span className="link-icon"><LifeBuoy size={18} /></span> Requests
          </NavLink>
          <NavLink to="/chat" className={({isActive}) => `sidebar-link ${isActive ? 'active' : ''}`}>
            <span className="link-icon"><MessageSquare size={18} /></span> Staff Chat
          </NavLink>
        </div>
        <div className="sidebar-section">
          <div className="sidebar-section-title">Analytics</div>
          <NavLink to="/analytics" className={({isActive}) => `sidebar-link ${isActive ? 'active' : ''}`}>
            <span className="link-icon"><BarChart3 size={18} /></span> Accessibility
          </NavLink>
          <NavLink to="/performance" className={({isActive}) => `sidebar-link ${isActive ? 'active' : ''}`}>
            <span className="link-icon"><Zap size={18} /></span> Performance
          </NavLink>
          <NavLink to="/reports" className={({isActive}) => `sidebar-link ${isActive ? 'active' : ''}`}>
            <span className="link-icon"><FileText size={18} /></span> Reports
          </NavLink>
        </div>
        <div className="sidebar-section">
          <div className="sidebar-section-title">Content</div>
          <NavLink to="/sign-dictionary" className={({isActive}) => `sidebar-link ${isActive ? 'active' : ''}`}>
            <span className="link-icon"><Hand size={18} /></span> Sign Dictionary
          </NavLink>
          <NavLink to="/sign-feedback" className={({isActive}) => `sidebar-link ${isActive ? 'active' : ''}`}>
            <span className="link-icon"><MessageCircle size={18} /></span> Sign Feedback
          </NavLink>
        </div>
        <div className="sidebar-section">
          <div className="sidebar-section-title">Settings</div>
          <NavLink to="/profile" className={({isActive}) => `sidebar-link ${isActive ? 'active' : ''}`}>
            <span className="link-icon"><Building2 size={18} /></span> Organization
          </NavLink>
        </div>
      </nav>
      <div className="sidebar-user">
        <div className="user-avatar">{initials || 'ST'}</div>
        <div className="user-info">
          <div className="user-name">{displayName}</div>
          <div className="user-role">KLIA Terminal 1 • Admin</div>
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
  const publicAuthRoutes = new Set(['/auth', '/verify-email', '/auth/callback', '/reset-password'])
  const isPublicAuthRoute = publicAuthRoutes.has(location.pathname)

  if (loading) return <div className="app-loading">Connecting to TravelEase…</div>

  if (isPublicAuthRoute) {
    if (location.pathname === '/auth' && session && staffContext) return <Navigate to="/dashboard" replace />
    return (
      <Routes>
        <Route path="/auth" element={<AuthPage />} />
        <Route path="/verify-email" element={<VerifyEmailPage />} />
        <Route path="/auth/callback" element={<AuthCallbackPage />} />
        <Route path="/reset-password" element={<ResetPasswordPage />} />
      </Routes>
    )
  }

  if (!session || !staffContext) return <Navigate to="/auth" replace state={{ from: location.pathname }} />

  return (
    <DashboardLayout>
      <Routes>
        <Route path="/" element={<Navigate to="/dashboard" replace />} />
        <Route path="/dashboard" element={<AnalyticsPage />} />
        <Route path="/profile" element={<ProfilePage />} />
        <Route path="/announcements" element={<AnnouncementPage />} />
        <Route path="/announcements/create" element={<CreateAnnouncementPage />} />
        <Route path="/announcements/:id/edit" element={<CreateAnnouncementPage />} />
        <Route path="/queue" element={<QueueUpdatePage />} />
        <Route path="/queue/add" element={<AddQueueLinePage />} />
        <Route path="/requests" element={<AssistanceRequestPage />} />
        <Route path="/chat" element={<StaffChatPage />} />
        <Route path="/analytics" element={<AnalyticsPage />} />
        <Route path="/performance" element={<ServicePerformancePage />} />
        <Route path="/reports" element={<ReportGenerationPage />} />
        <Route path="/sign-dictionary" element={<SignDictionaryMgmtPage />} />
        <Route path="/sign-feedback" element={<SignFeedbackPage />} />
      </Routes>
    </DashboardLayout>
  )
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <AppRoutes />
      </AuthProvider>
    </BrowserRouter>
  )
}
