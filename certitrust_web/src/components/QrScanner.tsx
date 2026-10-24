import { useEffect, useRef, useState } from "react";
import type { BrowserQRCodeReader, IScannerControls } from "@zxing/browser";

type QrScannerProps = {
    onScan: (value: string) => void;
    onClose: () => void;
};

function certificateValue(rawValue: string) {
    try {
        const url = new URL(rawValue);
        const queryValue = url.searchParams.get("hash")
            || url.searchParams.get("cert_hash")
            || url.searchParams.get("certificateId")
            || url.searchParams.get("code");
        if (queryValue) return queryValue;

        const certificatePath = url.pathname.match(/\/certificates\/([^/]+)\/?$/i);
        if (certificatePath?.[1]) return decodeURIComponent(certificatePath[1]);

        return rawValue;
    } catch {
        return rawValue;
    }
}

export default function QrScanner({ onScan, onClose }: QrScannerProps) {
    const videoRef = useRef<HTMLVideoElement>(null);
    const controlsRef = useRef<IScannerControls | null>(null);
    const isClosedRef = useRef(false);
    const hasScannedRef = useRef(false);
    const [error, setError] = useState("");
    const [isStarting, setIsStarting] = useState(false);
    const [isCameraActive, setIsCameraActive] = useState(false);
    const [hasVideoFrame, setHasVideoFrame] = useState(false);
    const readerRef = useRef<BrowserQRCodeReader | null>(null);

    const getReader = async () => {
        if (!readerRef.current) {
            const { BrowserQRCodeReader } = await import("@zxing/browser");
            readerRef.current = new BrowserQRCodeReader();
        }
        return readerRef.current;
    };

    const stopCameraTracks = () => {
        const stream = videoRef.current?.srcObject;
        if (stream instanceof MediaStream) {
            stream.getTracks().forEach((track) => track.stop());
        }
    };

    useEffect(() => {
        isClosedRef.current = false;
        return () => {
            isClosedRef.current = true;
            controlsRef.current?.stop();
            stopCameraTracks();
        };
    }, []);

    const stopCamera = () => {
        controlsRef.current?.stop();
        controlsRef.current = null;
        stopCameraTracks();
        if (videoRef.current) videoRef.current.srcObject = null;
        setIsCameraActive(false);
        setHasVideoFrame(false);
    };

    const close = () => {
        stopCamera();
        onClose();
    };

    const reportScan = (rawValue: string) => {
        if (hasScannedRef.current || isClosedRef.current) return;
        const value = certificateValue(rawValue).trim();
        if (!value) return;
        hasScannedRef.current = true;
        stopCamera();
        onScan(value);
    };

    const startCamera = async () => {
        if (!videoRef.current || isStarting) return;
        const video = videoRef.current;
        setError("");
        setHasVideoFrame(false);
        setIsStarting(true);
        try {
            if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) {
                setError("Camera access requires HTTPS or localhost. Open this page on a secure connection and try again.");
                return;
            }

            const reader = await getReader();
            const controls = await reader.decodeFromConstraints(
                {
                    audio: false,
                    video: { facingMode: { ideal: "environment" } },
                },
                video,
                (result) => {
                    if (!result) return;
                    reportScan(result.getText());
                },
            );
            if (isClosedRef.current) {
                controls.stop();
                return;
            }
            controlsRef.current = controls;
            setIsCameraActive(true);
        } catch (cameraError) {
            const errorName = cameraError instanceof DOMException ? cameraError.name : "";
            if (errorName === "NotAllowedError" || errorName === "PermissionDeniedError") {
                setError("Camera permission was blocked. Select the camera icon or site settings beside the address bar, allow camera access for this site, then try again.");
            } else if (errorName === "NotFoundError" || errorName === "DevicesNotFoundError") {
                setError("No camera was found on this device. Connect a camera or choose a QR image.");
            } else if (errorName === "NotReadableError" || errorName === "TrackStartError") {
                setError("The camera is in use by another app or browser tab. Close it there and try again.");
            } else {
                setError(cameraError instanceof Error
                    ? `Camera could not start: ${cameraError.message}`
                    : "Camera could not start. Check this site's camera permission or choose a QR image.");
            }
            stopCamera();
        } finally {
            setIsStarting(false);
        }
    };

    const scanImage = async (file?: File) => {
        if (!file) return;
        setError("");
        const imageUrl = URL.createObjectURL(file);
        try {
            const reader = await getReader();
            const result = await reader.decodeFromImageUrl(imageUrl);
            reportScan(result.getText());
        } catch {
            setError("No readable QR code was found in that image.");
        } finally {
            URL.revokeObjectURL(imageUrl);
        }
    };

    return (
        <div className="fixed inset-0 z-50 grid place-items-center bg-slate-950/70 p-4" onClick={close}>
            <section
                role="dialog"
                aria-modal="true"
                aria-labelledby="qr-scanner-title"
                className="w-full max-w-xl rounded-2xl bg-white p-5 shadow-2xl"
                onClick={(event) => event.stopPropagation()}
            >
                <div className="mb-4 flex items-center justify-between gap-4">
                    <h2 id="qr-scanner-title" className="text-xl font-extrabold text-slate-900">
                        Scan certificate QR code
                    </h2>
                    <button type="button" onClick={close} className="rounded-lg px-3 py-2 font-bold text-slate-600 hover:bg-slate-100">
                        Close
                    </button>
                </div>
                <video
                    ref={videoRef}
                    autoPlay
                    muted
                    playsInline
                    onLoadedData={() => setHasVideoFrame(videoRef.current?.videoWidth !== 0)}
                    onEmptied={() => setHasVideoFrame(false)}
                    className="block aspect-video max-h-[55vh] w-full rounded-xl bg-slate-950 object-contain"
                />
                <div className="mt-4 flex flex-wrap gap-3">
                    <button
                        type="button"
                        onClick={startCamera}
                        disabled={isStarting || isCameraActive}
                        className="rounded-xl bg-blue-700 px-4 py-3 font-bold text-white hover:bg-blue-800 disabled:opacity-60"
                    >
                        {isStarting ? "Requesting camera permission..." : "Allow camera access"}
                    </button>
                    <label className="cursor-pointer rounded-xl border border-slate-300 px-4 py-3 font-bold text-slate-700 hover:bg-slate-50">
                        Choose QR image
                        <input
                            className="sr-only"
                            type="file"
                            accept="image/*"
                            onChange={(event) => void scanImage(event.target.files?.[0])}
                        />
                    </label>
                    {isCameraActive && (
                        <button type="button" onClick={stopCamera} className="rounded-xl border border-slate-300 px-4 py-3 font-bold text-slate-700 hover:bg-slate-50">
                            Stop camera
                        </button>
                    )}
                </div>
                {isCameraActive && !hasVideoFrame && (
                    <p role="status" className="mt-3 text-sm font-medium text-amber-700">
                        Camera connected; waiting for a video frame. If the preview stays black, close other apps using the camera and retry.
                    </p>
                )}
                {error && <p role="alert" className="mt-3 text-sm font-medium text-red-700">{error}</p>}
                <p className="mt-3 text-sm text-slate-500">
                    When your browser asks, choose Allow. If you previously blocked access, open the camera/site-permissions icon beside the address bar, allow camera access, and retry. Camera access requires HTTPS or localhost.
                </p>
            </section>
        </div>
    );
}
