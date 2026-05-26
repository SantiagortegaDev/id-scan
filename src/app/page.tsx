'use client';

import { useState, useRef, useCallback, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import {
  ScanLine,
  Camera,
  RotateCcw,
  ChevronLeft,
  ZoomIn,
  ZoomOut,
  Sun,
  Loader2,
  AlertCircle,
  CheckCircle2,
  Hash,
  User,
  Copy,
  Check,
  Upload,
  FileText,
  Zap,
} from 'lucide-react';

// ====== TYPES ======
type AppScreen = 'welcome' | 'home' | 'camera' | 'results' | 'error';

interface OcrData {
  documentNumber: string;
  fullName: string;
  rawText: string;
  confidence: 'high' | 'medium' | 'low';
}

interface ScanResult {
  documentNumber: string;
  fullName: string;
  rawText: string;
  confidence: 'high' | 'medium' | 'low';
  method: string;
  timestamp: Date;
  capturedImage?: string;
}

// ====== WELCOME SCREEN ======
function WelcomeScreen({ onAccept }: { onAccept: () => void }) {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center bg-gradient-to-b from-slate-900 to-slate-800 text-white p-6">
      <div className="max-w-md w-full text-center space-y-8">
        <div className="mx-auto w-24 h-24 rounded-2xl bg-gradient-to-br from-emerald-400 to-emerald-600 flex items-center justify-center shadow-xl shadow-emerald-500/25">
          <ScanLine className="w-12 h-12 text-white" />
        </div>

        <div>
          <h1 className="text-3xl font-bold mb-2">ID Scan Colombia</h1>
          <p className="text-slate-400 text-lg">
            Escáner de cédula de ciudadanía
          </p>
        </div>

        <div className="space-y-4 text-left">
          <div className="flex items-start gap-3 p-4 rounded-xl bg-white/5 border border-white/10">
            <Zap className="w-5 h-5 text-emerald-400 mt-0.5 shrink-0" />
            <div>
              <p className="font-medium">Detección automática</p>
              <p className="text-sm text-slate-400">
                Apunta la cámara a la parte delantera de tu cédula y se detecta sola
              </p>
            </div>
          </div>
          <div className="flex items-start gap-3 p-4 rounded-xl bg-white/5 border border-white/10">
            <Hash className="w-5 h-5 text-emerald-400 mt-0.5 shrink-0" />
            <div>
              <p className="font-medium">Número y nombre</p>
              <p className="text-sm text-slate-400">
                Extrae el número de documento (sin puntos) y nombre completo
              </p>
            </div>
          </div>
          <div className="flex items-start gap-3 p-4 rounded-xl bg-white/5 border border-white/10">
            <FileText className="w-5 h-5 text-emerald-400 mt-0.5 shrink-0" />
            <div>
              <p className="font-medium">Texto crudo</p>
              <p className="text-sm text-slate-400">
                Muestra todo el texto leído de la cédula en crudo
              </p>
            </div>
          </div>
        </div>

        <div className="p-4 rounded-xl bg-amber-500/10 border border-amber-500/20 text-amber-200 text-sm">
          <p className="font-medium mb-1">Se requiere acceso a la cámara</p>
          <p>
            Esta app necesita acceso a tu cámara para escanear la parte delantera
            de tu cédula. La imagen se procesa de forma segura.
          </p>
        </div>

        <Button
          onClick={onAccept}
          className="w-full h-14 text-lg font-semibold bg-emerald-500 hover:bg-emerald-600 text-white rounded-xl shadow-lg shadow-emerald-500/25 transition-all duration-200"
        >
          <Camera className="w-5 h-5 mr-2" />
          Continuar y dar permisos
        </Button>
      </div>
    </div>
  );
}

