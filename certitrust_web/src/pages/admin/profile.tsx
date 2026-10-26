import { useEffect, useRef, useState } from "react";
import type { ChangeEvent } from "react";
import Sidebar from "@/Components/Organisms/Sidebar";
import CertiTrustLoadingIndicator from "@/Components/Atoms/CertiTrustLoadingIndicator";
import { getCurrentUser, getSessionUser, updateProfile } from "../../services/authService";
import type { AuthUser } from "../../services/authService";

function initials(value: string) {
    return value.split(/[\s@]+/).filter(Boolean).slice(0, 2).map((part) => part[0]).join("").toUpperCase();
}

export default function Profile() {
    const [user, setUser] = useState<AuthUser | null>(() => getSessionUser());
    const [loading, setLoading] = useState(true);
    const [isSaving, setIsSaving] = useState(false);
    const [error, setError] = useState("");
    const [notice, setNotice] = useState("");
    const fileInputRef = useRef<HTMLInputElement>(null);

    useEffect(() => {
        getCurrentUser()
            .then(setUser)
            .catch((requestError: unknown) => {
                setError(
                    (requestError as { response?: { data?: { message?: string } } })
                        .response?.data?.message || "Unable to load your profile.",
                );
            })
            .finally(() => setLoading(false));
    }, []);

    const updatePhoto = async (event: ChangeEvent<HTMLInputElement>) => {
        const file = event.target.files?.[0];
        event.target.value = "";
        if (!file) return;
        if (!file.type.startsWith("image/")) {
            setError("Choose an image file.");
            return;
        }
        if (file.size > 5 * 1024 * 1024) {
            setError("Image must be 5 MB or smaller.");
            return;
        }

        setIsSaving(true);
        setError("");
        setNotice("");
        try {
            await updateProfile({ image: file });
            setUser(getSessionUser());
            setNotice("Profile photo updated.");
        } catch (requestError) {
            setError(
                (requestError as { response?: { data?: { message?: string } } })
                    .response?.data?.message || "Could not update profile photo.",
            );
        } finally {
            setIsSaving(false);
        }
    };

    return (
        <div className="min-h-screen bg-[#F6F8FC] md:grid md:grid-cols-[286px_minmax(0,1fr)]">
            <Sidebar />
            <main className="h-screen min-w-0 overflow-y-auto p-4 sm:p-6 md:p-8">
                <header className="mb-5 flex flex-wrap items-center justify-between gap-4">
                    <div>
                        <p className="m-0 text-xs font-extrabold uppercase tracking-wider text-blue-700">Account Settings</p>
                        <h1 className="mt-1 text-2xl font-extrabold text-[#0A192F]">Profile</h1>
                    </div>
                    <button
                        type="button"
                        disabled={loading}
                        onClick={() => {
                            setLoading(true);
                            setError("");
                            getCurrentUser()
                                .then(setUser)
                                .catch((requestError: unknown) => {
                                    setError(
                                        (requestError as { response?: { data?: { message?: string } } })
                                            .response?.data?.message || "Unable to load your profile.",
                                    );
                                })
                                .finally(() => setLoading(false));
                        }}
                        className="rounded-xl bg-[#0A192F] px-4 py-2.5 text-sm font-bold text-white disabled:opacity-60"
                    >
                        {loading ? <CertiTrustLoadingIndicator size={18} message="Loading..." inline /> : "Refresh profile"}
                    </button>
                </header>

                <section className="mx-auto max-w-2xl overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
                    <div className="h-28 bg-gradient-to-r from-[#0A192F] to-[#2563EB]" />
                    <div className="px-5 pb-7 sm:px-8">
                        <div className="-mt-12 flex flex-col items-center text-center">
                            {user?.profile_image_url ? (
                                <img
                                    src={user.profile_image_url}
                                    alt="Profile"
                                    className="h-24 w-24 rounded-full border-4 border-white bg-white object-cover shadow-md"
                                />
                            ) : (
                                <div className="flex h-24 w-24 items-center justify-center rounded-full border-4 border-white bg-blue-50 text-2xl font-extrabold text-blue-700 shadow-md">
                                    {initials(user?.name || user?.email || "A")}
                                </div>
                            )}
                            <h2 className="mt-4 break-all text-lg font-bold text-[#0A192F]">
                                {user?.email || "Account"}
                            </h2>
                            <p className="mt-1 text-sm text-slate-500">
                                School: {user?.university_code || "Global"}
                            </p>
                        </div>

                        <input
                            ref={fileInputRef}
                            type="file"
                            accept="image/*"
                            onChange={(event) => void updatePhoto(event)}
                            className="hidden"
                        />
                        <button
                            type="button"
                            disabled={isSaving}
                            onClick={() => fileInputRef.current?.click()}
                            className="mt-6 w-full rounded-xl border border-blue-200 bg-blue-50 px-4 py-3 text-sm font-bold text-blue-700 transition hover:bg-blue-100 disabled:opacity-60"
                        >
                            {isSaving ? "Updating profile photo..." : "Choose photo from gallery"}
                        </button>
                        {error && <p role="alert" className="mt-4 rounded-lg bg-red-50 p-3 text-sm text-red-700">{error}</p>}
                        {notice && <p role="status" className="mt-4 rounded-lg bg-green-50 p-3 text-sm text-green-700">{notice}</p>}
                    </div>
                </section>
            </main>
        </div>
    );
}
