import { useEffect, useMemo, useState } from "react";
import Sidebar from "../../components/Sidebar";
import CertiTrustLoadingIndicator from "../../components/CertiTrustLoadingIndicator";
import { useNavigate } from "react-router-dom";
import { useCertificates } from "../../hooks/useCertificates";
import { useCertificateBatch } from "../../hooks/useCertificateBatch";
import { getSessionUser, isSuperAdminSession } from "../../services/authService";
import { listUniversities, type UniversityRecord } from "../../services/adminApi";
import SuperAdminSideBar from "../../components/SuperAdminSideBar";
import {
    requestCertificateDeletion,
    type CertificateRecord,
} from "../../services/certitrustApi";

type Certificate = {
    id: string;
    studentId: string;
    fullName: string;
    institutionalEmail: string;
    degreeProgram: string;
    degreeNumber: string;
    level: string;
    certificateCode: string;
    fileName: string;
    diplomaUrl?: string;
    issuedAt: string;
    publishedAt: string;
    status: string;
    blockchainStatus: string;
    blockchainTxHash?: string;
};

const FILTERS = ["All records", "Masteral", "Doctoral", "Bachelor's", "1st degree", "BSIT"];

const detectLevel = (program: string) => {
    if (/master/i.test(program)) return "Masteral";
    if (/doctor|ph\.?d/i.test(program)) return "Doctoral";
    return "Bachelor's";
};

const mapCertificate = (record: CertificateRecord): Certificate => ({
    id: String(record.id),
    studentId: record.student_id,
    fullName: record.student_name,
    institutionalEmail: record.student_email,
    degreeProgram: record.degree,
    degreeNumber: String(record.degree_number ?? 1),
    level: detectLevel(record.degree),
    certificateCode: record.certificate_code,
    fileName: record.diploma_file_name || "No file attached",
    diplomaUrl: record.diploma_url || undefined,
    issuedAt: record.issue_date,
    publishedAt: record.created_at ?? record.issue_date,
    status: record.status,
    blockchainStatus: record.blockchain_status ?? "not_configured",
    blockchainTxHash: record.blockchain_tx_hash ?? undefined,
});

const certTags = (c: Certificate) => [
    c.level,
    `${c.degreeNumber} degree`,
    c.degreeProgram,
];

const SearchIcon = () => (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="11" cy="11" r="7" />
        <path d="M20 20l-3.5-3.5" />
    </svg>
);

const CapIcon = () => (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 4L2 9l10 5 10-5-10-5z" />
        <path d="M6 11.5V16c0 1.2 2.7 3 6 3s6-1.8 6-3v-4.5" />
    </svg>
);

const ChevronIcon = ({ open }: { open: boolean }) => (
    <svg
        width="20"
        height="20"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        className={`transition-transform duration-200 ${open ? "rotate-180" : ""}`}
    >
        <path d="M6 9l6 6 6-6" />
    </svg>
);

const VerifyIcon = () => (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 2.5l2.4 1.7 2.9-.1 1 2.7 2.3 1.8-.9 2.8.9 2.8-2.3 1.8-1 2.7-2.9-.1L12 21.5l-2.4-1.7-2.9.1-1-2.7-2.3-1.8.9-2.8-.9-2.8 2.3-1.8 1-2.7 2.9.1L12 2.5z" />
        <path d="M8.5 12l2.5 2.5 4.5-5" />
    </svg>
);

const DiplomaIcon = () => (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="12" cy="9" r="6" />
        <path d="M12 6.5l.8 1.7 1.8.2-1.3 1.2.4 1.8-1.7-.9-1.7.9.4-1.8-1.3-1.2 1.8-.2z" />
        <path d="M8.5 14L7 21l5-2.5 5 2.5-1.5-7" />
    </svg>
);

const PlusCircleIcon = () => (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="12" cy="12" r="9" />
        <path d="M12 8v8M8 12h8" />
    </svg>
);

const TrashIcon = () => (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <path d="M4 7h16" />
        <path d="M9 7V4h6v3" />
        <path d="M6 7l1 13h10l1-13" />
    </svg>
);

