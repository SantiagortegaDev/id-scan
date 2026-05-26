'use client';

import { useState, useRef, useCallback, useEffect } from 'react';
import { parseBarcodeString, ColombianIdData } from '@/lib/colombia-id-parser';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
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
  FileText,
  User,
  Calendar,
  Droplets,
  Hash,
  Eye,
  Copy,
  Check,
  Sparkles,
  Upload,
  Crop,
} from 'lucide-react';

// ====== TYPES ======
type AppScreen = 'welcome' | 'home' | 'camera' | 'processing' | 'results' | 'error';

interface VlmData {
  barcodeReadable: boolean;
  rawBarcodeContent: string;
  documentNumber: string;
  firstName: string;
  middleName: string;
  lastName: string;
  secondLastName: string;
  birthDate: string;
  gender: string;
  bloodType: string;
  expiryDate: string;
  allVisibleText: string;
}

interface ScanResult {
  rawContent: string;
  parsedData: ColombianIdData | null;
  method: string;
  timestamp: Date;
  capturedImage?: string;
  vlmData?: VlmData;
  source?: 'barcode' | 'vlm';
}

// ====== WELCOME / PERMISSION SCREEN ======
function WelcomeScreen({ onAccept }: { onAccept: () => void }) {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center bg-gradient-to-b from-slate-900 to-slate-800 text-white p-6">
      <div className="max-w-md w-full text-center space-y-8">
        {/* Logo */}
        <div className="mx-auto w-24 h-24 rounded-2xl bg-gradient-to-br from-emerald-400 to-emerald-600 flex items-center justify-center shadow-xl shadow-emerald-500/25">
          <ScanLine className="w-12 h-12 text-white" />
        </div>

        {/* Title */}
        <div>
          <h1 className="text-3xl font-bold mb-2">ID Scan Colombia</h1>
          <p className="text-slate-400 text-lg">
            Escáner de cédula de ciudadanía colombiana
          </p>
        </div>

        {/* Features */}
        <div className="space-y-4 text-left">
          <div className="flex items-start gap-3 p-4 rounded-xl bg-white/5 border border-white/10">
            <ScanLine className="w-5 h-5 text-emerald-400 mt-0.5 shrink-0" />
            <div>
              <p className="font-medium">Escaneo PDF417</p>
              <p className="text-sm text-slate-400">
                Lee el código de barras de la parte trasera de tu cédula
              </p>
            </div>
          </div>
          <div className="flex items-start gap-3 p-4 rounded-xl bg-white/5 border border-white/10">
            <Eye className="w-5 h-5 text-emerald-400 mt-0.5 shrink-0" />
            <div>
              <p className="font-medium">Contenido en tiempo real</p>
              <p className="text-sm text-slate-400">
                Muestra primero el contenido crudo del código de barras
              </p>
            </div>
          </div>
          <div className="flex items-start gap-3 p-4 rounded-xl bg-white/5 border border-white/10">
            <User className="w-5 h-5 text-emerald-400 mt-0.5 shrink-0" />
            <div>
              <p className="font-medium">Datos parseados</p>
              <p className="text-sm text-slate-400">
                Extrae nombre, cédula, fecha de nacimiento y más
              </p>
            </div>
          </div>
        </div>

        {/* Permission Notice */}
        <div className="p-4 rounded-xl bg-amber-500/10 border border-amber-500/20 text-amber-200 text-sm">
          <p className="font-medium mb-1">Se requiere acceso a la cámara</p>
          <p>
            Esta app necesita acceso a tu cámara para escanear el código de
            barras de tu cédula. La imagen se procesa localmente y no se envía a
            ningún servidor externo.
          </p>
        </div>

        {/* Accept Button */}
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
function HomeScreen({ onScan, onImageUpload, lastResult }: { onScan: () => void; onImageUpload: (dataUrl: string) => void; lastResult: ScanResult | null }) {
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleFileSelect = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
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
    // Reset input so the same file can be selected again
    e.target.value = '';
  }, [onImageUpload]);

  return (
    <div className="min-h-screen flex flex-col bg-gradient-to-b from-slate-900 to-slate-800 text-white">
      {/* Header */}
      <header className="p-6 flex items-center gap-3">
        <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-emerald-400 to-emerald-600 flex items-center justify-center">
          <ScanLine className="w-5 h-5 text-white" />
        </div>
        <div>
          <h1 className="text-lg font-bold">ID Scan</h1>
          <p className="text-xs text-slate-400">Cédula de ciudadanía</p>
        </div>
      </header>

      {/* Main Content */}
      <div className="flex-1 flex flex-col items-center justify-center p-6 space-y-8">
        {/* Scan Button */}
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
          <p className="text-slate-300 font-medium">Toma una foto del reverso</p>
          <p className="text-slate-500 text-sm">
            Donde está el código de barras PDF417
          </p>
        </div>

        {/* Upload from gallery option */}
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

        {/* Last Result */}
        {lastResult && (
          <Card className="w-full max-w-sm bg-white/5 border-white/10 text-white">
            <CardHeader className="pb-2 flex flex-row items-center justify-between">
              <CardTitle className="text-sm text-slate-400">Último escaneo</CardTitle>
              {lastResult.source === 'vlm' && (
                <Badge className="bg-purple-500/20 text-purple-300 text-xs">
                  <Sparkles className="w-3 h-3 mr-1" />
                  IA
                </Badge>
              )}
            </CardHeader>
            <CardContent className="space-y-2">
              {lastResult.parsedData ? (
                <>
                  <p className="font-semibold">
                    {lastResult.parsedData.firstName} {lastResult.parsedData.middleName}{' '}
                    {lastResult.parsedData.lastName} {lastResult.parsedData.secondLastName}
                  </p>
                  <p className="text-sm text-slate-400">
                    CC {lastResult.parsedData.documentInfo.documentNumber}
                  </p>
                </>
              ) : (
                <p className="text-sm text-slate-400 truncate">
                  {lastResult.rawContent.substring(0, 60)}...
                </p>
              )}
              <p className="text-xs text-slate-500">
                {lastResult.timestamp.toLocaleTimeString('es-CO')}
              </p>
            </CardContent>
          </Card>
        )}
      </div>

      {/* Tips */}
      <div className="p-6">
        <div className="p-4 rounded-xl bg-white/5 border border-white/10 space-y-2">
          <p className="font-medium text-sm text-slate-300">Consejos para un buen escaneo:</p>
          <ul className="text-xs text-slate-400 space-y-1">
            <li>- Buena iluminación, sin reflejos</li>
            <li>- Coloca la cédula sobre una superficie plana</li>
            <li>- Acerca mucho la cámara al código (10-15 cm)</li>
            <li>- Mantén la cámara estable y enfocada</li>
            <li>- Si el código no se lee, la IA puede leer el texto</li>
          </ul>
        </div>
      </div>
    </div>
  );
}

