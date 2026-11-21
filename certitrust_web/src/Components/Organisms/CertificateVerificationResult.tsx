import type { PublicCertificateResult } from "@/services/certitrustApi";
import { getSessionUser, resolveProfileImageUrl } from "@/services/authService";
import { useNavigate } from "react-router-dom";

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

async function downloadDiploma(url: string, fileName: string) {
    try {
        const response = await fetch(url);
        if (!response.ok) throw new Error("Diploma download failed");
        const objectUrl = URL.createObjectURL(await response.blob());
        const link = document.createElement("a");
        link.href = objectUrl;
        link.download = fileName;
        document.body.appendChild(link);
        link.click();
        link.remove();
        window.setTimeout(() => URL.revokeObjectURL(objectUrl), 1000);
    } catch {
        window.open(url, "_blank", "noopener,noreferrer");
    }
}

function DetailRow({
    label,
    value,
}: {
    label: string;
    value?: string | number | null;
}) {
    return (
        <div className="grid gap-1 border-b border-slate-100 py-3 sm:grid-cols-[140px_minmax(0,1fr)] sm:gap-4">
            <dt className="text-sm font-bold text-[#0A192F]">{label}</dt>
            <dd className="break-words text-sm text-slate-700">
                {value === null || value === undefined || value === "" ? "N/A" : value}
            </dd>
        </div>
    );
}

