import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import Sidebar from "@/Components/Organisms/Sidebar";
import { getSessionUser } from "../../services/authService";
import { listCertificates, listRecentVerifications, type CertificateRecord } from "../../services/certitrustApi";

type Verified = {
    id: string;
    name: string;
    program: string;
    university: string;
    verifiedAt: string;
};

export default function PsuAdminDashboard() {
    const [verified, setVerified] = useState<Verified[]>([]);
    const [recentCredential, setRecentCredential] = useState<CertificateRecord | null>(null);
    const [error, setError] = useState("");

    useEffect(() => {
        const refresh = async () => {
            try {
                const [verifications, certificates] = await Promise.all([
                    listRecentVerifications(),
                    listCertificates(1),
                ]);

                setVerified(
                    verifications.map((record) => ({
                        id: String(record.id),
                        name: record.student_name || "Student",
                        program: record.degree || "Academic credential",
                        university: record.university_name || record.university_code || "Institution",
                        verifiedAt: record.verified_at || record.created_at || "",
                    }))
                );
                setRecentCredential(certificates[0] || null);
                setError("");
            } catch (err) {
                setError(
                    (err as { response?: { data?: { message?: string } } })
                        .response?.data?.message || "Unable to refresh PSU admin overview."
                );
            }
        };

        void refresh();
    }, []);

    const universityName = useMemo(() => {
        return getSessionUser()?.university_code || "PSU";
    }, []);

    return (
        <div className="min-h-screen bg-[#FAFAFD]">
            <div className="min-h-screen grid grid-cols-1 md:grid-cols-[286px_1fr]">
                <Sidebar />

                <main className="min-w-0 overflow-y-auto h-screen p-4 sm:p-6 md:p-10">
                    <div className="max-w-5xl mx-auto">
                        <div className="mb-8 flex items-center justify-between gap-4">
                            <div>
                                <p className="text-xs font-extrabold uppercase tracking-[0.22em] text-[#2563EB]">
                                    Pangasinan State University
                                </p>
                                <h1 className="mt-2 text-3xl font-extrabold text-[#0A192F]">
                                    PSU Admin Dashboard
                                </h1>
                            </div>
                            <div className="rounded-full border border-sky-200 bg-sky-50 px-4 py-2 text-sm font-bold text-sky-800">
                                University Access Control
                            </div>
                        </div>

                        {error && (
                            <p role="alert" className="mb-5 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
                                {error}
                            </p>
                        )}

                        <section className="flex items-center gap-8 rounded-3xl bg-[#F1F4F8] p-8 md:p-10 shadow-[0_4px_12px_rgba(15,23,42,0.12)]">
                            <div className="flex h-24 w-24 flex-none items-center justify-center rounded-full bg-[#E0E3EE] text-[#003366]">
                                <svg width="46" height="46" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                                    <path d="M12 3 1 9l11 6 9-4.9V17h2V9L12 3z" />
                                    <path d="M5 13.2v3.5c0 1.3 3.1 3.3 7 3.3s7-2 7-3.3v-3.5l-7 3.8-7-3.8z" />
                                </svg>
                            </div>

                            <div className="min-w-0">
                                <h2 className="text-3xl md:text-4xl font-bold text-[#111] leading-tight">
                                    Welcome to {universityName} Admin Portal
                                </h2>
                                <p className="mt-3 text-lg md:text-xl text-gray-500">
                                    Manage student credentials, validate academic records, and oversee university verification activity.
                                </p>
                            </div>
                        </section>

                        <h2 className="mt-10 mb-5 text-2xl font-bold text-[#111]">Quick Actions</h2>

                        <section className="grid grid-cols-1 lg:grid-cols-3 gap-5">
                            <Link
                                to="/records"
                                className="flex items-center gap-5 rounded-2xl bg-[#F1F4F8] p-6 shadow-[0_3px_8px_rgba(15,23,42,0.12)] transition-all duration-200 hover:-translate-y-1 hover:shadow-[0_8px_20px_rgba(15,23,42,0.16)]"
                            >
                                <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-[#DCEAFB] text-[#1E88E5]">
                                    <svg width="34" height="34" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                                        <path d="M12 1 3 5v6c0 5.5 3.8 10.7 9 12 .9-.2 1.7-.6 2.5-1A6 6 0 0 1 21 11.7V5l-9-4z" />
                                        <path d="M17 14v6M14 17h6" stroke="#00A3E0" strokeWidth="2" strokeLinecap="round" fill="none" />
                                    </svg>
                                </div>
                                <div>
                                    <h3 className="text-xl font-bold text-[#111]">Issue Records</h3>
                                    <p className="mt-1 text-base text-gray-500">Issue and publish academic credentials</p>
                                </div>
                            </Link>

                            <Link
                                to="/verification"
                                className="flex items-center gap-5 rounded-2xl bg-[#F1F4F8] p-6 shadow-[0_3px_8px_rgba(15,23,42,0.12)] transition-all duration-200 hover:-translate-y-1 hover:shadow-[0_8px_20px_rgba(15,23,42,0.16)]"
                            >
                                <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-[#D5E8EA] text-[#00897B]">
                                    <svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                                        <path d="M3 8V4h4M17 4h4v4M21 16v4h-4M7 20H3v-4" />
                                        <rect x="7" y="7" width="4" height="4" />
                                        <rect x="13" y="7" width="4" height="4" />
                                        <rect x="7" y="13" width="4" height="4" />
                                        <path d="M14 14h1M17 14h0M14 17h0M17 17h0" />
                                    </svg>
                                </div>
                                <div>
                                    <h3 className="text-xl font-bold text-[#111]">Verify Certificates</h3>
                                    <p className="mt-1 text-base text-gray-500">Check authenticity and blockchain status</p>
                                </div>
                            </Link>

                            <Link
                                to="/certificates"
                                className="flex items-center gap-5 rounded-2xl bg-[#F1F4F8] p-6 shadow-[0_3px_8px_rgba(15,23,42,0.12)] transition-all duration-200 hover:-translate-y-1 hover:shadow-[0_8px_20px_rgba(15,23,42,0.16)]"
                            >
                                <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-[#FBEBDD] text-[#F57C00]">
                                    <svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                                        <path d="M7 10V7a5 5 0 0 1 10 0v3" />
                                        <rect x="5" y="10" width="14" height="10" rx="2" />
                                        <path d="M12 14v3" />
                                    </svg>
                                </div>
                                <div>
                                    <h3 className="text-xl font-bold text-[#111]">Manage Credentials</h3>
                                    <p className="mt-1 text-base text-gray-500">Review and manage your university credentials</p>
                                </div>
                            </Link>
                        </section>

                        <section className="mt-10 rounded-3xl border border-slate-200 bg-white p-6 shadow-[0_4px_12px_rgba(15,23,42,0.08)]">
                            <div className="flex items-center justify-between gap-4 mb-5">
                                <h2 className="text-2xl font-bold text-[#111]">Recent University Verification Activity</h2>
                                <span className="text-sm font-semibold text-slate-500">Latest 5</span>
                            </div>

                            <div className="overflow-hidden rounded-2xl border border-slate-200">
                                <table className="min-w-full text-left">
                                    <thead className="bg-slate-50 text-sm font-bold uppercase tracking-wide text-slate-600">
                                        <tr>
                                            <th className="px-4 py-3">Student</th>
                                            <th className="px-4 py-3">Program</th>
                                            <th className="px-4 py-3">University</th>
                                            <th className="px-4 py-3">Verified</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {verified.length === 0 ? (
                                            <tr>
                                                <td colSpan={4} className="px-4 py-6 text-center text-sm text-slate-500">
                                                    No recent verification activity.
                                                </td>
                                            </tr>
                                        ) : (
                                            verified.map((item) => (
                                                <tr key={item.id} className="border-t border-slate-200">
                                                    <td className="px-4 py-3 font-semibold text-[#0A192F]">{item.name}</td>
                                                    <td className="px-4 py-3 text-slate-600">{item.program}</td>
                                                    <td className="px-4 py-3 text-slate-600">{item.university}</td>
                                                    <td className="px-4 py-3 text-slate-600">{item.verifiedAt || "Recently"}</td>
                                                </tr>
                                            ))
                                        )}
                                    </tbody>
                                </table>
                            </div>
                        </section>

                        <section className="mt-8 rounded-3xl border border-slate-200 bg-white p-6 shadow-[0_4px_12px_rgba(15,23,42,0.08)]">
                            <h2 className="text-2xl font-bold text-[#111]">Latest Credential</h2>
                            {recentCredential ? (
                                <div className="mt-5 grid gap-3 md:grid-cols-2">
                                    <div className="rounded-2xl bg-slate-50 p-4">
                                        <p className="text-xs font-bold uppercase tracking-wide text-slate-500">Student</p>
                                        <p className="mt-2 text-lg font-bold text-[#0A192F]">{recentCredential.student_name}</p>
                                    </div>
                                    <div className="rounded-2xl bg-slate-50 p-4">
                                        <p className="text-xs font-bold uppercase tracking-wide text-slate-500">Program</p>
                                        <p className="mt-2 text-lg font-bold text-[#0A192F]">{recentCredential.degree}</p>
                                    </div>
                                    <div className="rounded-2xl bg-slate-50 p-4">
                                        <p className="text-xs font-bold uppercase tracking-wide text-slate-500">Certificate Code</p>
                                        <p className="mt-2 text-lg font-bold text-[#0A192F]">{recentCredential.certificate_code}</p>
                                    </div>
                                    <div className="rounded-2xl bg-slate-50 p-4">
                                        <p className="text-xs font-bold uppercase tracking-wide text-slate-500">Issue Date</p>
                                        <p className="mt-2 text-lg font-bold text-[#0A192F]">{recentCredential.issue_date}</p>
                                    </div>
                                </div>
                            ) : (
                                <p className="mt-5 text-sm text-slate-500">No credential has been issued yet for this university.</p>
                            )}
                        </section>
                    </div>
                </main>
            </div>
        </div>
    );
}
