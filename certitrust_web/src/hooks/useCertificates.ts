import { useEffect, useState } from "react";
import { listCertificates, type CertificateRecord } from "../services/certitrustApi";

export function useCertificates() {
    const [certificates, setCertificates] = useState<CertificateRecord[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState("");

    const refresh = async (silent = false) => {
        if (!silent) setLoading(true);
        setError("");
        try {
            setCertificates(await listCertificates());
        } catch (requestError) {
            setError(requestError instanceof Error ? requestError.message : "Unable to load certificates.");
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        void refresh();
        const timer = window.setInterval(() => void refresh(true), 5000);
        return () => window.clearInterval(timer);
    }, []);

    return { certificates, loading, error, refresh };
}