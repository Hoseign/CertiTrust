import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import SuperAdminSideBar from "../../components/SuperAdminSideBar";
import CertiTrustLoadingIndicator from "../../components/CertiTrustLoadingIndicator";
import { getSuperAdminOverview } from "../../services/adminApi";

type CredentialActivity = {
    certificate_code?: string;
    student_name?: string;
    recipient_name?: string;
    university_code?: string;
    issue_date?: string;
    created_at?: string;
    status?: string;
};

type Overview = {
    total_universities?: number;
    total_credentials?: number;
    verified_credentials?: number;
    universities?: Record<string, unknown>[];
    activity?: CredentialActivity[];
};

const formatDate = (value?: string) => {
    if (!value) return "Date unavailable";
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? value : date.toLocaleString();
};

export default function SuperAdminLogs() {
    const [overview, setOverview] = useState<Overview | null>(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState("");
    const [search, setSearch] = useState("");

    const refresh = useCallback(async () => {
        try {
            const data = await getSuperAdminOverview() as Overview;
            setOverview(data);
            setError("");
        } catch (requestError) {
            const message = (requestError as { response?: { data?: { message?: string } } })
                .response?.data?.message;
            setError(message || "Unable to load global credential activity.");
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        void refresh();
        const timer = window.setInterval(() => void refresh(), 10000);
        return () => window.clearInterval(timer);
    }, [refresh]);

    const activities = overview?.activity ?? [];
    const query = search.trim().toLowerCase();
    const filteredActivities = activities.filter((item) =>
        [
            item.student_name,
            item.recipient_name,
            item.certificate_code,
            item.university_code,
            item.status,
        ].some((value) => String(value ?? "").toLowerCase().includes(query)),
    );
    const stats = [
        { label: "Total Activities", value: overview?.total_credentials ?? 0, color: "text-[#071426]" },
        { label: "Credentials Issued", value: overview?.total_credentials ?? 0, color: "text-blue-600" },
        { label: "Credentials Verified", value: overview?.verified_credentials ?? 0, color: "text-green-600" },
        { label: "Universities", value: overview?.total_universities ?? 0, color: "text-purple-600" },
    ];

    return (
        <div className="min-h-screen bg-[#F5F7FB] flex">
            <SuperAdminSideBar />
            <main className="min-w-0 flex-1 overflow-y-auto p-5 md:h-screen md:p-8">
                <div className="mx-auto max-w-6xl">
                    <div className="flex flex-wrap items-center justify-between gap-4">
                        <div>
                            <h1 className="text-3xl font-extrabold text-[#071426]">
                                Global Credential Logs
                            </h1>
                            <p className="mt-2 text-gray-500">
                                Live credential activity across registered universities.
                            </p>
                        </div>
                        <button
                            type="button"
                            onClick={() => void refresh()}
                            disabled={loading}
                            className="min-h-10 rounded-lg border border-slate-300 bg-white px-4 text-sm font-bold text-[#0A192F] hover:bg-slate-50 disabled:opacity-60"
                        >
                            {loading ? (
                                <CertiTrustLoadingIndicator size={18} message="Refreshing..." inline />
                            ) : "Refresh"}
                        </button>
                    </div>

                    {error && (
                        <p role="alert" className="mt-5 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
                            {error}
                        </p>
                    )}

                    <div className="mt-8 grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
                        {stats.map((stat) => (
                            <div key={stat.label} className="rounded-2xl bg-white p-5 shadow-sm">
                                <p className="text-sm text-gray-500">{stat.label}</p>
                                <h2 className={`mt-2 text-3xl font-bold ${stat.color}`}>
                                    {loading ? <CertiTrustLoadingIndicator size={28} /> : stat.value}
                                </h2>
                            </div>
                        ))}
                    </div>

                    <section className="mt-8 overflow-hidden rounded-2xl bg-white shadow-sm">
                        <div className="flex flex-wrap items-center justify-between gap-4 border-b border-gray-100 p-6">
                            <div>
                                <h2 className="text-xl font-bold text-[#071426]">Credential Activity</h2>
                                <p className="mt-1 text-sm text-gray-500">
                                    Select a record to open its public verification page.
                                </p>
                            </div>
                            <input
                                type="search"
                                value={search}
                                onChange={(event) => setSearch(event.target.value)}
                                placeholder="Search credentials"
                                aria-label="Search credential activity"
                                className="min-h-10 w-full max-w-sm rounded-lg border border-slate-200 px-3 text-sm outline-none focus:border-blue-600"
                            />
                        </div>

                        {loading ? (
                            <CertiTrustLoadingIndicator size={28} message="Loading global activity..." className="w-full p-6 text-sm text-gray-500" />
                        ) : filteredActivities.length === 0 ? (
                            <p className="p-6 text-sm text-gray-500">
                                {activities.length ? "No credentials match your search." : "No credential activity has been recorded yet."}
                            </p>
                        ) : (
                            <div className="divide-y divide-gray-100">
                                {filteredActivities.map((item, index) => {
                                    const code = item.certificate_code?.trim();
                                    const record = (
                                        <>
                                            <div className="flex min-w-0 flex-1 items-center justify-between gap-4">
                                                <div className="min-w-0">
                                                    <h3 className="truncate font-bold text-[#071426]">
                                                        {item.student_name || item.recipient_name || "Credential"}
                                                    </h3>
                                                    <p className="mt-1 truncate text-sm text-gray-500">
                                                        {code || "Certificate code unavailable"} · {item.university_code || "Unassigned"}
                                                    </p>
                                                    <p className="mt-1 text-xs text-gray-400">
                                                        {formatDate(item.created_at || item.issue_date)}
                                                    </p>
                                                </div>
                                                <span className="shrink-0 rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold text-slate-700">
                                                    {item.status || "Pending"}
                                                </span>
                                            </div>
                                            <span aria-hidden="true" className="text-xl text-blue-700">›</span>
                                        </>
                                    );

                                    return code ? (
                                        <Link
                                            key={`${code}-${index}`}
                                            to={`/public-verification?certificateId=${encodeURIComponent(code)}`}
                                            className="flex items-center gap-4 p-5 transition-colors hover:bg-slate-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-blue-600"
                                        >
                                            {record}
                                        </Link>
                                    ) : (
                                        <div key={`activity-${index}`} className="flex items-center gap-4 p-5">
                                            {record}
                                        </div>
                                    );
                                })}
                            </div>
                        )}
                    </section>
                </div>
            </main>
        </div>
    );
}
