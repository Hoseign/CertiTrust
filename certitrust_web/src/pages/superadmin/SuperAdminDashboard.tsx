import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import SuperAdminSideBar from "@/Components/Organisms/SuperAdminSideBar";
import CertiTrustLoadingIndicator from "@/Components/Atoms/CertiTrustLoadingIndicator";
import {
    getSuperAdminOverview,
    getAdminHistory,
    purgeAccountsAndCredentials,
} from "../../services/adminApi";

function StatIcon({ type }: { type: string }) {
    if (type === "university") {
        return (
            <svg
                width="34"
                height="34"
                viewBox="0 0 24 24"
                fill="none"
                stroke="#1F6A8F"
                strokeWidth="2.4"
                strokeLinecap="round"
                strokeLinejoin="round"
            >
                <polyline points="3 9 12 3 21 9" />
                <line x1="3" y1="9" x2="21" y2="9" />
                <line x1="6" y1="12" x2="6" y2="17" />
                <line x1="10" y1="12" x2="10" y2="17" />
                <line x1="14" y1="12" x2="14" y2="17" />
                <line x1="18" y1="12" x2="18" y2="17" />
                <line x1="3" y1="20.5" x2="21" y2="20.5" />
            </svg>
        );
    }

    if (type === "medal") {
        return (
            <svg
                width="34"
                height="34"
                viewBox="0 0 24 24"
                fill="none"
                stroke="#B7791F"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
            >
                <circle cx="12" cy="9" r="6.5" />
                <polygon
                    points="12 5.8 12.9 8 15.2 8.2 13.4 9.7 14 12 12 10.8 10 12 10.6 9.7 8.8 8.2 11.1 8 12 5.8"
                    fill="#B7791F"
                />
                <path d="M8.5 14.5L7 22l5-3 5 3-1.5-7.5" />
            </svg>
        );
    }

    if (type === "verified") {
        return (
            <svg width="34" height="34" viewBox="0 0 24 24">
                <path
                    d="M12 1.5l2.6 1.9 3.2-.2 1 3.1 2.7 1.8-1 3.1 1 3.1-2.7 1.8-1 3.1-3.2-.2L12 22.5l-2.6-1.9-3.2.2-1-3.1-2.7-1.8 1-3.1-1-3.1 2.7-1.8 1-3.1 3.2.2L12 1.5z"
                    fill="#2E8B57"
                />
                <polyline
                    points="7.5 12 10.5 15 16.5 9"
                    fill="none"
                    stroke="#fff"
                    strokeWidth="2.2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                />
            </svg>
        );
    }

    return (
        <svg width="34" height="34" viewBox="0 0 24 24">
            <path
                d="M12 2l8 3v6c0 5-3.5 9-8 11-4.5-2-8-6-8-11V5l8-3z"
                fill="#8B4A62"
            />
            <circle cx="12" cy="10" r="2.4" fill="#fff" />
            <path d="M7.8 15.5a4.2 3 0 0 1 8.4 0" fill="#fff" />
        </svg>
    );
}

