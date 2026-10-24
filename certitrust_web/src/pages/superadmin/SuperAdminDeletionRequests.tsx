import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import SuperAdminSideBar from "../../components/SuperAdminSideBar";
import CertiTrustLoadingIndicator from "../../components/CertiTrustLoadingIndicator";
import { listDeletionRequests, reviewDeletionRequest } from "../../services/adminApi";

type DeletionRequest = {
    id: number;
    student: string;
    studentId: string;
    email: string;
    school: string;
    degree: string;
    credentialCode: string;
    requestedBy: string;
    status: string;
    concern: string;
};

export default function SuperAdminDeletionRequests() {
    const navigate = useNavigate();
    const [selected, setSelected] = useState<DeletionRequest | null>(null);
    const [requests, setRequests] = useState<DeletionRequest[]>([]);
    const [reviewerNote, setReviewerNote] = useState("");
    const [isLoading, setIsLoading] = useState(true);
    const [isReviewing, setIsReviewing] = useState(false);
    const [error, setError] = useState("");

    const refresh = async (silent = false) => {
        if (!silent) setIsLoading(true);
        try {
            const records = await listDeletionRequests();
            setRequests(records.map((record) => ({
                id: Number(record.id),
                student: String(record.student_name || "Student"),
                studentId: String(record.student_id || "Not recorded"),
                email: String(record.student_email || "Not recorded"),
                school: String(record.university_code || ""),
                degree: String(record.degree || "Not recorded"),
                credentialCode: String(record.certificate_code || ""),
                requestedBy: String(record.requester_name || record.requester_email || "University admin"),
                status: String(record.status || "pending"),
                concern: String(record.reason || ""),
            })));
            setError("");
        } catch (requestError) {
            const message = (requestError as { response?: { data?: { message?: string } } })
                .response?.data?.message;
            setError(message || "Unable to load deletion requests.");
        } finally {
            if (!silent) setIsLoading(false);
        }
    };

    useEffect(() => {
        void refresh();
        const timer = window.setInterval(() => void refresh(true), 5000);
        return () => window.clearInterval(timer);
    }, []);

    const review = async (decision: "approved" | "rejected") => {
        if (!selected) return;
        setIsReviewing(true);
        try {
            await reviewDeletionRequest(selected.id, decision, reviewerNote.trim() || undefined);
            setSelected(null);
            setReviewerNote("");
            await refresh(true);
        } catch (requestError) {
            const message = (requestError as { response?: { data?: { message?: string } } })
                .response?.data?.message;
            setError(message || "Unable to review this request.");
        } finally {
            setIsReviewing(false);
        }
    };

    useEffect(() => {
        if (!selected) return;
        const onKey = (e: KeyboardEvent) => {
            if (e.key === "Escape") setSelected(null);
        };
        window.addEventListener("keydown", onKey);
        return () => window.removeEventListener("keydown", onKey);
    }, [selected]);

    const messageSubadmin = () => {
        setSelected(null);
        navigate("/superadmin/ask");
    };

    return (
        <div className="flex min-h-screen bg-[#F5F7FB]">

            <SuperAdminSideBar />

            <main className="flex-1 min-w-0 h-screen overflow-y-auto p-6 md:p-10">

                <div className="max-w-3xl mx-auto">

                    {/* HEADER */}
                    <h1 className="text-3xl font-extrabold text-[#0A192F] mb-8">
                        Credential Deletion Requests
                    </h1>
                    {error && <p role="alert" className="mb-5 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</p>}

                    {/* REQUESTS */}
                    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">

                        {isLoading ? <CertiTrustLoadingIndicator size={28} message="Loading requests..." className="w-full p-6 text-sm text-slate-500" /> : requests.map((r, index) => (
                            <div
                                key={r.id}
                                role="button"
                                tabIndex={0}
                                onClick={() => setSelected(r)}
                                onKeyDown={(e) => {
                                    if (e.key === "Enter") setSelected(r);
                                }}
                                className={`flex items-center gap-5 px-6 py-6 cursor-pointer hover:bg-gray-50 transition-colors ${index !== requests.length - 1
                                        ? "border-b border-gray-200"
                                        : ""
                                    }`}
                            >

                                {/* STATUS ICON */}
                                <div className="w-14 h-14 rounded-full bg-[#DCE8FA] text-[#0A3A6B] shrink-0 flex items-center justify-center">
                                    <svg
                                        width="30"
                                        height="30"
                                        viewBox="0 0 24 24"
                                        fill="none"
                                        stroke="currentColor"
                                        strokeWidth="2"
                                        strokeLinecap="round"
                                        strokeLinejoin="round"
                                    >
                                        <path d="M21 12a9 9 0 1 1-5.2-8.2" />
                                        <polyline points="8 11.5 12 15.5 21 6.5" />
                                    </svg>
                                </div>

                                {/* TEXT */}
                                <div className="flex-1 min-w-0">

                                    <p className="text-lg font-semibold text-[#0A192F] truncate">
                                        {r.student}
                                    </p>

                                    <p className="text-[15px] text-gray-600 mt-0.5">
                                        ID: {r.studentId} • {r.school}
                                    </p>

                                    <p className="text-[15px] text-gray-600">
                                        {r.status} • Requested by {r.requestedBy}
                                    </p>

                                </div>

                                {/* MESSAGE */}
                                <button
                                    type="button"
                                    aria-label="Message subadmin"
                                    onClick={(e) => {
                                        e.stopPropagation();
                                        navigate("/superadmin/ask");
                                    }}
                                    onKeyDown={(e) => e.stopPropagation()}
                                    className="p-2 rounded-lg text-[#333F4F] hover:bg-gray-200/70 transition-colors shrink-0"
                                >
                                    <svg width="28" height="28" viewBox="0 0 24 24" fill="currentColor">
                                        <path d="M4 3h16a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1H8l-4.3 3.6A.5.5 0 0 1 3 21.2V4a1 1 0 0 1 1-1z" />
                                        <rect x="7" y="7" width="10" height="1.6" fill="#fff" />
                                        <rect x="7" y="10.2" width="10" height="1.6" fill="#fff" />
                                        <rect x="7" y="13.4" width="10" height="1.6" fill="#fff" />
                                    </svg>
                                </button>

                            </div>
                        ))}

                    </div>

                </div>

                {/* DETAILS DIALOG */}
                {selected && (
                    <div
                        className="fixed inset-0 z-50 flex items-center justify-center p-4"
                        role="dialog"
                        aria-modal="true"
                    >
                        <div
                            className="absolute inset-0 bg-black/50"
                            onClick={() => setSelected(null)}
                        />

                        <div className="relative w-full max-w-md max-h-[90vh] overflow-y-auto bg-[#E9EBF1] rounded-3xl shadow-2xl p-8">

                            {/* TITLE */}
                            <div className="flex items-center gap-4 mb-6">
                                <span className="text-[#0A192F] shrink-0">
                                    <svg
                                        width="36"
                                        height="36"
                                        viewBox="0 0 24 24"
                                        fill="none"
                                        stroke="currentColor"
                                        strokeWidth="2"
                                        strokeLinecap="round"
                                        strokeLinejoin="round"
                                    >
                                        <path d="M21 11v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h8" />
                                        <polyline points="3.5 8 12 14 17 10.5" />
                                        <circle cx="19" cy="5" r="2.5" fill="currentColor" />
                                    </svg>
                                </span>

                                <h2 className="text-3xl font-normal text-[#0A192F] leading-tight">
                                    Deletion request {selected.status}
                                </h2>
                            </div>

                            {/* DETAILS */}
                            <div className="space-y-3 text-[17px] text-[#0A192F] break-words">
                                <p>Student: {selected.student}</p>
                                <p>Student ID: {selected.studentId}</p>
                                <p>Google email: {selected.email}</p>
                                <p>School: {selected.school}</p>
                                <p>Degree: {selected.degree}</p>
                                <p>Credential code: {selected.credentialCode}</p>
                                <p>Requested by: {selected.requestedBy}</p>
                            </div>

                            <div className="border-t-2 border-gray-300 my-6" />

                            {/* CONCERN */}
                            <h3 className="font-bold text-[17px] text-[#0A192F] mb-2">
                                Subadmin concern
                            </h3>

                            <p className="text-[17px] text-[#0A192F]">
                                {selected.concern || "No reason was provided."}
                            </p>
                            {selected.status === "pending" && (
                                <label className="mt-5 block text-sm font-bold text-[#0A192F]">
                                    Reviewer note
                                    <textarea
                                        value={reviewerNote}
                                        onChange={(event) => setReviewerNote(event.target.value)}
                                        className="mt-2 min-h-24 w-full rounded-lg border border-slate-300 bg-white p-3 font-normal outline-none focus:border-blue-600"
                                    />
                                </label>
                            )}

                            {/* ACTIONS */}
                            <div className="flex flex-col items-end gap-4 mt-10">

                                <button
                                    type="button"
                                    onClick={() => setSelected(null)}
                                    className="px-4 py-2 rounded-lg text-lg font-semibold text-[#0A3A6B] hover:bg-white/70 transition-colors"
                                >
                                    Close
                                </button>

                                {selected.status === "pending" && (
                                    <div className="flex gap-3">
                                        <button type="button" disabled={isReviewing} onClick={() => void review("rejected")} className="min-h-11 rounded-lg border border-red-300 px-4 font-semibold text-red-700 disabled:opacity-50">Reject</button>
                                        <button type="button" disabled={isReviewing} onClick={() => void review("approved")} className="min-h-11 rounded-lg bg-emerald-700 px-4 font-semibold text-white disabled:opacity-50">Approve</button>
                                    </div>
                                )}

                                <button
                                    type="button"
                                    onClick={messageSubadmin}
                                    className="flex items-center gap-3 px-4 py-2 rounded-lg text-lg font-semibold text-[#0A3A6B] hover:bg-white/70 transition-colors"
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
                                        <path d="M4 3h16a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1H8l-4.3 3.6A.5.5 0 0 1 3 21.2V4a1 1 0 0 1 1-1z" />
                                    </svg>
                                    Message subadmin
                                </button>

                            </div>

                        </div>
                    </div>
                )}

            </main>

        </div>
    );
}