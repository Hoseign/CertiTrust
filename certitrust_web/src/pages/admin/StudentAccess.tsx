import { useEffect, useMemo, useState } from "react";
import Sidebar from "../../components/Sidebar";
import CertiTrustLoadingIndicator from "../../components/CertiTrustLoadingIndicator";
import { deleteStudent, listUniversityStudents } from "../../services/adminApi";

type Student = {
    id: number;
    name: string;
    email: string;
    student_id?: string;
    degree?: string;
    batch_year?: string;
    credentials?: { degree?: string; certificate_code?: string }[];
};

export default function StudentAccess() {
    const [students, setStudents] = useState<Student[]>([]);
    const [search, setSearch] = useState("");
    const [isLoading, setIsLoading] = useState(true);
    const [workingId, setWorkingId] = useState<number | null>(null);
    const [error, setError] = useState("");
    const [message, setMessage] = useState("");

    const refresh = async () => {
        setIsLoading(true);
        try {
            const response = await listUniversityStudents<Student>();
            setStudents(response.data);
            setError("");
        } catch (requestError) {
            const responseMessage = (requestError as { response?: { data?: { message?: string } } })
                .response?.data?.message;
            setError(responseMessage || "Unable to load student accounts.");
        } finally {
            setIsLoading(false);
        }
    };

    useEffect(() => {
        void refresh();
    }, []);

    const filtered = useMemo(() => {
        const query = search.trim().toLowerCase();
        return students.filter((student) => !query || [
            student.name,
            student.email,
            student.student_id,
            student.degree,
        ].some((value) => String(value ?? "").toLowerCase().includes(query)));
    }, [students, search]);

    const requestRemoval = async (student: Student) => {
        if (!window.confirm(
            `Send a student removal request for ${student.name}? The account remains active until the Super Admin approves it. If approved, the account and credentials move to Junk.`,
        )) return;
        setWorkingId(student.id);
        setError("");
        setMessage("");
        try {
            const result = await deleteStudent(student.id);
            setMessage(String(result.message || "Removal request sent to the Super Admin."));
        } catch (requestError) {
            const responseMessage = (requestError as { response?: { data?: { message?: string } } })
                .response?.data?.message;
            setError(responseMessage || "Unable to send the student removal request.");
        } finally {
            setWorkingId(null);
        }
    };

    return (
        <div className="min-h-screen bg-[#FAFAFD]">
            <div className="min-h-screen grid grid-cols-1 md:grid-cols-[286px_1fr]">
                <Sidebar />
                <main className="h-screen min-w-0 overflow-y-auto p-5 md:p-10">
                    <div className="mx-auto max-w-5xl">
                        <h1 className="text-3xl font-extrabold text-[#0A192F]">Student Accounts</h1>
                        <p className="mt-2 text-slate-600">Review your university’s student accounts. Removal requires Super Admin approval and approved records are sent to the shared recycle bin.</p>
                        {error && <p role="alert" className="mt-5 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</p>}
                        {message && <p role="status" className="mt-5 rounded-lg border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800">{message}</p>}

                        <section className="mt-6 rounded-2xl border border-slate-200 bg-white p-5">
                            <div className="flex flex-wrap items-center justify-between gap-3">
                                <h2 className="text-lg font-bold text-[#0A192F]">Students ({students.length})</h2>
                                <button type="button" onClick={() => void refresh()} disabled={isLoading} className="min-h-10 rounded-lg border border-slate-300 px-4 font-semibold text-slate-700 disabled:opacity-50">Refresh</button>
                            </div>
                            <input value={search} onChange={(event) => setSearch(event.target.value)} aria-label="Search students" placeholder="Search name, email, student ID or course" className="mt-4 min-h-11 w-full rounded-lg border border-slate-300 px-3 outline-none focus:border-blue-600" />
                        </section>

                        <section className="mt-5 divide-y divide-slate-200 rounded-2xl border border-slate-200 bg-white">
                            {isLoading ? (
                                <CertiTrustLoadingIndicator size={28} message="Loading students..." className="w-full py-10 text-slate-500" />
                            ) : filtered.length === 0 ? (
                                <p className="p-8 text-center text-slate-500">{students.length ? "No students match your search." : "No student accounts found."}</p>
                            ) : filtered.map((student) => (
                                <article key={student.id} className="flex flex-wrap items-center justify-between gap-4 p-5">
                                    <div>
                                        <h3 className="font-bold text-[#0A192F]">{student.name}</h3>
                                        <p className="mt-1 text-sm text-slate-600">{student.email}</p>
                                        <p className="mt-1 text-sm text-slate-500">
                                            ID: {student.student_id || "Not recorded"} · {student.degree || "No course recorded"} · {student.credentials?.length || 0} credential(s)
                                        </p>
                                    </div>
                                    <button type="button" onClick={() => void requestRemoval(student)} disabled={workingId !== null} className="min-h-10 rounded-lg border border-red-300 px-4 font-bold text-red-700 hover:bg-red-50 disabled:opacity-50">
                                        {workingId === student.id ? "Sending..." : "Request removal"}
                                    </button>
                                </article>
                            ))}
                        </section>
                    </div>
                </main>
            </div>
        </div>
    );
}
