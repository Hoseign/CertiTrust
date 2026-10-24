import { useEffect, useState } from "react";
import { createUniversityAdmin, listAdminUsers } from "../services/certitrustApi";

export function useAdminUsers() {
    const [users, setUsers] = useState<Record<string, unknown>[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState("");

    const refresh = async (silent = false) => {
        if (!silent) setLoading(true);
        setError("");
        try {
            setUsers(await listAdminUsers());
        } catch (requestError) {
            setError(requestError instanceof Error ? requestError.message : "Unable to load users.");
        } finally {
            setLoading(false);
        }
    };

    const createAdmin = async (email: string, universityCode: string) => {
        await createUniversityAdmin(email, universityCode);
        await refresh();
    };

    useEffect(() => {
        void refresh();
        const timer = window.setInterval(() => void refresh(true), 5000);
        return () => window.clearInterval(timer);
    }, []);

    return { users, loading, error, refresh, createAdmin };
}