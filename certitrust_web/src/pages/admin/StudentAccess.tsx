import { useEffect, useMemo, useState } from "react";
import Sidebar from "@/Components/Organisms/Sidebar";
import CertiTrustLoadingIndicator from "@/Components/Atoms/CertiTrustLoadingIndicator";
import RecordFilterBar, { type RecordFilterValues } from "@/Components/Molecules/RecordFilterBar";
import { deleteStudent, listUniversityStudents } from "../../services/adminApi";
import { getAcademicLevel } from "../../utils/academicLevel";

type Student = {
    id: number;
    name: string;
    email: string;
    student_id?: string;
    degree?: string;
    batch_year?: string;
    credentials?: {
        degree?: string;
        degree_number?: number;
        certificate_code?: string;
        cert_hash?: string;
    }[];
    degree_number?: number;
    student_removal_status?: string | null;
};

export default function StudentAccess() {
    const [students, setStudents] = useState<Student[]>([]);
    const [filters, setFilters] = useState<RecordFilterValues>({
        academicLevel: "",
        program: "",
        year: "",
        search: "",
    });
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

    const programs = useMemo(
        () => Array.from(new Set(students.map((student) => student.degree).filter(Boolean)))
            .filter((degree): degree is string => Boolean(degree))
            .sort((a, b) => a.localeCompare(b)),
        [students],
    );
    const years = useMemo(
        () => Array.from(new Set(students.map((student) => student.batch_year)
            .filter((year): year is string => Boolean(year))))
            .sort((a, b) => b.localeCompare(a)),
        [students],
    );
    const filtered = useMemo(() => {
        const query = filters.search.trim().toLowerCase();
        return students.filter((student) => {
            const degreeNumber = student.degree_number ??
                Math.max(1, ...(student.credentials ?? []).map((credential) => credential.degree_number ?? 1));
            const matchesLevel = !filters.academicLevel ||
                getAcademicLevel(student.degree || "", degreeNumber) === filters.academicLevel;
            const matchesProgram = !filters.program || student.degree === filters.program;
            const matchesYear = !filters.year || student.batch_year === filters.year;
            const matchesSearch = !query || [
                student.name,
                student.email,
                student.student_id,
                student.degree,
                ...(student.credentials ?? []).flatMap((credential) => [
                    credential.certificate_code,
                    credential.cert_hash,
                ]),
            ].some((value) => String(value ?? "").toLowerCase().includes(query));
            return matchesLevel && matchesProgram && matchesYear && matchesSearch;
        });
    }, [students, filters]);

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
            await refresh();
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
                        </section>

                        <RecordFilterBar
                            value={filters}
                            onChange={setFilters}
                            programs={programs}
                            years={years}
                            searchPlaceholder="Search students by name, ID, email, or program..."
                        />

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
                                        {student.student_removal_status === "pending" && (
                                            <p className="mt-2 text-sm font-semibold text-amber-700">Removal request pending Super Admin approval</p>
                                        )}
                                        {student.student_removal_status === "rejected" && (
                                            <p className="mt-2 text-sm font-semibold text-slate-500">Previous removal request rejected</p>
                                        )}
                                    </div>
                                    <button type="button" onClick={() => void requestRemoval(student)} disabled={workingId !== null || student.student_removal_status === "pending"} className="min-h-10 rounded-lg border border-red-300 px-4 font-bold text-red-700 hover:bg-red-50 disabled:opacity-50">
                                        {workingId === student.id ? "Sending..." : student.student_removal_status === "pending" ? "Request pending" : "Request removal"}
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