export default function CertificateVerificationResult({
    result,
    searchedCode,
    onVerifyAnother,
}: CertificateVerificationResultProps) {
    const navigate = useNavigate();
    const sessionUser = getSessionUser();
    const certificates = result.certificates ?? [];
    const isMultipleDegree = certificates.length > 1;
    const singleCertificate = certificates.length === 1
        ? certificates[0]
        : result;
    const issuingInstitutions = new Map<string, string>();
    for (const certificate of isMultipleDegree ? certificates : [singleCertificate]) {
        const code = certificate.university_code?.trim() ?? "";
        if (code) {
            issuingInstitutions.set(
                code.toUpperCase(),
                certificate.university_name?.trim() || code,
            );
        }
    }

    const universityNamesByIdentity = new Map<string, string>();
    for (const certificate of certificates) {
        const code = certificate.university_code?.trim() ?? "";
        const name = certificate.university_name?.trim() ?? "";
        const identity = (code || name).toLowerCase();
        if (identity && !universityNamesByIdentity.has(identity)) {
            universityNamesByIdentity.set(identity, name || code);
        }
    }
    const topLevelCode = singleCertificate.university_code?.trim() ?? "";
    const topLevelName = singleCertificate.university_name?.trim() ?? "";
    const topLevelIdentity = (topLevelCode || topLevelName).toLowerCase();
    if (
        universityNamesByIdentity.size === 0
        && topLevelIdentity
        && !["multi", "multiple universities"].includes(topLevelIdentity)
    ) {
        universityNamesByIdentity.set(topLevelIdentity, topLevelName || topLevelCode);
    }

    const universityNames = [...universityNamesByIdentity.values()];
    const universityCount = universityNames.length;
    const universityCountLabel = universityCount > 0
        ? `${universityCount} ${universityCount === 1 ? "university" : "universities"}`
        : "multiple universities";
    const schoolCode = (isMultipleDegree ? "MULTI" : topLevelCode || "Verified Institution").toUpperCase();
    const fallbackSchoolName = schoolCode === "PSU"
        ? "Pangasinan State University"
        : schoolCode === "UCU"
            ? "Urdaneta City University"
            : schoolCode === "MULTI"
                ? universityCount === 1
                    ? universityNames[0]
                    : universityCount > 1
                        ? "Multiple Universities"
                        : "University information unavailable"
                : "Verified academic institution";
    const schoolName = [
        isMultipleDegree
            ? fallbackSchoolName
            : topLevelName || fallbackSchoolName,
        !isMultipleDegree ? singleCertificate.branch_campus?.trim() : "",
    ].filter(Boolean).join(" • ");
    const schoolLabel = isMultipleDegree
        ? universityCount === 1
            ? "1 University"
            : universityCount > 1
                ? "Multiple Universities"
                : schoolName
        : schoolCode;
    const schoolLogo = isMultipleDegree
        ? "/certitrustlogo.png"
        : resolveProfileImageUrl(singleCertificate.university_logo_url) || "/certitrustlogo.png";

    const isVerified = certificates.length > 0
        ? certificates.every(isCredentialVerified)
        : isCredentialVerified(result);
    const databaseStatuses = certificates.length > 0
        ? certificates.map((certificate) => String(certificate.status ?? "unknown"))
        : [String(result.status ?? "unknown")];
    const blockchainStatuses = certificates.length > 0
        ? certificates.map((certificate) => String(certificate.blockchain_verification?.status ?? "unknown"))
        : [String(result.blockchain_verification?.status ?? "unknown")];
    const databaseStatus = [...new Set(databaseStatuses)].join(", ") || "unknown";
    const blockchainStatus = [...new Set(blockchainStatuses)].join(", ") || "unknown";
    const hasValidDatabaseStatus = databaseStatuses.length > 0
        && databaseStatuses.every((status) => ["verified", "valid"].includes(status.toLowerCase()));
    const statusLabel = isVerified ? "Legitimate Credential" : "Credential Not Verified";
    const studentName = singleCertificate.student_name
        || singleCertificate.recipient_name
        || "the student";
    const verifiedMessage = isMultipleDegree
        ? `These ${certificates.length} credentials belong to ${result.student_name || "the student"} and were verified across ${universityCountLabel}.`
        : `This credential proves that ${studentName} graduated from ${schoolName} and was verified by CertiTrust.`;
    const incompleteMessage = !hasValidDatabaseStatus
        ? `The database marks this record as "${databaseStatus}". It cannot be considered a valid credential.`
        : blockchainStatuses.some((status) => status.toLowerCase() === "not_configured")
            ? "The database marks this credential as verified, but the Ethereum Sepolia check is not configured. Its on-chain authenticity cannot be confirmed."
            : blockchainStatuses.some((status) => status.toLowerCase() === "pending")
                ? "The database record exists, but its blockchain transaction is still pending. Verify again after the transaction is confirmed."
                : blockchainStatuses.some((status) => status.toLowerCase() === "failed")
                    ? "The database record exists, but the blockchain verification check failed. Do not treat it as on-chain verified until the transaction and network configuration are checked."
                    : `The database record exists, but the blockchain check returned "${blockchainStatus}". The credential cannot be confirmed on-chain yet.`;

    const network = (
        singleCertificate.blockchain_verification?.network
        || singleCertificate.blockchain_network
        || ""
    ).toLowerCase();
    const transactionUrl = singleCertificate.blockchain_tx_hash
        ? network.includes("sepolia")
            ? `https://sepolia.etherscan.io/tx/${singleCertificate.blockchain_tx_hash}`
            : network.includes("amoy")
                ? `https://amoy.polygonscan.com/tx/${singleCertificate.blockchain_tx_hash}`
                : null
        : null;

    return (
        <section className="mx-auto w-full max-w-3xl">
            <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm sm:p-8">
                <div className="flex flex-col items-center text-center">
                    <div className={`flex h-20 w-20 items-center justify-center rounded-full text-5xl font-bold ${isVerified ? "bg-emerald-50 text-emerald-600" : "bg-red-50 text-red-600"}`}>
                        {isVerified ? "✓" : "!"}
                    </div>
                    <h1 className={`mt-3 text-2xl font-extrabold ${isVerified ? "text-emerald-700" : "text-red-700"}`}>
                        {statusLabel}
                    </h1>
                    <div className="my-5 h-px w-full bg-slate-200" />
                    <img
                        src={schoolLogo}
                        alt={`${schoolName} logo`}
                        className="h-24 w-24 object-contain"
                        onError={(event) => {
                            const image = event.currentTarget;
                            if (image.dataset.fallbackApplied) {
                                image.hidden = true;
                                return;
                            }
                            image.dataset.fallbackApplied = "true";
                            image.src = "/certitrustlogo.png";
                        }}
                    />
                    <p className={`mt-3 text-xl font-extrabold ${isMultipleDegree ? "text-blue-700" : "text-red-600"}`}>
                        {schoolLabel}
                    </p>
                    <p className="mt-1 font-semibold text-[#0A192F]">{schoolName}</p>
                    <p className="mx-auto mt-3 max-w-2xl text-sm font-semibold leading-6 text-slate-700">
                        {isVerified ? verifiedMessage : incompleteMessage}
                    </p>
                </div>

                <div className="mt-6">
                    {isMultipleDegree ? (
                        <>
                            <dl>
                                <DetailRow label="Student name" value={result.student_name || result.recipient_name} />
                                <DetailRow label="Student ID" value={result.student_id} />
                            </dl>
                            <div className="mt-4 space-y-3">
                                {certificates.map((certificate, index) => {
                                    const universityCode = certificate.university_code?.toUpperCase() ?? "";
                                    const universityName = certificate.university_name
                                        || universityCode
                                        || "Verified academic institution";
                                    const displayName = certificate.display_name || universityCode;
                                    const campus = certificate.branch_campus?.trim();
                                    return (
                                        <article
                                            key={certificate.certificate_code || certificate.cert_hash || index}
                                            className="rounded-xl border border-slate-200 bg-[#F6F8FC] p-4"
                                        >
                                            <h2 className="font-bold text-[#0A192F]">
                                                {certificate.degree_number
                                                    ? `Degree ${certificate.degree_number}`
                                                    : "Degree credential"}
                                            </h2>
                                            <dl className="mt-2">
                                                <DetailRow
                                                    label="University"
                                                    value={[
                                                        universityCode
                                                            ? `${universityName} (${displayName || universityCode})`
                                                            : universityName,
                                                        campus,
                                                    ].filter(Boolean).join(" • ")}
                                                />
                                                <DetailRow
                                                    label="Degree and program"
                                                    value={certificate.degree || certificate.course_or_event}
                                                />
                                                <DetailRow label="Issue date" value={certificate.issue_date} />
                                                <DetailRow label="Status" value={certificate.status} />
                                            </dl>
                                            {certificate.diploma_url ? (
                                                <div className="mt-3">
                                                    <a href={certificate.diploma_url} target="_blank" rel="noreferrer">
                                                        <img
                                                            src={certificate.diploma_url}
                                                            alt={`${certificate.degree || "Degree"} diploma`}
                                                            className="max-h-80 w-full rounded-lg object-contain"
                                                        />
                                                    </a>
                                                    <button
                                                        type="button"
                                                        onClick={() => void downloadDiploma(
                                                            certificate.diploma_url!,
                                                            certificate.diploma_file_name || `${certificate.certificate_code || `degree-${index + 1}`}-diploma`,
                                                        )}
                                                        className="mt-2 min-h-10 rounded-lg px-3 text-sm font-bold text-blue-700 hover:bg-blue-50"
                                                    >
                                                        Download Diploma
                                                    </button>
                                                </div>
                                            ) : (
                                                <p className="mt-3 text-sm text-slate-500">
                                                    No diploma image was attached to this credential.
                                                </p>
                                            )}
                                        </article>
                                    );
                                })}
                            </div>
                        </>
                    ) : (
                        <>
                            <dl>
                                <DetailRow
                                    label="Student name"
                                    value={singleCertificate.student_name || singleCertificate.recipient_name}
                                />
                                <DetailRow label="Student ID" value={singleCertificate.student_id} />
                                <DetailRow
                                    label="Degree and program"
                                    value={singleCertificate.degree || singleCertificate.course_or_event}
                                />
                                <DetailRow label="Issue date" value={singleCertificate.issue_date} />
                            </dl>
                            {isVerified && singleCertificate.diploma_url ? (
                                <div className="mt-5">
                                    <h2 className="font-bold text-[#0A192F]">Attached diploma image</h2>
                                    <a href={singleCertificate.diploma_url} target="_blank" rel="noreferrer">
                                        <img
                                            src={singleCertificate.diploma_url}
                                            alt={`${singleCertificate.degree || singleCertificate.course_or_event || "Credential"} diploma`}
                                            className="mt-2 max-h-96 w-full rounded-lg object-contain"
                                        />
                                    </a>
                                    <button
                                        type="button"
                                        onClick={() => void downloadDiploma(
                                            singleCertificate.diploma_url!,
                                            singleCertificate.diploma_file_name || `${singleCertificate.certificate_code || "credential"}-diploma`,
                                        )}
                                        className="mt-2 min-h-10 rounded-lg px-3 text-sm font-bold text-blue-700 hover:bg-blue-50"
                                    >
                                        Download Diploma
                                    </button>
                                </div>
                            ) : isVerified ? (
                                <p className="mt-5 text-sm text-slate-600">
                                    No diploma image was attached to this credential.
                                </p>
                            ) : null}
                        </>
                    )}
                </div>

                {!isVerified && (
                    <div role="status" className="mt-5 rounded-xl border border-red-200 bg-red-50 p-4 text-sm leading-6 text-red-950">
                        <p className="font-bold">Verification failed for this credential</p>
                        <p className="mt-1">
                            Database status: <strong>{databaseStatus}</strong>
                            {" · "}
                            Blockchain status: <strong>{blockchainStatus}</strong>
                        </p>
                    </div>
                )}

                {transactionUrl && (
                    <a
                        className="mt-5 inline-block break-all text-sm font-semibold text-blue-700 underline"
                        href={transactionUrl}
                        target="_blank"
                        rel="noreferrer"
                    >
                        View blockchain transaction
                    </a>
                )}

                {issuingInstitutions.size > 0 && (
                    <div className="mt-5 rounded-xl border border-blue-100 bg-blue-50 p-4">
                        <p className="font-bold text-[#0A192F]">Questions about this credential?</p>
                        <div className="mt-3 flex flex-wrap gap-2">
                            {[...issuingInstitutions.entries()].map(([code, name]) => (
                                <button
                                    type="button"
                                    key={code}
                                    onClick={() => {
                                        const chatPath = `/institutional-chat?institution_code=${encodeURIComponent(code)}`;
                                        navigate(
                                            sessionUser
                                                ? chatPath
                                                : `/login?redirect=${encodeURIComponent(chatPath)}`,
                                        );
                                    }}
                                    className="min-h-11 rounded-lg bg-blue-700 px-4 py-2 text-sm font-bold text-white transition-colors hover:bg-blue-800"
                                >
                                    {issuingInstitutions.size > 1
                                        ? `Message ${name} Registrar Desk`
                                        : "Message Issuing University"}
                                </button>
                            ))}
                        </div>
                    </div>
                )}

                <div className={`mt-5 flex items-center gap-3 rounded-xl p-4 ${isVerified ? "bg-emerald-50 text-emerald-900" : "bg-red-50 text-red-900"}`}>
                    <span className="text-xl" aria-hidden="true">{isVerified ? "✓" : "!"}</span>
                    <p className="font-semibold">
                        {isVerified
                            ? "Verified on the CertiTrust ledger"
                            : "Verification failed for this credential"}
                    </p>
                </div>

                <div className="mt-5 rounded-xl border border-slate-200 bg-slate-50 p-4">
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
