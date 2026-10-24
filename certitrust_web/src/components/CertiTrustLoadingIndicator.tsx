type CertiTrustLoadingIndicatorProps = {
    size?: number;
    message?: string;
    className?: string;
    inline?: boolean;
};

export default function CertiTrustLoadingIndicator({
    size = 48,
    message,
    className = "",
    inline = false,
}: CertiTrustLoadingIndicatorProps) {
    return (
        <span
            className={`certitrust-loading ${inline ? "certitrust-loading-inline" : ""} ${className}`}
            role="status"
            aria-live="polite"
        >
            <span
                className="certitrust-loading-mark"
                style={{ width: size, height: size }}
                aria-hidden="true"
            >
                <img src="/certitrustlogo.png" alt="" />
                <span className="certitrust-loading-fill" />
            </span>
            {message ? <span className="certitrust-loading-message">{message}</span> : null}
        </span>
    );
}
