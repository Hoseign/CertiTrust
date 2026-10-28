import { useEffect, useMemo, useRef, useState } from "react";
import { QRCodeCanvas } from "qrcode.react";
import type { CertificateRecord } from "../../services/certitrustApi";

type Props = {
    records: CertificateRecord[];
    masterRecords?: CertificateRecord[];
    showStudentMasterQr?: boolean;
    emptyMessage?: string;
};

type CredentialRecord = CertificateRecord & { email?: string | null };

function recordEmail(record: CertificateRecord) {
    const credential = record as CredentialRecord;
    return (credential.student_email || credential.email || "").trim().toLowerCase();
}

function CredentialDetails({ record }: { record: CertificateRecord }) {
    const [showQr, setShowQr] = useState(false);
    const [showDiploma, setShowDiploma] = useState(false);
    const diplomaUrl = record.diploma_url || undefined;

    return (
        <div className="border-t border-slate-200 px-4 py-4 sm:px-5">
            <dl className="grid gap-x-6 gap-y-3 text-sm sm:grid-cols-2">
                <div><dt className="text-slate-500">Institution</dt><dd className="font-semibold">{record.university_name || record.university_code || "Institution unavailable"}</dd></div>
                <div><dt className="text-slate-500">Issue date</dt><dd>{record.issue_date}</dd></div>
                <div><dt className="text-slate-500">On-chain hash</dt><dd className="break-all font-mono text-xs">{record.cert_hash}</dd></div>
                <div><dt className="text-slate-500">Verification</dt><dd>{record.blockchain_status || record.status}</dd></div>
            </dl>
            <div className="mt-4 flex flex-wrap gap-2">
                <a href={`/public-verification?hash=${encodeURIComponent(record.cert_hash)}`} className="inline-flex min-h-9 items-center rounded-md border border-slate-300 px-3 text-sm font-bold">Verify this record</a>
                {diplomaUrl && <button type="button" onClick={() => setShowDiploma((visible) => !visible)} className="min-h-9 rounded-md border border-slate-300 px-3 text-sm font-bold">{showDiploma ? "Hide diploma" : "View your diploma"}</button>}
                <button type="button" onClick={() => setShowQr(true)} className="min-h-9 rounded-md border border-slate-300 px-3 text-sm font-bold">View QR code</button>
            </div>
            {showDiploma && diplomaUrl && <img src={diplomaUrl} alt={`${record.degree} diploma`} className="mt-4 max-h-80 w-full border border-slate-200 bg-white object-contain" />}
            {showQr && <div className="fixed inset-0 z-50 grid place-items-center bg-slate-950/60 p-4" role="presentation" onClick={() => setShowQr(false)}>
                <section role="dialog" aria-modal="true" aria-label={`${record.degree} verification QR code`} className="w-full max-w-sm rounded-xl bg-white p-5 text-center shadow-xl" onClick={(event) => event.stopPropagation()}>
                    <h3 className="text-lg font-bold text-[#0A192F]">Credential QR code</h3>
                    <div className="my-4 flex justify-center"><QRCodeCanvas value={`${window.location.origin}/public-verification?hash=${encodeURIComponent(record.cert_hash)}`} size={240} includeMargin /></div>
                    <p className="break-all font-mono text-xs text-slate-500">{record.cert_hash}</p>
                    <button type="button" onClick={() => setShowQr(false)} className="mt-4 min-h-10 rounded-lg bg-[#0A192F] px-4 text-sm font-bold text-white">Close</button>
                </section>
            </div>}
        </div>
    );
}

function studentKey(record: CertificateRecord) {
    const email = recordEmail(record);
    const id = record.student_id?.trim().toLowerCase();
    return email ? `email:${email}` : `id:${id || record.student_name.toLowerCase()}`;
}

