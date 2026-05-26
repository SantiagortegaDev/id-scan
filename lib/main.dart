import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';

// ============================================================================
// LOG GLOBAL — Panel de debug visible
// ============================================================================

class AppLog {
  static final List<String> _logs = [];
  static final List<void Function()> _listeners = [];

  static List<String> get logs => List.unmodifiable(_logs);

  static void add(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    final entry = '[$timestamp] $message';
    _logs.add(entry);
    if (_logs.length > 200) {
      _logs.removeRange(0, _logs.length - 200);
    }
    for (final listener in _listeners) {
      listener();
    }
    // ignore: avoid_print
    print(entry);
  }

  static void addError(String message) => add('ERROR: $message');
  static void addSuccess(String message) => add('OK: $message');
  static void addInfo(String message) => add('INFO: $message');
  static void addOcr(String message) => add('OCR: $message');
  static void addCamera(String message) => add('CAM: $message');

  static void clear() {
    _logs.clear();
    for (final listener in _listeners) {
      listener();
    }
  }

  static void addListener(void Function() listener) => _listeners.add(listener);
  static void removeListener(void Function() listener) => _listeners.remove(listener);
}

// ============================================================================
// MODELO DE DATOS
// ============================================================================

class CedulaData {
  String documentNumber = '';
  String fullName = '';
  String rawText = '';
  String confidence = 'low';

  bool get hasDocumentNumber => documentNumber.length >= 6;

  String cleanDocumentNumber() {
    // Remover puntos, comas, espacios - solo dígitos
    return documentNumber.replaceAll(RegExp(r'[^0-9]'), '');
  }
}

// ============================================================================
// PARSER DE OCR — PARTE FRONTAL DE LA CÉDULA
// ============================================================================

class OcrParser {
  static CedulaData parseFront(String text) {
    final data = CedulaData();
    data.rawText = text;

    if (text.isEmpty) return data;

    AppLog.addOcr('parseFront: longitud=${text.length}');
    AppLog.addOcr('Texto: "${text.substring(0, text.length > 150 ? 150 : text.length)}"');

    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    AppLog.addOcr('Líneas: ${lines.length}');

    // 1. Buscar número de documento
    // La cédula colombiana tiene entre 8 y 11 dígitos
    // Puede venir con puntos, comas o espacios: "1.234.567.890" o "1,234,567,890"
    String? docNumber;
    for (final line in lines) {
      // Buscar patrón de número con separadores: "1.234.567.890" o "1 234 567 890"
      final dottedMatch = RegExp(r'(\d{1,3}[.,\s]\d{3}[.,\s]\d{3,})').firstMatch(line);
      if (dottedMatch != null) {
        final raw = dottedMatch.group(1)!;
        final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.length >= 6 && digits.length <= 15) {
          docNumber = digits;
          AppLog.addOcr('Documento encontrado (con puntos): $raw -> $docNumber');
          break;
        }
      }

      // Buscar secuencia larga de solo dígitos
      final digitMatch = RegExp(r'(\d{6,15})').firstMatch(line);
      if (digitMatch != null) {
        final digits = digitMatch.group(1)!;
        if (digits.length >= 6 && digits.length <= 15) {
          docNumber = digits;
          AppLog.addOcr('Documento encontrado (dígitos): $docNumber');
          break;
        }
      }
    }

    if (docNumber != null) {
      data.documentNumber = docNumber;
      data.confidence = 'medium';
    } else {
      AppLog.addOcr('No se encontró número de documento');
      return data;
    }

    // 2. Buscar nombre completo
    // En la cédula, los nombres aparecen en mayúsculas, generalmente
    // después de palabras clave como "Nombres" o "Apellidos"
    final nameLines = <String>[];
    final skipWords = [
      'REPÚBLICA', 'COLOMBIA', 'CÉDULA', 'CEDULA', 'CIUDADANÍA',
      'CIUDADANIA', 'IDENTIFICACIÓN', 'IDENTIFICACION', 'MINISTERIO',
      'REGISTRO', 'NACIONAL', 'DEL', 'FECHA', 'NACIMIENTO', 'LUGAR',
      'EXPEDICIÓN', 'EXPEDICION', 'SEXO', 'GRUPO', 'SANGRE', 'RH',
      'ESTATURA', 'HUELLA', 'DIGITAL', 'DACTILAR', 'FIRMA',
    ];

