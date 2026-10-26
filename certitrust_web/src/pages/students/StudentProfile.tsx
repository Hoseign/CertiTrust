import { useRef, useState } from "react";
import type { ChangeEvent } from "react";
import StudentSidebar from "@/Components/Organisms/StudentSidebar";
import { getSessionUser, updateProfile } from "../../services/authService";

type AvatarType = "girl" | "boy";

export default function StudentProfile() {
    const sessionUser = getSessionUser();
    const [avatar, setAvatar] = useState<AvatarType>(sessionUser?.profile_icon || "girl");
    const [photo, setPhoto] = useState<string | null>(sessionUser?.profile_image_url || null);
    const [isSaving, setIsSaving] = useState(false);
    const [error, setError] = useState("");
    const [notice, setNotice] = useState("");
    const fileInputRef = useRef<HTMLInputElement>(null);

    const saveProfile = async (options: { profileIcon?: AvatarType; image?: File }) => {
        setIsSaving(true);
        setError("");
        setNotice("");
        try {
            const profile = await updateProfile(options);
            setPhoto(profile.profile_image_url || null);
            if (profile.profile_icon === "girl" || profile.profile_icon === "boy") {
                setAvatar(profile.profile_icon);
            } else if (options.profileIcon) {
                setAvatar(options.profileIcon);
            }
            setNotice("Profile updated.");
        } catch (requestError) {
            setError(
                (requestError as { response?: { data?: { message?: string } } })
                    .response?.data?.message || "Unable to update your profile.",
            );
        } finally {
            setIsSaving(false);
        }
    };

    const handlePhotoChange = (event: ChangeEvent<HTMLInputElement>) => {
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
        void saveProfile({ image: file });
    };

    const selectAvatar = (selectedAvatar: AvatarType) => {
        void saveProfile({ profileIcon: selectedAvatar });
    };

    const currentAvatar = photo || (
        avatar === "girl"
            ? "https://api.dicebear.com/9.x/adventurer/svg?seed=Jade"
            : "https://api.dicebear.com/9.x/adventurer/svg?seed=Felix"
    );

    return (
        <div className="min-h-screen bg-[#F4F7FB]">
            <StudentSidebar />
            <main className="min-h-screen min-w-0 md:ml-64">
                <div className="mx-auto w-full max-w-3xl px-4 py-8 sm:px-6 lg:py-10">
                    <header className="mb-7 text-center">
                        <p className="mb-2 text-sm font-semibold text-blue-600">STUDENT PORTAL / ACCOUNT</p>
                        <h1 className="text-3xl font-extrabold text-[#0A192F]">Profile</h1>
                        <p className="mt-2 text-gray-500">Manage your profile photo.</p>
                    </header>

                    <section className="overflow-hidden rounded-2xl border border-gray-100 bg-white shadow-sm">
                        <div className="h-28 bg-gradient-to-r from-[#0A192F] to-[#2563EB]" />
                        <div className="px-5 pb-7 sm:px-8">
                            <div className="-mt-14 flex flex-col items-center text-center">
                                <img
                                    src={currentAvatar}
                                    alt="Student profile"
                                    className="h-28 w-28 rounded-full border-4 border-white bg-blue-50 object-cover shadow-md"
                                />
                                <p className="mt-3 break-all text-sm text-gray-600">{sessionUser?.email || "Account"}</p>
                                <p className="mt-1 text-sm text-gray-500">School: {sessionUser?.university_code || "Global"}</p>
                            </div>

                            <input
                                ref={fileInputRef}
                                type="file"
                                accept="image/*"
                                onChange={(event) => handlePhotoChange(event)}
                                className="hidden"
                            />
                            <button
                                type="button"
                                onClick={() => fileInputRef.current?.click()}
                                disabled={isSaving}
                                className="mt-6 w-full rounded-xl border border-blue-200 bg-blue-50 px-4 py-3 text-sm font-bold text-blue-700 hover:bg-blue-100 disabled:opacity-60"
                            >
                                {isSaving ? "Updating profile..." : "Choose photo from gallery"}
                            </button>

                            <div className="mt-3 grid grid-cols-2 gap-3">
                                <button
                                    type="button"
                                    onClick={() => selectAvatar("girl")}
                                    disabled={isSaving}
                                    className="rounded-xl border border-slate-200 px-3 py-3 text-sm font-bold text-slate-700 hover:border-blue-300 hover:bg-blue-50 disabled:opacity-60"
                                >
                                    Girl avatar
                                </button>
                                <button
                                    type="button"
                                    onClick={() => selectAvatar("boy")}
                                    disabled={isSaving}
                                    className="rounded-xl border border-slate-200 px-3 py-3 text-sm font-bold text-slate-700 hover:border-blue-300 hover:bg-blue-50 disabled:opacity-60"
                                >
                                    Boy avatar
                                </button>
                            </div>
                            {error && <p role="alert" className="mt-4 rounded-lg bg-red-50 p-3 text-sm text-red-700">{error}</p>}
                            {notice && <p role="status" className="mt-4 rounded-lg bg-green-50 p-3 text-sm text-green-700">{notice}</p>}
                        </div>
                    </section>
                </div>
            </main>
        </div>
    );
}
