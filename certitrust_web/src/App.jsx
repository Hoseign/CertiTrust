
import { lazy, Suspense } from 'react'
import { Navigate, Route, Routes } from 'react-router-dom'
import { useAuth } from './context/AuthContext.jsx'
import { isSuperAdminSession } from './services/authService'
import CertiTrustLoadingIndicator from './components/CertiTrustLoadingIndicator'

const Dashboard = lazy(() => import('./pages/admin/dashboard'))
const StudentAccess = lazy(() => import('./pages/admin/StudentAccess'))
const PsuAdminDashboard = lazy(() => import('./pages/admin/PsuAdminDashboard'))
const Certificates = lazy(() => import('./pages/admin/certificates'))
const AuthPage = lazy(() => import('./pages/admin/AuthPage'))
const Notifications = lazy(() => import('./pages/admin/notifications'))
const Profile = lazy(() => import('./pages/admin/profile'))
const Records = lazy(() => import('./pages/admin/records.'))
const Verification = lazy(() => import('./pages/admin/verification'))
const AskQ = lazy(() => import('./pages/admin/AskQ'))
const StudentPortal = lazy(() => import('./pages/students/studentPortal'))
const CertificateVerification = lazy(() => import('./pages/students/certificateVerification'))
const StudentInbox = lazy(() => import('./pages/students/studentInbox'))
const StudentChat = lazy(() => import('./pages/students/studentChat'))
const StudentRecords = lazy(() => import('./pages/students/StudentRecords'))
const StudentProfile = lazy(() => import('./pages/students/StudentProfile'))
const SuperAdminDashboard = lazy(() => import('./pages/superadmin/SuperAdminDashboard'))
const SuperAdminRecords = lazy(() => import('./pages/superadmin/SuperAdminRecords'))
const SuperAdminVerify = lazy(() => import('./pages/superadmin/SuperAdminVerify'))
const SuperAdminAsk = lazy(() => import('./pages/superadmin/SuperAdminAsk'))
const SuperAdminCreateSubadmin = lazy(() => import('./pages/superadmin/SuperAdminCreateSubadmin'))
const SuperAdminLogs = lazy(() => import('./pages/superadmin/SuperAdminLogs'))
const SuperAdminFreezeAccess = lazy(() => import('./pages/superadmin/SuperAdminFreezeAccess'))
const SuperAdminStudentAccess = lazy(() => import('./pages/superadmin/SuperAdminStudentAccess'))
const SuperAdminDeletionRequests = lazy(() => import('./pages/superadmin/SuperAdminDeletionRequests'))
const SuperAdminChat = lazy(() => import('./pages/superadmin/SuperAdminChat'))
const SuperAdminJunk = lazy(() => import('./pages/superadmin/SuperAdminJunk'))

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
        <Suspense fallback={
            <main className="flex min-h-screen items-center justify-center bg-[#F6F8FC]">
                <CertiTrustLoadingIndicator size={96} message="Loading CertiTrust..." className="text-sm font-medium text-slate-600" />
            </main>
        }>
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
            <Route path="/student-accounts" element={admin(<StudentAccess />)} />
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
        </Suspense>
    )
}

export default App