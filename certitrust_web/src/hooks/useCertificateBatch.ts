import { useState } from "react";
import {
    issueCertificateBatch,
    type CertificateDraft,
} from "../services/certitrustApi";

export function useCertificateBatch() {
    const [isIssuing, setIsIssuing] = useState(false);
    const [error, setError] = useState("");

    const issueBatch = async (drafts: CertificateDraft[]) => {
        setIsIssuing(true);
        setError("");
        try {
            return await issueCertificateBatch(drafts);
        } catch (requestError) {
            const message = (requestError as { response?: { data?: { message?: string } } })
                .response?.data?.message;
            const errorMessage = message
                || (requestError instanceof Error ? requestError.message : "Certificate issuance failed.");
            setError(errorMessage);
            throw requestError;
        } finally {
            setIsIssuing(false);
        }
    };

    return { issueBatch, isIssuing, error };
}