
import { useEffect, useRef, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import StudentSidebar from "../../components/StudentSidebar";
import QrScanner from "../../components/QrScanner";
import {
    getCertificateByCode,
    getPublicCertificateByCode,
    type PublicCertificateResult,
} from "../../services/certitrustApi";

export default function CertificateVerification({ publicAccess = false }: { publicAccess?: boolean }) {
    const [searchParams] = useSearchParams();
    const [hashInput, setHashInput] = useState("");
    const [isVerifying, setIsVerifying] = useState(false);
    const [result, setResult] = useState<PublicCertificateResult | null>(null);
    const [errorMessage, setErrorMessage] = useState("");
    const [scannerOpen, setScannerOpen] = useState(false);
    const verificationAttemptRef = useRef(0);
    const initialCode = searchParams.get("hash") || searchParams.get("certificateId");

    useEffect(() => {
        if (!initialCode) return;

        let active = true;
        const attempt = ++verificationAttemptRef.current;
        setHashInput(initialCode);
        setIsVerifying(true);
        (publicAccess ? getPublicCertificateByCode(initialCode) : getCertificateByCode(initialCode))
            .then((record) => {
                if (active && attempt === verificationAttemptRef.current) setResult(record);
            })
            .catch((error) => {
                if (!active || attempt !== verificationAttemptRef.current) return;
                setErrorMessage(error?.response?.status === 410
                    ? error?.response?.data?.message || "This credential was removed from the database and is no longer valid."
                    : error?.response?.status === 404
                        ? "No certificate record matches that code or hash."
                        : error?.response?.data?.message || "Verification service is unavailable.");
            })
            .finally(() => {
                if (active && attempt === verificationAttemptRef.current) setIsVerifying(false);
            });

        return () => { active = false; };
    }, [initialCode, publicAccess]);

    const handleVerify = async (value = hashInput) => {
        const code = value.trim();
        if (!code) return;

        const attempt = ++verificationAttemptRef.current;
        setHashInput(code);
        setIsVerifying(true);
        setErrorMessage("");
        setResult(null);
        try {
            const record = publicAccess
                ? await getPublicCertificateByCode(code)
                : await getCertificateByCode(code);
            if (attempt === verificationAttemptRef.current) setResult(record);
        } catch (error) {
            if (attempt !== verificationAttemptRef.current) return;
            const status = (error as { response?: { status?: number; data?: { message?: string } } })
                .response?.status;
            const message = (error as { response?: { data?: { message?: string } } })
                .response?.data?.message;
            setErrorMessage(status === 410
                ? message || "This credential was removed from the database and is no longer valid."
                : status === 404
                    ? "No certificate record matches that code or hash."
                    : message || "Verification service is unavailable.");
        } finally {
            if (attempt === verificationAttemptRef.current) setIsVerifying(false);
        }
    };

    const handleReset = () => {
        verificationAttemptRef.current += 1;
        setResult(null);
        setHashInput("");
        setErrorMessage("");
    };

    const isVerified = !!result
        && ["verified", "valid"].includes(String(result.status ?? "").toLowerCase())
        && (result.multi_degree
            ? Boolean(result.certificates?.length)
                && result.certificates!.every((certificate) =>
                    ["verified", "valid"].includes(String(certificate.status ?? "").toLowerCase())
                    && certificate.blockchain_verification?.verified === true)
            : result.blockchain_verification?.verified === true);

    return (
        <div className="min-h-screen bg-[#F6F8FC]">
            {!publicAccess && <StudentSidebar />}

            <main className={`min-h-screen min-w-0 ${publicAccess ? "" : "md:ml-64"}`}>
                <div className="min-h-screen w-full p-4 sm:p-6 lg:p-8">
                    {publicAccess && (
                        <div className="mx-auto mb-5 flex max-w-5xl items-center justify-between gap-4">
                            <Link to="/login" className="text-sm font-bold text-[#1D4ED8] hover:underline">
                                Back to CertiTrust
                            </Link>
                            <span className="text-xs font-semibold text-slate-500">Public verification</span>
                        </div>
                    )}
                    <header className="mb-7 flex items-center gap-4 rounded-2xl border border-slate-200 bg-white p-5 shadow-[0_12px_35px_rgba(15,23,42,0.06)] md:p-6">
                        <div className="min-w-0">
                            <p className="mb-1 text-xs font-extrabold uppercase tracking-wider text-[#2563EB]">
                                Credential verification
                            </p>
                            <h1 className="text-2xl font-extrabold text-[#0A192F] md:text-3xl">
                                Certificate Verification
                            </h1>
                            <p className="mt-1 text-sm text-slate-500">
                                Check academic credential details using CertiTrust.
                            </p>
                        </div>
                    </header>

                    {isVerifying && (
                        <p role="status" className="mb-4 rounded-xl border border-blue-200 bg-blue-50 p-4 text-sm font-semibold text-blue-800">
                            Verifying scanned credential…
                        </p>
                    )}

                    {!result ? (
                        <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm md:p-8">
                            <div className="rounded-xl border border-[#BFDBFE] bg-[#EAF2FF] p-4 text-sm leading-6 text-[#1D4ED8]">
                                <p className="font-bold">Credential verification</p>
                                <p className="mt-1">
                                    Enter a certificate code or SHA-256 hash to check the Laravel record and Polygon Amoy anchor.
                                </p>
                            </div>

                            <div className="mt-6 grid gap-2">
                                <label
                                    htmlFor="certificate-hash"
                                    className="text-sm font-bold text-[#172033]"
                                >
                                    Certificate Hash
                                </label>
                                <input
                                    id="certificate-hash"
                                    type="text"
                                    value={hashInput}
                                    onChange={(event) => {
                                        setHashInput(event.target.value);
                                        setErrorMessage("");
                                    }}
                                    onKeyDown={(event) => {
                                        if (event.key === "Enter") handleVerify();
                                    }}
                                    placeholder="Enter certificate hash"
                                    className="min-h-12 w-full rounded-xl border border-slate-200 bg-white px-4 py-3 font-mono text-sm outline-none transition focus:border-[#1D4ED8] focus:ring-4 focus:ring-[#1D4ED8]/10"
                                />
                                <button
                                    type="button"
                                    onClick={() => setScannerOpen(true)}
                                    className="mt-3 inline-flex min-h-11 items-center justify-center gap-2 rounded-xl border border-[#1D4ED8] px-4 font-bold text-[#1D4ED8] hover:bg-blue-50"
                                >
                                    Scan QR code
                                </button>
                                <p className="text-xs text-slate-400">
                                        Search by a certificate code or SHA-256 hash.
                                </p>
                            </div>

                            {errorMessage && (
                                <div
                                    role="alert"
                                    className="mt-4 rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700"
                                >
                                    {errorMessage}
                                </div>
                            )}

                            <button
                                type="button"
                                onClick={() => void handleVerify()}
                                disabled={isVerifying || !hashInput.trim()}
                                className="mt-5 inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-xl bg-[#1D4ED8] px-5 font-bold text-white shadow-md transition-colors hover:bg-blue-800 disabled:cursor-not-allowed disabled:bg-slate-300 disabled:text-slate-600"
                            >
                                {isVerifying ? "Checking credential..." : "Verify This Record"}
                            </button>
                        </section>
                    ) : (
                        <div className="space-y-6">
                            <section className={`rounded-2xl border bg-white p-6 text-center shadow-sm md:p-8 ${isVerified ? "border-emerald-200" : "border-amber-200"}`}>
                                <div className={`mx-auto flex h-16 w-16 items-center justify-center rounded-full text-3xl font-bold ${isVerified ? "bg-emerald-50 text-emerald-600" : "bg-amber-50 text-amber-600"}`}>
                                    {isVerified ? "✓" : "!"}
                                </div>
                                <p className="mt-4 text-xs font-bold uppercase tracking-widest text-slate-600">
                                    {isVerified
                                        ? "On-chain credential verified"
                                        : ["verified", "valid"].includes(String(result.status ?? "").toLowerCase())
                                            ? "Record found; chain verification incomplete"
                                            : "Credential record found, but its database status is not valid"}
                                </p>
                                <h2 className="mt-2 text-2xl font-extrabold text-[#0A192F]">
                                        {result.student_name}
                                </h2>
                                <p className="mt-2 text-sm leading-6 text-slate-500">
                                        {isVerified
                                            ? `The credential is recorded on Polygon Amoy and issued by ${result.university_name || result.university_code || "the listed institution"}.`
                                            : result.multi_degree
                                                ? `The database record is ${result.status}. One or more degree credentials have not been verified on Polygon Amoy.`
                                                : `The database record is ${result.status}; Polygon Amoy reports ${result.blockchain_verification?.status || "unknown"}.`}
                                </p>
                            </section>

                            <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm md:p-7">
                                <h3 className="mb-5 text-lg font-extrabold text-[#0A192F]">
                                    Credential Details
                                </h3>

                                {result.multi_degree ? (
                                    <div className="space-y-3">
                                        <p className="text-sm font-semibold text-slate-600">
                                            Shared credential · {result.degree_count ?? result.certificates?.length ?? 0} degrees · scanned code: {hashInput}
                                        </p>
                                        {result.certificates?.map((certificate, index) => (
                                            <article key={certificate.certificate_code || certificate.cert_hash || index} className="rounded-xl border border-slate-200 bg-[#F6F8FC] p-4">
                                                <h4 className="font-bold text-[#0A192F]">
                                                    Degree {certificate.degree_number ?? index + 1}: {certificate.degree || certificate.course_or_event || "Academic credential"}
                                                </h4>
                                                <p className="mt-2 text-sm text-slate-600">
                                                    Certificate: {certificate.certificate_code || "Not available"}
                                                </p>
                                                <p className="mt-1 text-sm text-slate-600">
                                                    Status: {certificate.status} · Polygon Amoy: {certificate.blockchain_verification?.status || "unknown"}
                                                </p>
                                                {certificate.cert_hash && (
                                                    <p className="mt-2 break-all font-mono text-xs text-slate-500">
                                                        Hash: {certificate.cert_hash}
                                                    </p>
                                                )}
                                            </article>
                                        ))}
                                    </div>
                                ) : (
                                    <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
                                        {[
                                            ["Certificate ID", result.certificate_code],
                                            ["Student Name", result.student_name],
                                            ["Student ID", result.student_id],
                                            ["Degree and Program", result.degree || result.course_or_event],
                                            ["Issuing Institution", result.university_name || result.university_code],
                                            ["Issue Date", result.issue_date],
                                            ["Database status", result.status],
                                            ["Polygon Amoy", result.blockchain_verification?.status || "unknown"],
                                        ].map(([label, value]) => (
                                            <div
                                                key={label}
                                                className="flex min-w-0 flex-col gap-1 rounded-xl border border-slate-200 bg-[#F6F8FC] p-4 sm:flex-row sm:justify-between sm:gap-3"
                                            >
                                                <span className="text-xs font-bold text-slate-500">
                                                    {label}
                                                </span>
                                                <span className="break-words text-sm font-bold text-[#0A192F] sm:text-right">
                                                    {value || "Not available"}
                                                </span>
                                            </div>
                                        ))}
                                    </div>
                                )}
                                {result.blockchain_tx_hash && (
                                    <a className="mt-4 inline-block break-all text-sm font-semibold text-blue-700 underline" href={`https://amoy.polygonscan.com/tx/${result.blockchain_tx_hash}`} target="_blank" rel="noreferrer">
                                        View Polygon Amoy transaction
                                    </a>
                                )}

                                <div className="mt-4 rounded-xl border border-slate-200 bg-slate-50 p-4">
                                    <p className="mb-2 text-xs font-bold text-slate-500">
                                        Certificate Hash
                                    </p>
                                    <p className="break-all font-mono text-xs leading-6 text-[#0A192F]">
                                            {result.cert_hash || hashInput}
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
                                        onClick={handleReset}
                                        className="min-h-12 flex-1 rounded-xl border border-slate-200 px-5 font-bold text-[#0A192F] transition-colors hover:bg-slate-100"
                                    >
                                        Verify Another Record
                                    </button>
                                </div>
                            </section>
                        </div>
                    )}

                    <footer className="py-6 text-center text-xs text-slate-400">
                        CertiTrust · Secure Academic Credential Verification
                    </footer>
                </div>
            </main>
            {scannerOpen && (
                <QrScanner
                    onClose={() => setScannerOpen(false)}
                    onScan={(value) => {
                        setScannerOpen(false);
                        void handleVerify(value);
                    }}
                />
            )}
        </div>
    );
}