    bool foundNameSection = false;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final upper = line.toUpperCase();

      // Detectar si estamos en la sección de nombres
      if (upper.contains('NOMBRE') || upper.contains('APELLIDO')) {
        foundNameSection = true;
        // El nombre puede estar en la misma línea después de "Nombres:"
        final colonIdx = line.indexOf(':');
        if (colonIdx >= 0 && colonIdx < line.length - 2) {
          final afterColon = line.substring(colonIdx + 1).trim();
          if (afterColon.length > 2 && RegExp(r'^[A-Za-zÁÉÍÓÚÑÜ\s]+$').hasMatch(afterColon)) {
            nameLines.add(afterColon.toUpperCase());
          }
        }
        continue;
      }

      if (foundNameSection || i >= 1) {
        // Buscar líneas que sean solo texto en mayúsculas (nombres en la cédula)
        final cleaned = line.replaceAll(RegExp(r'[^\w\sÁÉÍÓÚÑÜ]'), '').trim();
        if (cleaned.length > 2 &&
            RegExp(r'^[A-Za-zÁÉÍÓÚÑÜ\s]+$').hasMatch(cleaned)) {
          final upperCleaned = cleaned.toUpperCase();
          bool isSkipWord = false;
          for (final skip in skipWords) {
            if (upperCleaned == skip || upperCleaned == '$skip:') {
              isSkipWord = true;
              break;
            }
          }
          if (!isSkipWord && !upperCleaned.contains('REPÚBLICA') && !upperCleaned.contains('COLOMBIA')) {
            nameLines.add(upperCleaned);
          }
        }
      }
    }

    if (nameLines.isNotEmpty) {
      // Tomar las primeras líneas que sean nombres (apellidos + nombres)
      data.fullName = nameLines.take(3).join(' ');
      data.confidence = 'high';
    }

    // 3. Si no encontramos nombre con la estrategia anterior, buscar líneas largas en mayúsculas
    if (data.fullName.isEmpty) {
      final candidateLines = <String>[];
      for (final line in lines) {
        final cleaned = line.replaceAll(RegExp(r'[^\w\sÁÉÍÓÚÑÜ]'), '').trim();
        if (cleaned.length > 3 &&
            cleaned.toUpperCase() == cleaned && // Todo en mayúsculas
            RegExp(r'^[A-Za-zÁÉÍÓÚÑÜ\s]+$').hasMatch(cleaned)) {
          bool isSkip = false;
          for (final skip in skipWords) {
            if (cleaned.toUpperCase().contains(skip)) {
              isSkip = true;
              break;
            }
          }
          if (!isSkip) {
            candidateLines.add(cleaned.toUpperCase());
          }
        }
      }
      if (candidateLines.isNotEmpty) {
        data.fullName = candidateLines.take(3).join(' ');
        data.confidence = 'medium';
      }
    }

    AppLog.addOcr('Resultado: doc=${data.documentNumber}, nombre=${data.fullName}, confianza=${data.confidence}');
    return data;
  }
}

// ============================================================================
// APP PRINCIPAL
// ============================================================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppLog.addInfo('ID Scan iniciado');
  runApp(const IdScanApp());
}

class IdScanApp extends StatelessWidget {
  const IdScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ID Scan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF10B981),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981),
          onPrimary: Colors.white,
          secondary: Color(0xFF10B981),
          surface: Color(0xFF1E293B),
          onSurface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const HomePage(),
    );
  }
}

// ============================================================================
// PANEL DE LOGS
// ============================================================================