export default function Certificates() {
    const currentUser = getSessionUser();
    const isSuperAdmin = isSuperAdminSession(currentUser);
    const [studentId, setStudentId] = useState<string>("");
    const [fullName, setFullName] = useState<string>("");
    const [institutionalEmail, setInstitutionalEmail] = useState<string>("");
    const [degreeProgram, setDegreeProgram] = useState<string>("");
    const [fileName, setFileName] = useState<string>("");
    const [diplomaUrl, setDiplomaUrl] = useState<string>("");
    const [selectedFile, setSelectedFile] = useState<File | null>(null);
    const [universities, setUniversities] = useState<UniversityRecord[]>([]);
    const [universityCode, setUniversityCode] = useState(currentUser?.university_code ?? "");
    const [universityError, setUniversityError] = useState("");
    const { certificates: apiCertificates, loading, error, refresh } = useCertificates();
    const { issueBatch, isIssuing } = useCertificateBatch();
    const certificates = useMemo(() => apiCertificates.map(mapCertificate), [apiCertificates]);
    const [activeCertificate, setActiveCertificate] = useState<Certificate | null>(null);
    const [deleteTarget, setDeleteTarget] = useState<Certificate | null>(null);
    const [deleteReason, setDeleteReason] = useState<string>("");

    const [search, setSearch] = useState<string>("");
    const [activeFilter, setActiveFilter] = useState<string>("All records");
    const [activeYear, setActiveYear] = useState<string>("All years");
    const [openId, setOpenId] = useState<string | null>(null);

    const navigate = useNavigate();

    useEffect(() => {
        if (!isSuperAdmin) return;
        let active = true;
        listUniversities().then((items) => {
            if (!active) return;
            setUniversities(items);
            setUniversityCode((current) =>
                items.some((university) => university.code === current)
                    ? current
                    : items[0]?.code ?? ""
            );
            setUniversityError(items.length ? "" : "No registered universities are available.");
        }).catch((requestError) => {
            if (!active) return;
            const message = (requestError as { response?: { data?: { message?: string } } })
                .response?.data?.message;
            setUniversityError(message || "Unable to load universities.");
        });
        return () => {
            active = false;
        };
    }, [isSuperAdmin]);

    const showToast = (message: string) => {
        const toast = document.getElementById("toast");
        if (!toast) return;
        toast.textContent = message;
        toast.classList.add("show");
        window.clearTimeout((showToast as any)._t);
        (showToast as any)._t = window.setTimeout(() => {
            toast.classList.remove("show");
        }, 2600);
    };

    const resetForm = () => {
        setStudentId("");
        setFullName("");
        setInstitutionalEmail("");
        setDegreeProgram("");
        setFileName("");
        setSelectedFile(null);
        if (diplomaUrl.startsWith("blob:")) URL.revokeObjectURL(diplomaUrl);
        setDiplomaUrl("");
    };

    const openIssueModal = () => {
        document.getElementById("issueModal")?.classList.add("show");
    };

    const handleIssueCertificate = async () => {
        if (
            !studentId ||
            !fullName ||
            !institutionalEmail ||
            !degreeProgram ||
            (isSuperAdmin && !universityCode)
        ) {
            showToast("Please fill in all required fields.");
            return;
        }

        try {
            const result = await issueBatch([{
                student_id: studentId,
                student_name: fullName,
                student_email: institutionalEmail,
                degree: degreeProgram,
                issue_date: new Date().toISOString().slice(0, 10),
                diploma_file: selectedFile ?? undefined,
                university_code: isSuperAdmin ? universityCode : undefined,
            }]);
            await refresh();
            resetForm();
            document.getElementById("issueModal")?.classList.remove("show");
            const blockchainStatus = result.data?.[0]?.blockchain_status;
            showToast(blockchainStatus === "submitted"
                ? "Certificate issued and submitted to Ethereum Sepolia."
                : "Certificate issued; blockchain anchoring is not configured or failed.");
        } catch (requestError) {
            const message = (requestError as { response?: { data?: { message?: string } } })
                .response?.data?.message;
            showToast(message || (requestError instanceof Error ? requestError.message : "Certificate issuance failed."));
        }
    };

    const openViewer = (certificate: Certificate) => {
        setActiveCertificate(certificate);
        document.getElementById("certificateViewerModal")?.classList.add("show");
    };

    const handleRequestDeletion = (cert: Certificate) => {
        setDeleteReason("");
        setDeleteTarget(cert);
    };

    const closeDeletion = () => {
        setDeleteTarget(null);
        setDeleteReason("");
    };

    const handleSendDeletionRequest = async () => {
        if (!deleteReason.trim()) {
            showToast("Please explain why this credential should be deleted.");
            return;
        }
        try {
            await requestCertificateDeletion(Number(deleteTarget.id), deleteReason.trim());
            closeDeletion();
            showToast("Deletion request sent for review.");
        } catch (requestError) {
            const message = (requestError as { response?: { data?: { message?: string } } })
                .response?.data?.message;
            showToast(message || "Unable to send the deletion request.");
        }
    };

    useEffect(() => {
        if (!deleteTarget) return;
        const onKey = (e: KeyboardEvent) => {
            if (e.key === "Escape") closeDeletion();
        };
        window.addEventListener("keydown", onKey);
        return () => window.removeEventListener("keydown", onKey);
    }, [deleteTarget]);

    const years = useMemo(() => {
        const set = new Set(certificates.map((c) => c.issuedAt.slice(0, 4)));
        return Array.from(set).sort((a, b) => Number(b) - Number(a));
    }, [certificates]);

    const filtered = useMemo(() => {
        const q = search.trim().toLowerCase();
        return certificates.filter((c) => {
            if (activeFilter !== "All records" && !certTags(c).includes(activeFilter)) return false;
            if (activeYear !== "All years" && c.issuedAt.slice(0, 4) !== activeYear) return false;
            if (!q) return true;
            return [
                c.fullName,
                c.studentId,
                c.institutionalEmail,
                c.degreeProgram,
                c.certificateCode,
                c.level,
            ].some((v) => v.toLowerCase().includes(q));
        });
    }, [certificates, search, activeFilter, activeYear]);

    const grouped = useMemo(() => {
        const map = new Map<string, Certificate[]>();
        filtered.forEach((c) => {
            const y = c.issuedAt.slice(0, 4);
            map.set(y, [...(map.get(y) ?? []), c]);
        });
        return Array.from(map.entries()).sort((a, b) => Number(b[0]) - Number(a[0]));
    }, [filtered]);

    const chipClass = (active: boolean) =>
        `inline-flex items-center gap-2 min-h-11 px-5 rounded-xl border text-sm font-semibold transition ${active
            ? "bg-[#D9E6FA] border-[#D9E6FA] text-[#0A192F]"
            : "bg-white border-slate-300 text-[#0A192F] hover:bg-slate-50"
        }`;

    const Check = () => (
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
            <path d="M5 12.5l4.5 4.5L19 7.5" />
        </svg>
    );

    const actionClass =
        "inline-flex items-center justify-center gap-2.5 min-h-11 px-4 rounded-xl text-[#0A4A8F] font-bold text-sm hover:bg-white transition";

    return (
        <div className="min-h-screen bg-[#F6F8FC]">
            <div className="min-h-screen grid grid-cols-1 md:grid-cols-[286px_1fr]">

                {/* Sidebar */}
                {isSuperAdmin ? <SuperAdminSideBar /> : <Sidebar />}

                {/* Main Content */}
                <main className="min-w-0 overflow-y-auto h-screen p-4 sm:p-5 md:p-8">

                    {/* Header */}
                    <header className="mb-7 p-5 md:p-6 border border-slate-200 rounded-2xl bg-white shadow-[0_12px_35px_rgba(15,23,42,0.06)] flex flex-col lg:flex-row items-start lg:items-center justify-between gap-5">

                        <div className="flex items-center gap-4">

                            <button
                                type="button"
                                data-toggle-sidebar
                                aria-label="Open navigation"
                                className="md:hidden w-10 h-10 flex items-center justify-center rounded-xl border border-slate-200 bg-slate-50 text-[#0A192F] font-bold"
                            >
                                ☰
                            </button>

                            <div>
                                <div className="flex items-center gap-2 mb-1">
                                    <span className="w-2 h-2 rounded-full bg-[#2563EB]" />

                                    <p className="m-0 text-[#2563EB] text-xs font-extrabold uppercase tracking-wider">
                                        Issued credentials
                                    </p>
                                </div>

                                <h1 className="mt-1 text-2xl md:text-3xl font-extrabold text-[#0A192F]">
                                    Certificates
                                </h1>

                                <p className="mt-1 text-sm text-slate-500">
                                    Manage and issue academic certificates.
                                </p>
                            </div>
                        </div>

                        {/* Issue Certificate Button */}
                        <button
                            type="button"
                            onClick={openIssueModal}
                            className="w-full lg:w-auto inline-flex items-center justify-center gap-2 min-h-11 px-5 rounded-xl bg-[#0A192F] text-white font-bold shadow-[0_10px_25px_rgba(10,25,47,0.18)] hover:-translate-y-0.5 transition"
                        >
                            <span className="text-lg">+</span>
                            Issue Certificate
                        </button>

                    </header>

                    {/* Search */}
                    <div className="relative mb-8">
                        <span className="absolute left-5 top-1/2 -translate-y-1/2 text-slate-600 pointer-events-none">
                            <SearchIcon />
                        </span>
                        <input
                            type="text"
                            value={search}
                            onChange={(e) => setSearch(e.target.value)}
                            placeholder="Search credentials"
                            aria-label="Search credentials"
                            className="w-full min-h-14 border border-slate-400 rounded-xl bg-white pl-14 pr-4 text-base text-[#0A192F] outline-none focus:border-[#1D4ED8] focus:ring-4 focus:ring-[#1D4ED8]/10 transition"
                        />
                    </div>

                    {/* Filter certificate records */}
                    <section className="mb-8">
                        <h2 className="mb-4 text-lg font-extrabold text-[#0A192F]">
                            Filter certificate records
                        </h2>
                        <div className="flex flex-wrap gap-3">
                            {FILTERS.map((f) => (
                                <button
                                    key={f}
                                    type="button"
                                    onClick={() => setActiveFilter(f)}
                                    aria-pressed={activeFilter === f}
                                    className={chipClass(activeFilter === f)}
                                >
                                    {activeFilter === f && <Check />}
                                    {f}
                                </button>
                            ))}
                        </div>
                    </section>

                    {/* Record batch year */}
                    <section className="mb-8">
                        <h2 className="mb-4 text-lg font-extrabold text-[#0A192F]">
                            Record batch year
                        </h2>
                        <div className="flex flex-wrap gap-3">
                            {["All years", ...years].map((y) => (
                                <button
                                    key={y}
                                    type="button"
                                    onClick={() => setActiveYear(y)}
                                    aria-pressed={activeYear === y}
                                    className={chipClass(activeYear === y)}
                                >
                                    {activeYear === y && <Check />}
                                    {y}
                                </button>
                            ))}
                        </div>
                    </section>

                    {/* Certificate Area */}
                    {loading ? (
                        <CertiTrustLoadingIndicator size={32} message="Loading certificates..." className="w-full py-12 text-sm font-semibold text-slate-500" />
                    ) : error ? (
                        <p role="alert" className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</p>
                    ) : certificates.length === 0 ? (
                        <section className="min-h-[520px] flex items-center justify-center bg-white border border-slate-200 rounded-2xl shadow-[0_12px_35px_rgba(15,23,42,0.05)]">

                            <div className="text-center px-6 py-12 max-w-md">

                                <div className="w-20 h-20 mx-auto mb-5 rounded-2xl bg-[#EAF2FF] text-[#1D4ED8] flex items-center justify-center">

                                    <svg
                                        width="38"
                                        height="38"
                                        viewBox="0 0 24 24"
                                        fill="none"
                                        stroke="currentColor"
                                        strokeWidth="1.7"
                                        strokeLinecap="round"
                                        strokeLinejoin="round"
                                    >
                                        <rect x="3" y="4" width="18" height="16" rx="2" />
                                        <path d="M8 9h8" />
                                        <path d="M8 13h5" />
                                        <path d="M8 17h3" />
                                    </svg>

                                </div>

                                <h2 className="text-xl md:text-2xl font-extrabold text-[#0A192F]">
                                    No Certificates Yet
                                </h2>

                                <p className="mt-2 text-sm md:text-base text-slate-500 leading-relaxed">
                                    Certificates that you issue will appear here.
                                    Start by creating a new academic certificate.
                                </p>

                                <button
                                    type="button"
                                    onClick={openIssueModal}
                                    className="mt-6 inline-flex items-center justify-center gap-2 min-h-11 px-5 rounded-xl bg-[#0A192F] text-white font-bold hover:bg-[#122744] transition"
                                >
                                    <span className="text-lg">+</span>
                                    Issue Your First Certificate
                                </button>

                            </div>

                        </section>
                    ) : (
                        <section className="grid gap-8">
                            {grouped.map(([year, items]) => (
                                <div key={year}>
                                    <h2 className="mb-4 text-2xl font-extrabold text-[#0A192F]">
                                        {year}
                                    </h2>

                                    <div className="grid gap-4">
                                        {items.map((cert) => {
                                            const isOpen = openId === cert.id;
                                            const rows: [string, string][] = [
                                                ["Student name", cert.fullName],
                                                ["Student ID", cert.studentId],
                                                ["Course / program", cert.degreeProgram],
                                                ["Degree number", cert.degreeNumber],
                                                ["Gmail", cert.institutionalEmail],
                                                ["Certificate code", cert.certificateCode],
                                                ["Issue date", cert.issuedAt],
                                                ["Published", cert.publishedAt],
                                                ["Status", cert.status],
                                                ["Blockchain status", cert.blockchainStatus],
                                            ];

                                            return (
                                                <div
                                                    key={cert.id}
                                                    className="bg-[#F1F3F9] rounded-2xl shadow-[0_4px_14px_rgba(15,23,42,0.12)] overflow-hidden"
                                                >
                                                    <button
                                                        type="button"
                                                        onClick={() => setOpenId(isOpen ? null : cert.id)}
                                                        aria-expanded={isOpen}
                                                        className="w-full flex items-center gap-4 px-6 py-5 text-left text-[#0A192F]"
                                                    >
                                                        <CapIcon />
                                                        <span className="flex-1 min-w-0 truncate text-lg font-extrabold">
                                                            {cert.fullName}
                                                        </span>
                                                        <ChevronIcon open={isOpen} />
                                                    </button>

                                                    {isOpen && (
                                                        <div className="px-6 pb-6 pt-2">
                                                            <dl className="grid gap-4 py-4">
                                                                {rows.map(([label, value]) => (
                                                                    <div
                                                                        key={label}
                                                                        className="grid grid-cols-1 sm:grid-cols-[200px_1fr] gap-1 sm:gap-6"
                                                                    >
                                                                        <dt className="font-extrabold text-[#0A192F]">
                                                                            {label}
                                                                        </dt>
                                                                        <dd className="m-0 text-[#172033] break-all">
                                                                            {value}
                                                                        </dd>
                                                                    </div>
                                                                ))}
                                                            </dl>
                                                            {cert.blockchainTxHash && (
                                                                <a
                                                                    href={`https://amoy.polygonscan.com/tx/${cert.blockchainTxHash}`}
                                                                    target="_blank"
                                                                    rel="noreferrer"
                                                                    className="break-all text-sm font-semibold text-blue-700 underline"
                                                                >
                                                                    View Ethereum Sepolia transaction
                                                                </a>
                                                            )}

                                                            <div className="mt-2 pt-4 border-t border-slate-200 flex flex-wrap items-center justify-center gap-x-4 gap-y-2">
                                                                <button
                                                                    type="button"
                                                                    onClick={() => navigate('/verification')}
                                                                    className={actionClass}
                                                                >
                                                                    <VerifyIcon />
                                                                    Verify this record
                                                                </button>
                                                                <button
                                                                    type="button"
                                                                    onClick={() => openViewer(cert)}
                                                                    className={actionClass}
                                                                >
                                                                    <DiplomaIcon />
                                                                    View This Diploma
                                                                </button>
                                                                <button
                                                                    type="button"
                                                                    onClick={() => navigate('/records')}
                                                                    className={actionClass}
                                                                >
                                                                    <PlusCircleIcon />
                                                                    Add another degree
                                                                </button>
                                                                <button
                                                                    type="button"
                                                                    onClick={() => handleRequestDeletion(cert)}
                                                                    className={actionClass}
                                                                >
                                                                    <TrashIcon />
                                                                    Request deletion
                                                                </button>
                                                            </div>
                                                        </div>
                                                    )}
                                                </div>
                                            );
                                        })}
                                    </div>
                                </div>
                            ))}

                            {grouped.length === 0 && (
                                <p className="text-sm text-slate-500">
                                    No certificates match your search or filters.
                                </p>
                            )}
                        </section>
                    )}

                </main>
            </div>

            {/* Issue Certificate Modal */}
            <div
                id="issueModal"
                aria-hidden="true"
                className="fixed inset-0 z-40 hidden place-items-center p-4 bg-[#0A192F]/60 backdrop-blur-sm [&.show]:grid"
            >

                <div
                    role="dialog"
                    aria-modal="true"
                    aria-labelledby="issueTitle"
                    className="relative w-[min(760px,100%)] max-h-[calc(100vh-36px)] overflow-auto grid gap-5 p-6 md:p-7 bg-white rounded-2xl shadow-[0_25px_70px_rgba(10,25,47,0.2)]"
                >

                    {/* Close Button */}
                    <button
                        type="button"
                        onClick={() => {
                            document
                                .getElementById("issueModal")
                                ?.classList.remove("show");
                        }}
                        aria-label="Close"
                        className="absolute top-4 right-4 w-9 h-9 rounded-full border border-slate-200 bg-white text-slate-500 font-bold hover:bg-slate-50 transition"
                    >
                        ×
                    </button>

                    {/* Modal Header */}
                    <div className="pr-10">

                        <span className="text-[#2563EB] text-xs font-extrabold uppercase tracking-wider">
                            New credential
                        </span>

                        <h2
                            id="issueTitle"
                            className="mt-1 text-2xl font-extrabold text-[#0A192F]"
                        >
                            Issue Certificate
                        </h2>

                        <p className="mt-1 text-sm text-slate-500">
                            Enter the academic credential information.
                        </p>

                    </div>

                    {/* Certificate Form */}
                    <div className="grid grid-cols-1 gap-5">

                        {isSuperAdmin && (
                            <div className="grid gap-2">
                                <label htmlFor="issueUniversity" className="text-[#172033] font-bold text-sm">
                                    University/School
                                </label>
                                <select
                                    id="issueUniversity"
                                    value={universityCode}
                                    onChange={(event) => setUniversityCode(event.target.value)}
                                    disabled={universities.length === 0}
                                    className="w-full min-h-12 border border-slate-200 rounded-xl bg-white px-4 py-3 outline-none focus:border-[#1D4ED8] focus:ring-4 focus:ring-[#1D4ED8]/10 transition disabled:bg-slate-100"
                                >
                                    <option value="">Select a university</option>
                                    {universities.map((university) => (
                                        <option key={university.code} value={university.code}>
                                            {university.university_name} ({university.code})
                                        </option>
                                    ))}
                                </select>
                                {universityError && (
                                    <p role="alert" className="text-sm text-red-700">{universityError}</p>
                                )}
                            </div>
                        )}

                        {/* Student ID */}
                        <div className="grid gap-2">
                            <label className="text-[#172033] font-bold text-sm">
                                Student ID
                            </label>
                            <input
                                type="text"
                                value={studentId}
                                onChange={(e) => setStudentId(e.target.value)}
                                placeholder="Student ID"
                                className="w-full min-h-12 border border-slate-200 rounded-xl bg-white px-4 py-3 outline-none focus:border-[#1D4ED8] focus:ring-4 focus:ring-[#1D4ED8]/10 transition"
                            />
                        </div>

                        {/* Student Fullname */}
                        <div className="grid gap-2">
                            <label className="text-[#172033] font-bold text-sm">
                                Student Fullname
                            </label>
                            <input
                                type="text"
                                value={fullName}
                                onChange={(e) => setFullName(e.target.value)}
                                placeholder="Student Fullname"
                                className="w-full min-h-12 border border-slate-200 rounded-xl bg-white px-4 py-3 outline-none focus:border-[#1D4ED8] focus:ring-4 focus:ring-[#1D4ED8]/10 transition"
                            />
                        </div>

                        {/* Student Google/Institutional Email */}
                        <div className="grid gap-2">
                            <label className="text-[#172033] font-bold text-sm">
                                Student Google/Institutional Email
                            </label>
                            <input
                                type="email"
                                value={institutionalEmail}
                                onChange={(e) => setInstitutionalEmail(e.target.value)}
                                placeholder="Student Google/Institutional Email"
                                className="w-full min-h-12 border border-slate-200 rounded-xl bg-white px-4 py-3 outline-none focus:border-[#1D4ED8] focus:ring-4 focus:ring-[#1D4ED8]/10 transition"
                            />
                        </div>

                        {/* Degree / Program Title */}
                        <div className="grid gap-2">
                            <label className="text-[#172033] font-bold text-sm">
                                Degree / Program Title
                            </label>
                            <input
                                type="text"
                                value={degreeProgram}
                                onChange={(e) => setDegreeProgram(e.target.value)}
                                placeholder="Degree / Program Title"
                                className="w-full min-h-12 border border-slate-200 rounded-xl bg-white px-4 py-3 outline-none focus:border-[#1D4ED8] focus:ring-4 focus:ring-[#1D4ED8]/10 transition"
                            />
                        </div>

                        {/* Select Diploma File */}
                        <div className="grid gap-2">
                            <label className="text-[#172033] font-bold text-sm">
                                Select Diploma File (PDF/image)
                            </label>
                            <input
                                type="file"
                                accept=".pdf,.jpg,.jpeg,.png"
                                onChange={(e) => {
                                    const file = e.target.files?.[0];
                                    if (file) {
                                        if (diplomaUrl.startsWith("blob:")) URL.revokeObjectURL(diplomaUrl);
                                        setSelectedFile(file);
                                        setFileName(file.name);
                                        setDiplomaUrl(URL.createObjectURL(file));
                                    }
                                }}
                                className="w-full min-h-12 border border-slate-200 rounded-xl bg-white px-4 py-3 cursor-pointer"
                            />

                            {fileName && (
                                <div className="p-3 rounded-xl bg-[#EAF2FF] border border-[#BFDBFE]">
                                    <p className="text-xs font-bold text-slate-500">
                                        Selected Diploma File
                                    </p>
                                    <p className="mt-1 text-sm font-bold text-[#0A192F] break-all">
                                        {fileName}
                                    </p>
                                </div>
                            )}
                        </div>

                    </div>

                    {/* Issue Certificate Button */}
                    <button
                        type="button"
                        id="saveCertificate"
                        onClick={handleIssueCertificate}
                        disabled={isIssuing || (isSuperAdmin && (!universityCode || Boolean(universityError)))}
                        className="min-h-11 px-5 rounded-xl bg-[#0A192F] text-white font-bold shadow-[0_10px_20px_rgba(10,25,47,0.16)] hover:-translate-y-0.5 transition disabled:cursor-wait disabled:opacity-60"
                    >
                        {isIssuing ? "Issuing..." : "Issue Certificate"}
                    </button>

                </div>
            </div>

            {/* Digital Diploma Copy Modal */}
            <div
                id="certificateViewerModal"
                aria-hidden="true"
                className="fixed inset-0 z-40 hidden place-items-center p-4 bg-black/50 [&.show]:grid"
                onClick={(e) => {
                    if (e.target === e.currentTarget) {
                        e.currentTarget.classList.remove("show");
                    }
                }}
            >

                <div
                    role="dialog"
                    aria-modal="true"
                    aria-labelledby="diplomaTitle"
                    className="w-[min(720px,100%)] max-h-[calc(100vh-36px)] overflow-auto rounded-[28px] bg-[#E8EAF1] shadow-[0_25px_70px_rgba(10,25,47,0.3)]"
                >

                    {/* Header */}
                    <div className="flex items-center justify-between gap-4 px-7 pt-6 pb-2">
                        <h2
                            id="diplomaTitle"
                            className="m-0 text-xl md:text-2xl font-normal text-[#111]"
                        >
                            Digital Diploma Copy
                        </h2>

                        <div className="flex items-center gap-2">
                            <a
                                href={activeCertificate?.diplomaUrl}
                                download={activeCertificate?.fileName}
                                aria-label="Download diploma"
                                aria-disabled={!activeCertificate?.diplomaUrl}
                                className={`p-2 rounded-full text-[#222] hover:bg-white/70 transition-colors ${activeCertificate?.diplomaUrl ? "" : "pointer-events-none opacity-40"
                                    }`}
                            >
                                <svg
                                    width="28"
                                    height="28"
                                    viewBox="0 0 24 24"
                                    fill="none"
                                    stroke="currentColor"
                                    strokeWidth="2.6"
                                    strokeLinecap="round"
                                    strokeLinejoin="round"
                                >
                                    <path d="M12 3v12M7 10.5l5 5 5-5M5 21h14" />
                                </svg>
                            </a>

                            <button
                                type="button"
                                aria-label="Close"
                                onClick={() => {
                                    document
                                        .getElementById("certificateViewerModal")
                                        ?.classList.remove("show");
                                }}
                                className="p-2 rounded-full text-[#222] hover:bg-white/70 transition-colors"
                            >
                                <svg
                                    width="28"
                                    height="28"
                                    viewBox="0 0 24 24"
                                    fill="none"
                                    stroke="currentColor"
                                    strokeWidth="2.6"
                                    strokeLinecap="round"
                                    strokeLinejoin="round"
                                >
                                    <path d="M6 6l12 12M18 6L6 18" />
                                </svg>
                            </button>
                        </div>
                    </div>

                    {/* Diploma */}
                    <div className="min-h-[55vh] flex items-center justify-center">
                        {activeCertificate?.diplomaUrl ? (
                            /\.pdf($|\?)/i.test(activeCertificate.fileName) ? (
                                <iframe
                                    src={activeCertificate.diplomaUrl}
                                    title="Digital Diploma Copy"
                                    className="w-full h-[65vh] border-0"
                                />
                            ) : (
                                <img
                                    src={activeCertificate.diplomaUrl}
                                    alt={`Diploma of ${activeCertificate.fullName}`}
                                    className="w-full h-auto object-contain"
                                />
                            )
                        ) : (
                            <p className="m-0 px-6 text-base text-gray-500">
                                No diploma file attached.
                            </p>
                        )}
                    </div>

                </div>
            </div>

            {/* Request Credential Deletion Popup */}
            {deleteTarget && (
                <div
                    className="fixed inset-0 z-50 grid place-items-center p-4 bg-black/50"
                    onClick={closeDeletion}
                >
                    <div
                        role="dialog"
                        aria-modal="true"
                        aria-labelledby="deleteTitle"
                        onClick={(e) => e.stopPropagation()}
                        className="w-[min(420px,100%)] max-h-[calc(100vh-36px)] overflow-auto rounded-[28px] bg-[#E8EAF1] p-7 shadow-[0_25px_70px_rgba(10,25,47,0.3)]"
                    >
                        <h2
                            id="deleteTitle"
                            className="m-0 text-3xl font-normal leading-snug text-[#111]"
                        >
                            Request credential deletion
                        </h2>

                        <p className="mt-6 mb-0 text-lg leading-relaxed text-[#111]">
                            Student: {deleteTarget.fullName}
                            <br />
                            Student ID: {deleteTarget.studentId}
                        </p>

                        <textarea
                            value={deleteReason}
                            onChange={(e) => setDeleteReason(e.target.value)}
                            placeholder="Explain why this credential should be deleted."
                            aria-label="Reason for deletion"
                            className="mt-5 block w-full h-40 resize-none rounded-lg border border-slate-500 bg-transparent px-4 py-3 text-lg text-[#111] placeholder:text-slate-600 outline-none focus:border-[#00356B] focus:ring-4 focus:ring-[#00356B]/10"
                        />

                        <div className="mt-8 flex items-center justify-end gap-4">
                            <button
                                type="button"
                                onClick={closeDeletion}
                                className="px-4 py-2 text-lg font-bold text-[#0A3D75] hover:bg-white/70 rounded-lg transition-colors"
                            >
                                Cancel
                            </button>

                            <button
                                type="button"
                                onClick={handleSendDeletionRequest}
                                className="inline-flex items-center gap-3 min-h-14 px-7 rounded-full bg-[#00356B] text-lg font-bold text-white hover:bg-[#002B57] transition-colors"
                            >
                                <svg
                                    width="26"
                                    height="26"
                                    viewBox="0 0 24 24"
                                    fill="currentColor"
                                >
                                    <path d="M2.5 20.5 22 12 2.5 3.5l.01 6.6L16 12 2.51 13.9z" />
                                </svg>
                                Send request
                            </button>
                        </div>
                    </div>
                </div>
            )}

            {/* Toast */}
            <div
                id="toast"
                role="status"
                aria-live="polite"
                className="fixed right-5 bottom-5 z-50 translate-y-6 opacity-0 pointer-events-none max-w-[380px] px-4 py-3.5 rounded-xl bg-[#0A192F] text-white shadow-[0_18px_44px_rgba(10,25,47,0.15)] transition-all duration-200 [&.show]:opacity-100 [&.show]:translate-y-0"
            />

        </div>
    );
}