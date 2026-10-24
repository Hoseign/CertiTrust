
import { Navigate, Route, Routes } from 'react-router-dom'
import { useAuth } from './context/AuthContext.jsx'
import { isSuperAdminSession } from './services/authService'

// Admin pages
import Dashboard from './pages/admin/dashboard'
import PsuAdminDashboard from './pages/admin/PsuAdminDashboard'
import Certificates from './pages/admin/certificates'
import AuthPage from './pages/admin/AuthPage'
import Notifications from './pages/admin/notifications'
import Profile from './pages/admin/profile'
import Records from './pages/admin/records.'
import Verification from './pages/admin/verification'
import AskQ from './pages/admin/AskQ'

// Student pages
import StudentPortal from './pages/students/studentPortal'
import CertificateVerification from './pages/students/certificateVerification'
import StudentInbox from './pages/students/studentInbox'
import StudentChat from './pages/students/studentChat'
import StudentRecords from './pages/students/StudentRecords'
import StudentProfile from './pages/students/StudentProfile'

// Super Admin pages
import SuperAdminDashboard from './pages/superadmin/SuperAdminDashboard'
import SuperAdminRecords from './pages/superadmin/SuperAdminRecords'
import SuperAdminVerify from './pages/superadmin/SuperAdminVerify'
import SuperAdminAsk from './pages/superadmin/SuperAdminAsk'
import SuperAdminCreateSubadmin from './pages/superadmin/SuperAdminCreateSubadmin'
import SuperAdminLogs from './pages/superadmin/SuperAdminLogs'
import SuperAdminFreezeAccess from './pages/superadmin/SuperAdminFreezeAccess'
import SuperAdminStudentAccess from './pages/superadmin/SuperAdminStudentAccess'
import SuperAdminDeletionRequests from './pages/superadmin/SuperAdminDeletionRequests'
import SuperAdminChat from './pages/superadmin/SuperAdminChat'
import SuperAdminJunk from './pages/superadmin/SuperAdminJunk'

function getLandingPath(user) {
    if (!user) return '/login'

    const isSuperAdmin = isSuperAdminSession(user)
    const isPSUAdmin = user.role === 'admin' && (
        String(user.university_code || '').toUpperCase() === 'PSU' ||
        String(user.email || '').toLowerCase().includes('psu') ||
        String(user.email || '').toLowerCase().includes('@psu.edu.ph')
    )

    if (isSuperAdmin) return '/superadmin'
    if (isPSUAdmin) return '/psu-admin'
    if (user.role === 'admin') return '/admin-dashboard'
    if (user.role === 'student') return '/portal'
    return '/login'
}

function ProtectedRoute({ children, role }) {
    const { user, isAuthenticated } = useAuth();
    if (!isAuthenticated || !user) return <Navigate to="/login" replace />

    const isSuperAdmin = isSuperAdminSession(user)
    const isPSUAdmin = user.role === 'admin' && (
        String(user.university_code || '').toUpperCase() === 'PSU' ||
        String(user.email || '').toLowerCase().includes('psu') ||
        String(user.email || '').toLowerCase().includes('@psu.edu.ph')
    )

    if (role === 'superadmin' && !isSuperAdmin) return <Navigate to={getLandingPath(user)} replace />
    if (role === 'admin' && user.role !== 'admin') return <Navigate to={getLandingPath(user)} replace />
    if (isSuperAdmin && role === 'admin') return <Navigate to="/superadmin" replace />
    if (role === 'student' && user.role === 'admin') {
        return <Navigate to={isSuperAdmin ? '/superadmin' : getLandingPath(user)} replace />
    }
    if (
        role === 'admin' &&
        isPSUAdmin &&
        ['/admin-dashboard', '/dashboard'].includes(window.location.pathname)
    ) {
        return <Navigate to="/psu-admin" replace />
    }
    return children
}

function RoleAwareRoute({ adminPage, studentPage }) {
    const { user } = useAuth();
    if (user?.role === 'student') return studentPage
    return adminPage
}

const admin = (element) => <ProtectedRoute role="admin">{element}</ProtectedRoute>
const student = (element) => <ProtectedRoute role="student">{element}</ProtectedRoute>
const superAdmin = (element) => <ProtectedRoute role="superadmin">{element}</ProtectedRoute>