class LogPanel extends StatefulWidget {
  const LogPanel({super.key});

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    AppLog.addListener(_onLogUpdate);
  }

  @override
  void dispose() {
    AppLog.removeListener(_onLogUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _onLogUpdate() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final logs = AppLog.logs;
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border.all(color: const Color(0xFF334155)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: Color(0xFF10B981), size: 14),
                const SizedBox(width: 6),
                Text(
                  'Logs (${logs.length})',
                  style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: AppLog.clear,
                  child: const Icon(Icons.delete_outline, color: Colors.white54, size: 16),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(4),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                Color textColor = Colors.white70;
                if (log.contains('ERROR:')) {
                  textColor = Colors.redAccent;
                } else if (log.contains('OK:')) {
                  textColor = const Color(0xFF10B981);
                } else if (log.contains('OCR:')) {
                  textColor = Colors.yellowAccent;
                }
                return Text(
                  log,
                  style: TextStyle(color: textColor, fontSize: 9, fontFamily: 'monospace', height: 1.3),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PANTALLA PRINCIPAL
// ============================================================================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  PermissionStatus _cameraStatus = PermissionStatus.denied;
  bool _isChecking = true;
  bool _showLogs = false;
  CedulaData? _lastResult;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    setState(() => _isChecking = true);
    final status = await Permission.camera.status;
    setState(() {
      _cameraStatus = status;
      _isChecking = false;
    });
  }

  Future<void> _requestPermission() async {
    setState(() => _isChecking = true);
    final status = await Permission.camera.request();
    setState(() {
      _cameraStatus = status;
      _isChecking = false;
    });
  }

  void _openScanner() async {
    if (_cameraStatus != PermissionStatus.granted) {
      await _requestPermission();
      if (_cameraStatus != PermissionStatus.granted) return;
    }
    if (!mounted) return;

    final result = await Navigator.of(context).push<CedulaData>(
      MaterialPageRoute(builder: (_) => const OcrScannerPage()),
    );

    if (result != null) {
      setState(() => _lastResult = result);
    }
    _checkPermission();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  // Logo
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF10B981), Color(0xFF059669)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.qr_code_scanner, size: 48, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'ID Scan',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Escáner de cédula colombiana',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 40),

                  // Último resultado
                  if (_lastResult != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 16),
                              const SizedBox(width: 6),
                              const Text(
                                'Último escaneo',
                                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _lastResult!.fullName.isNotEmpty ? _lastResult!.fullName : 'Sin nombre',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'CC ${_lastResult!.documentNumber}',
                            style: const TextStyle(color: Color(0xFF10B981), fontSize: 14, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Botón escanear
                  if (_isChecking)
                    const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
                  else
                    ElevatedButton.icon(
                      onPressed: _cameraStatus == PermissionStatus.granted ? _openScanner : _requestPermission,
                      icon: const Icon(Icons.camera_alt),
                      label: Text(_cameraStatus == PermissionStatus.granted ? 'Escanear Cédula' : 'Dar permiso de cámara'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),

                  if (_cameraStatus == PermissionStatus.permanentlyDenied) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => openAppSettings(),
                      icon: const Icon(Icons.settings),
                      label: const Text('Abrir configuración'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],

                  const Spacer(),

                  // Consejos
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Consejos:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text('• Apunta a la parte delantera de la cédula', style: TextStyle(color: const Color(0xFF64748B), fontSize: 11)),
                        Text('• Buena iluminación, sin reflejos', style: TextStyle(color: const Color(0xFF64748B), fontSize: 11)),
                        Text('• Detección automática, no necesitas tomar foto', style: TextStyle(color: const Color(0xFF64748B), fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Log toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: GestureDetector(
              onTap: () => setState(() => _showLogs = !_showLogs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_showLogs ? Icons.terminal : Icons.terminal_outlined, color: const Color(0xFF64748B), size: 16),
                  const SizedBox(width: 6),
                  Text('Logs', style: TextStyle(color: const Color(0xFF64748B), fontSize: 12)),
                ],
              ),
            ),
          ),
          if (_showLogs) const LogPanel(),
        ],
      ),
    );
  }
}