// ====== HOME SCREEN ======
function HomeScreen({
  onScan,
  onImageUpload,
  lastResult,
}: {
  onScan: () => void;
  onImageUpload: (dataUrl: string) => void;
  lastResult: ScanResult | null;
}) {
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleFileSelect = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (!file) return;

      const reader = new FileReader();
      reader.onload = (ev) => {
        const dataUrl = ev.target?.result as string;
        if (dataUrl) {
          onImageUpload(dataUrl);
        }
      };
      reader.readAsDataURL(file);
      e.target.value = '';
    },
    [onImageUpload]
  );

  return (
    <div className="min-h-screen flex flex-col bg-gradient-to-b from-slate-900 to-slate-800 text-white">
      <header className="p-6 flex items-center gap-3">
        <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-emerald-400 to-emerald-600 flex items-center justify-center">
          <ScanLine className="w-5 h-5 text-white" />
        </div>
        <div>
          <h1 className="text-lg font-bold">ID Scan</h1>
          <p className="text-xs text-slate-400">Cédula de ciudadanía</p>
        </div>
      </header>

      <div className="flex-1 flex flex-col items-center justify-center p-6 space-y-8">
        <button
          onClick={onScan}
          className="group relative w-48 h-48 rounded-full bg-gradient-to-br from-emerald-400 to-emerald-600 flex items-center justify-center shadow-2xl shadow-emerald-500/30 hover:shadow-emerald-500/50 transition-all duration-300 hover:scale-105 active:scale-95"
        >
          <div className="absolute inset-0 rounded-full bg-white/10 group-hover:bg-white/20 transition-colors" />
          <div className="flex flex-col items-center gap-3">
            <Camera className="w-16 h-16 text-white" />
            <span className="text-white font-bold text-lg">Escanear</span>
          </div>
        </button>

        <div className="text-center space-y-1">
          <p className="text-slate-300 font-medium">Apunta a la parte delantera</p>
          <p className="text-slate-500 text-sm">
            Detección automática de nombre y número de cédula
          </p>
        </div>

        <div className="w-full max-w-sm space-y-3">
          <div className="relative">
            <div className="absolute inset-0 flex items-center">
              <div className="w-full border-t border-white/10" />
            </div>
            <div className="relative flex justify-center text-xs">
              <span className="bg-slate-800 px-2 text-slate-400">o también</span>
            </div>
          </div>

          <Button
            variant="outline"
            onClick={() => fileInputRef.current?.click()}
            className="w-full h-12 border-white/20 text-white hover:bg-white/10 rounded-xl"
          >
            <Upload className="w-4 h-4 mr-2" />
            Subir foto de la galería
          </Button>
          <input
            ref={fileInputRef}
            type="file"
            accept="image/*"
            className="hidden"
            onChange={handleFileSelect}
          />
        </div>

        {lastResult && (
          <Card className="w-full max-w-sm bg-white/5 border-white/10 text-white">
            <CardContent className="p-4 space-y-2">
              <div className="flex items-center justify-between">
                <p className="text-sm text-slate-400">Último escaneo</p>
                <p className="text-xs text-slate-500">
                  {lastResult.timestamp.toLocaleTimeString('es-CO')}
                </p>
              </div>
              <p className="font-semibold">{lastResult.fullName || 'Sin nombre'}</p>
              <p className="text-sm text-slate-400 font-mono">
                CC {lastResult.documentNumber || 'N/A'}
              </p>
            </CardContent>
          </Card>
        )}
      </div>

      <div className="p-6">
        <div className="p-4 rounded-xl bg-white/5 border-white/10 space-y-2">
          <p className="font-medium text-sm text-slate-300">Consejos para un buen escaneo:</p>
          <ul className="text-xs text-slate-400 space-y-1">
            <li>- Buena iluminación, sin reflejos</li>
            <li>- Coloca la cédula sobre una superficie plana</li>
            <li>- Apunta la cámara a la parte delantera</li>
            <li>- La detección es automática, no necesitas tomar foto</li>
          </ul>
        </div>
      </div>
    </div>
  );
}

