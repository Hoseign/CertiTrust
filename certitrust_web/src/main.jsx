import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.jsx'
import { BrowserRouter } from 'react-router-dom'
import StudentVerificationProvider from './context/studentContext.js';
import { AuthProvider } from './context/AuthContext.jsx';

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <BrowserRouter>
      <AuthProvider>
        <StudentVerificationProvider>
          <App />
        </StudentVerificationProvider>
      </AuthProvider>
    </BrowserRouter>
  </StrictMode>,
)
