import { useEffect, useRef, useState } from "react";
import type { ChangeEvent } from "react";
import { useNavigate } from "react-router-dom";
import { QRCodeCanvas } from "qrcode.react";
import StudentSidebar from "@/Components/Organisms/StudentSidebar";
import { getSessionUser, updateProfile } from "../../services/authService";
import { getStudentPortfolio, type StudentPortfolio } from "../../services/certitrustApi";

type AvatarType = "girl" | "boy";

export default function StudentProfile() {
    const navigate = useNavigate();
    const sessionUser = getSessionUser();
    const [avatar, setAvatar] = useState<AvatarType>(sessionUser?.profile_icon || "girl");
    const [photo, setPhoto] = useState<string | null>(sessionUser?.profile_image_url || null);
    const [isSaving, setIsSaving] = useState(false);
    const [error, setError] = useState("");
    const [notice, setNotice] = useState("");
    const [portfolio, setPortfolio] = useState<StudentPortfolio | null>(null);
    const [portfolioError, setPortfolioError] = useState("");
    const fileInputRef = useRef<HTMLInputElement>(null);
    const qrRef = useRef<HTMLDivElement>(null);

    useEffect(() => {
        let active = true;
        const refreshPortfolio = () => getStudentPortfolio().then((data) => {
            if (active) {
                setPortfolio(data);
                setPortfolioError("");
            }
        }).catch(() => {
            if (active) setPortfolioError("Portfolio QR is unavailable until a credential is linked to this account.");
        });
        void refreshPortfolio();
        const timer = window.setInterval(() => void refreshPortfolio(), 30000);
        return () => {
            active = false;
            window.clearInterval(timer);
        };
    }, []);

    const masterHash = portfolio && portfolio.degree_count > 0 ? portfolio.master_hash : "";

    const downloadPortfolioQr = () => {
        const canvas = qrRef.current?.querySelector("canvas");
        if (!canvas) return;
        const link = document.createElement("a");
        link.download = "certitrust-portfolio-qr.png";
        link.href = canvas.toDataURL("image/png");
        link.click();
    };

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
                    <section className="mt-6 grid gap-5 rounded-xl border border-slate-200 bg-white p-5 shadow-sm sm:grid-cols-[1fr_auto] sm:items-center sm:p-7">
                        <div>
                            <p className="text-xs font-bold uppercase text-emerald-700">Academic portfolio</p>
                            <h2 className="mt-1 text-xl font-extrabold text-[#0A192F]">Master Portfolio QR Code</h2>
                            <p className="mt-2 text-sm text-slate-600">{portfolio?.degree_count ?? 0} verified credential(s) across institutions</p>
                            {portfolio?.student_id && <p className="mt-1 text-sm font-semibold text-slate-700">Student ID: {portfolio.student_id}</p>}
                            {portfolio && <p className="mt-2 break-all font-mono text-xs text-slate-500">Master hash: {portfolio.master_hash}</p>}
                            {portfolioError && <p role="status" className="mt-2 text-sm text-amber-700">{portfolioError}</p>}
                            <div className="mt-4 flex flex-wrap gap-2">
                                <button type="button" onClick={downloadPortfolioQr} disabled={!portfolio} className="min-h-10 rounded-lg bg-[#0A192F] px-4 text-sm font-bold text-white disabled:opacity-50">Download Portfolio QR Code</button>
                                <button type="button" onClick={() => navigate(`/verify?hash=${encodeURIComponent(masterHash)}&manual=1`)} disabled={!masterHash} className="min-h-10 rounded-lg border border-slate-300 px-4 text-sm font-bold text-[#0A192F] disabled:opacity-50">Verify this record</button>
                            </div>
                        </div>
                        <div ref={qrRef} className="mx-auto rounded-lg border border-slate-200 p-3 sm:mx-0">
                            {masterHash ? <QRCodeCanvas value={masterHash} size={160} level="H" includeMargin /> : <div className="grid h-40 w-40 place-items-center text-center text-xs text-slate-400">No linked credentials</div>}
                        </div>
                    </section>
                </div>
            </main>
        </div>
    );
}
