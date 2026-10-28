export type RecordFilterValues = {
    academicLevel: string;
    program: string;
    year: string;
    search: string;
    university?: string;
    status?: string;
};

type RecordFilterBarProps = {
    value: RecordFilterValues;
    onChange: (value: RecordFilterValues) => void;
    programs?: string[];
    years?: string[];
    universities?: { value: string; label: string }[];
    statuses?: string[];
    searchPlaceholder?: string;
};

const fieldClassName =
    "min-h-12 w-full rounded-lg border border-slate-300 bg-white px-3 text-sm text-slate-900 outline-none transition focus:border-blue-600 focus:ring-2 focus:ring-blue-100";

const labelClassName = "mb-1.5 block text-xs font-semibold text-slate-600";

export default function RecordFilterBar({
    value,
    onChange,
    programs = [],
    years = [],
    universities = [],
    statuses = [],
    searchPlaceholder = "Search credentials by student name, ID, or certificate hash...",
}: RecordFilterBarProps) {
    const update = (patch: Partial<RecordFilterValues>) =>
        onChange({ ...value, ...patch });

    const hasFilters = Boolean(
        value.academicLevel ||
        value.program ||
        value.year ||
        value.search ||
        value.university ||
        value.status,
    );

    return (
        <section
            aria-label="Record filters"
            className="mb-6 rounded-xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5"
        >
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
                {universities.length > 0 && (
                    <label className="min-w-0">
                        <span className={labelClassName}>University</span>
                        <select
                            className={fieldClassName}
                            value={value.university ?? ""}
                            onChange={(event) => update({ university: event.target.value })}
                        >
                            <option value="">All Universities</option>
                            {universities.map((university) => (
                                <option key={university.value} value={university.value}>
                                    {university.label}
                                </option>
                            ))}
                        </select>
                    </label>
                )}

                <label className="min-w-0">
                    <span className={labelClassName}>Academic Level</span>
                    <select
                        className={fieldClassName}
                        value={value.academicLevel}
                        onChange={(event) => update({ academicLevel: event.target.value })}
                    >
                        <option value="">All Levels</option>
                        <option value="bachelors">Undergraduate / Bachelor's</option>
                        <option value="masters">Master's Degree</option>
                        <option value="doctorate">Doctorate / Ph.D.</option>
                    </select>
                </label>

                <label className="min-w-0">
                    <span className={labelClassName}>Program / Degree Title</span>
                    <select
                        className={fieldClassName}
                        value={value.program}
                        onChange={(event) => update({ program: event.target.value })}
                    >
                        <option value="">All Programs</option>
                        {programs.map((program) => (
                            <option key={program} value={program}>
                                {program}
                            </option>
                        ))}
                    </select>
                </label>

                <label className="min-w-0">
                    <span className={labelClassName}>Batch / Academic Year</span>
                    <select
                        className={fieldClassName}
                        value={value.year}
                        onChange={(event) => update({ year: event.target.value })}
                    >
                        <option value="">All Years</option>
                        {years.map((year) => (
                            <option key={year} value={year}>
                                {year}
                            </option>
                        ))}
                    </select>
                </label>

                {statuses.length > 0 && (
                    <label className="min-w-0">
                        <span className={labelClassName}>Verification Status</span>
                        <select
                            className={fieldClassName}
                            value={value.status ?? ""}
                            onChange={(event) => update({ status: event.target.value })}
                        >
                            <option value="">All Statuses</option>
                            {statuses.map((status) => (
                                <option key={status} value={status}>
                                    {status}
                                </option>
                            ))}
                        </select>
                    </label>
                )}

                <label className="min-w-0 sm:col-span-2 xl:col-span-2">
                    <span className={labelClassName}>Search</span>
                    <input
                        type="search"
                        className={fieldClassName}
                        value={value.search}
                        onChange={(event) => update({ search: event.target.value })}
                        placeholder={searchPlaceholder}
                    />
                </label>
            </div>
            {hasFilters && (
                <div className="mt-3 flex justify-end">
                    <button
                        type="button"
                        onClick={() =>
                            onChange({
                                academicLevel: "",
                                program: "",
                                year: "",
                                search: "",
                                university: "",
                                status: "",
                            })
                        }
                        className="min-h-10 rounded-lg px-3 text-sm font-semibold text-blue-700 hover:bg-blue-50 focus:outline-none focus:ring-2 focus:ring-blue-200"
                    >
                        Reset filters
                    </button>
                </div>
            )}
        </section>
    );
}
