import { apiClient } from "./apiClient";

export type ApiCollection<T> = { data: T[] };
export type UniversityRecord = {
    code: string;
    university_name: string;
    display_name?: string;
    branch_campus?: string | null;
};
export type AdminAccount = {
    id: number;
    name: string;
    email: string;
    role: string;
    university_code: string;
    [field: string]: unknown;
};
export type DeletedSubadminUniversity = {
    university_code: string;
    university_name: string;
    deleted_subadmins: { email: string; deleted_at: string | null }[];
    latest_deleted_at: string | null;
};

export async function listDeletedSubadminUniversities() {
    const { data } = await apiClient.get<ApiCollection<DeletedSubadminUniversity>>("/admin/junk");
    return data.data;
}

export async function permanentlyDeleteJunkStudent(universityCode: string, userId: number) {
    const { data } = await apiClient.delete(
        `/admin/junk/${encodeURIComponent(universityCode)}/students/${userId}`,
    );
    return data as { message: string; deleted_certificate_count: number };
}

export async function permanentlyDeleteJunkUniversity(universityCode: string) {
    const { data } = await apiClient.delete(`/admin/junk/${encodeURIComponent(universityCode)}`);
    return data as {
        message: string;
        deleted_student_count: number;
        deleted_certificate_count: number;
    };
}

export async function listSubadmins(universityCode?: string) {
    const { data } = await apiClient.get<ApiCollection<AdminAccount>>("/admin/subadmins", {
        params: universityCode ? { university_code: universityCode } : undefined,
    });
    return data.data;
}

export async function listUniversities() {
    const { data } = await apiClient.get<ApiCollection<UniversityRecord>>("/admin/universities");
    return data.data;
}

export async function bindSubadmin(payload: {
    email: string;
    university_code: string;
    university_name: string;
    display_name: string;
    branch_campus?: string;
    name?: string;
}) {
    const { data } = await apiClient.post("/admin/subadmins", payload);
    return data;
}

export async function updateSubadmin(id: number, payload: Record<string, unknown>) {
    const { data } = await apiClient.put(`/admin/subadmins/${id}`, payload);
    return data;
}

export async function unbindSubadminGoogle(id: number) {
    const { data } = await apiClient.delete(`/admin/subadmins/${id}/google`);
    return data;
}

export async function deleteSubadmin(id: number) {
    const { data } = await apiClient.delete(`/admin/subadmins/${id}`);
    return data;
}

export async function purgeAccountsAndCredentials() {
    const { data } = await apiClient.delete("/admin/accounts-and-credentials");
    return data as {
        message: string;
        data: {
            deleted_subadmin_count: number;
            deleted_student_count: number;
            deleted_account_count: number;
            deleted_certificate_count: number;
        };
    };
}

export async function setUniversityAccess(universityCode: string, scope: "admin" | "students" | "both", frozen: boolean) {
    const { data } = await apiClient.patch(
        `/admin/universities/${encodeURIComponent(universityCode)}/access`,
        { scope, frozen },
    );
    return data;
}

export async function listUniversityStudents<T = Record<string, unknown>>(universityCode?: string) {
    const path = universityCode
        ? `/admin/universities/${encodeURIComponent(universityCode)}/students`
        : "/admin/students";
    const { data } = await apiClient.get<{
        data: T[];
        university_code?: string;
        university_students_frozen?: boolean;
        can_manage_university_freeze?: boolean;
    }>(path);
    return data;
}

export async function setAllStudentAccess(frozen: boolean) {
    const { data } = await apiClient.patch("/admin/students/access", { frozen });
    return data;
}

export async function deleteStudent(userId: number) {
    const { data } = await apiClient.delete(`/admin/students/${userId}`);
    return data;
}

export async function revokeCertificateRecord(certificateId: number) {
    const { data } = await apiClient.delete(`/admin/certificates/${certificateId}`);
    return data as {
        message: string;
        data: { certificate_id: number; certificate_code: string; university_code: string };
    };
}

export async function getSuperAdminOverview() {
    const { data } = await apiClient.get<{ data: Record<string, unknown> }>("/admin/overview");
    return data.data;
}

export async function getAdminHistory() {
    const { data } = await apiClient.get<ApiCollection<Record<string, unknown>>>("/admin/history");
    return data.data;
}

export async function listDeletionRequests() {
    const { data } = await apiClient.get<ApiCollection<Record<string, unknown>>>(
        "/admin/certificate-deletion-requests",
    );
    return data.data;
}

export async function reviewDeletionRequest(
    requestId: number,
    decision: "approved" | "rejected",
    reviewerNote?: string,
) {
    const { data } = await apiClient.patch(
        `/admin/certificate-deletion-requests/${requestId}`,
        { decision, reviewer_note: reviewerNote },
    );
    return data;
}