// ====== CAMERA SCREEN ======
function CameraScreen({
  onCapture,
  onCancel,
}: {
  onCapture: (imageData: string) => void;
  onCancel: () => void;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const [cameraReady, setCameraReady] = useState(false);
  const [zoom, setZoom] = useState(1);
  const [torchOn, setTorchOn] = useState(false);
  const [focusPoint, setFocusPoint] = useState<{ x: number; y: number } | null>(null);
  const [autoScanning, setAutoScanning] = useState(false);
  const [autoScanStatus, setAutoScanStatus] = useState<string>('');
  const scanIntervalRef = useRef<NodeJS.Timeout | null>(null);
  const barcodeDetectorRef = useRef<BarcodeDetector | null>(null);
  const [hasBarcodeDetector, setHasBarcodeDetector] = useState(false);

  // Initialize camera
  useEffect(() => {
    let mounted = true;

    async function startCamera() {
      try {
        // Request camera with ideal constraints for barcode scanning
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
        }

        // Check if BarcodeDetector API is available
        if ('BarcodeDetector' in window) {
          try {
            const detector = new BarcodeDetector({
              formats: ['pdf417', 'qr_code'],
            });
            barcodeDetectorRef.current = detector;
            setHasBarcodeDetector(true);
          } catch {
            setHasBarcodeDetector(false);
          }
        }
      } catch (err) {
        console.error('Camera error:', err);
        setAutoScanStatus('Error al acceder a la cámara');
      }
    }

    startCamera();

    return () => {
      mounted = false;
      if (streamRef.current) {
        streamRef.current.getTracks().forEach((t) => t.stop());
      }
      if (scanIntervalRef.current) {
        clearInterval(scanIntervalRef.current);
      }
    };
  }, []);

  // Capture a frame from the video
  const captureFrame = useCallback(() => {
    if (!videoRef.current || !canvasRef.current) return null;
    
    const video = videoRef.current;
    const canvas = canvasRef.current;
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    
    const ctx = canvas.getContext('2d');
    if (!ctx) return null;
    
    ctx.drawImage(video, 0, 0);
    return canvas.toDataURL('image/jpeg', 0.95);
  }, []);

  // Auto-scan with BarcodeDetector API
  const startAutoScan = useCallback(() => {
    if (!barcodeDetectorRef.current || !videoRef.current) return;
    
    setAutoScanning(true);
    setAutoScanStatus('Escaneando automáticamente...');

    let attempts = 0;
    const maxAttempts = 60; // ~30 seconds at 500ms intervals

    scanIntervalRef.current = setInterval(async () => {
      attempts++;
      
      if (attempts > maxAttempts) {
        setAutoScanStatus('No se detectó el código. Intenta tomar una foto manualmente.');
        if (scanIntervalRef.current) clearInterval(scanIntervalRef.current);
        setAutoScanning(false);
        return;
      }

      try {
        const video = videoRef.current!;
        if (video.readyState < 2) return;

        const detector = barcodeDetectorRef.current!;
        const barcodes = await detector.detect(video);

        if (barcodes.length > 0) {
          // Found a barcode!
          if (scanIntervalRef.current) clearInterval(scanIntervalRef.current);
          setAutoScanning(false);
          
          // Capture the current frame as proof
          const frameData = captureFrame();
          
          // Stop the camera
          if (streamRef.current) {
            streamRef.current.getTracks().forEach((t) => t.stop());
          }
          
          // Process the barcode content
          onCapture(barcodes[0].rawValue);
          return;
        }

        setAutoScanStatus(`Escaneando... intento ${attempts}/${maxAttempts}`);
      } catch (err) {
        console.error('Auto-scan error:', err);
      }
    }, 500);
  }, [onCapture, captureFrame]);

  // Manual capture
  const handleManualCapture = useCallback(() => {
    const imageData = captureFrame();
    if (imageData) {
      if (scanIntervalRef.current) clearInterval(scanIntervalRef.current);
      setAutoScanning(false);
      // Stop the camera
      if (streamRef.current) {
        streamRef.current.getTracks().forEach((t) => t.stop());
      }
      onCapture(imageData);
    }
  }, [captureFrame, onCapture]);

  // Touch to focus
  const handleTouchFocus = useCallback(
    async (e: React.TouchEvent | React.MouseEvent) => {
      if (!streamRef.current) return;

      const rect = (e.target as HTMLElement).getBoundingClientRect();
      let x: number, y: number;

      if ('touches' in e) {
        x = e.touches[0].clientX - rect.left;
        y = e.touches[0].clientY - rect.top;
      } else {
        x = e.clientX - rect.left;
        y = e.clientY - rect.top;
      }

      const relativeX = x / rect.width;
      const relativeY = y / rect.height;

      setFocusPoint({ x: relativeX * 100, y: relativeY * 100 });
      setTimeout(() => setFocusPoint(null), 1500);

      // Try to set focus point
      const track = streamRef.current.getVideoTracks()[0];
      if (track) {
        try {
          const capabilities = track.getCapabilities?.();
          if (capabilities?.pointsOfInterest) {
            await track.applyConstraints({
              advanced: [
                {
                  pointsOfInterest: [{ x: relativeX, y: relativeY }],
                  focusMode: 'manual',
                } as any,
              ],
            });
            // Return to continuous focus after a moment
            setTimeout(async () => {
              try {
                await track.applyConstraints({
                  advanced: [{ focusMode: 'continuous' } as any],
                });
              } catch {}
            }, 2000);
          }
        } catch (err) {
          console.log('Focus not supported:', err);
        }
      }
    },
    []
  );

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

  // Toggle torch
  const handleTorch = useCallback(async () => {
    if (!streamRef.current) return;
    const track = streamRef.current.getVideoTracks()[0];
    if (!track) return;

    try {
      await track.applyConstraints({
        advanced: [{ torch: !torchOn } as any],
      });
      setTorchOn(!torchOn);
    } catch {
      console.log('Torch not supported');
    }
  }, [torchOn]);

  return (
    <div className="fixed inset-0 bg-black flex flex-col">
      {/* Hidden canvas for frame capture */}
      <canvas ref={canvasRef} className="hidden" />

      {/* Camera View */}
      <div className="relative flex-1 overflow-hidden" onClick={handleTouchFocus}>
        <video
          ref={videoRef}
          className="absolute inset-0 w-full h-full object-cover"
          playsInline
          muted
          style={{ transform: `scale(${zoom})` }}
        />

        {/* Guide Overlay */}
        <div className="absolute inset-0 pointer-events-none">
          {/* Darkened areas outside the guide - narrow rectangle matching barcode shape */}
          <div className="absolute inset-0">
            {/* Top */}
            <div className="absolute top-0 left-0 right-0 h-[35%] bg-black/60" />
            {/* Bottom */}
            <div className="absolute bottom-0 left-0 right-0 h-[30%] bg-black/60" />
            {/* Left */}
            <div className="absolute top-[35%] left-0 w-[15%] h-[35%] bg-black/60" />
            {/* Right */}
            <div className="absolute top-[35%] right-0 w-[15%] h-[35%] bg-black/60" />
          </div>

          {/* Guide Rectangle - narrow/wide matching PDF417 barcode shape */}
          <div className="absolute top-[35%] left-[15%] right-[15%] bottom-[30%]">
            {/* Corner accents */}
            <div className="absolute top-0 left-0 w-6 h-6 border-t-3 border-l-3 border-emerald-400 rounded-tl" />
            <div className="absolute top-0 right-0 w-6 h-6 border-t-3 border-r-3 border-emerald-400 rounded-tr" />
            <div className="absolute bottom-0 left-0 w-6 h-6 border-b-3 border-l-3 border-emerald-400 rounded-bl" />
            <div className="absolute bottom-0 right-0 w-6 h-6 border-b-3 border-r-3 border-emerald-400 rounded-br" />

            {/* Scanning line animation */}
            {autoScanning && (
              <div className="absolute left-2 right-2 h-0.5 bg-emerald-400 animate-bounce shadow-lg shadow-emerald-400/50"
                style={{ 
                  animation: 'scanLine 2s ease-in-out infinite',
                  top: '50%',
                }}
              />
            )}
          </div>

          {/* Instructions */}
          <div className="absolute top-[10%] left-0 right-0 text-center">
            <div className="inline-block px-4 py-2 rounded-full bg-black/60 backdrop-blur-sm">
              <p className="text-white text-sm font-medium">
                Acerca el código de barras aquí
              </p>
              <p className="text-emerald-300 text-xs mt-0.5">
                Muy cerca (10-15 cm) • Buena luz • Sin reflejos
              </p>
            </div>
          </div>

          {/* Barcode illustration hint */}
          <div className="absolute top-[28%] left-1/2 -translate-x-1/2 pointer-events-none">
            <div className="flex items-end gap-0.5 opacity-50">
              {[2,3,1,4,1,3,2,1,4,2,1,3,1,2,4,1,3,2,1,2,3,1,4,2,1].map((h, i) => (
                <div
                  key={i}
                  className={`w-0.5 ${i % 2 === 0 ? 'bg-white' : 'bg-white/30'}`}
                  style={{ height: `${h * 4}px` }}
                />
              ))}
            </div>
          </div>

          {/* Focus indicator */}
          {focusPoint && (
            <div
              className="absolute w-16 h-16 border-2 border-yellow-400 rounded-full animate-ping"
              style={{
                left: `${focusPoint.x}%`,
                top: `${focusPoint.y}%`,
                transform: 'translate(-50%, -50%)',
              }}
            />
          )}
        </div>
      </div>

      {/* Controls */}
      <div className="bg-black/90 backdrop-blur-sm border-t border-white/10">
        {/* Auto-scan status */}
        {autoScanStatus && (
          <div className="px-4 py-2 text-center">
            <p className="text-sm text-slate-300">{autoScanStatus}</p>
          </div>
        )}

        <div className="flex items-center justify-between px-4 py-4">
          {/* Back button */}
          <Button
            variant="ghost"
            size="icon"
            onClick={() => {
              if (scanIntervalRef.current) clearInterval(scanIntervalRef.current);
              if (streamRef.current) {
                streamRef.current.getTracks().forEach((t) => t.stop());
              }
              onCancel();
            }}
            className="text-white hover:bg-white/10"
          >
            <ChevronLeft className="w-6 h-6" />
          </Button>

          {/* Zoom controls */}
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

          {/* Torch */}
          <Button
            variant="ghost"
            size="icon"
            onClick={handleTorch}
            className={`text-white hover:bg-white/10 ${torchOn ? 'bg-yellow-500/20 text-yellow-400' : ''}`}
          >
            <Sun className="w-5 h-5" />
          </Button>
        </div>

        <div className="flex items-center justify-center gap-6 px-4 pb-6">
          {/* Auto-scan button */}
          {hasBarcodeDetector && !autoScanning && (
            <Button
              onClick={startAutoScan}
              className="bg-emerald-500 hover:bg-emerald-600 text-white rounded-full px-6"
              disabled={!cameraReady}
            >
              <ScanLine className="w-4 h-4 mr-2" />
              Auto-escaneo
            </Button>
          )}

          {/* Capture button */}
          <button
            onClick={handleManualCapture}
            disabled={!cameraReady}
            className="w-20 h-20 rounded-full border-4 border-white bg-white/10 flex items-center justify-center hover:bg-white/20 transition-colors active:scale-90 disabled:opacity-50"
          >
            <div className="w-14 h-14 rounded-full bg-white" />
          </button>
        </div>

        <p className="text-center text-slate-400 text-xs pb-4">
          Toca para enfocar • Acerca mucho el código • También puedes subir foto
        </p>
      </div>

      {/* CSS Animation */}
      <style jsx>{`
        @keyframes scanLine {
          0%, 100% { top: 10%; }
          50% { top: 90%; }
        }
      `}</style>
    </div>
  );
}