async function makeMasterHash(records: CertificateRecord[]) {
    const hashes = records.map((record) => record.cert_hash?.trim()).filter((hash): hash is string => Boolean(hash)).sort();
    if (!hashes.length || !globalThis.crypto?.subtle) return "";
    const digest = await globalThis.crypto.subtle.digest("SHA-256", new TextEncoder().encode(hashes.join("|")));
    return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export default function StudentCredentialGroups({
    records,
    masterRecords = records,
    showStudentMasterQr = false,
    emptyMessage = "No credential records found.",
}: Props) {
    const [openStudents, setOpenStudents] = useState<string[]>([]);
    const [openDegrees, setOpenDegrees] = useState<string[]>([]);
    const [masterHashes, setMasterHashes] = useState<Record<string, string>>({});
    const [activeMasterQr, setActiveMasterQr] = useState<{ name: string; hash: string } | null>(null);
    const masterQrRef = useRef<HTMLDivElement>(null);
    const groups = useMemo(() => {
        const grouped = new Map<string, CertificateRecord[]>();
        records.forEach((record) => {
            const key = studentKey(record);
            grouped.set(key, [...(grouped.get(key) || []), record]);
        });
        return Array.from(grouped.entries());
    }, [records]);

    useEffect(() => {
        if (!showStudentMasterQr) {
            setMasterHashes({});
            return;
        }
        let active = true;
        setMasterHashes({});
        void Promise.all(groups.map(async ([key, credentials]) => {
            const emails = new Set(credentials.map(recordEmail).filter(Boolean));
            const ids = new Set(credentials.map((record) => record.student_id?.trim().toLowerCase()).filter(Boolean));
            masterRecords.forEach((record) => {
                if (emails.has(recordEmail(record)) && record.student_id?.trim()) {
                    ids.add(record.student_id.trim().toLowerCase());
                }
            });
            const portfolioRecords = masterRecords.filter((record) => {
                const email = recordEmail(record);
                const id = record.student_id?.trim().toLowerCase();
                return (email && emails.has(email)) || (id && ids.has(id));
            });
            return [key, await makeMasterHash(portfolioRecords)] as const;
        })).then((entries) => {
            if (active) setMasterHashes(Object.fromEntries(entries));
        }).catch(() => {
            if (active) setMasterHashes({});
        });
        return () => { active = false; };
    }, [groups, masterRecords, showStudentMasterQr]);

    const toggle = (current: string[], key: string, update: (next: string[]) => void) =>
        update(current.includes(key) ? current.filter((value) => value !== key) : [...current, key]);

    if (!groups.length) return <p className="py-8 text-center text-sm text-slate-500">{emptyMessage}</p>;

    return (
        <>
            <div className="divide-y divide-slate-200 border-y border-slate-200">
                {groups.map(([key, credentials]) => {
                    const name = credentials[0].student_name || "Student";
                    const degrees = new Map<string, CertificateRecord[]>();
                    credentials.forEach((record) => {
                        const degreeKey = `${record.degree.toLowerCase()}|${record.university_code || ""}`;
                        degrees.set(degreeKey, [...(degrees.get(degreeKey) || []), record]);
                    });
                    const studentOpen = openStudents.includes(key);
                    const masterHash = masterHashes[key];
                    return <section key={key}>
                        <div className="flex min-h-14 items-center gap-2 py-2">
                            <button type="button" aria-expanded={studentOpen} onClick={() => toggle(openStudents, key, setOpenStudents)} className="flex min-h-12 min-w-0 flex-1 items-center text-left">
                                <span className="min-w-0"><span className="block truncate font-bold text-[#0A192F]">{name}</span><span className="mt-1 block text-xs text-slate-500">{credentials[0].student_id || "No student ID"} · {degrees.size} degree{degrees.size === 1 ? "" : "s"}</span></span>
                            </button>
                            {showStudentMasterQr && <button type="button" disabled={!masterHash} title={masterHash ? "View student master QR code" : "Preparing student master QR code"} aria-label={`View ${name}'s master QR code`} onClick={() => masterHash && setActiveMasterQr({ name, hash: masterHash })} className="grid h-10 w-10 shrink-0 place-items-center rounded-lg border border-slate-200 text-[#0A192F] hover:bg-slate-50 disabled:opacity-40"><span aria-hidden="true">▦</span></button>}
                            <button type="button" aria-label={`${studentOpen ? "Collapse" : "Expand"} ${name}'s degrees`} aria-expanded={studentOpen} onClick={() => toggle(openStudents, key, setOpenStudents)} className="grid h-10 w-8 shrink-0 place-items-center text-sm font-semibold text-slate-600">{studentOpen ? "−" : "+"}</button>
                        </div>
                        {studentOpen && <div className="pb-3 pl-3 sm:pl-6">
                            {Array.from(degrees.entries()).map(([degreeKey, degreeRecords]) => {
                                const degreeOpen = openDegrees.includes(`${key}:${degreeKey}`);
                                const record = degreeRecords[0];
                                return <div key={degreeKey} className="border-l-2 border-emerald-600 pl-3">
                                    <button type="button" aria-expanded={degreeOpen} onClick={() => toggle(openDegrees, `${key}:${degreeKey}`, setOpenDegrees)} className="flex min-h-12 w-full items-center justify-between gap-4 py-2 text-left">
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
            {activeMasterQr && <div className="fixed inset-0 z-[60] grid place-items-center bg-slate-950/60 p-4" role="presentation" onClick={() => setActiveMasterQr(null)}>
                <section role="dialog" aria-modal="true" aria-label={`${activeMasterQr.name} master portfolio QR code`} className="w-full max-w-sm rounded-xl bg-white p-5 text-center shadow-xl" onClick={(event) => event.stopPropagation()}>
                    <h3 className="text-lg font-bold text-[#0A192F]">{activeMasterQr.name} · Master Portfolio QR</h3>
                    <div ref={masterQrRef} className="my-4 flex justify-center"><QRCodeCanvas value={activeMasterQr.hash} size={240} includeMargin /></div>
                    <p className="break-all font-mono text-xs text-slate-500">{activeMasterQr.hash}</p>
                    <div className="mt-5 flex flex-wrap justify-center gap-2">
                        <button type="button" onClick={() => {
                            const canvas = masterQrRef.current?.querySelector("canvas");
                            if (!canvas) return;
                            const link = document.createElement("a");
                            link.href = canvas.toDataURL("image/png");
                            link.download = `${activeMasterQr.name.replace(/[^A-Za-z0-9_-]/g, "_")}-master-portfolio-qr.png`;
                            link.click();
                        }} className="min-h-10 rounded-lg bg-[#0A192F] px-4 text-sm font-bold text-white">Download QR</button>
                        <a href={`/public-verification?hash=${encodeURIComponent(activeMasterQr.hash)}`} className="inline-flex min-h-10 items-center rounded-lg border border-slate-300 px-4 text-sm font-bold text-[#0A192F]">Verify on Chain</a>
                        <button type="button" onClick={() => setActiveMasterQr(null)} className="min-h-10 rounded-lg border border-slate-300 px-4 text-sm font-bold text-[#0A192F]">Close</button>
                    </div>
                </section>
            </div>}
        </>
    );
}