// ====== CAMERA SCREEN WITH AUTO OCR ======
function CameraScreen({
  onResult,
  onManualCapture,
  onCancel,
}: {
  onResult: (result: ScanResult) => void;
  onManualCapture: (imageData: string) => void;
  onCancel: () => void;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const [cameraReady, setCameraReady] = useState(false);
  const [zoom, setZoom] = useState(1);
  const [torchOn, setTorchOn] = useState(false);
  const [scanning, setScanning] = useState(false);
  const [scanStatus, setScanStatus] = useState<string>('Preparando cámara...');
  const [attempts, setAttempts] = useState(0);
  const [lastOcrError, setLastOcrError] = useState<string>('');
  const autoScanRef = useRef<boolean>(true);
  const processingRef = useRef<boolean>(false);

  // Initialize camera
  useEffect(() => {
    let mounted = true;

    async function startCamera() {
      try {
        const constraints: MediaStreamConstraints = {
          video: {
            facingMode: { ideal: 'environment' },
            width: { ideal: 1920 },
            height: { ideal: 1080 },
            advanced: [{ focusMode: 'continuous' } as any],
          },
          audio: false,
        };

        const stream = await navigator.mediaDevices.getUserMedia(constraints);
        if (!mounted) {
          stream.getTracks().forEach((t) => t.stop());
          return;
        }

        streamRef.current = stream;
        if (videoRef.current) {
          videoRef.current.srcObject = stream;
          await videoRef.current.play();
          setCameraReady(true);
          setScanStatus('Listo. Apunta la cédula...');
        }
      } catch (err) {
        console.error('Camera error:', err);
        setScanStatus('Error al acceder a la cámara');
      }
    }

    startCamera();

    return () => {
      mounted = false;
      autoScanRef.current = false;
      if (streamRef.current) {
        streamRef.current.getTracks().forEach((t) => t.stop());
      }
    };
  }, []);

  // Auto-scan loop: capture frame every 2.5s and send to OCR
  useEffect(() => {
    if (!cameraReady) return;

    autoScanRef.current = true;
    setScanning(true);

    const interval = setInterval(async () => {
      if (!autoScanRef.current || processingRef.current) return;
      if (!videoRef.current || !canvasRef.current) return;

      const video = videoRef.current;
      if (video.readyState < 2) return;

      processingRef.current = true;

      // Capture frame
      const canvas = canvasRef.current;
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      const ctx = canvas.getContext('2d');
      if (!ctx) {
        processingRef.current = false;
        return;
      }
      ctx.drawImage(video, 0, 0);

      const imageData = canvas.toDataURL('image/jpeg', 0.85);

      setScanStatus('Analizando...');
      setAttempts((prev) => prev + 1);

      try {
        const response = await fetch('/api/ocr', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ image: imageData }),
        });

        if (!response.ok) {
          throw new Error('Error en el servidor');
        }

        const data = await response.json();

        if (data.success && data.data) {
          const ocrData: OcrData = data.data;

          if (ocrData.documentNumber && ocrData.documentNumber.length >= 6) {
            // Found a document number! Stop scanning and show result
            autoScanRef.current = false;
            setScanning(false);

            // Stop camera
            if (streamRef.current) {
              streamRef.current.getTracks().forEach((t) => t.stop());
            }

            const result: ScanResult = {
              documentNumber: ocrData.documentNumber,
              fullName: ocrData.fullName || '',
              rawText: ocrData.rawText || '',
              confidence: ocrData.confidence || 'medium',
              method: 'OCR automático (IA)',
              timestamp: new Date(),
              capturedImage: imageData,
            };

            onResult(result);
            return;
          } else {
            // No document number found, keep scanning
            setScanStatus('No se detectó número. Apunta mejor la cédula...');
            setLastOcrError(ocrData.rawText ? `Texto parcial: ${ocrData.rawText.substring(0, 80)}...` : '');
          }
        }
      } catch (err) {
        console.error('OCR scan error:', err);
        setScanStatus('Error de conexión. Reintentando...');
        setLastOcrError(String(err));
      }

      processingRef.current = false;
    }, 2500); // Every 2.5 seconds

    return () => {
      clearInterval(interval);
    };
  }, [cameraReady, onResult]);

  // Manual capture button
  const handleManualCapture = useCallback(() => {
    if (!videoRef.current || !canvasRef.current) return;

    const video = videoRef.current;
    const canvas = canvasRef.current;
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    ctx.drawImage(video, 0, 0);
    const imageData = canvas.toDataURL('image/jpeg', 0.95);

    // Stop auto-scan
    autoScanRef.current = false;
    setScanning(false);

    // Stop camera
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((t) => t.stop());
    }

    onManualCapture(imageData);
  }, [onManualCapture]);

  // Zoom controls
  const handleZoomIn = useCallback(async () => {
    if (!streamRef.current) return;
    const track = streamRef.current.getVideoTracks()[0];
    if (!track) return;
    try {
      const capabilities = track.getCapabilities?.();
      if (capabilities?.zoom) {
        const newZoom = Math.min(zoom + 0.5, capabilities.zoom.max);
        await track.applyConstraints({ advanced: [{ zoom: newZoom } as any] });
        setZoom(newZoom);
      }
    } catch {}
  }, [zoom]);

  const handleZoomOut = useCallback(async () => {
    if (!streamRef.current) return;
    const track = streamRef.current.getVideoTracks()[0];
    if (!track) return;
    try {
      const capabilities = track.getCapabilities?.();
      if (capabilities?.zoom) {
        const newZoom = Math.max(zoom - 0.5, capabilities.zoom.min);
        await track.applyConstraints({ advanced: [{ zoom: newZoom } as any] });
        setZoom(newZoom);
      }
    } catch {}
  }, [zoom]);

  const handleTorch = useCallback(async () => {
    if (!streamRef.current) return;
    const track = streamRef.current.getVideoTracks()[0];
    if (!track) return;
    try {
      await track.applyConstraints({
        advanced: [{ torch: !torchOn } as any],
      });
      setTorchOn(!torchOn);
    } catch {}
  }, [torchOn]);

  const handleCancel = useCallback(() => {
    autoScanRef.current = false;
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((t) => t.stop());
    }
    onCancel();
  }, [onCancel]);

  return (
    <div className="fixed inset-0 bg-black flex flex-col">
      <canvas ref={canvasRef} className="hidden" />

      {/* Camera View */}
      <div className="relative flex-1 overflow-hidden">
        <video
          ref={videoRef}
          className="absolute inset-0 w-full h-full object-cover"
          playsInline
          muted
          style={{ transform: `scale(${zoom})` }}
        />

        {/* Guide Overlay - ID card shape */}
        <div className="absolute inset-0 pointer-events-none">
          {/* Darkened areas */}
          <div className="absolute inset-0">
            <div className="absolute top-0 left-0 right-0 h-[20%] bg-black/50" />
            <div className="absolute bottom-0 left-0 right-0 h-[20%] bg-black/50" />
            <div className="absolute top-[20%] left-0 w-[8%] h-[60%] bg-black/50" />
            <div className="absolute top-[20%] right-0 w-[8%] h-[60%] bg-black/50" />
          </div>

          {/* ID Card guide rectangle */}
          <div className="absolute top-[20%] left-[8%] right-[8%] bottom-[20%]">
            {/* Corner accents */}
            <div className="absolute top-0 left-0 w-8 h-8 border-t-2 border-l-2 border-emerald-400 rounded-tl" />
            <div className="absolute top-0 right-0 w-8 h-8 border-t-2 border-r-2 border-emerald-400 rounded-tr" />
            <div className="absolute bottom-0 left-0 w-8 h-8 border-b-2 border-l-2 border-emerald-400 rounded-bl" />
            <div className="absolute bottom-0 right-0 w-8 h-8 border-b-2 border-r-2 border-emerald-400 rounded-br" />

            {/* Scanning animation */}
            {scanning && (
              <div
                className="absolute left-3 right-3 h-0.5 bg-emerald-400 shadow-lg shadow-emerald-400/50"
                style={{
                  animation: 'scanLine 2.5s ease-in-out infinite',
                  top: '50%',
                }}
              />
            )}
          </div>

          {/* Instructions at top */}
          <div className="absolute top-[5%] left-0 right-0 text-center">
            <div className="inline-block px-4 py-2 rounded-full bg-black/70 backdrop-blur-sm">
              <p className="text-white text-sm font-medium">
                Apunta la parte delantera de la cédula
              </p>
              <p className="text-emerald-300 text-xs mt-0.5">
                Detección automática • Buena iluminación
              </p>
            </div>
          </div>

          {/* Status at bottom of camera */}
          <div className="absolute bottom-[22%] left-0 right-0 text-center">
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-black/70 backdrop-blur-sm">
              {scanning ? (
                <Loader2 className="w-4 h-4 text-emerald-400 animate-spin" />
              ) : (
                <Camera className="w-4 h-4 text-slate-400" />
              )}
              <p className="text-sm text-white">{scanStatus}</p>
            </div>
          </div>
        </div>
      </div>

      {/* Controls */}
      <div className="bg-black/90 backdrop-blur-sm border-t border-white/10">
        <div className="flex items-center justify-between px-4 py-3">
          <Button
            variant="ghost"
            size="icon"
            onClick={handleCancel}
            className="text-white hover:bg-white/10"
          >
            <ChevronLeft className="w-6 h-6" />
          </Button>

          <div className="flex items-center gap-2">
            <Button
              variant="ghost"
              size="icon"
              onClick={handleZoomOut}
              className="text-white hover:bg-white/10"
            >
              <ZoomOut className="w-5 h-5" />
            </Button>
            <span className="text-white text-sm font-mono min-w-[3ch] text-center">
              {zoom.toFixed(1)}x
            </span>
            <Button
              variant="ghost"
              size="icon"
              onClick={handleZoomIn}
              className="text-white hover:bg-white/10"
            >
              <ZoomIn className="w-5 h-5" />
            </Button>
          </div>

          <Button
            variant="ghost"
            size="icon"
            onClick={handleTorch}
            className={`text-white hover:bg-white/10 ${torchOn ? 'bg-yellow-500/20 text-yellow-400' : ''}`}
          >
            <Sun className="w-5 h-5" />
          </Button>
        </div>

        <div className="flex items-center justify-center gap-6 px-4 pb-4">
          {/* Manual capture button */}
          <button
            onClick={handleManualCapture}
            disabled={!cameraReady}
            className="w-20 h-20 rounded-full border-4 border-white bg-white/10 flex items-center justify-center hover:bg-white/20 transition-colors active:scale-90 disabled:opacity-50"
          >
            <div className="w-14 h-14 rounded-full bg-white" />
          </button>
        </div>

        <div className="text-center pb-3 px-4">
          <p className="text-slate-400 text-xs">
            Escaneo automático cada 2.5s • Intento #{attempts} • O toca el botón para capturar manual
          </p>
          {lastOcrError && (
            <p className="text-amber-400/70 text-xs mt-1 truncate">
              {lastOcrError}
            </p>
          )}
        </div>
      </div>

      <style jsx>{`
        @keyframes scanLine {
          0%, 100% { top: 15%; }
          50% { top: 85%; }
        }
      `}</style>
    </div>
  );
}