export default function SuperAdminDashboard() {
    const [historyOpen, setHistoryOpen] = useState(false);
    const [historyFilters, setHistoryFilters] = useState({
        university: "",
        action: "",
        year: "",
        search: "",
    });
    const [overview, setOverview] = useState<Record<string, unknown> | null>(null);
    const [actionHistory, setActionHistory] = useState<Record<string, unknown>[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState("");
    const [isPurging, setIsPurging] = useState(false);
    const [purgeMessage, setPurgeMessage] = useState("");
    const [purgeError, setPurgeError] = useState("");
    const [selectedStat, setSelectedStat] = useState<{
        label: string;
        items: Record<string, unknown>[];
    } | null>(null);

    const historyUniversities = Array.from(new Set(actionHistory
        .map((item) => String(item.university_code ?? ""))
        .filter(Boolean))).sort();
    const historyActions = Array.from(new Set(actionHistory
        .map((item) => String(item.action ?? ""))
        .filter(Boolean))).sort();
    const historyYears = Array.from(new Set(actionHistory
        .map((item) => String(item.created_at ?? "").slice(0, 4))
        .filter((year) => /^\d{4}$/.test(year)))).sort((a, b) => b.localeCompare(a));
    const visibleActionHistory = actionHistory.filter((item) => {
        const query = historyFilters.search.trim().toLowerCase();
        const action = String(item.action ?? "");
        const university = String(item.university_code ?? "");
        const year = String(item.created_at ?? "").slice(0, 4);
        const searchable = [
            action,
            item.actor_email,
            item.target_email,
            item.details,
            university,
            item.created_at,
        ].map((value) => String(value ?? "").toLowerCase());
        return (!historyFilters.university || university === historyFilters.university) &&
            (!historyFilters.action || action === historyFilters.action) &&
            (!historyFilters.year || year === historyFilters.year) &&
            (!query || searchable.some((value) => value.includes(query)));
    });

    const refresh = async (silent = false) => {
        if (!silent) setLoading(true);
        try {
            const [nextOverview, nextHistory] = await Promise.all([
                getSuperAdminOverview(),
                getAdminHistory(),
            ]);
            setOverview(nextOverview);
            setActionHistory(nextHistory);
            setError("");
        } catch (requestError) {
            const message = (requestError as { response?: { data?: { message?: string } } })
                .response?.data?.message;
            setError(message || "Unable to load global activity.");
        } finally {
            if (!silent) setLoading(false);
        }
    };

    useEffect(() => {
        void refresh();
        const timer = window.setInterval(() => void refresh(true), 5000);
        return () => window.clearInterval(timer);
    }, []);

    const purgeAllUniversityData = async () => {
        const confirmation = window.prompt(
            "This permanently removes all university registrations, access controls, subadmin accounts, student/user accounts, and database credentials. Old QR codes will report removed. The Super Admin account and blockchain history remain. Type WIPE ALL to continue.",
        );
        if (confirmation !== "WIPE ALL") return;

        setIsPurging(true);
        setPurgeError("");
        setPurgeMessage("");
        try {
            const result = await purgeAccountsAndCredentials();
            setPurgeMessage(result.message);
            await refresh(true);
        } catch (requestError) {
            const message = (requestError as { response?: { data?: { message?: string } } })
                .response?.data?.message;
            setPurgeError(message || "Unable to wipe university data.");
        } finally {
            setIsPurging(false);
        }
    };

    const stats = [
        {
            label: "Total Universities",
            value: overview?.total_universities ?? 0,
            icon: "university",
            items: Array.isArray(overview?.universities) ? overview.universities as Record<string, unknown>[] : [],
        },
        {
            label: "Total Credentials",
            value: overview?.total_credentials ?? 0,
            icon: "medal",
            items: Array.isArray(overview?.activity) ? overview.activity as Record<string, unknown>[] : [],
        },
        {
            label: "Verified Credentials",
            value: overview?.verified_credentials ?? 0,
            icon: "verified",
            items: Array.isArray(overview?.activity)
                ? (overview.activity as Record<string, unknown>[]).filter((item) =>
                    ["verified", "valid"].includes(String(item.status || "").toLowerCase()))
                : [],
        },
        {
            label: "Subadmin Accounts",
            value: Array.isArray(overview?.admins) ? overview.admins.length : 0,
            icon: "shield",
            items: Array.isArray(overview?.admins) ? overview.admins as Record<string, unknown>[] : [],
        },
    ];
    const logs = (Array.isArray(overview?.activity) ? overview.activity : []).map((item) => {
        const record = item as Record<string, unknown>;
        return {
            credential: String(record.student_name || record.recipient_name || record.certificate_code || "Credential"),
            university: String(record.university_code || ""),
            date: String(record.created_at || record.issue_date || ""),
        };
    });

    useEffect(() => {
        if (!historyOpen) return;
        const onKey = (e: KeyboardEvent) => {
            if (e.key === "Escape") setHistoryOpen(false);
        };
        window.addEventListener("keydown", onKey);
        return () => window.removeEventListener("keydown", onKey);
    }, [historyOpen]);

    return (
        <div className="flex min-h-screen bg-[#F5F7FB]">

            <SuperAdminSideBar />

            <main className="flex-1 min-w-0 h-screen overflow-y-auto p-6 md:p-10">

                <div className="max-w-5xl mx-auto">

                    {/* ACCOUNT BAR */}
                    <div className="flex items-center justify-between gap-4 bg-white rounded-2xl border border-gray-100 shadow-sm px-5 py-4 mb-8">

                        <div className="flex items-center gap-3 min-w-0">
                            <span className="text-gray-600 shrink-0">
                                <svg
                                    width="30"
                                    height="30"
                                    viewBox="0 0 24 24"
                                    fill="none"
                                    stroke="currentColor"
                                    strokeWidth="1.8"
                                    strokeLinecap="round"
                                    strokeLinejoin="round"
                                >
                                    <circle cx="12" cy="12" r="10" />
                                    <circle cx="12" cy="10" r="3" />
                                    <path d="M6.2 18.5a6.5 5 0 0 1 11.6 0" />
                                </svg>
                            </span>

                            <span className="text-[#0A192F] font-medium truncate">
                                certitrust256@gmail.com
                            </span>
                        </div>

                        <div className="flex items-center gap-5 shrink-0">

                            <span className="flex items-center gap-2 text-sm font-medium text-[#0A192F]">
                                <span className="w-2.5 h-2.5 rounded-full bg-green-500" />
                                Operational
                            </span>

                            <span className="text-gray-500 font-medium">
                                Global scope
                            </span>

                        </div>

                    </div>

                    {/* HEADER */}
                    <h1 className="text-3xl font-extrabold text-[#0A192F]">
                        Super Admin Dashboard
                    </h1>

                    <p className="text-gray-500 mt-2 mb-8">
                        Register subadmins and monitor global credential activity.
                    </p>

                    {error && <p role="alert" className="mb-5 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</p>}
                    {purgeError && <p role="alert" className="mb-5 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">{purgeError}</p>}
                    {purgeMessage && <p role="status" className="mb-5 rounded-lg border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800">{purgeMessage}</p>}

                    {/* STAT CARDS */}
                    <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-5 mb-8">

                        {stats.map((s) => (
                            <button
                                type="button"
                                key={s.label}
                                onClick={() => setSelectedStat({ label: s.label, items: s.items })}
                                className="w-full rounded-3xl border border-gray-200 bg-[#F3F5F9] p-6 text-left shadow-md transition hover:bg-white hover:shadow-lg focus-visible:outline focus-visible:outline-2 focus-visible:outline-blue-600"
                            >
                                <StatIcon type={s.icon} />

                                <h2 className="text-4xl font-extrabold text-[#0A192F] mt-3">
                                    {loading ? <CertiTrustLoadingIndicator size={28} /> : s.value}
                                </h2>

                                <p className="text-gray-600 font-medium mt-1">
                                    {s.label}
                                </p>
                            </button>
                        ))}

                    </div>

                    {/* ACTION BUTTONS */}
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-12">

                        <Link
                            to="/superadmin/create-subadmin"
                            className="flex items-center justify-center gap-3 py-4 rounded-full bg-[#003366] hover:bg-[#002650] text-white text-lg font-semibold shadow-lg shadow-slate-400/40 transition-all"
                        >
                            <svg
                                width="26"
                                height="26"
                                viewBox="0 0 24 24"
                                fill="none"
                                stroke="currentColor"
                                strokeWidth="2.2"
                                strokeLinecap="round"
                                strokeLinejoin="round"
                            >
                                <circle cx="9" cy="8" r="4" />
                                <path d="M2 21v-1a6 6 0 0 1 6-6h2a6 6 0 0 1 6 6v1" />
                                <line x1="19" y1="8" x2="19" y2="14" />
                                <line x1="16" y1="11" x2="22" y2="11" />
                            </svg>
                            Create subadmin account
                        </Link>

                        <Link
                            to="/superadmin/freeze-access"
                            className="flex items-center justify-center gap-3 py-4 rounded-full bg-transparent border-2 border-gray-400 hover:bg-white text-[#0A3A6B] text-lg font-semibold transition-all"
                        >
                            <svg
                                width="26"
                                height="26"
                                viewBox="0 0 24 24"
                                fill="none"
                                stroke="currentColor"
                                strokeWidth="2"
                                strokeLinecap="round"
                                strokeLinejoin="round"
                            >
                                <path d="M3 12a9 9 0 1 0 3-6.7" />
                                <polyline points="3 4 3 9 8 9" />
                                <rect x="9" y="11" width="6" height="5" rx="1" />
                                <path d="M10.5 11V9.5a1.5 1.5 0 0 1 3 0V11" />
                            </svg>
                            Freeze or unfreeze access
                        </Link>

                        <Link
                            to="/superadmin/deletion-requests"
                            className="flex items-center justify-center gap-3 py-4 rounded-full bg-transparent border-2 border-gray-400 hover:bg-white text-[#0A3A6B] text-lg font-semibold transition-all"
                        >
                            <svg
                                width="26"
                                height="26"
                                viewBox="0 0 24 24"
                                fill="none"
                                stroke="currentColor"
                                strokeWidth="2"
                                strokeLinecap="round"
                                strokeLinejoin="round"
                            >
                                <path d="M9 4H6a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h4" />
                                <rect x="8" y="2" width="6" height="4" rx="1" />
                                <path d="M14 4h2a2 2 0 0 1 2 2v3" />
                                <circle cx="17" cy="17" r="4.5" />
                                <polyline points="17 14.5 17 17 18.8 18" />
                            </svg>
                            Credential deletion requests
                        </Link>

                        <button
                            type="button"
                            onClick={() => setHistoryOpen(true)}
                            className="flex items-center justify-center gap-3 py-4 rounded-full bg-transparent border-2 border-gray-400 hover:bg-white text-[#0A3A6B] text-lg font-semibold transition-all"
                        >
                            <svg
                                width="26"
                                height="26"
                                viewBox="0 0 24 24"
                                fill="none"
                                stroke="currentColor"
                                strokeWidth="2"
                                strokeLinecap="round"
                                strokeLinejoin="round"
                            >
                                <path d="M3 12a9 9 0 1 0 3-6.7" />
                                <polyline points="3 4 3 9 8 9" />
                                <polyline points="12 7 12 12 15.5 14" />
                            </svg>
                            Action history
                        </button>

                        <button
                            type="button"
                            onClick={() => void purgeAllUniversityData()}
                            disabled={isPurging}
                            className="flex items-center justify-center gap-3 py-4 rounded-full border-2 border-red-700 bg-red-700 text-white text-lg font-semibold shadow-lg shadow-red-900/20 transition-all hover:bg-red-800 disabled:cursor-wait disabled:opacity-60"
                        >
                            <svg
                                width="26"
                                height="26"
                                viewBox="0 0 24 24"
                                fill="none"
                                stroke="currentColor"
                                strokeWidth="2"
                                strokeLinecap="round"
                                strokeLinejoin="round"
                            >
                                <path d="M3 6h18" />
                                <path d="M8 6V4h8v2" />
                                <path d="m19 6-1 14H6L5 6" />
                                <path d="M10 11v5m4-5v5" />
                            </svg>
                            {isPurging ? "Wiping university data..." : "Wipe all university data"}
                        </button>

                    </div>

                    {/* GLOBAL CREDENTIAL LOGS */}
                    <h2 className="text-2xl font-bold text-[#0A192F] mb-5">
                        Global Credential Logs
                    </h2>

                    <div className="bg-[#F3F5F9] rounded-3xl border border-gray-200 shadow-md overflow-hidden">

                        <div className="overflow-x-auto">

                            <table className="w-full text-left">

                                <thead>
                                    <tr className="border-b-2 border-gray-300">
                                        <th className="px-7 py-6 text-lg font-bold text-[#0A192F]">
                                            Credential
                                        </th>

                                        <th className="px-7 py-6 text-lg font-bold text-[#0A192F]">
                                            University
                                        </th>

                                        <th className="px-7 py-6 text-lg font-bold text-[#0A192F]">
                                            Date
                                        </th>
                                    </tr>
                                </thead>

                                <tbody>
                                    {logs.map((log, index) => (
                                        <tr
                                            key={log.credential}
                                            className={`hover:bg-white/60 transition-colors ${index !== logs.length - 1
                                                    ? "border-b border-gray-300"
                                                    : ""
                                                }`}
                                        >
                                            <td className="px-7 py-6 text-[#0A192F]">
                                                {log.credential}
                                            </td>

                                            <td className="px-7 py-6 text-[#0A192F]">
                                                {log.university}
                                            </td>

                                            <td className="px-7 py-6 text-[#0A192F]">
                                                {log.date}
                                            </td>
                                        </tr>
                                    ))}
                                    {!loading && logs.length === 0 && (
                                        <tr><td className="px-7 py-6 text-sm text-slate-500" colSpan={3}>No credential activity yet.</td></tr>
                                    )}
                                </tbody>

                            </table>

                        </div>

                    </div>

                </div>

                {/* ACTION HISTORY POPUP */}
                {historyOpen && (
                    <div
                        className="fixed inset-0 z-50 flex items-center justify-center p-4"
                        role="dialog"
                        aria-modal="true"
                    >
                        <div
                            className="absolute inset-0 bg-black/50"
                            onClick={() => setHistoryOpen(false)}
                        />

                        <div className="relative w-full max-w-3xl max-h-[90vh] flex flex-col bg-[#E9EBF1] rounded-3xl shadow-2xl p-6 sm:p-8">

                            <h2 className="text-3xl font-normal text-[#0A192F] leading-tight mb-6">
                                Super Admin Action History
                            </h2>

                            <div className="mb-5 grid grid-cols-1 gap-3 sm:grid-cols-2">
                                <label className="text-sm font-semibold text-slate-700">
                                    University
                                    <select
                                        value={historyFilters.university}
                                        onChange={(event) => setHistoryFilters((current) => ({
                                            ...current,
                                            university: event.target.value,
                                        }))}
                                        className="mt-1 min-h-11 w-full rounded-lg border border-slate-300 bg-white px-3 font-normal"
                                    >
                                        <option value="">All Universities</option>
                                        {historyUniversities.map((university) => (
                                            <option key={university} value={university}>{university}</option>
                                        ))}
                                    </select>
                                </label>
                                <label className="text-sm font-semibold text-slate-700">
                                    Action
                                    <select
                                        value={historyFilters.action}
                                        onChange={(event) => setHistoryFilters((current) => ({
                                            ...current,
                                            action: event.target.value,
                                        }))}
                                        className="mt-1 min-h-11 w-full rounded-lg border border-slate-300 bg-white px-3 font-normal"
                                    >
                                        <option value="">All Actions</option>
                                        {historyActions.map((action) => (
                                            <option key={action} value={action}>{action.replaceAll("_", " ")}</option>
                                        ))}
                                    </select>
                                </label>
                                <label className="text-sm font-semibold text-slate-700">
                                    Year
                                    <select
                                        value={historyFilters.year}
                                        onChange={(event) => setHistoryFilters((current) => ({
                                            ...current,
                                            year: event.target.value,
                                        }))}
                                        className="mt-1 min-h-11 w-full rounded-lg border border-slate-300 bg-white px-3 font-normal"
                                    >
                                        <option value="">All Years</option>
                                        {historyYears.map((year) => (
                                            <option key={year} value={year}>{year}</option>
                                        ))}
                                    </select>
                                </label>
                                <label className="text-sm font-semibold text-slate-700">
                                    Search audit history
                                    <input
                                        type="search"
                                        value={historyFilters.search}
                                        onChange={(event) => setHistoryFilters((current) => ({
                                            ...current,
                                            search: event.target.value,
                                        }))}
                                        placeholder="Action, administrator, email, or details"
                                        className="mt-1 min-h-11 w-full rounded-lg border border-slate-300 bg-white px-3 font-normal"
                                    />
                                </label>
                                {(historyFilters.university || historyFilters.action || historyFilters.year || historyFilters.search) && (
                                    <button
                                        type="button"
                                        onClick={() => setHistoryFilters({
                                            university: "",
                                            action: "",
                                            year: "",
                                            search: "",
                                        })}
                                        className="min-h-10 justify-self-start rounded-lg px-3 text-sm font-semibold text-blue-700 hover:bg-white/70 sm:col-span-2"
                                    >
                                        Reset filters
                                    </button>
                                )}
                            </div>

                            <div className="flex-1 min-h-0 overflow-y-auto pr-1">
                                {visibleActionHistory.map((item, index) => (
                                    <div
                                        key={String(item.id || index)}
                                        className={`py-5 ${index !== actionHistory.length - 1
                                                ? "border-b-2 border-gray-300"
                                                : ""
                                            }`}
                                    >
                                        <p className="text-xl text-[#0A192F]">
                                            {String(item.action || "Administrative action")}
                                        </p>

                                        <p className="text-[15px] text-gray-600 mt-1">
                                            {String(item.actor_email || "System administrator")} • {String(item.university_code || item.target_email || "Global")}
                                        </p>

                                        <p className="text-[15px] text-gray-600">
                                            {String(item.created_at || "")}
                                        </p>
                                    </div>
                                ))}
                                {visibleActionHistory.length === 0 && (
                                    <p className="py-6 text-sm text-slate-600">
                                        {actionHistory.length
                                            ? "No audit entries match the selected filters."
                                            : "No administrative actions have been recorded yet."}
                                    </p>
                                )}
                            </div>

                            <div className="flex justify-end mt-6">
                                <button
                                    type="button"
                                    onClick={() => setHistoryOpen(false)}
                                    className="px-4 py-2 rounded-lg text-lg font-semibold text-[#0A3A6B] hover:bg-white/70 transition-colors"
                                >
                                    Close
                                </button>
                            </div>

                        </div>
                    </div>
                )}

                {selectedStat && (
                    <div
                        className="fixed inset-0 z-50 flex items-center justify-center p-4"
                        role="dialog"
                        aria-modal="true"
                        aria-labelledby="superadmin-stat-title"
                    >
                        <button
                            type="button"
                            className="absolute inset-0 cursor-default bg-black/50"
                            aria-label="Close details"
                            onClick={() => setSelectedStat(null)}
                        />
                        <section className="relative max-h-[85vh] w-full max-w-xl overflow-y-auto rounded-2xl bg-white p-6 shadow-2xl">
                            <div className="mb-4 flex items-start justify-between gap-4">
                                <h2 id="superadmin-stat-title" className="text-xl font-bold text-[#0A192F]">
                                    {selectedStat.label}
                                </h2>
                                <button
                                    type="button"
                                    onClick={() => setSelectedStat(null)}
                                    className="rounded-lg px-3 py-1 font-bold text-slate-500 hover:bg-slate-100"
                                >
                                    Close
                                </button>
                            </div>
                            {selectedStat.items.length === 0 ? (
                                <p className="py-8 text-center text-sm text-slate-500">
                                    No details are available yet.
                                </p>
                            ) : (
                                <div className="divide-y divide-slate-100">
                                    {selectedStat.items.map((item, index) => {
                                        const title = String(
                                            item.name || item.student_name || item.recipient_name ||
                                            item.email || item.certificate_code || "Record",
                                        );
                                        const subtitle = [
                                            item.email,
                                            item.university_code || item.code,
                                            item.status,
                                            item.created_at || item.issue_date,
                                        ].filter(Boolean).join(" · ");
                                        return (
                                            <div key={String(item.id || item.certificate_code || index)} className="py-3">
                                                <p className="font-semibold text-[#0A192F]">{title}</p>
                                                {subtitle && <p className="mt-1 text-sm text-slate-500">{subtitle}</p>}
                                            </div>
                                        );
                                    })}
                                </div>
                            )}
                        </section>
                    </div>
                )}

            </main>

        </div>
    );
}