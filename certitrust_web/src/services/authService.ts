import { apiClient, clearAuthSession, getAuthToken } from "./apiClient";

export type AuthUser = {
    id: number;
    name: string;
    email: string;
    role: "admin" | "student" | "user" | string;
    university_code?: string | null;
    profile_image_url?: string | null;
    profile_icon?: "girl" | "boy" | null;
    login_method?: "password" | "google";
    has_certificate?: boolean;
    access_frozen?: boolean;
};

type LoginPayload = {
    token?: string | null;
    access_token?: string | null;
    accessToken?: string | null;
    user?: AuthUser;
    email?: string;
    role?: AuthUser["role"];
    university_code?: string | null;
    has_certificate?: boolean;
    access_frozen?: boolean;
    data?: LoginPayload;
    result?: LoginPayload;
};

type LoginResponse = LoginPayload;

function persistLoginSession(
    response: LoginResponse,
    loginMethod: AuthUser["login_method"],
    remember = false,
) {
    let data = response;
    let token: string | null | undefined;
    for (let depth = 0; depth < 4 && data; depth += 1) {
        token = data.token || data.access_token || data.accessToken;
        if (token) break;
        data = data.data ?? data.result ?? {};
    }
    if (!token) throw new Error("The API response did not include a login token.");

    const email = data.email ?? data.user?.email ?? response.email ?? response.user?.email ?? "";
    const responseUser = data.user ?? response.user;
    const user: AuthUser = responseUser
        ? {
            ...responseUser,
            has_certificate: data.has_certificate ?? response.has_certificate,
            access_frozen: data.access_frozen ?? response.access_frozen,
            login_method: loginMethod,
        }
        : {
        id: 0,
        name: email,
        email,
        role: data.role ?? response.role ?? "user",
        university_code: data.university_code ?? response.university_code,
        has_certificate: data.has_certificate ?? response.has_certificate,
        access_frozen: data.access_frozen ?? response.access_frozen,
        login_method: loginMethod,
    };
    clearAuthSession();
    const storage = remember ? localStorage : sessionStorage;
    storage.setItem("certitrust_token", token);
    storage.setItem("certitrust_user", JSON.stringify(user));
    return user;
}

export async function login(email: string, password: string, remember = false) {
    if (email.trim().toLowerCase() === "certitrust256@gmail.com") {
        throw new Error("This account must sign in with Continue with Google.");
    }

    const { data } = await apiClient.post<LoginResponse>("/login", {
        email: email.trim(),
        password,
    });

    return persistLoginSession(data, "password", remember);
}

export async function loginWithGoogle(idToken?: string, accessToken?: string, remember = false) {
    const { data } = await apiClient.post<LoginResponse>("/auth/google", {
        ...(idToken ? { id_token: idToken } : {}),
        ...(accessToken ? { access_token: accessToken } : {}),
    });

    return persistLoginSession(data, "google", remember);
}

export function isSuperAdminSession(user: AuthUser | null = getSessionUser()) {
    return user?.email?.trim().toLowerCase() === "certitrust256@gmail.com"
        && user.login_method === "google";
}

export function logout() {
    const hadToken = Boolean(getAuthToken());
    clearAuthSession();
    if (hadToken) {
        void apiClient.post("/logout").catch((error: unknown) => {
            console.error("Could not revoke the server session during logout.", error);
        });
    }
}

export function getSessionUser(): AuthUser | null {
    const value =
        sessionStorage.getItem("certitrust_user") ||
        localStorage.getItem("certitrust_user");
    if (!value) return null;
    try {
        return JSON.parse(value) as AuthUser;
    } catch {
        clearAuthSession();
        return null;
    }
}

export async function getCurrentUser() {
    const { data } = await apiClient.get<AuthUser>("/user");
    const storage = localStorage.getItem("certitrust_token") ? localStorage : sessionStorage;
    const user = {
        ...data,
        login_method: getSessionUser()?.login_method,
    };
    storage.setItem("certitrust_user", JSON.stringify(user));
    return user;
}

export async function verifyStudentId(email: string, studentId: string) {
    const { data } = await apiClient.post("/auth/verify-student", {
        email,
        student_id: studentId,
    });
    return data;
}

export async function updateProfile(options: { profileIcon?: "girl" | "boy"; image?: File }) {
    const form = new FormData();
    if (options.profileIcon) form.append("profile_icon", options.profileIcon);
    if (options.image) form.append("profile_image", options.image);
    const { data } = await apiClient.post("/user/profile", form);
    const profile = data as { profile_image_url?: string | null; profile_icon?: string | null };
    const user = getSessionUser();
    if (user) {
        const storage = localStorage.getItem("certitrust_token") ? localStorage : sessionStorage;
        storage.setItem("certitrust_user", JSON.stringify({ ...user, ...profile }));
    }
    return profile;
}