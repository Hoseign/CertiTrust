export type AcademicLevel = "bachelors" | "masters" | "doctorate" | "other";

export function getAcademicLevel(program: string): AcademicLevel {
    const normalized = program.trim().toLowerCase();
    const acronym = normalized.replace(/[^a-z0-9]/g, "");

    if (
        normalized.includes("master") ||
        /^(mba|ma|ms|mpa|mph|mfa)/.test(acronym)
    ) {
        return "masters";
    }

    if (
        normalized.includes("doctor") ||
        ["phd", "edd", "dba", "dpa", "deng", "md", "jd"].some((code) =>
            acronym.startsWith(code),
        )
    ) {
        return "doctorate";
    }

    if (
        normalized.includes("bachelor") ||
        /^(bs|ba|beed|bsed|bshm|bstm|bsn|bsa)/.test(acronym)
    ) {
        return "bachelors";
    }

    return "other";
}
