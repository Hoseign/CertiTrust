import { useCallback, useEffect, useMemo, useState } from "react";
import SuperAdminSideBar from "../../components/SuperAdminSideBar";
import CertiTrustLoadingIndicator from "../../components/CertiTrustLoadingIndicator";
import {
    listDeletedSubadminUniversities,
    listUniversityStudents,
    permanentlyDeleteJunkStudent,
    permanentlyDeleteJunkUniversity,
    type DeletedSubadminUniversity,
} from "../../services/adminApi";

type StudentRecord = {
    id: number;
    name: string;
    email: string;
    student_id?: string;
    degree?: string;
    degrees?: string[];
    batch_year?: string;
    credentials?: { degree?: string; issue_date?: string; certificate_code?: string }[];
};

export default function SuperAdminJunk() {
    const [universities, setUniversities] = useState<DeletedSubadminUniversity[]>([]);
    const [selectedCode, setSelectedCode] = useState("");
    const [students, setStudents] = useState<StudentRecord[]>([]);
    const [search, setSearch] = useState("");
    const [selectedYear, setSelectedYear] = useState("all");
    const [selectedCourse, setSelectedCourse] = useState("all");
    const [isLoading, setIsLoading] = useState(true);
    const [isWorking, setIsWorking] = useState(false);
    const [error, setError] = useState("");
    const [message, setMessage] = useState("");
    const [studentToDelete, setStudentToDelete] = useState<StudentRecord | null>(null);
    const [isBulkDeleteOpen, setIsBulkDeleteOpen] = useState(false);
    const [bulkConfirmCode, setBulkConfirmCode] = useState("");

    const selectedUniversity = universities.find((item) => item.university_code === selectedCode);

    const refreshStudents = useCallback(async (code: string) => {
        if (!code) {
            setStudents([]);
            return;
        }
        const response = await listUniversityStudents<StudentRecord>(code);
        setStudents(response.data);
    }, []);

    useEffect(() => {
        let active = true;
        const load = async () => {
            try {
                setIsLoading(true);
                const items = await listDeletedSubadminUniversities();
                if (!active) return;
                setUniversities(items);
                setSelectedCode((current) =>
                    items.some((item) => item.university_code === current)
                        ? current
                        : items[0]?.university_code ?? "",
                );
                setError("");
            } catch (requestError) {
                if (!active) return;
                setError((requestError as { response?: { data?: { message?: string } } })
                    .response?.data?.message || "Unable to load Super Admin Junk.");
            } finally {
                if (active) setIsLoading(false);
            }
        };
        void load();
        return () => { active = false; };
    }, []);

    useEffect(() => {
        let active = true;
        setSelectedYear("all");
        setSelectedCourse("all");
        setSearch("");
        setMessage("");
        if (!selectedCode) {
            setStudents([]);
            return;
        }
        setIsLoading(true);
        listUniversityStudents<StudentRecord>(selectedCode)
            .then((response) => {
                if (active) setStudents(response.data);
            })
            .catch((requestError) => {
                if (active) {
                    setError((requestError as { response?: { data?: { message?: string } } })
                        .response?.data?.message || "Unable to load this university's student records.");
                }
            })
            .finally(() => { if (active) setIsLoading(false); });
        return () => { active = false; };
    }, [selectedCode]);

    const years = useMemo(
        () => [...new Set(students.map((student) => student.batch_year).filter(Boolean))].sort().reverse(),
        [students],
    );
    const courses = useMemo(
        () => [...new Set(students.flatMap((student) => student.degrees?.length ? student.degrees : [student.degree])
            .filter((degree): degree is string => Boolean(degree)))].sort(),
        [students],
    );
    const filteredStudents = useMemo(() => {
        const query = search.trim().toLowerCase();
        return students.filter((student) => {
            const studentCourses = student.degrees?.length ? student.degrees : [student.degree].filter(Boolean) as string[];
            const matchesSearch = !query || [
                student.name,
                student.email,
                student.student_id,
                ...studentCourses,
            ].some((value) => String(value ?? "").toLowerCase().includes(query));
            return matchesSearch
                && (selectedYear === "all" || student.batch_year === selectedYear)
                && (selectedCourse === "all" || studentCourses.includes(selectedCourse));
        });
    }, [students, search, selectedYear, selectedCourse]);

    const removeStudent = async (student: StudentRecord) => {
        if (!selectedCode) return;
        setIsWorking(true);
        setError("");
        setMessage("");
        try {
            const result = await permanentlyDeleteJunkStudent(selectedCode, student.id);
            await refreshStudents(selectedCode);
            setMessage(`${student.name} was removed. ${result.deleted_certificate_count} database certificate record(s) deleted.`);
            setStudentToDelete(null);
        } catch (requestError) {
            setError((requestError as { response?: { data?: { message?: string } } })
                .response?.data?.message || "Unable to delete this student record.");
        } finally {
            setIsWorking(false);
        }
    };

    const removeUniversityStudents = async () => {
        if (!selectedCode) return;
        setIsWorking(true);
        setError("");
        setMessage("");
        try {
            const result = await permanentlyDeleteJunkUniversity(selectedCode);
            await refreshStudents(selectedCode);
            setMessage(`${selectedCode} cleanup complete: ${result.deleted_student_count} student account(s) and ${result.deleted_certificate_count} database certificate record(s) permanently deleted.`);
            setIsBulkDeleteOpen(false);
            setBulkConfirmCode("");
        } catch (requestError) {
            setError((requestError as { response?: { data?: { message?: string } } })
                .response?.data?.message || "Unable to delete this university's student records.");
        } finally {
            setIsWorking(false);
        }
    };

    const handleUniversityChange = (code: string) => {
        setError("");
        setSelectedCode(code);
    };

    return (
        <div className="flex min-h-screen bg-[#F5F7FB]">
            <SuperAdminSideBar />
            <main className="h-screen min-w-0 flex-1 overflow-y-auto p-5 md:p-10">
                <div className="mx-auto max-w-5xl">
                    <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#2563EB]">Super Admin</p>
                    <h1 className="mt-2 text-3xl font-extrabold text-[#0A192F]">Junk</h1>
                    <p className="mt-3 max-w-3xl leading-7 text-slate-600">
                        Review student records from universities whose subadmin accounts were deleted. Select a university, filter its students by year or course, and permanently remove selected records.
                    </p>

                    <div className="mt-6 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm leading-6 text-amber-950">
                        Permanent cleanup removes student accounts and matching database certificate records. University registration and subadmin accounts are retained. Existing blockchain transactions are immutable and cannot be deleted.
                    </div>

                    {error && <p role="alert" className="mt-5 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</p>}
                    {message && <p role="status" className="mt-5 rounded-lg border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800">{message}</p>}

                    {isLoading && universities.length === 0 ? (
                        <CertiTrustLoadingIndicator size={32} message="Loading deleted subadmin records..." className="w-full mt-8 text-slate-500" />
                    ) : universities.length === 0 ? (
                        <section className="mt-8 rounded-2xl border border-slate-200 bg-white p-8 text-center">
                            <h2 className="text-xl font-bold text-[#0A192F]">Junk is empty</h2>
                            <p className="mt-2 text-slate-600">Deleted subadmin universities will appear here with their student records.</p>
                        </section>
                    ) : (
                        <>
                            <section className="mt-7 rounded-2xl border border-slate-200 bg-white p-5">
                                <label htmlFor="junk-university" className="mb-2 block text-sm font-bold text-slate-700">
                                    Select university
                                </label>
                                <select
                                    id="junk-university"
                                    value={selectedCode}
                                    onChange={(event) => handleUniversityChange(event.target.value)}
                                    className="min-h-12 w-full rounded-xl border border-slate-300 bg-white px-4 font-semibold text-[#0A192F] outline-none focus:border-blue-600 focus:ring-4 focus:ring-blue-100"
                                >
                                    {universities.map((university) => (
                                        <option key={university.university_code} value={university.university_code}>
                                            {university.university_name} ({university.university_code})
                                        </option>
                                    ))}
                                </select>
                                {selectedUniversity && (
                                    <p className="mt-3 text-sm text-slate-500">
                                        Deleted subadmins: {selectedUniversity.deleted_subadmins.map((admin) => admin.email).join(", ") || "Unknown"}
                                    </p>
                                )}
                            </section>

                            <section className="mt-6 rounded-2xl border border-slate-200 bg-white p-5 md:p-6">
                                <div className="flex flex-wrap items-center justify-between gap-4">
                                    <div>
                                        <h2 className="text-xl font-extrabold text-[#0A192F]">
                                            {selectedUniversity?.university_name || selectedCode} student records
                                        </h2>
                                        <p className="mt-1 text-sm text-slate-500">
                                            {students.length} student account(s)
                                        </p>
                                    </div>
                                    <button
                                        type="button"
                                        onClick={() => {
                                            setBulkConfirmCode("");
                                            setIsBulkDeleteOpen(true);
                                        }}
                                        disabled={isWorking || students.length === 0}
                                        className="min-h-11 rounded-xl border border-red-300 px-4 font-bold text-red-700 hover:bg-red-50 disabled:cursor-not-allowed disabled:opacity-50"
                                    >
                                        Delete all university student records
                                    </button>
                                </div>

                                <div className="mt-5 grid gap-3 md:grid-cols-3">
                                    <input
                                        value={search}
                                        onChange={(event) => setSearch(event.target.value)}
                                        placeholder="Search name, email, ID or course"
                                        aria-label="Search student records"
                                        className="min-h-11 rounded-lg border border-slate-300 px-3 outline-none focus:border-blue-600 md:col-span-1"
                                    />
                                    <select aria-label="Filter by year" value={selectedYear} onChange={(event) => setSelectedYear(event.target.value)} className="min-h-11 rounded-lg border border-slate-300 bg-white px-3">
                                        <option value="all">All years</option>
                                        {years.map((year) => <option key={year} value={year}>{year}</option>)}
                                    </select>
                                    <select aria-label="Filter by course" value={selectedCourse} onChange={(event) => setSelectedCourse(event.target.value)} className="min-h-11 rounded-lg border border-slate-300 bg-white px-3">
                                        <option value="all">All courses</option>
                                        {courses.map((course) => <option key={course} value={course}>{course}</option>)}
                                    </select>
                                </div>

                                {isLoading ? (
                                    <CertiTrustLoadingIndicator size={28} message="Loading university student records..." className="w-full py-8 text-slate-500" />
                                ) : filteredStudents.length === 0 ? (
                                    <p className="py-8 text-center text-slate-500">
                                        {students.length ? "No students match these filters." : "No student accounts remain for this university."}
                                    </p>
                                ) : (
                                    <div className="mt-5 divide-y divide-slate-100">
                                        {filteredStudents.map((student) => (
                                            <article key={student.id} className="flex flex-wrap items-center justify-between gap-4 py-4">
                                                <div className="min-w-0">
                                                    <h3 className="font-bold text-[#0A192F]">{student.name}</h3>
                                                    <p className="mt-1 break-all text-sm text-slate-600">{student.email}</p>
                                                    <p className="mt-1 text-sm text-slate-500">
                                                        ID: {student.student_id || "Not recorded"} · Year: {student.batch_year || "Unknown"}
                                                    </p>
                                                    <p className="mt-1 text-sm text-slate-500">
                                                        {(student.degrees?.length ? student.degrees : [student.degree].filter(Boolean)).join(" · ") || "No course recorded"} · {student.credentials?.length || 0} certificate record(s)
                                                    </p>
                                                </div>
                                                <button
                                                    type="button"
                                                    onClick={() => setStudentToDelete(student)}
                                                    disabled={isWorking}
                                                    className="min-h-10 rounded-lg border border-red-200 px-3 font-semibold text-red-700 hover:bg-red-50 disabled:opacity-50"
                                                >
                                                    Permanently delete
                                                </button>
                                            </article>
                                        ))}
                                    </div>
                                )}
                            </section>
                        </>
                    )}
                </div>
            </main>
            {studentToDelete && (
                <div className="fixed inset-0 z-50 grid place-items-center bg-slate-950/60 p-4">
                    <section
                        role="dialog"
                        aria-modal="true"
                        aria-labelledby="delete-student-title"
                        className="w-full max-w-lg rounded-2xl bg-white p-6 shadow-2xl"
                    >
                        <h2 id="delete-student-title" className="text-xl font-extrabold text-red-800">
                            Permanently delete student record?
                        </h2>
                        <p className="mt-3 leading-6 text-slate-700">
                            This removes <strong>{studentToDelete.name}</strong> ({studentToDelete.email}), their student account, and all matching database certificate records at {selectedCode}. Blockchain transactions cannot be erased.
                        </p>
                        <div className="mt-6 flex flex-wrap justify-end gap-3">
                            <button
                                type="button"
                                onClick={() => setStudentToDelete(null)}
                                disabled={isWorking}
                                className="min-h-11 rounded-lg border border-slate-300 px-4 font-semibold text-slate-700"
                            >
                                Cancel
                            </button>
                            <button
                                type="button"
                                onClick={() => void removeStudent(studentToDelete)}
                                disabled={isWorking}
                                className="min-h-11 rounded-lg bg-red-700 px-4 font-bold text-white disabled:opacity-60"
                            >
                                {isWorking ? "Deleting..." : "Permanently delete"}
                            </button>
                        </div>
                    </section>
                </div>
            )}
            {isBulkDeleteOpen && (
                <div className="fixed inset-0 z-50 grid place-items-center bg-slate-950/60 p-4">
                    <section
                        role="dialog"
                        aria-modal="true"
                        aria-labelledby="delete-university-title"
                        className="w-full max-w-lg rounded-2xl bg-white p-6 shadow-2xl"
                    >
                        <h2 id="delete-university-title" className="text-xl font-extrabold text-red-800">
                            Delete all student records for {selectedCode}?
                        </h2>
                        <p className="mt-3 leading-6 text-slate-700">
                            This permanently deletes every student account and database certificate record for this university. The university and subadmin registrations remain. Blockchain transactions cannot be erased.
                        </p>
                        <label htmlFor="confirm-university-code" className="mt-5 block text-sm font-bold text-slate-700">
                            Type {selectedCode} to confirm
                        </label>
                        <input
                            id="confirm-university-code"
                            value={bulkConfirmCode}
                            onChange={(event) => setBulkConfirmCode(event.target.value)}
                            autoComplete="off"
                            className="mt-2 min-h-11 w-full rounded-lg border border-slate-300 px-3"
                        />
                        <div className="mt-6 flex flex-wrap justify-end gap-3">
                            <button
                                type="button"
                                onClick={() => setIsBulkDeleteOpen(false)}
                                disabled={isWorking}
                                className="min-h-11 rounded-lg border border-slate-300 px-4 font-semibold text-slate-700"
                            >
                                Cancel
                            </button>
                            <button
                                type="button"
                                onClick={() => void removeUniversityStudents()}
                                disabled={isWorking || bulkConfirmCode.trim().toUpperCase() !== selectedCode}
                                className="min-h-11 rounded-lg bg-red-700 px-4 font-bold text-white disabled:cursor-not-allowed disabled:opacity-50"
                            >
                                {isWorking ? "Deleting..." : "Delete all records"}
                            </button>
                        </div>
                    </section>
                </div>
            )}
        </div>
    );
}
