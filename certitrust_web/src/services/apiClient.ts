import axios from "axios";

export const API_BASE_URL =
    import.meta.env.VITE_API_BASE_URL ||
    "https://certitrust-yhzl.onrender.com/api";

export const apiClient = axios.create({
    baseURL: API_BASE_URL.replace(/\/$/, ""),
    headers: {
        Accept: "application/json",
    },
    timeout: 30000,
});

export const publicApiClient = axios.create({
    baseURL: API_BASE_URL.replace(/\/$/, ""),
    headers: {
        Accept: "application/json",
    },
    timeout: 30000,
});

export const getAuthToken = () =>
    sessionStorage.getItem("certitrust_token") ||
    localStorage.getItem("certitrust_token");

export const clearAuthSession = () => {
    sessionStorage.removeItem("certitrust_token");
    sessionStorage.removeItem("certitrust_user");
    localStorage.removeItem("certitrust_token");
    localStorage.removeItem("certitrust_user");
};

apiClient.interceptors.request.use((config) => {
    const token = getAuthToken();
    if (token) config.headers.Authorization = `Bearer ${token}`;
    return config;
});

apiClient.interceptors.response.use(
    (response) => response,
    (error) => {
        if (error.response?.status === 401) {
            const hadSession = Boolean(getAuthToken());
            clearAuthSession();
            if (hadSession) window.dispatchEvent(new Event("certitrust:unauthorized"));
        }
        return Promise.reject(error);
    },
);