// ============================================================================
// ESCÁNER OCR — CÁMARA CON DETECCIÓN AUTOMÁTICA
// ============================================================================

class OcrScannerPage extends StatefulWidget {
  const OcrScannerPage({super.key});

  @override
  State<OcrScannerPage> createState() => _OcrScannerPageState();
}

class _OcrScannerPageState extends State<OcrScannerPage> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  bool _cameraReady = false;
  bool _isProcessing = false;
  bool _found = false;
  String _statusText = 'Preparando cámara...';
  int _scanAttempts = 0;
  double _zoomFactor = 1.0;
  bool _torchOn = false;
  bool _showLogs = true;
  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        AppLog.addError('No se encontró cámara');
        setState(() => _statusText = 'No se encontró cámara');
        return;
      }

      // Usar cámara trasera
      final camera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();

      try {
        await _cameraController!.setFocusMode(FocusMode.continuous);
      } catch (_) {}

      setState(() {
        _cameraReady = true;
        _statusText = 'Apunta la parte delantera de la cédula';
      });

      AppLog.addCamera('Cámara inicializada OK');

      // Iniciar escaneo automático cada 2 segundos
      _startAutoScan();
    } catch (e) {
      AppLog.addError('Error cámara: $e');
      setState(() => _statusText = 'Error: $e');
    }
  }

  void _startAutoScan() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_isProcessing && _cameraReady && !_found) {
        _scanFrame();
      }
    });
  }

  Future<void> _scanFrame() async {
    if (_isProcessing || _found || _cameraController == null) return;
    if (!_cameraController!.value.isInitialized) return;

    _isProcessing = true;
    _scanAttempts++;
    setState(() => _statusText = 'Analizando... (intento #$_scanAttempts)');

    try {
      final XFile file = await _cameraController!.takePicture();
      final InputImage inputImage = InputImage.fromFilePath(file.path);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      final text = recognizedText.text;
      AppLog.addOcr('Frame #$_scanAttempts: ${text.length} chars');

      final data = OcrParser.parseFront(text);

      // Borrar la foto temporal
      try {
        final tempFile = File(file.path);
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}

      if (data.hasDocumentNumber) {
        // Encontramos un número de documento!
        _found = true;
        _scanTimer?.cancel();
        AppLog.addSuccess('Cédula detectada! Doc: ${data.documentNumber}, Nombre: ${data.fullName}');

        if (mounted) {
          Navigator.of(context).pop(data);
        }
      } else {
        setState(() => _statusText = 'No detectado. Apunta mejor la cédula...');
      }
    } catch (e) {
      AppLog.addError('Error escaneando: $e');
      setState(() => _statusText = 'Error. Reintentando...');
    }

    _isProcessing = false;
  }

  Future<void> _manualCapture() async {
    if (_isProcessing || _found || _cameraController == null) return;

    _isProcessing = true;
    setState(() => _statusText = 'Procesando foto manual...');

    try {
      final XFile file = await _cameraController!.takePicture();
      final InputImage inputImage = InputImage.fromFilePath(file.path);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      final text = recognizedText.text;
      final data = OcrParser.parseFront(text);

      try {
        final tempFile = File(file.path);
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}

      if (data.hasDocumentNumber) {
        _found = true;
        _scanTimer?.cancel();
        AppLog.addSuccess('Cédula detectada (manual)! Doc: ${data.documentNumber}');
        if (mounted) {
          Navigator.of(context).pop(data);
        }
      } else {
        setState(() => _statusText = 'No se detectó número. Intenta de nuevo.');
      }
    } catch (e) {
      AppLog.addError('Error captura manual: $e');
      setState(() => _statusText = 'Error. Intenta de nuevo.');
    }

    _isProcessing = false;
  }

  void _toggleTorch() async {
    if (_cameraController == null) return;
    try {
      _torchOn = !_torchOn;
      await _cameraController!.setFlashMode(_torchOn ? FlashMode.torch : FlashMode.off);
      AppLog.addCamera('Flash: ${_torchOn ? "ON" : "OFF"}');
      setState(() {});
    } catch (e) {
      AppLog.addCamera('Flash no disponible: $e');
    }
  }

  void _zoomIn() async {
    if (_cameraController == null) return;
    _zoomFactor = (_zoomFactor + 0.5).clamp(1.0, 5.0);
    try {
      await _cameraController!.setZoomLevel(_zoomFactor);
    } catch (_) {}
    setState(() {});
  }

  void _zoomOut() async {
    if (_cameraController == null) return;
    _zoomFactor = (_zoomFactor - 0.5).clamp(1.0, 5.0);
    try {
      await _cameraController!.setZoomLevel(_zoomFactor);
    } catch (_) {}
    setState(() {});
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _cameraController?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Cámara
          if (_cameraReady && _cameraController != null)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraController!.value.previewSize?.height ?? 360,
                  height: _cameraController!.value.previewSize?.width ?? 640,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),

          // Guía overlay - forma de cédula
          _buildOverlay(topPad),

          // Barra superior
          Positioned(
            top: topPad + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                // Cerrar
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 24),
                  ),
                ),
                const Spacer(),
                // Status
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isProcessing)
                        Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.only(right: 8),
                          child: const CircularProgressIndicator(
                            color: Color(0xFF10B981),
                            strokeWidth: 2,
                          ),
                        ),
                      Text(
                        _statusText,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Logs
                GestureDetector(
                  onTap: () => setState(() => _showLogs = !_showLogs),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(
                      _showLogs ? Icons.terminal : Icons.terminal_outlined,
                      color: const Color(0xFF10B981),
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Controles inferiores
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: bottomPad + 16),
              decoration: const BoxDecoration(
                color: Color(0xAA000000),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Zoom + Torch
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Zoom out
                      _circleButton(Icons.zoom_out, _zoomOut),
                      // Zoom label
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '${_zoomFactor.toStringAsFixed(1)}x',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                        ),
                      ),
                      // Zoom in
                      _circleButton(Icons.zoom_in, _zoomIn),
                      // Torch
                      _circleButton(
                        _torchOn ? Icons.flash_on : Icons.flash_off,
                        _toggleTorch,
                        active: _torchOn,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Botón de captura manual
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: _manualCapture,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isProcessing ? Colors.grey : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Toca para capturar manualmente',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                  ),
                  Text(
                    'Auto-escaneo cada 2s • Intento #$_scanAttempts',
                    style: const TextStyle(color: Color(0xFF475569), fontSize: 10),
                  ),
                ],
              ),
            ),
          ),

          // Log panel
          if (_showLogs)
            Positioned(
              bottom: 240,
              left: 8,
              right: 8,
              child: const LogPanel(),
            ),
        ],
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap, {bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? const Color(0xFF10B981) : const Color(0xFF1E293B),
        ),
        child: Icon(icon, color: active ? Colors.white : Colors.white70, size: 22),
      ),
    );
  }

  Widget _buildOverlay(double topPad) {
    return Positioned.fill(
      child: CustomPaint(
        painter: _ScannerOverlayPainter(),
      ),
    );
  }
}

