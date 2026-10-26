import { useEffect, useRef, useState } from "react";
import { QRCodeCanvas } from "qrcode.react";
import Sidebar from "@/Components/Organisms/Sidebar";
import { Link, useNavigate } from "react-router-dom";
import {
    listCertificates,
    listRecentVerifications,
    requestCertificateDeletion,
    type CertificateRecord,
} from "../../services/certitrustApi";
import { getSessionUser } from "../../services/authService";

type Verified = {
    id: string;
    name: string;
    program: string;
    university: string;
    verifiedAt: string;
};

const popupActionClass =
    "inline-flex items-center justify-center gap-3 min-h-12 px-4 rounded-xl text-[#0A3D75] font-bold text-lg hover:bg-white transition";

export default function Dashboard() {
    const navigate = useNavigate();
    const [verified, setVerified] = useState<Verified[]>([]);
    const [recentCredential, setRecentCredential] = useState<CertificateRecord | null>(null);
    const [refreshError, setRefreshError] = useState("");
    const [actionMessage, setActionMessage] = useState("");
    const [recentOpen, setRecentOpen] = useState<boolean>(false);
    const [detailsOpen, setDetailsOpen] = useState<boolean>(false);
    const [qrOpen, setQrOpen] = useState<boolean>(false);
    const qrWrapRef = useRef<HTMLDivElement>(null);

    const refresh = async () => {
        try {
            const [verifications, certificates] = await Promise.all([
                listRecentVerifications(),
                listCertificates(1),
            ]);
            setVerified(verifications.map((record) => ({
                id: String(record.id),
                name: record.student_name || "Student",
                program: record.degree || "Academic credential",
                university: record.university_name || record.university_code || "Institution",
                verifiedAt: record.verified_at || record.created_at || "",
            })));
            setRecentCredential(certificates[0] || null);
            setRefreshError("");
        } catch (error) {
            setRefreshError((error as { response?: { data?: { message?: string } } })
                .response?.data?.message || "Unable to refresh dashboard activity.");
        }
    };

    useEffect(() => {
        void refresh();
        const timer = window.setInterval(() => void refresh(), 5000);
        return () => window.clearInterval(timer);
    }, []);

    useEffect(() => {
        if (!recentOpen && !qrOpen) return;
        const onKey = (e: KeyboardEvent) => {
            if (e.key !== "Escape") return;
            if (qrOpen) setQrOpen(false);
            else setRecentOpen(false);
        };
        window.addEventListener("keydown", onKey);
        return () => window.removeEventListener("keydown", onKey);
    }, [recentOpen, qrOpen]);

    const saveQr = () => {
        const canvas = qrWrapRef.current?.querySelector("canvas");
        if (!canvas) return;
        const link = document.createElement("a");
        link.href = canvas.toDataURL("image/png");
        link.download = `qr-${recentCredential?.student_id || "credential"}.png`;
        link.click();
    };

    const openRecentVerification = () => {
        if (!recentCredential) return;
        const code = recentCredential.cert_hash || recentCredential.certificate_code;
        navigate(`/verification?hash=${encodeURIComponent(code)}`);
        setRecentOpen(false);
    };

    const openRecentDiploma = () => {
        if (!recentCredential?.diploma_url) {
            setActionMessage("No diploma file is attached to the latest credential.");
            return;
        }
        window.open(recentCredential.diploma_url, "_blank", "noopener,noreferrer");
    };

    const requestRecentDeletion = async () => {
        if (!recentCredential) return;
        const reason = window.prompt("Why should this credential be deleted?");
        if (reason === null) return;
        if (!reason.trim()) {
            setActionMessage("Enter a reason before requesting deletion.");
            return;
        }
        try {
            await requestCertificateDeletion(recentCredential.id, reason.trim());
            setActionMessage("Deletion request sent for review.");
        } catch (error) {
            setActionMessage((error as { response?: { data?: { message?: string } } })
                .response?.data?.message || "Unable to send the deletion request.");
        }
    };

    const recentRows: [string, string][] = recentCredential ? [
        ["Student name", recentCredential.student_name],
        ["Student ID", recentCredential.student_id],
        ["Course / program", recentCredential.degree],
        ["Degree number", String(recentCredential.degree_number ?? 1)],
        ["University", recentCredential.university_code || ""],
        ["Email", recentCredential.student_email],
        ["Certificate code", recentCredential.certificate_code],
        ["Issue date", recentCredential.issue_date],
        ["Status", recentCredential.status],
        ["Blockchain status", recentCredential.blockchain_status || "not_configured"],
    ] : [];
    const qrPayload = recentCredential?.cert_hash || recentCredential?.certificate_code || "";

    return (
        <div className="min-h-screen bg-[#FAFAFD]">
            <div className="min-h-screen grid grid-cols-1 md:grid-cols-[286px_1fr]">

                {/* Sidebar */}
                <Sidebar />

                {/* Main Content */}
                <main className="min-w-0 overflow-y-auto h-screen p-4 sm:p-6 md:p-10">
                    <div className="max-w-5xl mx-auto">

                        {/* Page Header */}
                        <h1 className="text-3xl font-extrabold text-[#0A192F] mb-8">
                            CertiTrust Dashboard
                        </h1>
                        {refreshError && <p role="alert" className="mb-5 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">{refreshError}</p>}

                        {/* Welcome Card */}
                        <section className="flex items-center gap-8 rounded-3xl bg-[#F1F4F8] p-8 md:p-10 shadow-[0_4px_12px_rgba(15,23,42,0.12)]">
                            <div className="flex h-24 w-24 flex-none items-center justify-center rounded-full bg-[#E0E3EE] text-[#003366]">
                                <svg
                                    width="46"
                                    height="46"
                                    viewBox="0 0 24 24"
                                    fill="currentColor"
                                >
                                    <path d="M12 3 1 9l11 6 9-4.9V17h2V9L12 3z" />
                                    <path d="M5 13.2v3.5c0 1.3 3.1 3.3 7 3.3s7-2 7-3.3v-3.5l-7 3.8-7-3.8z" />
                                </svg>
                            </div>

                            <div className="min-w-0">
                                <h2 className="text-3xl md:text-4xl font-bold text-[#111] leading-tight">
                                    Welcome to {getSessionUser()?.university_code || "your institution"} (Admin)
                                </h2>

                                <p className="mt-3 text-lg md:text-xl text-gray-500">
                                    Manage and verify blockchain-anchored academic credentials.
                                </p>
                            </div>
                        </section>

                        {/* Quick Actions */}
                        <h2 className="mt-10 mb-5 text-2xl font-bold text-[#111]">
                            Quick Actions
                        </h2>

                        <section className="grid grid-cols-1 lg:grid-cols-3 gap-5">

                            {/* Issue Certificate */}
                            <Link
                                to="/records"
                                className="flex items-center gap-5 rounded-2xl bg-[#F1F4F8] p-6 shadow-[0_3px_8px_rgba(15,23,42,0.12)] transition-all duration-200 hover:-translate-y-1 hover:shadow-[0_8px_20px_rgba(15,23,42,0.16)]"
                            >
                                <div className="flex h-16 w-16 flex-none items-center justify-center rounded-2xl bg-[#DCEAFB] text-[#1E88E5]">
                                    <svg width="34" height="34" viewBox="0 0 24 24" fill="currentColor">
                                        <path d="M12 1 3 5v6c0 5.5 3.8 10.7 9 12 .9-.2 1.7-.6 2.5-1A6 6 0 0 1 21 11.7V5l-9-4z" />
                                        <path
                                            d="M17 14v6M14 17h6"
                                            stroke="#00A3E0"
                                            strokeWidth="2"
                                            strokeLinecap="round"
                                            fill="none"
                                        />
                                    </svg>
                                </div>

                                <div className="min-w-0">
                                    <h3 className="text-xl font-bold text-[#111]">
                                        Issue Certificate
                                    </h3>
                                    <p className="mt-1 text-base text-gray-500">
                                        Upload and hash new diploma
                                    </p>
                                </div>
                            </Link>

                            {/* Verify Hash / QR */}
                            <Link
                                to="/verification"
                                className="flex items-center gap-5 rounded-2xl bg-[#F1F4F8] p-6 shadow-[0_3px_8px_rgba(15,23,42,0.12)] transition-all duration-200 hover:-translate-y-1 hover:shadow-[0_8px_20px_rgba(15,23,42,0.16)]"
                            >
                                <div className="flex h-16 w-16 flex-none items-center justify-center rounded-2xl bg-[#D5E8EA] text-[#00897B]">
                                    <svg
                                        width="34"
                                        height="34"
                                        viewBox="0 0 24 24"
                                        fill="none"
                                        stroke="currentColor"
                                        strokeWidth="2"
                                        strokeLinecap="round"
                                        strokeLinejoin="round"
                                    >
                                        <path d="M3 8V4h4M17 4h4v4M21 16v4h-4M7 20H3v-4" />
                                        <rect x="7" y="7" width="4" height="4" />
                                        <rect x="13" y="7" width="4" height="4" />
                                        <rect x="7" y="13" width="4" height="4" />
                                        <path d="M14 14h1M17 14h0M14 17h0M17 17h0" />
                                    </svg>
                                </div>

                                <div className="min-w-0">
                                    <h3 className="text-xl font-bold text-[#111]">
                                        Verify Hash / QR
                                    </h3>
                                    <p className="mt-1 text-base text-gray-500">
                                        Check authenticity on chain
                                    </p>
                                </div>
                            </Link>

                            {/* Recent Credentials */}
                            <button
                                type="button"
                                onClick={() => {
                                    setDetailsOpen(false);
                                    setRecentOpen(true);
                                }}
                                aria-haspopup="dialog"
                                className="w-full text-left flex items-center gap-5 rounded-2xl bg-[#F1F4F8] p-6 shadow-[0_3px_8px_rgba(15,23,42,0.12)] transition-all duration-200 hover:-translate-y-1 hover:shadow-[0_8px_20px_rgba(15,23,42,0.16)]"
                            >
                                <div className="flex h-16 w-16 flex-none items-center justify-center rounded-2xl bg-[#FBEBDD] text-[#F57C00]">
                                    <svg
                                        width="34"
                                        height="34"
                                        viewBox="0 0 24 24"
                                        fill="none"
                                        stroke="currentColor"
                                        strokeWidth="2.2"
                                        strokeLinecap="round"
                                        strokeLinejoin="round"
                                    >
                                        <path d="M3 12a9 9 0 1 0 3-6.7" />
                                        <polyline points="3 4 3 9 8 9" />
                                        <polyline points="12 7 12 12 15.5 14" />
                                    </svg>
                                </div>

                                <div className="min-w-0">
                                    <h3 className="text-xl font-bold text-[#111]">
                                        Recent Credentials
                                    </h3>
                                    <p className="mt-1 text-base text-gray-500">
                                        Latest: {recentCredential?.student_name || "No recent credential"} &bull; {recentCredential?.degree || ""}
                                    </p>
                                </div>
                            </button>

                        </section>

                        {/* Recent Verified */}
                        <div className="mt-10 mb-5 flex items-center justify-between">
                            <h2 className="text-2xl font-bold text-[#111]">
                                Recent Verified
                            </h2>

                            <button
                                type="button"
                                aria-label="Refresh recent verified"
                                onClick={refresh}
                                className="p-2 rounded-full text-[#222] hover:bg-gray-200/70 transition-colors"
                            >
                                <svg
                                    width="28"
                                    height="28"
                                    viewBox="0 0 24 24"
                                    fill="none"
                                    stroke="currentColor"
                                    strokeWidth="2.4"
                                    strokeLinecap="round"
                                    strokeLinejoin="round"
                                >
                                    <path d="M20 12a8 8 0 1 1-2.6-5.9" />
                                    <polyline points="20 3 20 8 15 8" />
                                </svg>
                            </button>
                        </div>

                        <section className="rounded-2xl bg-[#F1F4F8] shadow-[0_3px_8px_rgba(15,23,42,0.12)] overflow-hidden">
                            {verified.map((v, index) => (
                                <div
                                    key={v.id}
                                    className={`flex items-start gap-5 px-6 py-6 ${index !== verified.length - 1
                                        ? "border-b border-gray-300"
                                        : ""
                                        }`}
                                >
                                    {/* Verified badge */}
                                    <span className="flex-none text-[#2EAA4A]">
                                        <svg width="40" height="40" viewBox="0 0 24 24" fill="currentColor">
                                            <path d="M23 12l-2.4-2.8.3-3.7-3.6-.8-1.9-3.2L12 3 8.6 1.5 6.7 4.7l-3.6.8.3 3.7L1 12l2.4 2.8-.3 3.7 3.6.8 1.9 3.2L12 21l3.4 1.5 1.9-3.2 3.6-.8-.3-3.7L23 12z" />
                                            <polyline
                                                points="7.5 12.2 10.7 15.4 16.5 9.2"
                                                fill="none"
                                                stroke="#fff"
                                                strokeWidth="2.4"
                                                strokeLinecap="round"
                                                strokeLinejoin="round"
                                            />
                                        </svg>
                                    </span>

                                    <div className="min-w-0">
                                        <p className="text-xl text-[#111]">{v.name}</p>
                                        <p className="mt-1 text-base text-gray-600">
                                            {v.program} &bull; {v.university}
                                        </p>
                                        <p className="text-base text-gray-600">
                                            Verified &bull; {v.verifiedAt}
                                        </p>
                                    </div>
                                </div>
                            ))}
                        </section>

                    </div>
                </main>
            </div>

            {/* Recent Issued Credentials Popup */}
            {recentOpen && (
                <div
                    className="fixed inset-0 z-40 grid place-items-center p-4 bg-[#0A192F]/60 backdrop-blur-sm"
                    onClick={() => setRecentOpen(false)}
                >
                    <div
                        role="dialog"
                        aria-modal="true"
                        aria-labelledby="recentTitle"
                        onClick={(e) => e.stopPropagation()}
                        className="w-[min(640px,100%)] max-h-[calc(100vh-36px)] overflow-auto rounded-3xl bg-[#FAFAFD] p-6 md:p-8 shadow-[0_25px_70px_rgba(10,25,47,0.25)]"
                    >
                        {/* Popup header */}
                        <div className="flex items-center justify-between gap-4 pb-5 border-b border-gray-300">
                            <h2
                                id="recentTitle"
                                className="m-0 text-2xl font-extrabold text-[#111]"
                            >
                                Recent Issued Credentials
                            </h2>

                            <div className="flex items-center gap-2">
                                <button
                                    type="button"
                                    aria-label="Refresh recent issued credentials"
                                    onClick={refresh}
                                    className="p-2 rounded-full text-[#222] hover:bg-gray-200/70 transition-colors"
                                >
                                    <svg
                                        width="28"
                                        height="28"
                                        viewBox="0 0 24 24"
                                        fill="none"
                                        stroke="currentColor"
                                        strokeWidth="2.4"
                                        strokeLinecap="round"
                                        strokeLinejoin="round"
                                    >
                                        <path d="M20 12a8 8 0 1 1-2.6-5.9" />
                                        <polyline points="20 3 20 8 15 8" />
                                    </svg>
                                </button>

                                <button
                                    type="button"
                                    aria-label="Close"
                                    onClick={() => setRecentOpen(false)}
                                    className="p-2 rounded-full text-[#222] hover:bg-gray-200/70 transition-colors"
                                >
                                    <svg
                                        width="28"
                                        height="28"
                                        viewBox="0 0 24 24"
                                        fill="none"
                                        stroke="currentColor"
                                        strokeWidth="2.4"
                                        strokeLinecap="round"
                                        strokeLinejoin="round"
                                    >
                                        <path d="M6 6l12 12M18 6L6 18" />
                                    </svg>
                                </button>
                            </div>
                        </div>

                        {/* Credential card */}
                        <div className="mt-5 rounded-2xl bg-[#F1F4F8] shadow-[0_3px_8px_rgba(15,23,42,0.12)] overflow-hidden">
                            <div className="w-full flex items-center gap-4 px-6 py-5">
                                <button
                                    type="button"
                                    onClick={() => setDetailsOpen((o) => !o)}
                                    aria-expanded={detailsOpen}
                                    className="min-w-0 flex-1 flex items-center gap-4 text-left"
                                >
                                    <span className="flex-none text-[#1E88E5]">
                                        <svg width="34" height="34" viewBox="0 0 24 24" fill="currentColor">
                                            <path d="M12 3 1 9l11 6 9-4.9V17h2V9L12 3z" />
                                            <path d="M5 13.2v3.5c0 1.3 3.1 3.3 7 3.3s7-2 7-3.3v-3.5l-7 3.8-7-3.8z" />
                                        </svg>
                                    </span>

                                    <span className="min-w-0 flex-1">
                                        <span className="block truncate text-xl text-[#111]">
                                            {recentCredential?.student_name || "No recent credential"}
                                        </span>
                                        <span className="block truncate text-lg text-[#111]">
                                            {recentCredential?.degree || ""} &bull; ID: {recentCredential?.student_id || ""}
                                        </span>
                                    </span>
                                </button>

                                <button
                                    type="button"
                                    aria-label="Show QR code"
                                    onClick={() => setQrOpen(true)}
                                    className="flex-none p-1.5 rounded-lg text-[#00A88F] hover:bg-white transition-colors"
                                >
                                    <svg
                                        width="34"
                                        height="34"
                                        viewBox="0 0 24 24"
                                        fill="none"
                                        stroke="currentColor"
                                        strokeWidth="2.2"
                                        strokeLinecap="round"
                                        strokeLinejoin="round"
                                    >
                                        <rect x="3" y="3" width="7" height="7" rx="1" />
                                        <rect x="14" y="3" width="7" height="7" rx="1" />
                                        <rect x="3" y="14" width="7" height="7" rx="1" />
                                        <path d="M14 14h2.5v2.5H14zM18.5 14H21M14 19h2M18.5 18.5H21v2.5h-2.5z" />
                                    </svg>
                                </button>

                                <button
                                    type="button"
                                    aria-label={detailsOpen ? "Collapse details" : "Expand details"}
                                    onClick={() => setDetailsOpen((o) => !o)}
                                    className="flex-none p-1.5 rounded-lg text-[#0A3D75] hover:bg-white transition-colors"
                                >
                                    <svg
                                        width="26"
                                        height="26"
                                        viewBox="0 0 24 24"
                                        fill="none"
                                        stroke="currentColor"
                                        strokeWidth="2.6"
                                        strokeLinecap="round"
                                        strokeLinejoin="round"
                                        className={`transition-transform duration-200 ${detailsOpen ? "rotate-180" : ""}`}
                                    >
                                        <path d="M6 9l6 6 6-6" />
                                    </svg>
                                </button>
                            </div>

                            {detailsOpen && (
                                <div className="px-6 pb-6">
                                    <dl className="grid gap-3 py-2">
                                        {recentRows.map(([label, value]) => (
                                            <div
                                                key={label}
                                                className="grid grid-cols-[150px_1fr] sm:grid-cols-[190px_1fr] gap-4"
                                            >
                                                <dt className="font-extrabold text-lg text-[#111]">
                                                    {label}
                                                </dt>
                                                <dd className="m-0 text-lg text-[#111] break-all">
                                                    {value}
                                                </dd>
                                            </div>
                                        ))}
                                    </dl>

                                    {actionMessage && (
                                        <p role="status" className="mt-4 rounded-lg bg-blue-50 p-3 text-sm font-semibold text-blue-800">
                                            {actionMessage}
                                        </p>
                                    )}

                                    <div className="mt-4 grid justify-center gap-1">
                                                <button type="button" onClick={openRecentVerification} disabled={!recentCredential} className={`${popupActionClass} disabled:cursor-not-allowed disabled:opacity-50`}>
                                            <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                                                <path d="M12 2.5l2.4 1.7 2.9-.1 1 2.7 2.3 1.8-.9 2.8.9 2.8-2.3 1.8-1 2.7-2.9-.1L12 21.5l-2.4-1.7-2.9.1-1-2.7-2.3-1.8.9-2.8-.9-2.8 2.3-1.8 1-2.7 2.9.1L12 2.5z" />
                                                <path d="M8.5 12l2.5 2.5 4.5-5" />
                                            </svg>
                                            Verify this record
                                        </button>

                                        <button type="button" onClick={openRecentDiploma} disabled={!recentCredential} className={`${popupActionClass} disabled:cursor-not-allowed disabled:opacity-50`}>
                                            <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                                                <circle cx="12" cy="9" r="6" />
                                                <path d="M12 6.5l.8 1.7 1.8.2-1.3 1.2.4 1.8-1.7-.9-1.7.9.4-1.8-1.3-1.2 1.8-.2z" />
                                                <path d="M8.5 14L7 21l5-2.5 5 2.5-1.5-7" />
                                            </svg>
                                            View This Diploma
                                        </button>

                                        <button type="button" onClick={() => {
                                            setRecentOpen(false);
                                            navigate("/records");
                                        }} className={popupActionClass}>
                                            <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                                                <circle cx="12" cy="12" r="9" />
                                                <path d="M12 8v8M8 12h8" />
                                            </svg>
                                            Add another degree
                                        </button>

                                        <button type="button" onClick={() => void requestRecentDeletion()} disabled={!recentCredential} className={`${popupActionClass} disabled:cursor-not-allowed disabled:opacity-50`}>
                                            <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                                                <path d="M4 7h16" />
                                                <path d="M9 7V4h6v3" />
                                                <path d="M6 7l1 13h10l1-13" />
                                            </svg>
                                            Request deletion
                                        </button>
                                    </div>
                                </div>
                            )}
                        </div>
                    </div>
                </div>
            )}

            {/* QR Code Popup */}
            {qrOpen && (
                <div
                    className="fixed inset-0 z-50 grid place-items-center p-4 bg-black/50"
                    onClick={() => setQrOpen(false)}
                >
                    <div
                        role="dialog"
                        aria-modal="true"
                        aria-labelledby="qrTitle"
                        onClick={(e) => e.stopPropagation()}
                        className="w-[min(420px,100%)] max-h-[calc(100vh-36px)] overflow-auto rounded-[28px] bg-[#ECEEF4] p-7 shadow-[0_25px_70px_rgba(10,25,47,0.3)]"
                    >
                        <h2
                            id="qrTitle"
                            className="m-0 text-3xl font-normal leading-snug text-[#111]"
                        >
                            QR Code: {recentCredential.name}
                        </h2>

                        <p className="mt-6 mb-5 text-center text-base text-gray-500">
                            Scan this QR code to verify this credential.
                        </p>

                        <div
                            ref={qrWrapRef}
                            className="mx-auto w-fit rounded-3xl bg-white p-6"
                        >
                            <QRCodeCanvas
                                value={qrPayload}
                                size={240}
                                level="M"
                                marginSize={0}
                            />
                        </div>

                        <p className="mt-6 mb-0 text-center text-base text-gray-500 break-all">
                            Code: {qrPayload}
                        </p>

                        <div className="mt-10 flex flex-col items-end gap-4">
                            <button
                                type="button"
                                onClick={() => setQrOpen(false)}
                                className="px-3 py-2 text-lg font-bold text-[#0A3D75] hover:bg-white/70 rounded-lg transition-colors"
                            >
                                Close
                            </button>

                            <button
                                type="button"
                                onClick={saveQr}
                                className="inline-flex items-center gap-3 min-h-14 px-7 rounded-full bg-[#F6F7FB] text-lg font-bold text-[#0A3D75] shadow-[0_3px_8px_rgba(15,23,42,0.18)] hover:bg-white transition-colors"
                            >
                                <svg
                                    width="24"
                                    height="24"
                                    viewBox="0 0 24 24"
                                    fill="none"
                                    stroke="currentColor"
                                    strokeWidth="2.6"
                                    strokeLinecap="round"
                                    strokeLinejoin="round"
                                >
                                    <path d="M12 4v11M7 11l5 5 5-5M5 20h14" />
                                </svg>
                                Save to Gallery
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}