export const PROGRAM_SUGGESTIONS = [
    "Doctor of Information Technology (DIT)",
    "Doctor of Philosophy (PhD)",
    "MS Information Technology (MSIT)",
    "Master in Business Administration (MBA)",
    "BS Information Technology (BSIT)",
    "BS Computer Science (BSCS)",
    "BS Business Administration (BSBA)",
    "BS Education (BSEd)",
    "Cert. in Cybersecurity & Web Security",
    "Professional Certificate in Cybersecurity",
];

export const ACADEMIC_LEVELS = [
    { value: "bachelors_first", label: "Bachelor's (1st Degree)" },
    { value: "second_degree", label: "Second Degree" },
    { value: "masters", label: "Master's" },
    { value: "doctoral", label: "Doctoral" },
    { value: "professional", label: "Professional" },
] as const;

export type AcademicLevel =
    | (typeof ACADEMIC_LEVELS)[number]["value"]
    | "other";

export function getAcademicLevel(program: string, degreeNumber = 1): AcademicLevel {
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
        ["phd", "dit", "edd", "dba", "dpa", "deng", "md", "jd"].some((code) =>
            acronym.startsWith(code),
        )
    ) {
        return "doctoral";
    }

    if (
        normalized.includes("professional") ||
        normalized.includes("certification") ||
        normalized.startsWith("cert")
    ) {
        return "professional";
    }

    if (
        normalized.includes("bachelor") ||
        /^(bs|ba|beed|bsed|bshm|bstm|bsn|bsa)/.test(acronym)
    ) {
        return degreeNumber > 1 ? "second_degree" : "bachelors_first";
    }

    return degreeNumber > 1 ? "second_degree" : "other";
}

export function getAcademicLevelLabel(program: string, degreeNumber = 1): string {
    const level = getAcademicLevel(program, degreeNumber);
    return ACADEMIC_LEVELS.find((option) => option.value === level)?.label ?? "Other";
}