// ============================================================================
// OVERLAY PAINTER — Guía visual de la cédula
// ============================================================================

class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cardWidth = size.width * 0.84;
    final cardHeight = cardWidth * 0.63; // Proporción cédula
    final left = (size.width - cardWidth) / 2;
    final top = size.height * 0.22;

    // Área oscura fuera de la tarjeta
    final outsidePath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final cardRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, cardWidth, cardHeight),
      const Radius.circular(12),
    );

    final insidePath = Path()..addRRect(cardRect);

    final overlayPath = Path.combine(PathOperation.difference, outsidePath, insidePath);

    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );

    // Bordes de la tarjeta
    final borderPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRRect(cardRect, borderPaint);

    // Esquinas acentuadas
    final cornerLength = 24.0;
    final cornerPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawLine(Offset(left, top + cornerLength), Offset(left, top), cornerPaint);
    canvas.drawLine(Offset(left, top), Offset(left + cornerLength, top), cornerPaint);
    // Top-right
    canvas.drawLine(Offset(left + cardWidth - cornerLength, top), Offset(left + cardWidth, top), cornerPaint);
    canvas.drawLine(Offset(left + cardWidth, top), Offset(left + cardWidth, top + cornerLength), cornerPaint);
    // Bottom-left
    canvas.drawLine(Offset(left, top + cardHeight - cornerLength), Offset(left, top + cardHeight), cornerPaint);
    canvas.drawLine(Offset(left, top + cardHeight), Offset(left + cornerLength, top + cardHeight), cornerPaint);
    // Bottom-right
    canvas.drawLine(Offset(left + cardWidth, top + cardHeight - cornerLength), Offset(left + cardWidth, top + cardHeight), cornerPaint);
    canvas.drawLine(Offset(left + cardWidth - cornerLength, top + cardHeight), Offset(left + cardWidth, top + cardHeight), cornerPaint);

    // Texto guía arriba
    final textSpan = TextSpan(
      text: 'Apunta la parte DELANTERA de la cédula aquí',
      style: TextStyle(
        color: const Color(0xFF10B981),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset((size.width - textPainter.width) / 2, top - 28),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================================
// PANTALLA DE RESULTADOS
// ============================================================================

class ResultPage extends StatelessWidget {
  final CedulaData data;

  const ResultPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resultado'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Indicador de éxito
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF10B981)),
                  SizedBox(width: 12),
                  Text(
                    'Cédula detectada exitosamente',
                    style: TextStyle(color: Color(0xFF10B981), fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Número de documento
            _buildFieldCard(
              icon: Icons.badge,
              iconColor: const Color(0xFF3B82F6),
              label: 'Número de cédula',
              value: data.documentNumber,
              isMono: true,
              context: context,
            ),
            const SizedBox(height: 12),

            // Nombre completo
            _buildFieldCard(
              icon: Icons.person,
              iconColor: const Color(0xFF8B5CF6),
              label: 'Nombre completo',
              value: data.fullName.isNotEmpty ? data.fullName : 'No detectado',
              context: context,
            ),
            const SizedBox(height: 12),

            // Confianza
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Text('Confianza:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: data.confidence == 'high'
                          ? const Color(0xFF10B981).withValues(alpha: 0.2)
                          : data.confidence == 'medium'
                              ? Colors.amber.withValues(alpha: 0.2)
                              : Colors.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      data.confidence == 'high' ? 'Alta' : data.confidence == 'medium' ? 'Media' : 'Baja',
                      style: TextStyle(
                        color: data.confidence == 'high'
                            ? const Color(0xFF10B981)
                            : data.confidence == 'medium'
                                ? Colors.amber
                                : Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Texto crudo
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.text_snippet, color: Color(0xFF64748B), size: 16),
                      const SizedBox(width: 8),
                      const Text('Texto crudo detectado', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: data.rawText));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Texto copiado'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        child: const Icon(Icons.copy, color: Color(0xFF64748B), size: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Text(
                        data.rawText.isNotEmpty ? data.rawText : 'Sin texto',
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 11,
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Botones
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.home),
                    label: const Text('Inicio'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push<CedulaData>(
                        MaterialPageRoute(builder: (_) => const OcrScannerPage()),
                      ).then((result) {
                        if (result != null) {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (_) => ResultPage(data: result)),
                          );
                        }
                      });
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Escanear otra'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    bool isMono = false,
    required BuildContext context,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isMono ? 22 : 17,
                          fontWeight: FontWeight.bold,
                          fontFamily: isMono ? 'monospace' : null,
                          letterSpacing: isMono ? 2 : 0,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: value));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('$label copiado'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                      child: const Icon(Icons.copy, color: Color(0xFF64748B), size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
