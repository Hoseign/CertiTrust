import { useEffect, useMemo, useState } from "react";
import SuperAdminSideBar from "@/Components/Organisms/SuperAdminSideBar";
import CertiTrustLoadingIndicator from "@/Components/Atoms/CertiTrustLoadingIndicator";
import {
    listJunkItems,
    permanentlyDeleteJunkItem,
    restoreJunkItem,
    type JunkItem,
} from "../../services/adminApi";

function sourceLabel(sourceValue: unknown) {
    const source = typeof sourceValue === "string" ? sourceValue : "";
    if (!source) return "Unknown source";
    if (source === "subadmin_removed") return "Subadmin removed";
    if (source === "student_removal_approved") return "Student removal approved";
    if (source === "credential_removal_approved") return "Credential removal approved";
    if (source === "credential_revoked") return "Credential revoked";
    return source.replaceAll("_", " ");
}

export default function SuperAdminJunk() {
    const [items, setItems] = useState<JunkItem[]>([]);
    const [search, setSearch] = useState("");
    const [isLoading, setIsLoading] = useState(true);
    const [workingId, setWorkingId] = useState<number | null>(null);
    const [error, setError] = useState("");
    const [message, setMessage] = useState("");
    const [selected, setSelected] = useState<JunkItem | null>(null);

    const refresh = async () => {
        setIsLoading(true);
        try {
            setItems(await listJunkItems());
            setError("");
        } catch (requestError) {
            const responseMessage = (requestError as { response?: { data?: { message?: string } } })
                .response?.data?.message;
            setError(responseMessage || "Unable to load the recycle bin.");
        } finally {
            setIsLoading(false);
        }
    };

    useEffect(() => {
        void refresh();
    }, []);

    const filteredItems = useMemo(() => {
        const query = search.trim().toLowerCase();
        return items.filter((item) => !query || [
            item.student_name,
            item.student_email,
            item.student_id,
            item.university_code,
            item.university_name,
            item.record_type,
            item.source,
            item.deleted_by_email,
        ].some((value) => String(value ?? "").toLowerCase().includes(query)));
    }, [items, search]);

    const permanentlyDelete = async (item: JunkItem) => {
        setWorkingId(item.id);
        setError("");
        setMessage("");
        try {
            const result = await permanentlyDeleteJunkItem(item.id);
            setItems((current) => current.filter((candidate) => candidate.id !== item.id));
            setSelected(null);
            setMessage(result.message);
        } catch (requestError) {
            const responseMessage = (requestError as { response?: { data?: { message?: string } } })
                .response?.data?.message;
            setError(responseMessage || "Unable to permanently delete this item.");
        } finally {
            setWorkingId(null);
        }
    };

    const restore = async (item: JunkItem) => {
        setWorkingId(item.id);
        setError("");
        setMessage("");
        try {
            const result = await restoreJunkItem(item.id);
            setItems((current) => current.filter((candidate) => candidate.id !== item.id));
            setMessage(result.message);
        } catch (requestError) {
            const responseMessage = (requestError as { response?: { data?: { message?: string } } })
                .response?.data?.message;
            setError(responseMessage || "Unable to restore this item.");
        } finally {
            setWorkingId(null);
        }
    };

    return (
        <div className="flex min-h-screen bg-[#F5F7FB]">
            <SuperAdminSideBar />
            <main className="h-screen min-w-0 flex-1 overflow-y-auto p-5 md:p-10">
                <div className="mx-auto max-w-5xl">
                    <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#2563EB]">Super Admin</p>
                    <h1 className="mt-2 text-3xl font-extrabold text-[#0A192F]">Junk / Recycle Bin</h1>
                    <p className="mt-3 max-w-3xl leading-7 text-slate-600">
                        Deleted accounts and credentials are held here until restored or permanently deleted. Database credentials are removed from active verification while in Junk; blockchain history remains immutable.
                    </p>
                    <div className="mt-6 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm leading-6 text-amber-950">
                        Restore an item to return its account or credential to active records. Permanently deleting an item cannot be undone.
                    </div>

                    {error && <p role="alert" className="mt-5 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</p>}
                    {message && <p role="status" className="mt-5 rounded-lg border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800">{message}</p>}

                    <section className="mt-6 rounded-2xl border border-slate-200 bg-white p-5">
                        <div className="flex flex-wrap items-center justify-between gap-4">
                            <h2 className="text-xl font-extrabold text-[#0A192F]">
                                Recycle bin items <span className="text-slate-500">({items.length})</span>
                            </h2>
                            <button type="button" onClick={() => void refresh()} disabled={isLoading} className="min-h-10 rounded-lg border border-slate-300 px-4 font-semibold text-slate-700 hover:bg-slate-50 disabled:opacity-50">
                                Refresh
                            </button>
                        </div>
                        <input
                            value={search}
                            onChange={(event) => setSearch(event.target.value)}
                            placeholder="Search name, email, student ID, university or source"
                            aria-label="Search recycle bin"
                            className="mt-4 min-h-11 w-full rounded-lg border border-slate-300 px-3 outline-none focus:border-blue-600"
                        />
                    </section>

                    <section className="mt-5 divide-y divide-slate-200 rounded-2xl border border-slate-200 bg-white">
                        {isLoading ? (
                            <CertiTrustLoadingIndicator size={28} message="Loading recycle bin..." className="w-full py-10 text-slate-500" />
                        ) : filteredItems.length === 0 ? (
                            <p className="p-8 text-center text-slate-500">{items.length ? "No items match your search." : "The recycle bin is empty."}</p>
                        ) : filteredItems.map((item) => {
                            const certificateRecords = Array.isArray(item.payload?.certificates)
                                ? item.payload.certificates
                                : [];
                            const certificateCodes = certificateRecords.flatMap((certificate) => {
                                if (!certificate || typeof certificate !== "object") return [];
                                const code = certificate.certificate_code;
                                return code ? [String(code)] : [];
                            });
                            return (
                                <article key={item.id} className="flex flex-wrap items-center justify-between gap-4 p-5">
                                    <div className="min-w-0">
                                    <h3 className="font-bold text-[#0A192F]">
                                        {item.record_type === "subadmin_account"
                                            ? `Subadmin: ${item.student_name || item.student_email || "Unknown"}`
                                            : item.student_name || "Student account"}
                                    </h3>
                                    <p className="mt-1 break-all text-sm text-slate-600">
                                        {item.student_email || "No email"}{item.student_id ? ` · ID: ${item.student_id}` : ""}
                                    </p>
                                    <p className="mt-1 text-sm text-slate-500">
                                        {item.university_name || "Unknown university"} ({item.university_code || "N/A"}) · {sourceLabel(item.source)} · {item.credential_count ?? 0} credential(s)
                                    </p>
                                    {certificateCodes?.length ? <p className="mt-1 break-all text-xs text-slate-500">Credential code(s): {certificateCodes.join(", ")}</p> : null}
                                    <p className="mt-1 text-xs text-slate-400">
                                        Deleted {item.deleted_at ? new Date(item.deleted_at).toLocaleString() : "date unavailable"}
                                        {item.deleted_by_email ? ` by ${item.deleted_by_email}` : ""}
                                    </p>
                                    </div>
                                    <div className="flex flex-wrap gap-2">
                                        <button
                                            type="button"
                                            onClick={() => void restore(item)}
                                            disabled={workingId !== null}
                                            className="min-h-10 rounded-lg border border-emerald-300 px-4 font-bold text-emerald-800 hover:bg-emerald-50 disabled:opacity-50"
                                        >
                                            {workingId === item.id ? "Restoring..." : "Restore"}
                                        </button>
                                        <button
                                            type="button"
                                            onClick={() => setSelected(item)}
                                            disabled={workingId !== null}
                                            className="min-h-10 rounded-lg bg-red-700 px-4 font-bold text-white hover:bg-red-800 disabled:opacity-50"
                                        >
                                            Permanently delete
                                        </button>
                                    </div>
                                </article>
                            );
                        })}
                    </section>
                </div>
            </main>
            {selected && (
                <div className="fixed inset-0 z-50 grid place-items-center bg-slate-950/60 p-4">
                    <section role="dialog" aria-modal="true" aria-labelledby="permanent-delete-title" className="w-full max-w-lg rounded-2xl bg-white p-6 shadow-2xl">
                        <h2 id="permanent-delete-title" className="text-xl font-extrabold text-red-800">Permanently delete this item?</h2>
                        <p className="mt-3 leading-6 text-slate-700">
                            This permanently removes <strong>{selected.student_name || selected.student_email || "this record"}</strong> and its recycle-bin snapshot. The deleted student account and database credential records cannot be restored. Blockchain history is not affected.
                        </p>
                        {error && <p role="alert" className="mt-3 text-sm text-red-700">{error}</p>}
                        <div className="mt-6 flex justify-end gap-3">
                            <button type="button" onClick={() => setSelected(null)} disabled={workingId !== null} className="min-h-11 rounded-lg border border-slate-300 px-4 font-semibold text-slate-700">Cancel</button>
                            <button type="button" onClick={() => void permanentlyDelete(selected)} disabled={workingId !== null} className="min-h-11 rounded-lg bg-red-700 px-4 font-bold text-white disabled:opacity-60">
                                {workingId === selected.id ? "Deleting..." : "Permanently delete"}
                            </button>
                        </div>
                    </section>
                </div>
            )}
        </div>
    );
}
