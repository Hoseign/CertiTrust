
import { useEffect, useRef, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import StudentSidebar from "@/Components/Organisms/StudentSidebar";
import QrScanner from "@/Components/Organisms/QrScanner";
import CertificateVerificationResult from "@/Components/Organisms/CertificateVerificationResult";
import {
    getCertificateByCode,
    getPublicPortfolio,
    getPublicCertificateByCode,
    type StudentPortfolio,
    type PublicCertificateResult,
} from "../../services/certitrustApi";

export default function CertificateVerification({ publicAccess = false }: { publicAccess?: boolean }) {
    const [searchParams] = useSearchParams();
    const [hashInput, setHashInput] = useState("");
    const [isVerifying, setIsVerifying] = useState(false);
    const [result, setResult] = useState<PublicCertificateResult | null>(null);
    const [portfolio, setPortfolio] = useState<StudentPortfolio | null>(null);
    const [errorMessage, setErrorMessage] = useState("");
    const [scannerOpen, setScannerOpen] = useState(false);
    const verificationAttemptRef = useRef(0);
    const initialCode = searchParams.get("hash") || searchParams.get("certificateId");
    const manualEntry = searchParams.get("manual") === "1";
    const portfolioToken = searchParams.get("portfolio");

    useEffect(() => {
        if (!portfolioToken) return;
        let active = true;
        setIsVerifying(true);
        getPublicPortfolio(portfolioToken).then((data) => {
            if (active) setPortfolio(data);
        }).catch(() => {
            if (active) setErrorMessage("This public portfolio could not be found.");
        }).finally(() => {
            if (active) setIsVerifying(false);
        });
        return () => { active = false; };
    }, [portfolioToken]);

    const downloadAllDiplomas = () => {
        portfolio?.certificates.forEach((certificate, index) => {
            const url = certificate.diploma_url?.toString();
            if (!url) return;
            const link = document.createElement("a");
            link.href = url;
            link.download = `${certificate.student_id || "student"}-diploma-${index + 1}`;
            link.target = "_blank";
            link.rel = "noreferrer";
            link.click();
        });
    };

    useEffect(() => {
        if (!initialCode) return;
        if (initialCode.trim().toLowerCase() === "preview") {
            setHashInput("");
            setErrorMessage("Enter a certificate code or SHA-256 hash to verify.");
            return;
        }

        let active = true;
        if (manualEntry) {
            setHashInput(initialCode);
            setIsVerifying(false);
            return () => { active = false; };
        }
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
    }, [initialCode, manualEntry, publicAccess]);

    const handleVerify = async (value = hashInput) => {
        const code = value.trim();
        if (!code) return;
        if (code.toLowerCase() === "preview") {
            setErrorMessage("Enter a certificate code or SHA-256 hash to verify.");
            return;
        }

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

                    {portfolio ? (
                        <section className="mx-auto max-w-5xl">
                            <div className="mb-5 flex flex-wrap items-end justify-between gap-4 border-b border-slate-200 pb-4">
                                <div><p className="text-xs font-bold uppercase text-emerald-700">Verified portfolio</p><h2 className="mt-1 text-2xl font-extrabold text-[#0A192F]">{portfolio.student_name || "Student portfolio"}</h2><p className="mt-1 text-sm text-slate-600">{portfolio.degree_count} credentials · Master hash {portfolio.master_hash}</p></div>
                                <button type="button" onClick={downloadAllDiplomas} className="min-h-10 rounded-lg bg-[#0A192F] px-4 text-sm font-bold text-white">Download All Diplomas</button>
                            </div>
                            <div className="space-y-5">
                                {portfolio.groups.map((group) => <section key={group.university_code}>
                                    <h3 className="mb-2 text-lg font-bold text-[#0A192F]">{group.university_name}</h3>
                                    <div className="divide-y divide-slate-200 border-y border-slate-200 bg-white">
                                        {group.certificates.map((credential) => <details key={credential.id || credential.certificate_code} className="group p-4">
                                            <summary className="cursor-pointer font-bold text-[#0A192F]">{credential.degree} <span className="ml-2 text-xs font-medium text-slate-500">{credential.issue_date}</span></summary>
                                            <div className="mt-4 grid gap-4 sm:grid-cols-[minmax(0,1fr)_220px]">
                                                <dl className="grid gap-3 text-sm sm:grid-cols-2"><div><dt className="text-slate-500">Institution</dt><dd>{credential.university_name || group.university_name}</dd></div><div><dt className="text-slate-500">Issue date</dt><dd>{credential.issue_date}</dd></div><div className="sm:col-span-2"><dt className="text-slate-500">On-chain hash</dt><dd className="break-all font-mono text-xs">{credential.cert_hash}</dd></div><div><dt className="text-slate-500">Verification</dt><dd>{credential.blockchain_verification?.verified ? "Verified on chain" : credential.status}</dd></div></dl>
                                                {credential.diploma_url && <a href={credential.diploma_url} target="_blank" rel="noreferrer" className="block"><img src={credential.diploma_url} alt={`${credential.degree} diploma`} className="max-h-48 w-full border border-slate-200 object-contain" /></a>}
                                            </div>
                                            {credential.diploma_url && <a href={credential.diploma_url} download className="mt-3 inline-flex min-h-9 items-center rounded-md border border-slate-300 px-3 text-sm font-bold">Download Diploma</a>}
                                        </details>)}
                                    </div>
                                </section>)}
                            </div>
                        </section>
                    ) : !result ? (
                        <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm md:p-8">
                            <div className="rounded-xl border border-[#BFDBFE] bg-[#EAF2FF] p-4 text-sm leading-6 text-[#1D4ED8]">
                                <p className="font-bold">Credential verification</p>
                                <p className="mt-1">
                                    Enter a certificate code or SHA-256 hash to check the Laravel record and Ethereum Sepolia anchor.
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
                        <CertificateVerificationResult
                            result={result}
                            searchedCode={hashInput}
                            onVerifyAnother={handleReset}
                        />
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
