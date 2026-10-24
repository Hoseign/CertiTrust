import type { PublicCertificateResult } from "../services/certitrustApi";

type CertificateVerificationResultProps = {
    result: PublicCertificateResult;
    searchedCode: string;
    onVerifyAnother: () => void;
};

function isCredentialVerified(credential: {
    status?: string;
    blockchain_verification?: { verified: boolean };
}) {
    return ["verified", "valid"].includes(String(credential.status ?? "").toLowerCase())
        && credential.blockchain_verification?.verified === true;
}

export default function CertificateVerificationResult({
    result,
    searchedCode,
    onVerifyAnother,
}: CertificateVerificationResultProps) {
    const certificates = result.certificates ?? [];
    const isVerified = result.multi_degree
        ? certificates.length > 0 && certificates.every(isCredentialVerified)
        : isCredentialVerified(result);
    const databaseStatuses = result.multi_degree
        ? certificates.map((certificate) => String(certificate.status ?? "unknown"))
        : [String(result.status ?? "unknown")];
    const blockchainStatuses = result.multi_degree
        ? certificates.map((certificate) => String(certificate.blockchain_verification?.status ?? "unknown"))
        : [String(result.blockchain_verification?.status ?? "unknown")];
    const databaseStatus = [...new Set(databaseStatuses)].join(", ") || "unknown";
    const blockchainStatus = [...new Set(blockchainStatuses)].join(", ") || "unknown";
    const hasValidDatabaseStatus = databaseStatuses.length > 0
        && databaseStatuses.every((status) => ["verified", "valid"].includes(status.toLowerCase()));
    const statusLabel = isVerified
        ? "Legitimate Credential"
        : hasValidDatabaseStatus && blockchainStatuses.some((status) => status.toLowerCase() === "not_configured")
            ? "Credential Found · Blockchain Not Configured"
            : "Credential Found · Not Verified";
    const institution = result.university_name || result.university_code || "Not available";
    const incompleteMessage = !hasValidDatabaseStatus
        ? `The database marks this record as "${databaseStatus}". It cannot be considered a valid credential.`
        : blockchainStatuses.some((status) => status.toLowerCase() === "not_configured")
            ? "The database marks this credential as verified, but the Polygon Amoy check is not configured. Its on-chain authenticity cannot be confirmed."
            : blockchainStatuses.some((status) => status.toLowerCase() === "pending")
                ? "The database record exists, but its blockchain transaction is still pending. Verify again after the transaction is confirmed."
                : blockchainStatuses.some((status) => status.toLowerCase() === "failed")
                    ? "The database record exists, but the blockchain verification check failed. Do not treat it as on-chain verified until the transaction and network configuration are checked."
                    : `The database record exists, but the blockchain check returned "${blockchainStatus}". The credential cannot be confirmed on-chain yet.`;

    const details: [string, string | undefined][] = [
        ["Certificate ID", result.certificate_code],
        ["Student Name", result.student_name],
        ["Student ID", result.student_id],
        ["Degree and Program", result.degree || result.course_or_event],
        ["Issuing Institution", institution],
        ["Issue Date", result.issue_date],
        ["Database Status", result.status],
        ["Polygon Amoy", result.blockchain_verification?.status || "unknown"],
    ];

    return (
        <section className="mx-auto w-full max-w-4xl space-y-5">
            <div className={`rounded-2xl border bg-white p-6 text-center shadow-sm md:p-8 ${isVerified ? "border-emerald-200" : "border-amber-200"}`}>
                <div className={`mx-auto flex h-16 w-16 items-center justify-center rounded-full text-3xl font-bold ${isVerified ? "bg-emerald-50 text-emerald-600" : "bg-amber-50 text-amber-600"}`}>
                    {isVerified ? "✓" : "!"}
                </div>
                <p className={`mt-4 text-xs font-extrabold uppercase tracking-widest ${isVerified ? "text-emerald-700" : "text-amber-700"}`}>
                    {statusLabel}
                </p>
                <h1 className="mt-2 text-2xl font-extrabold text-[#0A192F]">
                    {result.student_name || "Credential result"}
                </h1>
                <p className="mx-auto mt-2 max-w-2xl text-sm leading-6 text-slate-600">
                    {isVerified
                        ? `This credential was verified on Polygon Amoy and is recorded as issued by ${institution}.`
                        : incompleteMessage}
                </p>
            </div>

            <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm md:p-7">
                <h2 className="mb-5 break-words text-lg font-extrabold text-[#0A192F]">Credential Details</h2>

                {result.multi_degree && certificates.length > 0 ? (
                    <div className="space-y-3">
                        <p className="text-sm font-semibold text-slate-600">
                            Shared credential · {result.degree_count ?? certificates.length} degrees
                        </p>
                        {certificates.map((certificate, index) => (
                            <article
                                key={certificate.certificate_code || certificate.cert_hash || index}
                                className="rounded-xl border border-slate-200 bg-[#F6F8FC] p-4"
                            >
                                <h3 className="font-bold text-[#0A192F]">
                                    Degree {certificate.degree_number ?? index + 1}: {certificate.degree || certificate.course_or_event || "Academic credential"}
                                </h3>
                                <dl className="mt-3 grid gap-3 sm:grid-cols-2">
                                    {[
                                        ["Certificate ID", certificate.certificate_code],
                                        ["Status", certificate.status],
                                        ["Polygon Amoy", certificate.blockchain_verification?.status || "unknown"],
                                        ["SHA-256 Hash", certificate.cert_hash],
                                    ].map(([label, value]) => (
                                        <div key={label}>
                                            <dt className="text-xs font-bold uppercase text-slate-500">{label}</dt>
                                            <dd className="mt-1 break-all text-sm font-semibold text-[#0A192F]">{value || "Not available"}</dd>
                                        </div>
                                    ))}
                                </dl>
                            </article>
                        ))}
                    </div>
                ) : (
                    <dl className="grid gap-3 sm:grid-cols-2">
                        {details.map(([label, value]) => (
                            <div key={label} className="rounded-xl border border-slate-200 bg-[#F6F8FC] p-4">
                                <dt className="text-xs font-bold uppercase text-slate-500">{label}</dt>
                                <dd className="mt-1 break-words text-sm font-semibold text-[#0A192F]">{value || "Not available"}</dd>
                            </div>
                        ))}
                    </dl>
                )}

                {!isVerified && (
                    <div role="status" className="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm leading-6 text-amber-950">
                        <p className="font-bold">Verification is incomplete</p>
                        <p className="mt-1">
                            Database status: <strong>{databaseStatus}</strong>
                            {" · "}
                            Blockchain status: <strong>{blockchainStatus}</strong>
                        </p>
                        <p className="mt-1">
                            A database record alone does not prove on-chain authenticity.
                        </p>
                    </div>
                )}

                {result.blockchain_tx_hash && (
                    <a
                        className="mt-5 inline-block break-all text-sm font-semibold text-blue-700 underline"
                        href={`https://amoy.polygonscan.com/tx/${result.blockchain_tx_hash}`}
                        target="_blank"
                        rel="noreferrer"
                    >
                        View Polygon Amoy transaction
                    </a>
                )}

                <div className="mt-4 rounded-xl border border-slate-200 bg-slate-50 p-4">
                    <p className="mb-2 text-xs font-bold uppercase text-slate-500">Scanned / searched code</p>
                    <p className="break-all font-mono text-xs leading-6 text-[#0A192F]">
                        {result.cert_hash || searchedCode}
                    </p>
                </div>

                <div className="mt-5 flex flex-col gap-3 sm:flex-row">
                    <button
                        type="button"
                        onClick={() => window.print()}
                        className="min-h-12 flex-1 rounded-xl bg-[#1D4ED8] px-5 font-bold text-white transition-colors hover:bg-blue-800"
                    >
                        Print / Save as PDF
                    </button>
                    <button
                        type="button"
                        onClick={onVerifyAnother}
                        className="min-h-12 flex-1 rounded-xl border border-slate-200 px-5 font-bold text-[#0A192F] transition-colors hover:bg-slate-100"
                    >
                        Verify Another Record
                    </button>
                </div>
            </div>
        </section>
    );
}
