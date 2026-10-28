
import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import StudentSidebar from "@/Components/Organisms/StudentSidebar";
import CertiTrustLoadingIndicator from "@/Components/Atoms/CertiTrustLoadingIndicator";
import RecordFilterBar, { type RecordFilterValues } from "@/Components/Molecules/RecordFilterBar";
import StudentCredentialGroups from "@/Components/Organisms/StudentCredentialGroups";
import { useCertificates } from "../../hooks/useCertificates";
import { getAcademicLevel } from "../../utils/academicLevel";

export default function StudentRecords() {
    const navigate = useNavigate();
    const [filters, setFilters] = useState<RecordFilterValues>({
        academicLevel: "",
        program: "",
        year: "",
        search: "",
    });
    const [selectedCode, setSelectedCode] = useState<string | null>(null);
    const { certificates, loading, error } = useCertificates();
    const programs = useMemo(
        () => Array.from(new Set(certificates.map((certificate) => certificate.degree)))
            .filter(Boolean)
            .sort((a, b) => a.localeCompare(b)),
        [certificates],
    );
    const years = useMemo(
        () => Array.from(new Set(certificates.map((certificate) => certificate.issue_date.slice(0, 4))))
            .filter((year) => /^\d{4}$/.test(year))
            .sort((a, b) => b.localeCompare(a)),
        [certificates],
    );
    const filteredRecords = useMemo(() => {
        const query = filters.search.trim().toLowerCase();
        return certificates.filter((certificate) => {
            const matchesLevel = !filters.academicLevel ||
                getAcademicLevel(certificate.degree, certificate.degree_number ?? 1) === filters.academicLevel;
            const matchesProgram = !filters.program || certificate.degree === filters.program;
            const matchesYear = !filters.year || certificate.issue_date.slice(0, 4) === filters.year;
            const matchesSearch = !query || [
                certificate.student_name,
                certificate.student_id,
                certificate.degree,
                certificate.student_email,
                certificate.certificate_code,
                certificate.cert_hash,
            ].some((value) => value?.toLowerCase().includes(query));
            return matchesLevel && matchesProgram && matchesYear && matchesSearch;
        });
    }, [certificates, filters]);
    const record = filteredRecords.find((certificate) => certificate.certificate_code === selectedCode)
        || filteredRecords[0];

    const handleVerify = () => {
        if (!record) return;
        navigate(
            `/certificate-verification?studentId=${encodeURIComponent(
                record.student_id
            )}&certificateId=${encodeURIComponent(
                record.certificate_code
            )}`
        );
    };

    const handleViewDiploma = () => {
        navigate("/portal");
    };

    return (
        <div className="min-h-screen bg-[#F4F7FB] md:flex">
            <StudentSidebar />

            <main className="min-w-0 flex-1 p-4 sm:p-6 lg:p-10 md:ml-64">
                <div className="mx-auto max-w-5xl">
                    {/* Page Header */}
                    <div className="mb-8">
                        <p className="mb-2 text-sm font-medium text-blue-600">
                            Student Portal
                        </p>

                        <h1 className="text-3xl font-bold text-[#0A192F]">
                            Certificate Records
                        </h1>

                        <p className="mt-2 text-gray-500">
                            View your academic credentials and their
                            verification status.
                        </p>
                    </div>

                    <RecordFilterBar
                        value={filters}
                        onChange={setFilters}
                        programs={programs}
                        years={years}
                        searchPlaceholder="Search credentials by student name, ID, or certificate hash..."
                    />

                    {/* Certificate Record */}
                    {loading ? <CertiTrustLoadingIndicator size={32} message="Loading your records..." className="w-full py-12 text-sm text-slate-500" /> : error ? (
                        <p role="alert" className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</p>
                    ) : record ? (
                        <StudentCredentialGroups records={filteredRecords} />
                    ) : (
                        <div className="rounded-2xl border border-gray-200 bg-white px-6 py-12 text-center shadow-sm">
                            <h2 className="text-lg font-semibold text-[#0A192F]">No matching credentials found</h2>
                            <p className="mt-2 text-sm text-gray-500">No certificate records match your search.</p>
                        </div>
                    )}

                    {false && !loading && !error && record ? (
                        <div className="overflow-hidden rounded-2xl border border-gray-200 bg-white shadow-sm">
                            {/* Record Header */}
                            <div className="flex flex-col gap-4 border-b border-gray-100 bg-gradient-to-r from-blue-50 to-white p-5 sm:flex-row sm:items-center sm:justify-between sm:p-7">
                                <div>
                                    <p className="mb-2 text-sm font-medium text-blue-600">
                                        Degree record
                                    </p>

                                    <h2 className="text-2xl font-bold text-[#0A192F]">
                                        {record.student_name}
                                    </h2>

                                    <p className="mt-1 text-sm text-gray-500">
                                        Academic Credential
                                    </p>
                                </div>

                                <span className="inline-flex w-fit items-center gap-2 rounded-full border border-green-200 bg-green-50 px-4 py-2 text-sm font-semibold text-green-700">
                                    <span className="h-2 w-2 rounded-full bg-green-500" />
                                    {record.status}
                                </span>
                            </div>

                            {/* Record Details */}
                            <div className="p-5 sm:p-7">
                                <h3 className="mb-5 text-lg font-semibold text-[#0A192F]">
                                    Certificate Information
                                </h3>

                                <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
                                    <Detail
                                        label="Student name"
                                        value={record.student_name}
                                    />

                                    <Detail
                                        label="Student ID"
                                        value={record.student_id}
                                    />

                                    <Detail
                                        label="Course / program"
                                        value={record.degree}
                                    />

                                    <Detail
                                        label="Degree number"
                                        value={String(record.degree_number ?? 1)}
                                    />

                                    <Detail
                                        label="Gmail"
                                        value={record.student_email}
                                    />

                                    <Detail
                                        label="Certificate code"
                                        value={record.certificate_code}
                                        copyable
                                    />

                                    <Detail
                                        label="Issue date"
                                        value={record.issue_date}
                                    />

                                    <Detail
                                        label="Published"
                                        value={record.created_at || record.issue_date}
                                    />
                                </div>

                                {/* Verification Status */}
                                <div className="mt-7 rounded-xl border border-green-100 bg-green-50 p-4">
                                    <div className="flex items-start gap-3">
                                        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-white text-xl text-green-600">
                                            ✓
                                        </span>

                                        <div>
                                            <p className="font-semibold text-green-800">
                                                Status: {record.status}
                                            </p>

                                            <p className="mt-1 text-sm leading-6 text-green-700">
                                                This record is marked as
                                                stored in your CertiTrust account.
                                            </p>
                                        </div>
                                    </div>
                                </div>

                                {/* Action Buttons */}
                                <div className="mt-7 grid grid-cols-1 gap-3 sm:grid-cols-2">
                                    <button
                                        type="button"
                                        onClick={handleVerify}
                                        className="flex items-center justify-center gap-2 rounded-xl bg-[#0A192F] px-5 py-3 font-semibold text-white transition hover:bg-blue-900 focus:outline-none focus:ring-2 focus:ring-blue-300"
                                    >
                                        <span>✓</span>
                                        Verify this record
                                    </button>

                                    <button
                                        type="button"
                                        onClick={handleViewDiploma}
                                        className="flex items-center justify-center gap-2 rounded-xl border border-blue-200 bg-white px-5 py-3 font-semibold text-blue-700 transition hover:bg-blue-50 focus:outline-none focus:ring-2 focus:ring-blue-200"
                                    >
                                        <span>▤</span>
                                        View Your Diploma
                                    </button>
                                </div>
                            </div>
                        </div>
                    ) : null}

                    {/* Footer */}
                    <p className="mt-8 text-center text-xs text-gray-400">
                        CertiTrust · Secure Academic Credential Verification
                    </p>
                </div>
            </main>

        </div>
    );
}

type DetailProps = {
    label: string;
    value: string;
    copyable?: boolean;
};

function Detail({ label, value, copyable = false }: DetailProps) {
    const [copied, setCopied] = useState(false);

    const handleCopy = async () => {
        try {
            await navigator.clipboard.writeText(value);
            setCopied(true);
            window.setTimeout(() => setCopied(false), 1500);
        } catch {
            setCopied(false);
        }
    };

    return (
        <div className="min-w-0 border-b border-gray-100 pb-4">
            <p className="mb-2 text-sm text-gray-500">{label}</p>

            <div className="flex items-center justify-between gap-3">
                <p className="break-words text-sm font-semibold text-[#0A192F] sm:text-base">
                    {value}
                </p>

                {copyable && (
                    <button
                        type="button"
                        onClick={handleCopy}
                        className="shrink-0 rounded-lg px-2 py-1 text-xs font-medium text-blue-600 transition hover:bg-blue-50"
                        title="Copy certificate code"
                    >
                        {copied ? "Copied!" : "Copy"}
                    </button>
                )}
            </div>
        </div>
    );
}
