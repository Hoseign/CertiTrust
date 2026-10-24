import { useCallback, useEffect, useRef, useState } from "react";
import { createUniversityAdmin, listAdminUsers } from "../services/certitrustApi";

export function useAdminUsers() {
    const [users, setUsers] = useState<Record<string, unknown>[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState("");
    const refreshing = useRef(false);

    const refresh = useCallback(async (silent = false) => {
        if (refreshing.current) return;
        refreshing.current = true;
        if (!silent) setLoading(true);
        try {
            setUsers(await listAdminUsers());
            setError("");
        } catch (requestError) {
            setError(requestError instanceof Error ? requestError.message : "Unable to load users.");
        } finally {
            refreshing.current = false;
            setLoading(false);
        }
    }, []);

    const createAdmin = async (email: string, universityCode: string) => {
        await createUniversityAdmin(email, universityCode);
        await refresh();
    };

    useEffect(() => {
        void refresh();
        const refreshWhenVisible = () => {
            if (document.visibilityState === "visible") void refresh(true);
        };
        const timer = window.setInterval(refreshWhenVisible, 5000);
        document.addEventListener("visibilitychange", refreshWhenVisible);
        return () => {
            window.clearInterval(timer);
            document.removeEventListener("visibilitychange", refreshWhenVisible);
        };
    }, [refresh]);

    return { users, loading, error, refresh, createAdmin };
}