function App() {
    const { user, isAuthenticated } = useAuth();
    const isSuperAdmin = isSuperAdminSession(user);

    return (
        <Routes>
            {/* Login / splash */}
            <Route path="/" element={isAuthenticated ? <Navigate to={getLandingPath(user)} replace /> : <AuthPage />} />
            <Route path="/login" element={isAuthenticated ? <Navigate to={getLandingPath(user)} replace /> : <AuthPage />} />
            <Route path="/splash" element={isAuthenticated ? <Navigate to={getLandingPath(user)} replace /> : <AuthPage />} />
            <Route path="/public-verification" element={<CertificateVerification publicAccess />} />

            {/* Mobile-style shared routes */}
            <Route path="/dashboard" element={<RoleAwareRoute adminPage={admin(<Dashboard />)} studentPage={student(<StudentPortal />)} />} />
            <Route path="/records" element={<RoleAwareRoute adminPage={admin(<Records />)} studentPage={student(<StudentRecords />)} />} />
            <Route path="/issue" element={isSuperAdmin ? superAdmin(<Certificates />) : <RoleAwareRoute adminPage={admin(<Certificates />)} studentPage={student(<StudentPortal />)} />} />
            <Route path="/verify" element={<RoleAwareRoute adminPage={admin(<Verification />)} studentPage={student(<CertificateVerification />)} />} />
            <Route path="/profile" element={<RoleAwareRoute adminPage={admin(<Profile />)} studentPage={student(<StudentProfile />)} />} />
            <Route path="/ansq" element={<RoleAwareRoute adminPage={admin(<AskQ />)} studentPage={student(<StudentInbox />)} />} />
            <Route path="/askq" element={<RoleAwareRoute adminPage={admin(<AskQ />)} studentPage={student(<StudentChat />)} />} />
            <Route path="/admin-management" element={superAdmin(<SuperAdminDashboard />)} />
            <Route path="/admin-management/access" element={superAdmin(<SuperAdminFreezeAccess />)} />
            <Route path="/admin-management/university/:code" element={superAdmin(<SuperAdminStudentAccess />)} />
            <Route path="/student-access" element={superAdmin(<SuperAdminStudentAccess />)} />
            <Route path="/deletion-requests" element={superAdmin(<SuperAdminDeletionRequests />)} />
            <Route path="/frozen-chat" element={<RoleAwareRoute adminPage={admin(<AskQ />)} studentPage={student(<StudentChat />)} />} />
            <Route path="/qr-scanner" element={<RoleAwareRoute adminPage={admin(<Certificates />)} studentPage={student(<StudentPortal />)} />} />
            <Route path="/verification-confirmation" element={<RoleAwareRoute adminPage={admin(<Verification />)} studentPage={student(<CertificateVerification />)} />} />

            {/* PSU admin */}
            <Route path="/psu-admin" element={admin(<PsuAdminDashboard />)} />

            {/* Super Admin */}
            <Route path="/superadmin" element={superAdmin(<SuperAdminDashboard />)} />
            <Route path="/superadmin/records" element={superAdmin(<SuperAdminRecords />)} />
            <Route path="/superadmin/issue" element={superAdmin(<Certificates />)} />
            <Route path="/superadmin/verify" element={superAdmin(<SuperAdminVerify />)} />
            <Route path="/superadmin/ask" element={superAdmin(<SuperAdminAsk />)} />
            <Route path="/superadmin/create-subadmin" element={superAdmin(<SuperAdminCreateSubadmin />)} />
            <Route path="/superadmin/logs" element={superAdmin(<SuperAdminLogs />)} />
            <Route path="/superadmin/freeze-access" element={superAdmin(<SuperAdminFreezeAccess />)} />
            <Route path="/superadmin/freeze-access/:code" element={superAdmin(<SuperAdminStudentAccess />)} />
            <Route path="/superadmin/deletion-requests" element={superAdmin(<SuperAdminDeletionRequests />)} />
            <Route path="/superadmin/junk" element={superAdmin(<SuperAdminJunk />)} />
            <Route path="/superadmin/ask/:id" element={superAdmin(<SuperAdminChat />)} />

            {/* Admin */}
            <Route path="/admin-dashboard" element={admin(<Dashboard />)} />
            <Route path="/chat" element={admin(<AskQ />)} />
            <Route path="/certificates" element={admin(<Certificates />)} />
            <Route path="/inbox" element={<Navigate to="/ansq" replace />} />
            <Route path="/notifications" element={admin(<Notifications />)} />
            <Route path="/verification" element={admin(<Verification />)} />

            {/* Student */}
            <Route path="/portal" element={student(<StudentPortal />)} />
            <Route path="/portal/records" element={student(<StudentRecords />)} />
            <Route path="/portal/profile" element={student(<StudentProfile />)} />
            <Route path="/certificate-verification" element={student(<CertificateVerification />)} />
            <Route path="/student-askq" element={<Navigate to="/ansq" replace />} />
            <Route path="/ask-admin" element={student(<StudentChat />)} />
            <Route path="*" element={<Navigate to={isAuthenticated ? getLandingPath(user) : '/login'} replace />} />
        </Routes>
    )
}

export default App