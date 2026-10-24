import { useCallback, useEffect, useRef, useState } from "react";
import { listCertificates, type CertificateRecord } from "../services/certitrustApi";

export function useCertificates() {
    const [certificates, setCertificates] = useState<CertificateRecord[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState("");
    const refreshing = useRef(false);

    const refresh = useCallback(async (silent = false) => {
        if (refreshing.current) return;
        refreshing.current = true;
        if (!silent) setLoading(true);
        setError("");
        try {
            setCertificates(await listCertificates());
        } catch (requestError) {
            setError(requestError instanceof Error ? requestError.message : "Unable to load certificates.");
        } finally {
            refreshing.current = false;
            setLoading(false);
        }
    }, []);

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

    return { certificates, loading, error, refresh };
}