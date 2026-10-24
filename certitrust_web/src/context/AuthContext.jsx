import { createContext, useContext, useEffect, useMemo, useState } from 'react';
import {
  getCurrentUser,
  getSessionUser,
  login as loginUser,
  loginWithGoogle as loginWithGoogleUser,
  logout as logoutUser,
} from '../services/authService';
import { getAuthToken } from '../services/apiClient';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(() => getSessionUser());
  const [token, setToken] = useState(() => getAuthToken());

  useEffect(() => {
    const clearInvalidSession = () => {
      setUser(null);
      setToken(null);
    };
    window.addEventListener('certitrust:unauthorized', clearInvalidSession);
    return () => window.removeEventListener('certitrust:unauthorized', clearInvalidSession);
  }, []);

  const syncSession = (nextUser) => {
    setUser(nextUser ?? getSessionUser());
    setToken(getAuthToken());
  };

  const login = async (email, password, remember) => {
    const nextUser = await loginUser(email, password, remember);
    syncSession(nextUser);
    return nextUser;
  };

  const loginWithGoogle = async (idToken, accessToken, remember) => {
    const nextUser = await loginWithGoogleUser(idToken, accessToken, remember);
    syncSession(nextUser);
    return nextUser;
  };

  const refreshUser = async () => {
    const nextUser = await getCurrentUser();
    syncSession(nextUser);
    return nextUser;
  };

  const logout = async () => {
    try {
      await logoutUser();
    } finally {
      setUser(null);
      setToken(null);
    }
  };

  const value = useMemo(
    () => ({
      user,
      token,
      isAuthenticated: Boolean(token && user),
      login,
      loginWithGoogle,
      logout,
      refreshUser,
      syncSession,
    }),
    [token, user],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
