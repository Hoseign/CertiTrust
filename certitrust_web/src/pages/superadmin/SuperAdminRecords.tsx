import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import SuperAdminSideBar from "@/Components/Organisms/SuperAdminSideBar";
import CertiTrustLoadingIndicator from "@/Components/Atoms/CertiTrustLoadingIndicator";
import RecordFilterBar, { type RecordFilterValues } from "@/Components/Molecules/RecordFilterBar";
import { useCertificates } from "../../hooks/useCertificates";
import { getAcademicLevel } from "../../utils/academicLevel";

type RecordItem = {
  id: string;
  studentName: string;
  studentId: string;
  program: string;
  degreeNumber: string;
  email: string;
  certificateCode: string;
  issueDate: string;
  published: string;
  status: string;
  year: string;
  blockchainStatus: string;
  universityCode: string;
  certHash: string;
};

export default function SuperAdminRecords() {
  const [filters, setFilters] = useState<RecordFilterValues>({
    academicLevel: "",
    program: "",
    year: "",
    search: "",
    university: "",
    status: "",
  });
  const [openIds, setOpenIds] = useState<string[]>([]);
  const { certificates: apiRecords, loading, error } = useCertificates();
  const records: RecordItem[] = apiRecords.map((record) => ({
    id: String(record.id),
    studentName: record.student_name,
    studentId: record.student_id,
    program: record.degree,
    degreeNumber: String(record.degree_number ?? 1),
    email: record.student_email,
    certificateCode: record.certificate_code,
    issueDate: record.issue_date,
    published: record.created_at || record.issue_date,
    status: record.status,
    year: record.issue_date.slice(0, 4),
    blockchainStatus: record.blockchain_status || "not_configured",
    universityCode: record.university_code || "",
    certHash: record.cert_hash,
  }));

  const years = useMemo(
    () => Array.from(new Set(records.map((r) => r.year))).sort((a, b) => b.localeCompare(a)),
    [records]
  );
  const programs = useMemo(
    () => Array.from(new Set(records.map((record) => record.program))).sort((a, b) => a.localeCompare(b)),
    [records],
  );
  const universities = useMemo(
    () => Array.from(new Set(records.map((record) => record.universityCode).filter(Boolean)))
      .sort()
      .map((code) => ({ value: code, label: code })),
    [records],
  );
  const statuses = useMemo(
    () => Array.from(new Set(records.map((record) => record.status).filter(Boolean))).sort(),
    [records],
  );

  const filtered = useMemo(() => {
    const q = filters.search.trim().toLowerCase();

    return records.filter((r) => {
      const matchesYear = !filters.year || r.year === filters.year;
      const matchesProgram = !filters.program || r.program === filters.program;
      const matchesLevel = !filters.academicLevel ||
        getAcademicLevel(r.program, Number(r.degreeNumber)) === filters.academicLevel;
      const matchesUniversity = !filters.university || r.universityCode === filters.university;
      const matchesStatus = !filters.status || r.status === filters.status;
      const matchesSearch =
        q === "" ||
        [r.studentName, r.studentId, r.program, r.email, r.certificateCode, r.certHash]
          .join(" ")
          .toLowerCase()
          .includes(q);

      return matchesYear && matchesProgram && matchesLevel &&
        matchesUniversity && matchesStatus && matchesSearch;
    });
  }, [records, filters]);

  const groups = useMemo(
    () =>
      years
        .map((year) => ({
          year,
          items: filtered.filter((r) => r.year === year),
        }))
        .filter((g) => g.items.length > 0),
    [years, filtered]
  );

  const toggle = (id: string) => {
    setOpenIds((prev) =>
      prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]
    );
  };

  return (
    <div className="min-h-screen flex bg-[#F5F8FC]">

      <SuperAdminSideBar />

      {/* MAIN CONTENT */}
      <main className="flex-1 min-w-0 min-h-screen p-8">

        <div className="mx-auto max-w-6xl">

          {/* HEADER */}
          <div className="mb-8">
            <p className="text-sm font-semibold text-[#2563EB] mb-2">
              Super Admin
            </p>

            <h1 className="text-3xl font-extrabold text-[#0A192F]">
              Certificate Records
            </h1>

            <p className="text-gray-500 mt-2">
              View and monitor academic credentials from all universities.
            </p>
          </div>

          <RecordFilterBar
            value={filters}
            onChange={setFilters}
            programs={programs}
            years={years}
            universities={universities}
            statuses={statuses}
          />

          {/* RECORD GROUPS */}
          {error && <p role="alert" className="mb-5 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</p>}
          {loading && <CertiTrustLoadingIndicator size={28} message="Loading records..." className="w-full py-6 text-sm text-slate-500" />}
          {!loading && groups.length === 0 && (
            <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-8 text-center text-gray-500">
              No records found.
            </div>
          )}

          {groups.map((group) => (
            <section key={group.year} className="mb-8">

              <h3 className="text-xl font-bold text-[#0A192F] mb-4">
                {group.year}
              </h3>

              <div className="space-y-4">
                {group.items.map((r) => {
                  const isOpen = openIds.includes(r.id);

                  const details = [
                    { label: "Student name", value: r.studentName },
                    { label: "Student ID", value: r.studentId },
                    { label: "Course / program", value: r.program },
                    { label: "Degree number", value: r.degreeNumber },
                    { label: "Gmail", value: r.email },
                    { label: "Certificate code", value: r.certificateCode },
                    { label: "Issue date", value: r.issueDate },
                    { label: "Published", value: r.published },
                    { label: "Status", value: r.status },
                    { label: "Blockchain status", value: r.blockchainStatus },
                  ];

                  return (
                    <div
                      key={r.id}
                      className="bg-[#F1F4F9] rounded-2xl shadow-md border border-gray-200 overflow-hidden"
                    >

                      {/* HEADER (always visible) */}
                      <button
                        type="button"
                        onClick={() => toggle(r.id)}
                        aria-expanded={isOpen}
                        className="w-full flex items-center justify-between gap-4 px-6 py-5 text-left hover:bg-[#E9EEF6] transition-colors"
                      >
                        <span className="flex items-center gap-4 min-w-0">
                          <span className="text-[#0A3A6B] shrink-0">
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
                              <path d="M22 10L12 5 2 10l10 5 10-5z" />
                              <path d="M6 12v5c3 3 9 3 12 0v-5" />
                            </svg>
                          </span>

                          <span className="text-lg font-bold text-[#0A192F] truncate">
                            {r.studentName}
                          </span>
                        </span>

                        <span
                          className={`text-[#0A3A6B] shrink-0 transition-transform duration-300 ${isOpen ? "rotate-180" : ""
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

                      {/* FULL DETAILS (only when opened) */}
                      {isOpen && (
                        <div className="px-6 pb-6">

                          <dl className="space-y-4 mt-2">
                            {details.map((d) => (
                              <div
                                key={d.label}
                                className="grid grid-cols-[170px_1fr] gap-4 text-[15px]"
                              >
                                <dt className="font-bold text-[#0A192F]">
                                  {d.label}
                                </dt>

                                <dd className="text-[#0A192F] break-words">
                                  {d.value}
                                </dd>
                              </div>
                            ))}
                          </dl>

                          <div className="flex flex-col items-center gap-5 mt-8">

                            <Link
                              to="/superadmin/verify"
                              className="inline-flex items-center gap-2 font-semibold text-[#0A3A6B] hover:underline"
                            >
                              <svg
                                width="22"
                                height="22"
                                viewBox="0 0 24 24"
                                fill="none"
                                stroke="currentColor"
                                strokeWidth="2"
                                strokeLinecap="round"
                                strokeLinejoin="round"
                              >
                                <path d="M12 2l8 3v6c0 5-3.5 9-8 11-4.5-2-8-6-8-11V5l8-3z" />
                                <polyline points="8.5 12 11 14.5 15.5 9.5" />
                              </svg>
                              Verify this record
                            </Link>

                            <button
                              type="button"
                              className="inline-flex items-center gap-2 font-semibold text-[#0A3A6B] hover:underline"
                            >
                              <svg
                                width="22"
                                height="22"
                                viewBox="0 0 24 24"
                                fill="none"
                                stroke="currentColor"
                                strokeWidth="2"
                                strokeLinecap="round"
                                strokeLinejoin="round"
                              >
                                <circle cx="12" cy="9" r="6" />
                                <polygon points="12 6.5 12.9 8.4 15 8.7 13.5 10.1 13.9 12.2 12 11.2 10.1 12.2 10.5 10.1 9 8.7 11.1 8.4 12 6.5" />
                                <path d="M8.5 14L7 22l5-3 5 3-1.5-8" />
                              </svg>
                              View Your Diploma
                            </button>

                          </div>
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            </section>
          ))}

        </div>
      </main>
    </div>
  );
}