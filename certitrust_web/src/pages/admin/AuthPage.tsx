import { useEffect, useRef, useState, type FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../../context/AuthContext.jsx";
import { verifyStudentId } from "../../services/authService";
import CertiTrustLoadingIndicator from "@/Components/Atoms/CertiTrustLoadingIndicator";

type GoogleTokenResponse = {
    access_token?: string;
    error?: string;
    error_description?: string;
};

type GoogleOAuthError = { type: string; message?: string };

declare global {
    interface Window {
        google?: {
            accounts?: {
                oauth2?: {
                    initTokenClient: (options: {
                        client_id: string;
                        scope: string;
                        callback: (response: GoogleTokenResponse) => void;
                        error_callback?: (error: GoogleOAuthError) => void;
                    }) => {
                        requestAccessToken: (options?: { prompt?: string }) => void;
                    };
                };
            };
        };
    }
}

function getLandingRoute(user: { email: string; role: string; university_code?: string | null }) {
    const email = user.email.trim().toLowerCase();
    const isSuperAdmin = email === "certitrust256@gmail.com";
    const isPsuAdmin =
        user.role === "admin" &&
        (String(user.university_code ?? "").toUpperCase() === "PSU" ||
            email.includes("psu") ||
            email.includes("@psu.edu.ph"));

    if (isSuperAdmin) return "/superadmin";
    if (isPsuAdmin) return "/psu-admin";
    if (user.role === "admin") return "/admin-dashboard";
    return "/portal";
}

export default function AuthPage() {
    const navigate = useNavigate();
    const { loginWithGoogle, logout } = useAuth();
    const googleCredentialHandlerRef = useRef<(response: GoogleTokenResponse) => void>(() => undefined);
    const [isGoogleReady, setIsGoogleReady] = useState(false);
    const [googleLoadError, setGoogleLoadError] = useState(false);
    const [googleLoadAttempt, setGoogleLoadAttempt] = useState(0);
    const [isSubmitting, setIsSubmitting] = useState(false);
    const [message, setMessage] = useState("");
    const [studentEmail, setStudentEmail] = useState("");
    const [studentId, setStudentId] = useState("");
    const [isVerifyingStudent, setIsVerifyingStudent] = useState(false);
    const [needsStudentVerification, setNeedsStudentVerification] = useState(false);

    const googleClientId =
        import.meta.env.VITE_GOOGLE_CLIENT_ID ||
        "839744246515-npnpn8u8urse0emqmt6ag0fscdfdqmsm.apps.googleusercontent.com";

    useEffect(() => {
        let active = true;
        const existingScript = document.getElementById("google-gsi-script") as HTMLScriptElement | null;
        const googleOAuth = window.google?.accounts?.oauth2;
        if (googleOAuth) {
            setIsGoogleReady(true);
            setGoogleLoadError(false);
            return;
        }

        const script = existingScript ?? document.createElement("script");
        let timeout = 0;
        const handleError = () => {
            if (!active) return;
            window.clearTimeout(timeout);
            setIsGoogleReady(false);
            setGoogleLoadError(true);
            setMessage("Google sign-in could not load. Check your connection and try again.");
            script.remove();
        };

        const handleLoad = () => {
            if (!active) return;
            window.clearTimeout(timeout);
            if (!window.google?.accounts?.oauth2) {
                handleError();
                return;
            }
            script.dataset.loaded = "true";
            setIsGoogleReady(true);
            setGoogleLoadError(false);
            setMessage("");
        };

        timeout = window.setTimeout(handleError, 10000);
        script.addEventListener("load", handleLoad, { once: true });
        script.addEventListener("error", handleError, { once: true });

        if (script.dataset.loaded === "true") {
            handleLoad();
        } else if (!existingScript) {
            script.id = "google-gsi-script";
            script.src = "https://accounts.google.com/gsi/client";
            script.async = true;
            script.defer = true;
            document.head.appendChild(script);
        }

        return () => {
            active = false;
            window.clearTimeout(timeout);
            script.removeEventListener("load", handleLoad);
            script.removeEventListener("error", handleError);
        };
    }, [googleClientId, googleLoadAttempt]);

    googleCredentialHandlerRef.current = (response) => {
        void (async () => {
            setMessage("");
            setIsSubmitting(true);
            try {
                if (!response.access_token) {
                    throw new Error(response.error_description || "Google did not return an access token.");
                }
                const user = await loginWithGoogle(undefined, response.access_token);
                if (user.access_frozen) {
                    navigate("/frozen-chat", { replace: true });
                    return;
                }
                if (user.role !== "admin") {
                    if (user.has_certificate !== true) {
                        await logout();
                        setMessage(
                            `This Google account (${user.email}) is not registered to a certificate record. Please use a registered student or administrator account.`,
                        );
                        return;
                    }
                    setStudentEmail(user.email);
                    setStudentId("");
                    setNeedsStudentVerification(true);
                    return;
                }
                navigate(getLandingRoute(user), { replace: true });
            } catch (error) {
                const responseMessage = (
                    error as { response?: { data?: { message?: string } } }
                ).response?.data?.message;
                setMessage(
                    responseMessage ||
                        (error instanceof Error
                            ? error.message
                            : "Unable to sign in with Google."),
                );
            } finally {
                setIsSubmitting(false);
            }
        })();
    };

    const handleGoogleSignIn = () => {
        const googleOAuth = window.google?.accounts?.oauth2;
        if (!isGoogleReady || !googleOAuth) {
            setMessage("Google sign-in is still loading. Please try again in a moment.");
            return;
        }
        setMessage("");
        setIsSubmitting(true);
        const tokenClient = googleOAuth.initTokenClient({
            client_id: googleClientId,
            scope: "openid email profile",
            callback: (response) => {
                if (response.error || !response.access_token) {
                    setIsSubmitting(false);
                    if (response.error !== "access_denied" && response.error !== "popup_closed") {
                        setMessage(
                            response.error_description || "Google sign-in could not be completed. Please try again.",
                        );
                    }
                    return;
                }
                googleCredentialHandlerRef.current(response);
            },
            error_callback: (error) => {
                setIsSubmitting(false);
                if (error.type !== "popup_closed") {
                    setMessage(error.message || "Google sign-in could not be completed. Please try again.");
                }
            },
        });
        tokenClient.requestAccessToken({ prompt: "select_account" });
    };

    const handleStudentVerification = async (event: FormEvent<HTMLFormElement>) => {
        event.preventDefault();
        if (!studentId.trim()) {
            setMessage("Enter your official Student ID to continue.");
            return;
        }
        setMessage("");
        setIsVerifyingStudent(true);
        try {
            await verifyStudentId(studentEmail, studentId.trim());
            navigate("/portal", { replace: true });
        } catch (error) {
            const responseMessage = (
                error as { response?: { data?: { message?: string } } }
            ).response?.data?.message;
            setMessage(responseMessage || "Student ID verification failed. Please check it and try again.");
        } finally {
            setIsVerifyingStudent(false);
        }
    };

    const cancelStudentVerification = async () => {
        setIsSubmitting(true);
        try {
            await logout();
            setNeedsStudentVerification(false);
            setStudentEmail("");
            setStudentId("");
            setMessage("");
        } finally {
            setIsSubmitting(false);
        }
    };

    return (
        <div className="min-h-screen bg-[#F6F8FC]">
            <div className="min-h-screen grid grid-cols-1 lg:grid-cols-2">
                <div className="hidden lg:flex bg-[#0A192F] text-white p-12 xl:p-20 flex-col justify-center">
                    <div className="max-w-xl mx-auto">
                        <div className="mb-10 flex items-center gap-4">
                            <img className="h-14 w-14 rounded-xl bg-white p-1" src="/certitrustlogo.png" alt="CertiTrust logo" />
                            <span className="text-2xl font-bold tracking-wide">CertiTrust</span>
                        </div>
                        <h2 className="text-4xl xl:text-5xl font-extrabold leading-tight">
                            Secure Academic
                            <br />
                            Credentials
                        </h2>
                        <p className="mt-6 text-slate-300 text-base xl:text-lg leading-relaxed">
                            CertiTrust provides a secure platform for issuing, managing, and verifying academic credentials.
                        </p>
                        <div className="mt-10 space-y-4 text-slate-300">
                            <p>✓ Blockchain-backed credential records</p>
                            <p>✓ Trusted identity verification</p>
                            <p>✓ Secure access for students and administrators</p>
                        </div>
                    </div>
                </div>

                <div className="flex items-center justify-center p-6 sm:p-10">
                    <div className="w-full max-w-md rounded-2xl bg-white p-8 shadow-xl sm:p-10">
                        <div className="mb-8 text-center">
                            <img className="mx-auto h-16 w-16 rounded-xl object-contain lg:hidden" src="/certitrustlogo.png" alt="CertiTrust logo" />
                            <h1 className="mt-4 text-3xl font-bold text-[#0A192F]">CertiTrust</h1>
                            <p className="mt-2 text-sm text-slate-500">
                                {needsStudentVerification
                                    ? "Confirm your student identity to continue"
                                    : "Blockchain-anchored academic credential verification"}
                            </p>
                        </div>

                        {needsStudentVerification ? (
                            <form className="space-y-5" onSubmit={handleStudentVerification}>
                                <div className="rounded-lg bg-slate-50 p-3 text-sm text-slate-600">
                                    Signed in as <span className="font-semibold text-slate-800">{studentEmail}</span>
                                </div>
                                <label className="block text-sm font-medium text-slate-700" htmlFor="student-id">
                                    Official Student ID
                                    <input
                                        id="student-id"
                                        autoComplete="off"
                                        value={studentId}
                                        onChange={(event) => setStudentId(event.target.value)}
                                        className="mt-2 w-full rounded-lg border border-slate-300 px-4 py-3 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100"
                                        placeholder="Enter your Student ID"
                                        disabled={isVerifyingStudent || isSubmitting}
                                    />
                                </label>
                                <button
                                    type="submit"
                                    disabled={isVerifyingStudent || isSubmitting}
                                    className="w-full rounded-lg bg-[#0A192F] px-4 py-3 font-semibold text-white transition hover:bg-[#142b4a] disabled:cursor-not-allowed disabled:opacity-60"
                                >
                                    {isVerifyingStudent ? "Verifying..." : "Verify and continue"}
                                </button>
                                <button
                                    type="button"
                                    onClick={() => void cancelStudentVerification()}
                                    disabled={isVerifyingStudent || isSubmitting}
                                    className="w-full rounded-lg border border-slate-300 px-4 py-3 font-medium text-slate-600 transition hover:bg-slate-50 disabled:opacity-60"
                                >
                                    Cancel and sign out
                                </button>
                            </form>
                        ) : (
                            <>
                                <div className="flex min-h-12 justify-center">
                                    <button
                                        type="button"
                                        disabled={isSubmitting}
                                        onClick={handleGoogleSignIn}
                                        className={`flex w-full items-center justify-center gap-3 rounded-lg border px-4 py-3 font-semibold transition disabled:cursor-wait disabled:opacity-70 ${
                                            isSubmitting
                                                ? "border-[#0A192F] bg-[#0A192F] text-white"
                                                : "border-slate-300 text-slate-700 hover:bg-slate-50"
                                        }`}
                                    >
                                        {isSubmitting ? (
                                            <CertiTrustLoadingIndicator
                                                size={20}
                                                message="Signing in..."
                                                inline
                                                className="text-white"
                                            />
                                        ) : (
                                            <svg aria-hidden="true" viewBox="0 0 48 48" className="h-5 w-5">
                                                <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5Z" />
                                                <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.74 7.18l7.72 5.99c4.51-4.16 7.06-10.29 7.06-17.64Z" />
                                                <path fill="#FBBC05" d="M10.53 28.59a14.4 14.4 0 0 1 0-9.18l-7.98-6.19a23.93 23.93 0 0 0 0 21.56l7.98-6.19Z" />
                                                <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.91-5.81l-7.72-5.99c-2.14 1.44-4.89 2.3-8.19 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48Z" />
                                            </svg>
                                        )}
                                        {!isSubmitting ? "Sign in with Google" : null}
                                    </button>
                                </div>
                            </>
                        )}

                        {message ? (
                            <div role="alert" className="mt-5 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
                                {message}
                                {googleLoadError ? (
                                    <button
                                        type="button"
                                        onClick={() => {
                                            setMessage("");
                                            setGoogleLoadError(false);
                                            setGoogleLoadAttempt((attempt) => attempt + 1);
                                        }}
                                        className="mt-2 block font-semibold underline"
                                    >
                                        Retry Google sign-in
                                    </button>
                                ) : null}
                            </div>
                        ) : null}

                        <div className="mt-8 border-t border-slate-100 pt-5 text-center">
                            <button
                                type="button"
                                onClick={() => navigate("/public-verification?hash=preview")}
                                className="text-sm font-medium text-blue-700 hover:text-blue-900"
                            >
                                Public Certificate Verification
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
}