// ====== PROCESSING OVERLAY ======
function ProcessingOverlay({ status }: { status: string }) {
  return (
    <div className="fixed inset-0 bg-black/80 backdrop-blur-sm flex flex-col items-center justify-center z-50">
      <div className="flex flex-col items-center gap-4">
        <Loader2 className="w-12 h-12 animate-spin text-emerald-400" />
        <p className="text-white text-lg font-medium">Procesando...</p>
        <p className="text-slate-400 text-sm">{status}</p>
      </div>
    </div>
  );
}

// ====== RESULTS SCREEN ======
function ResultsScreen({
  result,
  onNewScan,
  onBack,
}: {
  result: ScanResult;
  onNewScan: () => void;
  onBack: () => void;
}) {
  const [copied, setCopied] = useState<'doc' | 'name' | 'raw' | null>(null);

  const copyToClipboard = useCallback(async (text: string, field: 'doc' | 'name' | 'raw') => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(field);
      setTimeout(() => setCopied(null), 2000);
    } catch {}
  }, []);

  const confidenceColor = result.confidence === 'high'
    ? 'text-emerald-400'
    : result.confidence === 'medium'
    ? 'text-amber-400'
    : 'text-red-400';

  const confidenceLabel = result.confidence === 'high'
    ? 'Alta'
    : result.confidence === 'medium'
    ? 'Media'
    : 'Baja';

  return (
    <div className="min-h-screen flex flex-col bg-gradient-to-b from-slate-900 to-slate-800 text-white">
      {/* Header */}
      <header className="p-4 flex items-center gap-3 border-b border-white/10">
        <Button
          variant="ghost"
          size="icon"
          onClick={onBack}
          className="text-white hover:bg-white/10"
        >
          <ChevronLeft className="w-5 h-5" />
        </Button>
        <div>
          <h1 className="text-lg font-bold">Resultado</h1>
          <p className="text-xs text-slate-400">
            {result.method} • {result.timestamp.toLocaleTimeString('es-CO')}
          </p>
        </div>
      </header>

      <div className="flex-1 p-4 space-y-4 overflow-y-auto">
        {/* Success indicator */}
        <div className="flex items-center gap-2 p-3 rounded-xl bg-emerald-500/10 border border-emerald-500/20">
          <CheckCircle2 className="w-5 h-5 text-emerald-400 shrink-0" />
          <p className="text-sm text-emerald-200">
            Cédula detectada exitosamente
          </p>
        </div>

        {/* Document Number */}
        <Card className="bg-white/5 border-white/10 text-white">
          <CardContent className="p-5">
            <div className="flex items-center justify-between mb-2">
              <div className="flex items-center gap-2">
                <div className="w-10 h-10 rounded-lg bg-blue-500/20 flex items-center justify-center shrink-0">
                  <Hash className="w-5 h-5 text-blue-400" />
                </div>
                <p className="text-sm text-slate-400">Número de cédula</p>
              </div>
              <button
                onClick={() => copyToClipboard(result.documentNumber, 'doc')}
                className="p-1.5 rounded-lg hover:bg-white/10 transition-colors"
              >
                {copied === 'doc' ? (
                  <Check className="w-4 h-4 text-emerald-400" />
                ) : (
                  <Copy className="w-4 h-4 text-slate-400" />
                )}
              </button>
            </div>
            <p className="text-3xl font-bold font-mono tracking-wider">
              {result.documentNumber}
            </p>
          </CardContent>
        </Card>

        {/* Full Name */}
        <Card className="bg-white/5 border-white/10 text-white">
          <CardContent className="p-5">
            <div className="flex items-center justify-between mb-2">
              <div className="flex items-center gap-2">
                <div className="w-10 h-10 rounded-lg bg-purple-500/20 flex items-center justify-center shrink-0">
                  <User className="w-5 h-5 text-purple-400" />
                </div>
                <p className="text-sm text-slate-400">Nombre completo</p>
              </div>
              <button
                onClick={() => copyToClipboard(result.fullName, 'name')}
                className="p-1.5 rounded-lg hover:bg-white/10 transition-colors"
              >
                {copied === 'name' ? (
                  <Check className="w-4 h-4 text-emerald-400" />
                ) : (
                  <Copy className="w-4 h-4 text-slate-400" />
                )}
              </button>
            </div>
            <p className="text-xl font-semibold">
              {result.fullName || 'No detectado'}
            </p>
          </CardContent>
        </Card>

        {/* Confidence */}
        <div className="flex items-center gap-2 px-1">
          <span className="text-xs text-slate-400">Confianza:</span>
          <span className={`text-xs font-medium ${confidenceColor}`}>
            {confidenceLabel}
          </span>
        </div>

        {/* Raw Text */}
        <Card className="bg-white/5 border-white/10 text-white">
          <CardContent className="p-5">
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center gap-2">
                <FileText className="w-4 h-4 text-slate-400" />
                <p className="text-sm text-slate-400">Texto crudo detectado</p>
              </div>
              <button
                onClick={() => copyToClipboard(result.rawText, 'raw')}
                className="p-1.5 rounded-lg hover:bg-white/10 transition-colors"
              >
                {copied === 'raw' ? (
                  <Check className="w-4 h-4 text-emerald-400" />
                ) : (
                  <Copy className="w-4 h-4 text-slate-400" />
                )}
              </button>
            </div>
            <div className="p-3 rounded-lg bg-black/30 font-mono text-xs leading-relaxed break-all max-h-48 overflow-y-auto whitespace-pre-wrap">
              {result.rawText || 'Sin texto detectado'}
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Bottom Actions */}
      <div className="p-4 border-t border-white/10 space-y-3">
        <Button
          onClick={onNewScan}
          className="w-full h-12 bg-emerald-500 hover:bg-emerald-600 text-white rounded-xl font-semibold"
        >
          <Camera className="w-4 h-4 mr-2" />
          Nuevo escaneo
        </Button>
      </div>
    </div>
  );
}

