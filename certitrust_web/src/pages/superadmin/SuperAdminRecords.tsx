import { useMemo, useState } from "react";
import SuperAdminSideBar from "@/Components/Organisms/SuperAdminSideBar";
import CertiTrustLoadingIndicator from "@/Components/Atoms/CertiTrustLoadingIndicator";
import RecordFilterBar, { type RecordFilterValues } from "@/Components/Molecules/RecordFilterBar";
import StudentCredentialGroups from "@/Components/Organisms/StudentCredentialGroups";
import { useCertificates } from "../../hooks/useCertificates";
import { getAcademicLevel } from "../../utils/academicLevel";

export default function SuperAdminRecords() {
  const [filters, setFilters] = useState<RecordFilterValues>({
    academicLevel: "",
    program: "",
    year: "",
    search: "",
    university: "",
    status: "",
  });
  const { certificates, loading, error } = useCertificates();
  const years = useMemo(
    () => Array.from(new Set(certificates.map((record) => record.issue_date.slice(0, 4))))
      .filter((year) => /^\d{4}$/.test(year))
      .sort((a, b) => b.localeCompare(a)),
    [certificates],
  );
  const programs = useMemo(
    () => Array.from(new Set(certificates.map((record) => record.degree).filter(Boolean)))
      .sort((a, b) => a.localeCompare(b)),
    [certificates],
  );
  const universities = useMemo(
    () => Array.from(new Set(certificates.map((record) => record.university_code).filter(Boolean)))
      .sort()
      .map((code) => ({ value: code, label: code })),
    [certificates],
  );
  const statuses = useMemo(
    () => Array.from(new Set(certificates.map((record) => record.status).filter(Boolean))).sort(),
    [certificates],
  );
  const filtered = useMemo(() => {
    const query = filters.search.trim().toLowerCase();
    return certificates.filter((record) => {
      const matchesQuery = !query || [
        record.student_name,
        record.student_id,
        record.student_email,
        record.degree,
        record.certificate_code,
        record.cert_hash,
      ].some((value) => value?.toLowerCase().includes(query));
      return matchesQuery &&
        (!filters.year || record.issue_date.slice(0, 4) === filters.year) &&
        (!filters.program || record.degree === filters.program) &&
        (!filters.academicLevel || getAcademicLevel(record.degree, record.degree_number ?? 1) === filters.academicLevel) &&
        (!filters.university || record.university_code === filters.university) &&
        (!filters.status || record.status === filters.status);
    });
  }, [certificates, filters]);

  return (
    <div className="min-h-screen flex bg-[#F5F8FC]">
      <SuperAdminSideBar />
      <main className="flex-1 min-w-0 min-h-screen p-4 sm:p-8">
        <div className="mx-auto max-w-6xl">
          <header className="mb-8">
            <p className="text-sm font-semibold text-[#2563EB] mb-2">Super Admin</p>
            <h1 className="text-3xl font-extrabold text-[#0A192F]">Certificate Records</h1>
            <p className="text-gray-500 mt-2">Search and review student credentials from all universities.</p>
          </header>
          <RecordFilterBar
            value={filters}
            onChange={setFilters}
            programs={programs}
            years={years}
            universities={universities}
            statuses={statuses}
          />
          {error && <p role="alert" className="mb-5 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</p>}
          {loading ? (
            <CertiTrustLoadingIndicator size={28} message="Loading records..." className="w-full py-6 text-sm text-slate-500" />
          ) : (
            <div className="mt-6 rounded-xl bg-white px-4 shadow-sm sm:px-6">
              <StudentCredentialGroups
                records={filtered}
                masterRecords={certificates}
                showStudentMasterQr
                emptyMessage="No records match these filters."
              />
            </div>
          )}
        </div>
      </main>
    </div>
  );
}
