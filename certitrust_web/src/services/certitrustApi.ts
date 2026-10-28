import { apiClient, publicApiClient } from "./apiClient";
import { getSessionUser, isSuperAdminSession } from "./authService";
import type { UniversityRecord } from "./adminApi";

export type CertificateRecord = {
    id: number;
    certificate_code: string;
    student_id: string;
    student_name: string;
    student_email: string;
    degree: string;
    degree_number?: number;
    issue_date: string;
    status: string;
    cert_hash: string;
    university_code?: string | null;
    university_name?: string | null;
    created_at?: string;
    diploma_url?: string | null;
    diploma_file_name?: string | null;
    blockchain_status?: string;
    blockchain_tx_hash?: string | null;
};

export type PublicCertificateResult = Partial<CertificateRecord> & {
    status: string;
    course_or_event?: string;
    university_name?: string;
    blockchain_verification?: { status: string; verified: boolean; network?: string };
    multi_degree?: boolean;
    degree_count?: number;
    certificates?: (Partial<CertificateRecord> & {
        status: string;
        blockchain_verification?: { status: string; verified: boolean; network?: string };
    })[];
};

export type StudentPortfolio = {
    master_hash: string;
    portfolio_token: string;
    student_name: string | null;
    student_id?: string | null;
    degree_count: number;
    status: string;
    groups: {
        university_code: string;
        university_name: string;
        certificates: (Partial<CertificateRecord> & Record<string, unknown>)[];
    }[];
    certificates: (Partial<CertificateRecord> & Record<string, unknown>)[];
};

export async function getStudentPortfolio() {
    const { data } = await apiClient.get<{ data: StudentPortfolio }>("/v1/student/portfolio");
    return data.data;
}

export async function getPublicPortfolio(token: string) {
    const { data } = await publicApiClient.get<{ data: StudentPortfolio }>(
        `/v1/student/portfolio/${encodeURIComponent(token)}`,
    );
    return data.data;
}

export type CertificateDraft = {
    student_id: string;
    student_name: string;
    student_email: string;
    degree: string;
    issue_date: string;
    diploma_file?: File;
    university_code?: string;
    degree_number?: number;
    additional_degree?: boolean;
};

export async function listCertificates(limit?: number) {
    const { data } = await apiClient.get<{ data: CertificateRecord[] }>("/v1/records", {
        params: limit ? { limit } : undefined,
    });
    return data.data;
}

export async function getCertificateByCode(code: string) {
    const { data } = await apiClient.get<{ data: PublicCertificateResult }>(
        `/certificates/${encodeURIComponent(code.trim())}`,
    );
    return data.data;
}

export async function getPublicCertificateByCode(code: string) {
    const { data } = await publicApiClient.get<{ data: PublicCertificateResult }>(
        `/certificates/${encodeURIComponent(code.trim())}`,
    );
    return data.data;
}

async function sha256Hex(buffer: ArrayBuffer) {
    const digest = await crypto.subtle.digest("SHA-256", buffer);
    return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function uploadDiploma(file: File, universityCode?: string) {
    const form = new FormData();
    form.append("diploma_file", file);
    if (universityCode) form.append("university_code", universityCode);
    const { data } = await apiClient.post<{ data: { diploma_url: string; diploma_file_name: string } }>(
        "/certificates/diploma",
        form,
    );
    return data.data;
}

export async function issueCertificateBatch(drafts: CertificateDraft[]) {
    const universityCode = drafts[0]?.university_code;
    if (drafts.some((draft) => draft.university_code && draft.university_code !== universityCode)) {
        throw new Error("A certificate batch can only target one university.");
    }
    const certificates = await Promise.all(drafts.map(async (draft) => {
        const targetUniversity = draft.university_code || getSessionUser()?.university_code || "";
        const uploaded = draft.diploma_file
            ? await uploadDiploma(draft.diploma_file, draft.university_code)
            : null;
        const hashInput = draft.diploma_file
            ? await draft.diploma_file.arrayBuffer()
            : await (async () => {
                const metadata = JSON.stringify({
                    student_id: draft.student_id.trim(),
                    student_name: draft.student_name.trim(),
                    student_email: draft.student_email.trim().toLowerCase(),
                    degree: draft.degree.trim(),
                    university_code: targetUniversity.trim().toUpperCase(),
                });
                return new TextEncoder().encode(metadata).buffer;
            })();

        return {
            student_id: draft.student_id.trim(),
            student_name: draft.student_name.trim(),
            student_email: draft.student_email.trim().toLowerCase(),
            degree: draft.degree.trim(),
            issue_date: draft.issue_date,
            university_code: targetUniversity || undefined,
            degree_number: draft.degree_number ?? 1,
            additional_degree: draft.additional_degree ?? false,
            cert_hash: await sha256Hex(hashInput),
            diploma_url: uploaded?.diploma_url ?? null,
            diploma_file_name: uploaded?.diploma_file_name ?? null,
        };
    }));

    const { data } = await apiClient.post<{ data: CertificateRecord[]; count: number }>(
        "/certificates/batch",
        { certificates, university_code: universityCode || undefined },
    );
    return data;
}

export async function listAdminUsers() {
    const user = getSessionUser();
    const path = isSuperAdminSession(user)
        ? "/admin/subadmins"
        : "/admin/students";
    const { data } = await apiClient.get<{ data: Record<string, unknown>[] }>(path);
    return data.data;
}

export async function createUniversityAdmin(email: string, universityCode: string) {
    const { data } = await apiClient.post("/admin/users", {
        email,
        university_code: universityCode,
    });
    return data;
}

export async function updateStudentAccess(userId: number, frozen: boolean) {
    const { data } = await apiClient.patch(`/admin/students/${userId}/access`, {
        frozen,
    });
    return data;
}

export async function validateCertificateBatch(
    certificates: Record<string, unknown>[],
    universityCode?: string,
) {
    const { data } = await apiClient.post("/certificates/validate-batch", {
        certificates,
        university_code: universityCode || undefined,
    });
    return data as Record<string, unknown>;
}

export async function lookupStudentCredentials(studentId?: string, studentEmail?: string) {
    const { data } = await apiClient.get<{ data: CertificateRecord[]; degree_count: number; next_degree_number: number }>(
        "/v1/students/credential-lookup",
        { params: { student_id: studentId || undefined, student_email: studentEmail || undefined } },
    );
    return data;
}

export async function checkDiplomaFileNames(fileNames: string[]) {
    const { data } = await apiClient.post("/certificates/check-diploma-file-names", {
        file_names: fileNames,
    });
    return data as Record<string, unknown>;
}

export async function listRecentVerifications(limit = 5) {
    const { data } = await apiClient.get<{ data: CertificateRecord[] }>(
        "/admin/recent-verifications",
        { params: { limit } },
    );
    return data.data;
}

export async function requestCertificateDeletion(certificateId: number, reason: string) {
    const { data } = await apiClient.post(`/certificates/${certificateId}/deletion-request`, { reason });
    return data;
}
