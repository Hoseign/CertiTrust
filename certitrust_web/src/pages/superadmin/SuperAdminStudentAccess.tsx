import { useEffect, useMemo, useState } from "react";
import { useParams } from "react-router-dom";
import SuperAdminSideBar from "@/Components/Organisms/SuperAdminSideBar";
import CertiTrustLoadingIndicator from "@/Components/Atoms/CertiTrustLoadingIndicator";
import RecordFilterBar, { type RecordFilterValues } from "@/Components/Molecules/RecordFilterBar";
import { listUniversityStudents, listUniversities, setUniversityAccess } from "../../services/adminApi";
import { updateStudentAccess as updateStudentAccessApi } from "../../services/certitrustApi";
import { getAcademicLevel } from "../../utils/academicLevel";

type Student = {
    id: string;
    name: string;
    studentId: string;
    program: string;
    degreeLevel: string;
    email: string;
    level: string;
    year: string;
    universityCode: string;
    frozen: boolean;
    canManageAccess: boolean;
    freezeOwnerEmail?: string;
};

export default function SuperAdminStudentAccess() {
    const { code } = useParams<{ code: string }>();
    const universityCode = (code ?? "").toUpperCase();
    const [students, setStudents] = useState<Student[]>([]);
    const [universityName, setUniversityName] = useState(universityCode);
    const [universityFrozen, setUniversityFrozenState] = useState(false);
    const [canManageUniversityFreeze, setCanManageUniversityFreeze] = useState(true);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState("");
    const [filters, setFilters] = useState<RecordFilterValues>({
        academicLevel: "",
        program: "",
        year: "",
        search: "",
    });
    const [openIds, setOpenIds] = useState<string[]>([]);
    const [menuId, setMenuId] = useState<string | null>(null);

    const refresh = async (silent = false) => {
        if (!silent) setLoading(true);
        try {
            const [accessResponse, universities] = await Promise.all([
                listUniversityStudents(universityCode),
                listUniversities(),
            ]);
            const university = universities.find((item) => item.code === universityCode);
            setUniversityName(university?.university_name || universityCode);
            setUniversityFrozenState(Boolean(accessResponse.university_students_frozen));
            setCanManageUniversityFreeze(accessResponse.can_manage_university_freeze !== false);
            setStudents(accessResponse.data.map((record) => {
                const credentials = Array.isArray(record.credentials) ? record.credentials : [];
                const latestCredential = credentials[0] as Record<string, unknown> | undefined;
                const degree = String(record.degree || "Credential not recorded");
                return {
                    id: String(record.id),
                    name: String(record.name || "Student"),
                    email: String(record.email || ""),
                    studentId: String(record.student_id || "Not recorded"),
                    program: degree,
                    degreeLevel: `Credential #${latestCredential?.degree_number || 1}`,
                    level: getAcademicLevel(degree),
                    year: String(record.batch_year || "Unknown"),
                    universityCode,
                    frozen: Boolean(record.is_frozen),
                    canManageAccess: record.can_manage_access !== false,
                    freezeOwnerEmail: record.freeze_owner_email as string | undefined,
                };
            }));
            setError("");
        } catch (requestError) {
            const message = (requestError as { response?: { data?: { message?: string } } })
                .response?.data?.message;
            setError(message || "Unable to load student access records.");
        } finally {
            if (!silent) setLoading(false);
        }
    };

    useEffect(() => {
        void refresh();
        const timer = window.setInterval(() => void refresh(true), 5000);
        return () => window.clearInterval(timer);
    }, [universityCode]);

    const universityStudents = useMemo(
        () => students.filter((s) => s.universityCode === universityCode),
        [students, universityCode]
    );

    const years = useMemo(
        () => Array.from(new Set(universityStudents.map((student) => student.year)))
            .filter((year) => year !== "Unknown")
            .sort((a, b) => b.localeCompare(a)),
        [universityStudents],
    );
    const programs = useMemo(
        () => Array.from(new Set(universityStudents.map((student) => student.program)))
            .filter((program) => program !== "Credential not recorded")
            .sort((a, b) => a.localeCompare(b)),
        [universityStudents],
    );

    const filtered = useMemo(() => {
        const q = filters.search.trim().toLowerCase();

        return universityStudents.filter((s) => {
            const matchesYear = !filters.year || s.year === filters.year;
            const matchesProgram = !filters.program || s.program === filters.program;
            const matchesLevel = !filters.academicLevel || s.level === filters.academicLevel;
            const matchesSearch =
                q === "" ||
                [s.name, s.studentId, s.program, s.email].join(" ").toLowerCase().includes(q);

            return matchesYear && matchesProgram && matchesLevel && matchesSearch;
        });
    }, [universityStudents, filters]);

    const toggleOpen = (id: string) => {
        setOpenIds((prev) =>
            prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]
        );
    };

    const setFrozen = async (id: string, frozen: boolean) => {
        try {
            await updateStudentAccessApi(Number(id), frozen);
            await refresh(true);
        } catch (requestError) {
            const message = (requestError as { response?: { data?: { message?: string } } })
                .response?.data?.message;
            setError(message || "Unable to update student access.");
        }
    };

    const setUniversityFrozen = async (frozen: boolean) => {
        try {
            await setUniversityAccess(universityCode, "students", frozen);
            await refresh(true);
        } catch (requestError) {
            const message = (requestError as { response?: { data?: { message?: string } } })
                .response?.data?.message;
            setError(message || "Unable to update university student access.");
        }
    };

    return (
        <div className="flex min-h-screen bg-[#F5F7FB]">

            <SuperAdminSideBar />

            <main className="flex-1 min-w-0 h-screen overflow-y-auto p-6 md:p-10">

                <div className="max-w-3xl mx-auto">

                    {!universityCode ? (
                        <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-8 text-center text-gray-500">
                            University not found.
                        </div>
                    ) : (
                        <>
                            {/* HEADER */}
                            <h1 className="text-3xl font-extrabold text-[#0A192F] leading-tight">
                                {universityName} students
                            </h1>

                            <p className="text-gray-500 mt-4 mb-8 leading-7">
                                Search and filter student accounts at this university.
                                Student freeze controls are available from each account
                                menu.
                            </p>
                            {error && <p role="alert" className="mb-5 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</p>}

                            <div className="mb-8 flex flex-wrap items-center justify-between gap-4 rounded-xl border border-slate-200 bg-white p-4">
                                <div>
                                    <p className="font-bold text-[#0A192F]">University-wide student access</p>
                                    <p className="mt-1 text-sm text-slate-500">{universityFrozen ? "Frozen" : "Active"}</p>
                                </div>
                                <button type="button" disabled={!canManageUniversityFreeze} onClick={() => void setUniversityFrozen(!universityFrozen)} className="min-h-10 rounded-lg bg-[#0A192F] px-4 font-semibold text-white disabled:cursor-not-allowed disabled:opacity-50">
                                    {universityFrozen ? "Restore all students" : "Freeze all students"}
                                </button>
                            </div>

                            <RecordFilterBar
                                value={filters}
                                onChange={setFilters}
                                programs={programs}
                                years={years}
                                searchPlaceholder="Search students by name, ID, email, or program..."
                            />

                            {/* STUDENTS */}
                            {loading ? <CertiTrustLoadingIndicator size={28} message="Loading students..." className="w-full py-8 text-sm text-slate-500" /> : <div className="space-y-4">

                                {filtered.map((s) => {
                                    const isOpen = openIds.includes(s.id);

                                    return (
                                        <div
                                            key={s.id}
                                            className="bg-[#F3F5F9] rounded-2xl border border-gray-200 shadow-md"
                                        >

                                            <button
                                                type="button"
                                                onClick={() => toggleOpen(s.id)}
                                                aria-expanded={isOpen}
                                                className="w-full flex items-center justify-between gap-4 px-6 py-5 text-left rounded-2xl hover:bg-[#E9EEF6] transition-colors"
                                            >
                                                <span className="flex items-center gap-5 min-w-0">

                                                    <span className="text-[#0F9D8A] shrink-0">
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
                                                            <path d="M22 10L12 5 2 10l10 5 10-5z" />
                                                            <path d="M6 12v5c3 3 9 3 12 0v-5" />
                                                        </svg>
                                                    </span>

                                                    <span className="min-w-0">
                                                        <span className="block text-xl font-semibold text-[#0A192F] truncate">
                                                            {s.name}
                                                        </span>

                                                        <span className="block text-[17px] text-[#0A192F]">
                                                            Student ID: {s.studentId}
                                                        </span>
                                                    </span>

                                                </span>

                                                <span
                                                    className={`shrink-0 transition-transform duration-300 ${isOpen ? "rotate-180 text-[#0A3A6B]" : "text-[#333F4F]"
                                                        }`}
                                                >
                                                    <svg
                                                        width="26"
                                                        height="26"
                                                        viewBox="0 0 24 24"
                                                        fill="none"
                                                        stroke="currentColor"
                                                        strokeWidth="2.5"
                                                        strokeLinecap="round"
                                                        strokeLinejoin="round"
                                                    >
                                                        <polyline points="6 9 12 15 18 9" />
                                                    </svg>
                                                </span>
                                            </button>

                                            {isOpen && (
                                                <div className="px-6 pb-4">

                                                    <div className="pl-1 text-[17px] text-[#0A192F] leading-8">
                                                        <p>{s.email}</p>
                                                        <p>
                                                            {s.degreeLevel}: {s.program} (
                                                            {s.level === "masters"
                                                                ? "Master's Degree"
                                                                : s.level === "doctorate"
                                                                    ? "Doctorate / Ph.D."
                                                                    : s.level === "bachelors"
                                                                        ? "Undergraduate / Bachelor's"
                                                                        : "Other"})
                                                        </p>
                                                        <p>Batch: {s.year}</p>
                                                    </div>

                                                    <div className="relative flex justify-end mt-8">

                                                        <button
                                                            type="button"
                                                            aria-label="Student account menu"
                                                            aria-haspopup="menu"
                                                            aria-expanded={menuId === s.id}
                                                            onClick={() =>
                                                                setMenuId(menuId === s.id ? null : s.id)
                                                            }
                                                            className="p-2 rounded-lg text-[#0A192F] hover:bg-gray-200/70 transition-colors"
                                                        >
                                                            <svg
                                                                width="26"
                                                                height="26"
                                                                viewBox="0 0 24 24"
                                                                fill="currentColor"
                                                            >
                                                                <circle cx="12" cy="5" r="2" />
                                                                <circle cx="12" cy="12" r="2" />
                                                                <circle cx="12" cy="19" r="2" />
                                                            </svg>
                                                        </button>

                                                        {menuId === s.id && (
                                                            <>
                                                                <div
                                                                    className="fixed inset-0 z-10"
                                                                    onClick={() => setMenuId(null)}
                                                                />

                                                                <div
                                                                    role="menu"
                                                                    className="absolute right-0 bottom-full mb-1 z-20 w-64 bg-white rounded-xl border border-gray-200 shadow-xl py-2"
                                                                >
                                                                    <button
                                                                        type="button"
                                                                        role="menuitem"
                                                                        disabled={s.frozen || !s.canManageAccess}
                                                                        onClick={() => {
                                                                            void setFrozen(s.id, true);
                                                                            setMenuId(null);
                                                                        }}
                                                                        className="w-full text-left px-4 py-3 text-sm font-semibold text-red-600 hover:bg-gray-50 transition-colors disabled:text-gray-300 disabled:hover:bg-transparent disabled:cursor-not-allowed"
                                                                    >
                                                                        Freeze student access
                                                                    </button>
                                                                    <button type="button" role="menuitem" disabled={!s.frozen || !s.canManageAccess} onClick={() => { void setFrozen(s.id, false); setMenuId(null); }} className="w-full text-left px-4 py-3 text-sm font-semibold text-emerald-700 hover:bg-gray-50 disabled:text-gray-300 disabled:hover:bg-transparent disabled:cursor-not-allowed">
                                                                        Restore student access
                                                                    </button>
                                                                    {s.freezeOwnerEmail && <p className="px-4 py-2 text-xs text-slate-500">Frozen by {s.freezeOwnerEmail}</p>}
                                                                </div>
                                                            </>
                                                        )}

                                                    </div>
                                                </div>
                                            )}

                                        </div>
                                    );
                                })}

                                {filtered.length === 0 && (
                                    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-8 text-center text-gray-500">
                                        No students found.
                                    </div>
                                )}

                            </div>}
                        </>
                    )}

                </div>

            </main>

        </div>
    );
}