// ====== PROCESSING SCREEN ======
function ProcessingScreen({ status }: { status: string }) {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center bg-gradient-to-b from-slate-900 to-slate-800 text-white p-6">
      <div className="flex flex-col items-center gap-6">
        <div className="relative">
          <Loader2 className="w-16 h-16 animate-spin text-emerald-400" />
          <div className="absolute inset-0 flex items-center justify-center">
            <ScanLine className="w-6 h-6 text-emerald-400" />
          </div>
        </div>
        <div className="text-center space-y-2">
          <p className="text-lg font-medium">Procesando imagen...</p>
          <p className="text-sm text-slate-400">{status}</p>
        </div>
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
  const [showRaw, setShowRaw] = useState(true);
  const [copied, setCopied] = useState(false);
  const [showParsed, setShowParsed] = useState(false);

  const copyToClipboard = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(result.rawContent);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {}
  }, [result.rawContent]);

  const genderLabel = result.parsedData?.gender === 'M' ? 'Masculino' : 
                       result.parsedData?.gender === 'F' ? 'Femenino' : 
                       result.parsedData?.gender || 'N/A';

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
          <h1 className="text-lg font-bold">Resultado del escaneo</h1>
          <p className="text-xs text-slate-400">
            Método: {result.method} • {result.timestamp.toLocaleTimeString('es-CO')}
          </p>
        </div>
      </header>

      {/* Content */}
      <div className="flex-1 p-4 space-y-4 overflow-y-auto">
        {/* Success indicator */}
        <div className="flex items-center gap-2 p-3 rounded-xl bg-emerald-500/10 border border-emerald-500/20">
          {result.source === 'vlm' ? (
            <Sparkles className="w-5 h-5 text-purple-400 shrink-0" />
          ) : (
            <CheckCircle2 className="w-5 h-5 text-emerald-400 shrink-0" />
          )}
          <p className="text-sm text-emerald-200">
            {result.source === 'vlm' 
              ? 'Cédula leída con IA visual' 
              : 'Código de barras detectado exitosamente'}
          </p>
        </div>

        {/* Tabs: Raw / Parsed */}
        <div className="flex gap-2">
          <button
            onClick={() => { setShowRaw(true); setShowParsed(false); }}
            className={`flex-1 py-2.5 rounded-xl text-sm font-medium transition-colors ${
              showRaw
                ? 'bg-emerald-500 text-white'
                : 'bg-white/5 text-slate-400 hover:bg-white/10'
            }`}
          >
            <FileText className="w-4 h-4 inline mr-1.5" />
            Contenido crudo
          </button>
          <button
            onClick={() => { setShowRaw(false); setShowParsed(true); }}
            className={`flex-1 py-2.5 rounded-xl text-sm font-medium transition-colors ${
              showParsed
                ? 'bg-emerald-500 text-white'
                : 'bg-white/5 text-slate-400 hover:bg-white/10'
            }`}
          >
            <User className="w-4 h-4 inline mr-1.5" />
            Datos parseados
          </button>
        </div>

        {/* Raw Content */}
        {showRaw && (
          <Card className="bg-white/5 border-white/10 text-white">
            <CardHeader className="pb-2 flex flex-row items-center justify-between">
              <CardTitle className="text-sm text-slate-400">
                Contenido del código de barras
              </CardTitle>
              <Button
                variant="ghost"
                size="sm"
                onClick={copyToClipboard}
                className="text-slate-400 hover:text-white hover:bg-white/10"
              >
                {copied ? (
                  <Check className="w-4 h-4 text-emerald-400" />
                ) : (
                  <Copy className="w-4 h-4" />
                )}
              </Button>
            </CardHeader>
            <CardContent>
              <div className="p-3 rounded-lg bg-black/30 font-mono text-xs leading-relaxed break-all max-h-64 overflow-y-auto">
                {result.rawContent}
              </div>
              <div className="mt-2 flex gap-2">
                <Badge variant="outline" className="text-xs border-white/20 text-slate-400">
                  {result.rawContent.length} caracteres
                </Badge>
                <Badge variant="outline" className="text-xs border-white/20 text-slate-400">
                  PDF417
                </Badge>
              </div>
            </CardContent>
          </Card>
        )}

        {/* Parsed Data */}
        {showParsed && result.parsedData && (
          <div className="space-y-3">
            {/* Document Number */}
            <Card className="bg-white/5 border-white/10 text-white">
              <CardContent className="p-4 flex items-center gap-3">
                <div className="w-10 h-10 rounded-lg bg-blue-500/20 flex items-center justify-center shrink-0">
                  <Hash className="w-5 h-5 text-blue-400" />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-xs text-slate-400">Número de cédula</p>
                  <p className="text-lg font-bold font-mono">
                    {result.parsedData.documentInfo.documentNumber || 'N/A'}
                  </p>
                </div>
              </CardContent>
            </Card>

            {/* Names */}
            <Card className="bg-white/5 border-white/10 text-white">
              <CardContent className="p-4 flex items-center gap-3">
                <div className="w-10 h-10 rounded-lg bg-purple-500/20 flex items-center justify-center shrink-0">
                  <User className="w-5 h-5 text-purple-400" />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-xs text-slate-400">Nombre completo</p>
                  <p className="font-semibold">
                    {result.parsedData.firstName} {result.parsedData.middleName}
                  </p>
                  <p className="text-sm text-slate-300">
                    {result.parsedData.lastName} {result.parsedData.secondLastName}
                  </p>
                </div>
              </CardContent>
            </Card>

            {/* Birth Date & Gender */}
            <div className="grid grid-cols-2 gap-3">
              <Card className="bg-white/5 border-white/10 text-white">
                <CardContent className="p-4 flex items-center gap-3">
                  <div className="w-8 h-8 rounded-lg bg-amber-500/20 flex items-center justify-center shrink-0">
                    <Calendar className="w-4 h-4 text-amber-400" />
                  </div>
                  <div className="min-w-0">
                    <p className="text-xs text-slate-400">Fecha de nacimiento</p>
                    <p className="text-sm font-semibold">
                      {result.parsedData.birthDate || 'N/A'}
                    </p>
                  </div>
                </CardContent>
              </Card>
              <Card className="bg-white/5 border-white/10 text-white">
                <CardContent className="p-4 flex items-center gap-3">
                  <div className="w-8 h-8 rounded-lg bg-pink-500/20 flex items-center justify-center shrink-0">
                    <User className="w-4 h-4 text-pink-400" />
                  </div>
                  <div className="min-w-0">
                    <p className="text-xs text-slate-400">Sexo</p>
                    <p className="text-sm font-semibold">{genderLabel}</p>
                  </div>
                </CardContent>
              </Card>
            </div>

            {/* Blood Type */}
            <Card className="bg-white/5 border-white/10 text-white">
              <CardContent className="p-4 flex items-center gap-3">
                <div className="w-10 h-10 rounded-lg bg-red-500/20 flex items-center justify-center shrink-0">
                  <Droplets className="w-5 h-5 text-red-400" />
                </div>
                <div>
                  <p className="text-xs text-slate-400">Grupo sanguíneo</p>
                  <p className="text-lg font-bold">
                    {result.parsedData.bloodType || 'N/A'}
                  </p>
                </div>
              </CardContent>
            </Card>

            {/* Additional Info */}
            <Card className="bg-white/5 border-white/10 text-white">
              <CardContent className="p-4">
                <p className="text-xs text-slate-400 mb-2">Información adicional</p>
                <div className="grid grid-cols-2 gap-2 text-sm">
                  <div>
                    <span className="text-slate-400">Código AFIS:</span>{' '}
                    <span className="font-mono">
                      {result.parsedData.documentInfo.afisCode || 'N/A'}
                    </span>
                  </div>
                  <div>
                    <span className="text-slate-400">Finger Card:</span>{' '}
                    <span className="font-mono">
                      {result.parsedData.documentInfo.fingerCard || 'N/A'}
                    </span>
                  </div>
                </div>
              </CardContent>
            </Card>
          </div>
        )}

        {/* No parsed data available */}
        {showParsed && !result.parsedData && (
          <Card className="bg-white/5 border-white/10 text-white">
            <CardContent className="p-6 text-center space-y-3">
              <AlertCircle className="w-10 h-10 text-amber-400 mx-auto" />
              <p className="font-medium">No se pudieron parsear los datos</p>
              <p className="text-sm text-slate-400">
                El código de barras fue detectado pero no coincide con el formato
                estándar de la cédula colombiana. Puedes ver el contenido crudo
                en la pestaña &quot;Contenido crudo&quot;.
              </p>
            </CardContent>
          </Card>
        )}
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
  const capturedImageRef = useRef<string | null>(null);

  // Check if user has already seen the welcome screen
  useEffect(() => {
    const hasSeenWelcome = localStorage.getItem('idscan_welcomed');
    if (hasSeenWelcome) {
      setScreen('home');
    }
  }, []);

  // Handle welcome acceptance
  const handleWelcomeAccept = useCallback(() => {
    localStorage.setItem('idscan_welcomed', 'true');
    setScreen('home');
  }, []);

  // Handle scan start
  const handleStartScan = useCallback(() => {
    setScanResult(null);
    capturedImageRef.current = null;
    setScreen('camera');
  }, []);

  // Handle camera capture
  const handleCapture = useCallback(async (imageOrBarcode: string) => {
    // Check if this is a barcode string (from auto-scan) or an image
    const isBarcode = !imageOrBarcode.startsWith('data:image');
    
    if (isBarcode) {
      // Direct barcode content from auto-scan
      const parsed = parseBarcodeString(imageOrBarcode);
      const result: ScanResult = {
        rawContent: imageOrBarcode,
        parsedData: parsed,
        method: 'Auto-detección (BarcodeDetector API)',
        timestamp: new Date(),
        capturedImage: capturedImageRef.current || undefined,
      };
      setScanResult(result);
      setLastResult(result);
      setScreen('results');
      return;
    }

    // Image captured - need to process
    capturedImageRef.current = imageOrBarcode;
    setScreen('processing');
    setProcessingStatus('Procesando imagen capturada...');

    try {
      // Strategy 1: Try BarcodeDetector API on the captured image
      if ('BarcodeDetector' in window) {
        setProcessingStatus('Intentando detección directa...');

        const img = new Image();
        img.crossOrigin = 'anonymous';
        
        await new Promise<void>((resolve, reject) => {
          img.onload = () => resolve();
          img.onerror = () => reject(new Error('Failed to load image'));
          img.src = imageOrBarcode;
        });

        try {
          const detector = new BarcodeDetector({ formats: ['pdf417', 'qr_code'] });
          const barcodes = await detector.detect(img);
          
          if (barcodes.length > 0) {
            const raw = barcodes[0].rawValue;
            const parsed = parseBarcodeString(raw);
            const result: ScanResult = {
              rawContent: raw,
              parsedData: parsed,
              method: 'BarcodeDetector API (imagen capturada)',
              timestamp: new Date(),
              capturedImage: imageOrBarcode,
            };
            setScanResult(result);
            setLastResult(result);
            setScreen('results');
            return;
          }
        } catch (err) {
          console.log('BarcodeDetector on image failed:', err);
        }
      }

      // Strategy 2: Use html5-qrcode to decode the image
      setProcessingStatus('Intentando con ZXing...');
      
      const Html5Qrcode = (await import('html5-qrcode')).Html5Qrcode;
      
      try {
        const html5QrCode = new Html5Qrcode('hidden-scanner-div');
        
        const decodedText = await new Promise<string>((resolve, reject) => {
          // Create a blob URL from the base64 data
          const base64Data = imageOrBarcode.split(',')[1];
          const byteCharacters = atob(base64Data);
          const byteNumbers = new Array(byteCharacters.length);
          for (let i = 0; i < byteCharacters.length; i++) {
            byteNumbers[i] = byteCharacters.charCodeAt(i);
          }
          const byteArray = new Uint8Array(byteNumbers);
          const blob = new Blob([byteArray], { type: 'image/jpeg' });
          const blobUrl = URL.createObjectURL(blob);

          html5QrCode
            .scanFileV2(blob, true)
            .then((result) => {
              URL.revokeObjectURL(blobUrl);
              resolve(result.decodedText);
            })
            .catch((err) => {
              URL.revokeObjectURL(blobUrl);
              reject(err);
            });
        });

        const parsed = parseBarcodeString(decodedText);
        const result: ScanResult = {
          rawContent: decodedText,
          parsedData: parsed,
          method: 'ZXing (html5-qrcode)',
          timestamp: new Date(),
          capturedImage: imageOrBarcode,
        };
        setScanResult(result);
        setLastResult(result);
        setScreen('results');
        return;
      } catch (err) {
        console.log('html5-qrcode failed:', err);
      }

      // Strategy 3: Backend enhancement + re-attempt
      setProcessingStatus('Enviando al servidor para mejora de imagen...');
      
      try {
        const enhanceResponse = await fetch('/api/scan', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ image: imageOrBarcode, mode: 'analyze' }),
        });

        if (enhanceResponse.ok) {
          const enhanceData = await enhanceResponse.json();
          
          if (enhanceData.enhancedImages) {
            // Try decoding each enhanced image
            for (const enhanced of enhanceData.enhancedImages) {
              setProcessingStatus(`Probando: ${enhanced.description}...`);

              if ('BarcodeDetector' in window) {
                try {
                  const img = new Image();
                  img.crossOrigin = 'anonymous';
                  
                  await new Promise<void>((resolve, reject) => {
                    img.onload = () => resolve();
                    img.onerror = () => reject(new Error('Failed to load enhanced image'));
                    img.src = enhanced.image;
                  });

                  const detector = new BarcodeDetector({ formats: ['pdf417', 'qr_code'] });
                  const barcodes = await detector.detect(img);
                  
                  if (barcodes.length > 0) {
                    const raw = barcodes[0].rawValue;
                    const parsed = parseBarcodeString(raw);
                    const result: ScanResult = {
                      rawContent: raw,
                      parsedData: parsed,
                      method: `Servidor + BarcodeDetector (${enhanced.name})`,
                      timestamp: new Date(),
                      capturedImage: imageOrBarcode,
                      source: 'barcode',
                    };
                    setScanResult(result);
                    setLastResult(result);
                    setScreen('results');
                    return;
                  }
                } catch {}
              }

              // Also try html5-qrcode on enhanced images
              try {
                const Html5Qrcode = (await import('html5-qrcode')).Html5Qrcode;
                const html5QrCode = new Html5Qrcode('hidden-scanner-div-2');
                
                const base64Data = enhanced.image.split(',')[1];
                const byteCharacters = atob(base64Data);
                const byteNumbers = new Array(byteCharacters.length);
                for (let i = 0; i < byteCharacters.length; i++) {
                  byteNumbers[i] = byteCharacters.charCodeAt(i);
                }
                const byteArray = new Uint8Array(byteNumbers);
                const blob = new Blob([byteArray], { type: 'image/jpeg' });
                const blobUrl = URL.createObjectURL(blob);

                const decoded = await html5QrCode.scanFileV2(blob, true);
                URL.revokeObjectURL(blobUrl);

                const parsed = parseBarcodeString(decoded.decodedText);
                const result: ScanResult = {
                  rawContent: decoded.decodedText,
                  parsedData: parsed,
                  method: `Servidor + ZXing (${enhanced.name})`,
                  timestamp: new Date(),
                  capturedImage: imageOrBarcode,
                  source: 'barcode',
                };
                setScanResult(result);
                setLastResult(result);
                setScreen('results');
                return;
              } catch {}
            }
          }
        }
      } catch (err) {
        console.log('Backend enhancement failed:', err);
      }

      // Strategy 4: VLM (Vision AI) - Last resort, reads the card visually
      setProcessingStatus('Usando IA para leer la cédula...');
      
      try {
        const vlmResponse = await fetch('/api/scan', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ image: imageOrBarcode, mode: 'vlm' }),
        });

        if (vlmResponse.ok) {
          const vlmData = await vlmResponse.json();
          
          if (vlmData.success && vlmData.data) {
            const aiData = vlmData.data as VlmData;
            
            // If AI could read the barcode content, try to parse it
            let parsed: ColombianIdData | null = null;
            if (aiData.rawBarcodeContent) {
              parsed = parseBarcodeString(aiData.rawBarcodeContent);
            }
            
            // If parsing failed or no barcode content, construct from AI-extracted fields
            if (!parsed && (aiData.documentNumber || aiData.firstName)) {
              parsed = {
                source: 'pdf417',
                firstName: aiData.firstName || '',
                middleName: aiData.middleName || '',
                lastName: aiData.lastName || '',
                secondLastName: aiData.secondLastName || '',
                birthDate: aiData.birthDate || '',
                bloodType: aiData.bloodType || '',
                gender: aiData.gender || '',
                documentInfo: {
                  documentNumber: aiData.documentNumber || '',
                  afisCode: '',
                  fingerCard: '',
                },
              };
            }

            const rawContent = aiData.rawBarcodeContent || 
              aiData.allVisibleText || 
              `CC: ${aiData.documentNumber} | ${aiData.firstName} ${aiData.lastName} | ${aiData.birthDate}`;

            const result: ScanResult = {
              rawContent,
              parsedData: parsed,
              method: aiData.barcodeReadable 
                ? 'IA Visual (lectura de código de barras)' 
                : 'IA Visual (lectura de texto en la cédula)',
              timestamp: new Date(),
              capturedImage: imageOrBarcode,
              vlmData: aiData,
              source: 'vlm',
            };
            setScanResult(result);
            setLastResult(result);
            setScreen('results');
            return;
          }
        }
      } catch (err) {
        console.error('VLM failed:', err);
      }

      // All strategies failed
      setErrorMessage(
        'No se pudo detectar el código de barras PDF417 ni leer la cédula con IA. Intenta de nuevo con mejor iluminación, acercándote más al código de barras, y asegurándote de que esté bien enfocado.'
      );
      setScreen('error');
    } catch (err) {
      console.error('Processing error:', err);
      setErrorMessage(
        `Error al procesar la imagen: ${err instanceof Error ? err.message : 'Error desconocido'}. Intenta de nuevo.`
      );
      setScreen('error');
    }
  }, []);

  // Handle image upload from gallery
  const handleImageUpload = useCallback((dataUrl: string) => {
    capturedImageRef.current = null;
    // Directly process the uploaded image
    handleCapture(dataUrl);
  }, [handleCapture]);

  // Handle camera cancel
  const handleCameraCancel = useCallback(() => {
    setScreen('home');
  }, []);

  // Handle back from results
  const handleBackFromResults = useCallback(() => {
    setScreen('home');
  }, []);

  // Handle retry from error
  const handleRetry = useCallback(() => {
    handleStartScan();
  }, [handleStartScan]);

  // Render current screen
  return (
    <>
      {/* Hidden divs for html5-qrcode library (needs a container) */}
      <div id="hidden-scanner-div" style={{ display: 'none' }} />
      <div id="hidden-scanner-div-2" style={{ display: 'none' }} />

      {screen === 'welcome' && <WelcomeScreen onAccept={handleWelcomeAccept} />}
      {screen === 'home' && (
        <HomeScreen onScan={handleStartScan} onImageUpload={handleImageUpload} lastResult={lastResult} />
      )}
      {screen === 'camera' && (
        <CameraScreen onCapture={handleCapture} onCancel={handleCameraCancel} />
      )}
      {screen === 'processing' && (
        <ProcessingScreen status={processingStatus} />
      )}
      {screen === 'results' && scanResult && (
        <ResultsScreen
          result={scanResult}
          onNewScan={handleStartScan}
          onBack={handleBackFromResults}
        />
      )}
      {screen === 'error' && (
        <ErrorScreen
          message={errorMessage}
          onRetry={handleRetry}
          onBack={() => setScreen('home')}
        />
      )}
    </>
  );
}