// ====== ERROR SCREEN ======
function ErrorScreen({
  message,
  onRetry,
  onBack,
}: {
  message: string;
  onRetry: () => void;
  onBack: () => void;
}) {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center bg-gradient-to-b from-slate-900 to-slate-800 text-white p-6">
      <div className="max-w-md w-full text-center space-y-6">
        <AlertCircle className="w-16 h-16 text-red-400 mx-auto" />
        <div>
          <h2 className="text-xl font-bold mb-2">Error al escanear</h2>
          <p className="text-slate-400">{message}</p>
        </div>
        <div className="space-y-3">
          <Button
            onClick={onRetry}
            className="w-full h-12 bg-emerald-500 hover:bg-emerald-600 text-white rounded-xl font-semibold"
          >
            <RotateCcw className="w-4 h-4 mr-2" />
            Intentar de nuevo
          </Button>
          <Button
            variant="ghost"
            onClick={onBack}
            className="w-full text-slate-400 hover:text-white hover:bg-white/10"
          >
            Volver al inicio
          </Button>
        </div>
      </div>
    </div>
  );
}

// ====== MAIN APP ======
export default function Home() {
  const [screen, setScreen] = useState<AppScreen>('welcome');
  const [scanResult, setScanResult] = useState<ScanResult | null>(null);
  const [lastResult, setLastResult] = useState<ScanResult | null>(null);
  const [errorMessage, setErrorMessage] = useState('');
  const [processingStatus, setProcessingStatus] = useState('');
  const [isProcessing, setIsProcessing] = useState(false);

  useEffect(() => {
    const hasSeenWelcome = localStorage.getItem('idscan_welcomed');
    if (hasSeenWelcome) {
      setScreen('home');
    }
  }, []);

  const handleWelcomeAccept = useCallback(() => {
    localStorage.setItem('idscan_welcomed', 'true');
    setScreen('home');
  }, []);

  const handleStartScan = useCallback(() => {
    setScanResult(null);
    setScreen('camera');
  }, []);

  // Called when auto-OCR finds a result
  const handleAutoResult = useCallback((result: ScanResult) => {
    setScanResult(result);
    setLastResult(result);
    setIsProcessing(false);
    setScreen('results');
  }, []);

  // Called when user manually captures a photo
  const handleManualCapture = useCallback(async (imageData: string) => {
    setIsProcessing(true);
    setProcessingStatus('Procesando imagen capturada con IA...');

    try {
      const response = await fetch('/api/ocr', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ image: imageData }),
      });

      if (!response.ok) {
        throw new Error('Error en el servidor');
      }

      const data = await response.json();

      if (data.success && data.data) {
        const ocrData: OcrData = data.data;

        if (ocrData.documentNumber && ocrData.documentNumber.length >= 6) {
          const result: ScanResult = {
            documentNumber: ocrData.documentNumber,
            fullName: ocrData.fullName || '',
            rawText: ocrData.rawText || '',
            confidence: ocrData.confidence || 'medium',
            method: 'OCR manual (IA)',
            timestamp: new Date(),
            capturedImage: imageData,
          };
          setScanResult(result);
          setLastResult(result);
          setIsProcessing(false);
          setScreen('results');
          return;
        }

        // No document number found
        setIsProcessing(false);
        setErrorMessage(
          'No se pudo detectar el número de documento. Intenta con mejor iluminación y acercando más la cédula.'
        );
        setScreen('error');
      }
    } catch (err) {
      setIsProcessing(false);
      setErrorMessage(`Error de conexión: ${String(err)}`);
      setScreen('error');
    }
  }, []);

  // Called when user uploads an image from gallery
  const handleImageUpload = useCallback(
    async (dataUrl: string) => {
      setIsProcessing(true);
      setProcessingStatus('Procesando imagen con IA...');
      setScreen('home'); // stay on home with overlay

      try {
        const response = await fetch('/api/ocr', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ image: dataUrl }),
        });

        if (!response.ok) {
          throw new Error('Error en el servidor');
        }

        const data = await response.json();

        if (data.success && data.data) {
          const ocrData: OcrData = data.data;

          if (ocrData.documentNumber && ocrData.documentNumber.length >= 6) {
            const result: ScanResult = {
              documentNumber: ocrData.documentNumber,
              fullName: ocrData.fullName || '',
              rawText: ocrData.rawText || '',
              confidence: ocrData.confidence || 'medium',
              method: 'OCR desde galería (IA)',
              timestamp: new Date(),
              capturedImage: dataUrl,
            };
            setScanResult(result);
            setLastResult(result);
            setIsProcessing(false);
            setScreen('results');
            return;
          }

          // No document number found
          setIsProcessing(false);
          setErrorMessage(
            'No se pudo detectar el número de documento en la imagen. Intenta con otra foto más clara.'
          );
          setScreen('error');
        }
      } catch (err) {
        setIsProcessing(false);
        setErrorMessage(`Error de conexión: ${String(err)}`);
        setScreen('error');
      }
    },
    []
  );

  const handleNewScan = useCallback(() => {
    setScanResult(null);
    setScreen('camera');
  }, []);

  const handleBackToHome = useCallback(() => {
    setIsProcessing(false);
    setScreen('home');
  }, []);

  return (
    <>
      {/* Processing overlay */}
      {isProcessing && <ProcessingOverlay status={processingStatus} />}

      {screen === 'welcome' && (
        <WelcomeScreen onAccept={handleWelcomeAccept} />
      )}
      {screen === 'home' && (
        <HomeScreen
          onScan={handleStartScan}
          onImageUpload={handleImageUpload}
          lastResult={lastResult}
        />
      )}
      {screen === 'camera' && (
        <CameraScreen
          onResult={handleAutoResult}
          onManualCapture={handleManualCapture}
          onCancel={handleBackToHome}
        />
      )}
      {screen === 'results' && scanResult && (
        <ResultsScreen
          result={scanResult}
          onNewScan={handleNewScan}
          onBack={handleBackToHome}
        />
      )}
      {screen === 'error' && (
        <ErrorScreen
          message={errorMessage}
          onRetry={handleNewScan}
          onBack={handleBackToHome}
        />
      )}
    </>
  );
}
