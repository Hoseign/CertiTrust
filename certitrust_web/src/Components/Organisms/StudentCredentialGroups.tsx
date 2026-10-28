import { useMemo, useRef, useState } from "react";
import { QRCodeCanvas } from "qrcode.react";
import type { CertificateRecord } from "../../services/certitrustApi";

type Props = {
    records: CertificateRecord[];
    emptyMessage?: string;
};

function CredentialDetails({ record }: { record: CertificateRecord }) {
    const qrRef = useRef<HTMLDivElement>(null);
    const diplomaUrl = record.diploma_url || undefined;

    const downloadQr = () => {
        const canvas = qrRef.current?.querySelector("canvas");
        if (!canvas) return;
        const link = document.createElement("a");
        link.href = canvas.toDataURL("image/png");
        link.download = `${record.certificate_code}-qr.png`;
        link.click();
    };

    const downloadDiploma = () => {
        if (!diplomaUrl) return;
        const link = document.createElement("a");
        link.href = diplomaUrl;
        link.download = record.diploma_file_name || `${record.certificate_code}-diploma`;
        link.target = "_blank";
        link.rel = "noreferrer";
        link.click();
    };

    return (
        <div className="border-t border-slate-200 px-4 py-4 sm:px-5">
            <dl className="grid gap-x-6 gap-y-3 text-sm sm:grid-cols-2">
                <div><dt className="text-slate-500">Institution</dt><dd className="font-semibold">{record.university_name || record.university_code || "Institution unavailable"}</dd></div>
                <div><dt className="text-slate-500">Issue date</dt><dd>{record.issue_date}</dd></div>
                <div><dt className="text-slate-500">On-chain hash</dt><dd className="break-all font-mono text-xs">{record.cert_hash}</dd></div>
                <div><dt className="text-slate-500">Verification</dt><dd>{record.blockchain_status || record.status}</dd></div>
            </dl>
            {diplomaUrl && <img src={diplomaUrl} alt={`${record.degree} diploma`} className="mt-4 max-h-80 w-full border border-slate-200 bg-white object-contain" />}
            <div className="mt-4 flex flex-wrap gap-2">
                {diplomaUrl && <button type="button" onClick={downloadDiploma} className="min-h-9 rounded-md border border-slate-300 px-3 text-sm font-bold">Download Diploma</button>}
                <a href={`/public-verification?hash=${encodeURIComponent(record.cert_hash)}`} className="inline-flex min-h-9 items-center rounded-md border border-slate-300 px-3 text-sm font-bold">Verify on Chain</a>
                <button type="button" onClick={downloadQr} className="min-h-9 rounded-md border border-slate-300 px-3 text-sm font-bold">Download QR Code</button>
            </div>
            <div ref={qrRef} className="sr-only" aria-hidden="true"><QRCodeCanvas value={`${window.location.origin}/public-verification?hash=${encodeURIComponent(record.cert_hash)}`} size={240} /></div>
        </div>
    );
}

export default function StudentCredentialGroups({ records, emptyMessage = "No credential records found." }: Props) {
    const [openStudents, setOpenStudents] = useState<string[]>([]);
    const [openDegrees, setOpenDegrees] = useState<string[]>([]);
    const groups = useMemo(() => {
        const grouped = new Map<string, CertificateRecord[]>();
        records.forEach((record) => {
            const email = record.student_email?.trim().toLowerCase();
            const studentId = record.student_id?.trim().toLowerCase();
            const key = email ? `email:${email}` : `id:${studentId || record.student_name.toLowerCase()}`;
            grouped.set(key, [...(grouped.get(key) || []), record]);
        });
        return Array.from(grouped.entries());
    }, [records]);

    const toggle = (current: string[], key: string, update: (next: string[]) => void) =>
        update(current.includes(key) ? current.filter((value) => value !== key) : [...current, key]);

    if (!groups.length) return <p className="py-8 text-center text-sm text-slate-500">{emptyMessage}</p>;

    return (
        <div className="divide-y divide-slate-200 border-y border-slate-200">
            {groups.map(([studentKey, credentials]) => {
                const studentName = credentials[0].student_name || "Student";
                const degrees = new Map<string, CertificateRecord[]>();
                credentials.forEach((record) => {
                    const degreeKey = `${record.degree.toLowerCase()}|${record.university_code || ""}`;
                    degrees.set(degreeKey, [...(degrees.get(degreeKey) || []), record]);
                });
                const studentOpen = openStudents.includes(studentKey);
                const degreeCount = degrees.size;
                return <section key={studentKey}>
                    <button type="button" aria-expanded={studentOpen} onClick={() => toggle(openStudents, studentKey, setOpenStudents)} className="flex min-h-14 w-full items-center justify-between gap-4 py-3 text-left">
                        <span className="min-w-0"><span className="block truncate font-bold text-[#0A192F]">{studentName}</span><span className="mt-1 block text-xs text-slate-500">{credentials[0].student_id || "No student ID"} · {degreeCount} degree{degreeCount === 1 ? "" : "s"}</span></span>
                        <span className="shrink-0 text-sm font-semibold text-slate-600">{studentOpen ? "−" : "+"}</span>
                    </button>
                    {studentOpen && <div className="pb-3 pl-3 sm:pl-6">
                        {Array.from(degrees.entries()).map(([degreeKey, degreeRecords]) => {
                            const degreeOpen = openDegrees.includes(`${studentKey}:${degreeKey}`);
                            const record = degreeRecords[0];
                            return <div key={degreeKey} className="border-l-2 border-emerald-600 pl-3">
                                <button type="button" aria-expanded={degreeOpen} onClick={() => toggle(openDegrees, `${studentKey}:${degreeKey}`, setOpenDegrees)} className="flex min-h-12 w-full items-center justify-between gap-4 py-2 text-left">
                                    <span className="min-w-0"><span className="block truncate text-sm font-semibold text-[#0A192F]">{record.degree}</span><span className="text-xs text-slate-500">{record.university_name || record.university_code || "Institution unavailable"}</span></span>
                                    <span className="shrink-0 text-xs text-slate-500">{degreeOpen ? "Hide details" : "Details"}</span>
                                </button>
                                {degreeOpen && <div>{degreeRecords.map((credential) => <CredentialDetails key={credential.id} record={credential} />)}</div>}
                            </div>;
                        })}
                    </div>}
                </section>;
            })}
        </div>
    );
}
