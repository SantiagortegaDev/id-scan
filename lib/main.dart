import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
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
  static void addBarcode(String message) => add('BARCODE: $message');
  static void addParser(String message) => add('PARSER: $message');
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
// MODELO DE DATOS — CÉDULA COLOMBIANA DESDE PDF417
// ============================================================================

class CedulaData {
  String documentNumber = '';
  String firstName = '';
  String secondName = '';
  String firstLastName = '';
  String secondLastName = '';
  String birthDate = '';
  String gender = '';
  String expeditionDate = '';
  String expeditionPlace = '';
  String bloodType = '';

  String get fullName {
    final parts = [firstName, secondName, firstLastName, secondLastName].where((p) => p.isNotEmpty);
    return parts.join(' ');
  }

  Map<String, String> toMap() => {
        'Número de cédula': documentNumber.isNotEmpty ? documentNumber : 'No detectado',
        'Primer nombre': firstName.isNotEmpty ? firstName : 'No detectado',
        'Segundo nombre': secondName.isNotEmpty ? secondName : 'No detectado',
        'Primer apellido': firstLastName.isNotEmpty ? firstLastName : 'No detectado',
        'Segundo apellido': secondLastName.isNotEmpty ? secondLastName : 'No detectado',
        'Nombre completo': fullName.isNotEmpty ? fullName : 'No detectado',
        'Fecha de nacimiento': birthDate.isNotEmpty ? birthDate : 'No detectado',
        'Género': gender.isNotEmpty ? (gender == 'M' ? 'Masculino' : 'Femenino') : 'No detectado',
        'Fecha de expedición': expeditionDate.isNotEmpty ? expeditionDate : 'No detectado',
        'Lugar de expedición': expeditionPlace.isNotEmpty ? expeditionPlace : 'No detectado',
        'Tipo de sangre': bloodType.isNotEmpty ? bloodType : 'No detectado',
      };
}

// ============================================================================
// PARSER DE PDF417 — CÉDULA COLOMBIANA
// Formato estándar: campos separados por @
// Ej: @1152212345@PÉREZ@GÓMEZ@JUAN@CARLOS@H@01/01/1990@01/01/2020@BOGOTÁ@O+
// ============================================================================

class IdScanParser {
  static CedulaData parsePdf417(String raw) {
    final data = CedulaData();

    if (raw.isEmpty) {
      AppLog.addParser('parsePdf417: raw vacío');
      return data;
    }

    AppLog.addParser('parsePdf417: longitud=${raw.length}');
    AppLog.addParser('Primeros 150 chars: "${raw.substring(0, raw.length > 150 ? 150 : raw.length)}"');
    AppLog.addParser('Contiene @=${raw.contains("@")}, LF=${raw.contains("\n")}, CR=${raw.contains("\r")}');

    // Limpiar caracteres de control pero mantener @, /, +, -
    final cleaned = raw
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
        .trim();

    // Estrategia 1: Separador @ (formato estándar colombiano)
    if (cleaned.contains('@')) {
      _parseAtFormat(data, cleaned);
    }

    // Si no funcionó, estrategia 2: CR/LF
    if (_isEmptyData(data) && (cleaned.contains('\n') || cleaned.contains('\r'))) {
      _parseCrLfFormat(data, cleaned);
    }

    // Si no funcionó, estrategia 3: regex fallback
    if (_isEmptyData(data)) {
      _parseFallback(data, cleaned);
    }

    AppLog.addParser('Resultado: doc=${data.documentNumber}, nombre=${data.fullName}, nac=${data.birthDate}');
    return data;
  }

  /// Formato estándar colombiano con separador @
  /// Los campos vienen en orden fijo según la norma técnico-cédula
  static void _parseAtFormat(CedulaData data, String raw) {
    final parts = raw.split('@').where((p) => p.isNotEmpty).toList();
    AppLog.addParser('Formato @: ${parts.length} campos');

    if (parts.isEmpty) return;

    // Imprimir todos los campos para debug
    for (int i = 0; i < parts.length; i++) {
      final preview = parts[i].length > 60 ? '${parts[i].substring(0, 60)}...' : parts[i];
      AppLog.addParser('  Campo[$i]: "$preview"');
    }

    // Asignar campos por posición — la cédula colombiana tiene un orden fijo
    // pero puede variar ligeramente. Buscamos por tipo de dato.
    _assignFieldsFromList(data, parts);
  }

  /// Formato con saltos de línea
  static void _parseCrLfFormat(CedulaData data, String raw) {
    final parts = raw
        .split(RegExp(r'[\r\n]+'))
        .where((p) => p.trim().isNotEmpty)
        .map((p) => p.trim())
        .toList();
    AppLog.addParser('Formato CR/LF: ${parts.length} campos');
    _assignFieldsFromList(data, parts);
  }

  /// Fallback: extraer datos con regex
  static void _parseFallback(CedulaData data, String raw) {
    AppLog.addParser('Usando fallback regex...');

    final docMatch = RegExp(r'(\d{8,12})').firstMatch(raw);
    if (docMatch != null) {
      data.documentNumber = docMatch.group(1)!;
    }

    final birthMatch = RegExp(r'(\d{2}/\d{2}/\d{4})').firstMatch(raw);
    if (birthMatch != null) {
      data.birthDate = birthMatch.group(1)!;
    }

    final genderMatch = RegExp(r'\b([MF])\b').firstMatch(raw);
    if (genderMatch != null) {
      data.gender = genderMatch.group(1)!;
    }

    final bloodMatch = RegExp(r'\b([ABO][+-])\b').firstMatch(raw);
    if (bloodMatch != null) {
      data.bloodType = bloodMatch.group(1)!;
    }

    // Buscar nombres en mayúscula sostenida
    final words = raw.split(RegExp(r'[^A-Za-zÁÉÍÓÚÑÜ]+')).where((w) => w.length > 2).toList();
    final nameWords = <String>[];
    for (final word in words) {
      if (word.toUpperCase() == word && word.length > 2) {
        nameWords.add(word);
      }
    }
    if (nameWords.length >= 4) {
      data.firstLastName = nameWords[0];
      data.secondLastName = nameWords[1];
      data.firstName = nameWords[2];
      data.secondName = nameWords[3];
    } else if (nameWords.length >= 2) {
      data.firstLastName = nameWords[0];
      data.firstName = nameWords[1];
    }
  }

  /// Asigna campos desde una lista, buscando por tipo de dato
  static void _assignFieldsFromList(CedulaData data, List<String> parts) {
    if (parts.isEmpty) return;

    int offset = 0;

    // Saltar prefijo corto (código del formato, ej: "CC", "CE")
    if (parts.isNotEmpty && parts[0].length <= 3 && !RegExp(r'^\d{6,}').hasMatch(parts[0])) {
      offset = 1;
      AppLog.addParser('Saltando prefijo: "${parts[0]}", offset=$offset');
    }

    // Buscar número de documento (6-12 dígitos)
    if (data.documentNumber.isEmpty) {
      for (int i = offset; i < parts.length; i++) {
        final numMatch = RegExp(r'^(\d{6,12})$').firstMatch(parts[i].trim());
        if (numMatch != null) {
          data.documentNumber = numMatch.group(1)!;
          offset = i + 1;
          AppLog.addParser('Documento encontrado en campo[$i]: ${data.documentNumber}');
          break;
        }
      }
      // Si no encontró exacto, buscar parcial
      if (data.documentNumber.isEmpty) {
        for (int i = 0; i < parts.length && i < 3; i++) {
          final numMatch = RegExp(r'(\d{6,12})').firstMatch(parts[i].trim());
          if (numMatch != null) {
            data.documentNumber = numMatch.group(1)!;
            offset = i + 1;
            AppLog.addParser('Documento encontrado (parcial) en campo[$i]: ${data.documentNumber}');
            break;
          }
        }
      }
    }

    // Buscar nombres (palabras alfabéticas, mayúsculas, después del documento)
    final nameParts = <String>[];
    for (int i = offset; i < parts.length; i++) {
      final part = parts[i].trim();
      if (RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(part)) break;
      if (RegExp(r'^\d+$').hasMatch(part)) continue;
      if (part == 'M' || part == 'F') continue;
      if (RegExp(r'^[ABO][+-]$').hasMatch(part)) continue;
      if (part.length > 1 && RegExp(r'^[A-Za-zÁÉÍÓÚÑÜ]+$').hasMatch(part)) {
        nameParts.add(part.toUpperCase());
      }
    }

    // Asignar nombres: apellido1, apellido2, nombre1, nombre2
    if (nameParts.length >= 4) {
      data.firstLastName = nameParts[0];
      data.secondLastName = nameParts[1];
      data.firstName = nameParts[2];
      data.secondName = nameParts[3];
    } else if (nameParts.length == 3) {
      data.firstLastName = nameParts[0];
      data.firstName = nameParts[1];
      data.secondName = nameParts[2];
    } else if (nameParts.length == 2) {
      data.firstLastName = nameParts[0];
      data.firstName = nameParts[1];
    } else if (nameParts.length == 1) {
      data.firstName = nameParts[0];
    }

    // Buscar fechas (dd/mm/yyyy)
    final dates = <String>[];
    for (final part in parts) {
      final dateMatch = RegExp(r'(\d{2}/\d{2}/\d{4})').firstMatch(part.trim());
      if (dateMatch != null) {
        dates.add(dateMatch.group(1)!);
      }
    }
    if (dates.isNotEmpty && data.birthDate.isEmpty) {
      data.birthDate = dates[0];
    }
    if (dates.length > 1 && data.expeditionDate.isEmpty) {
      data.expeditionDate = dates[1];
    }

    // Buscar género
    if (data.gender.isEmpty) {
      for (final part in parts) {
        final trimmed = part.trim();
        if (trimmed == 'M' || trimmed == 'F') {
          data.gender = trimmed;
          break;
        }
      }
    }

    // Buscar tipo de sangre
    if (data.bloodType.isEmpty) {
      for (final part in parts) {
        final bloodMatch = RegExp(r'^([ABO][+-])$').firstMatch(part.trim());
        if (bloodMatch != null) {
          data.bloodType = bloodMatch.group(1)!;
          break;
        }
      }
    }

    // Buscar lugar de expedición (último campo alfabético largo)
    if (data.expeditionPlace.isEmpty) {
      for (int i = parts.length - 1; i >= 0; i--) {
        final part = parts[i].trim();
        if (part.length > 2 &&
            RegExp(r'^[A-Za-zÁÉÍÓÚÑÜ\s]+$').hasMatch(part) &&
            !nameParts.contains(part.toUpperCase())) {
          data.expeditionPlace = part.toUpperCase();
          break;
        }
      }
    }
  }

  static bool _isEmptyData(CedulaData data) {
    return data.documentNumber.isEmpty &&
        data.firstName.isEmpty &&
        data.firstLastName.isEmpty &&
        data.birthDate.isEmpty;
  }
}

// ============================================================================
// APP PRINCIPAL
// ============================================================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppLog.addInfo('ID Scan iniciada — solo PDF417');
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
        brightness: Brightness.light,
        primaryColor: Colors.black,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: const ColorScheme.light(
          primary: Colors.black,
          onPrimary: Colors.white,
          secondary: Colors.black,
          onSecondary: Colors.white,
          surface: Colors.white,
          onSurface: Colors.black,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.black,
            side: const BorderSide(color: Colors.black, width: 2),
            minimumSize: const Size(double.infinity, 50),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

// ============================================================================
// PANTALLA PRINCIPAL — Un solo botón: Tomar Foto
// ============================================================================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _showLogs = false;

  Future<void> _tomarFoto() async {
    // Pedir permiso de cámara si no lo tiene
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Se necesita permiso de cámara para escanear la cédula'),
            action: SnackBarAction(
              label: 'Config',
              onPressed: openAppSettings,
            ),
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    // Abrir cámara directamente
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const CameraPage()),
    );

    if (result != null && result.isNotEmpty && mounted) {
      // Procesar la foto automáticamente
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProcessPage(imagePath: result),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ID Scan'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_showLogs ? Icons.terminal : Icons.terminal_outlined),
            tooltip: 'Mostrar logs',
            onPressed: () => setState(() => _showLogs = !_showLogs),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  const Icon(Icons.qr_code_2, size: 80, color: Colors.black),
                  const SizedBox(height: 24),
                  const Text(
                    'Escáner de Cédula',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Toma una foto de la parte trasera\ny lee el código PDF417',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                  const SizedBox(height: 48),
                  ElevatedButton.icon(
                    onPressed: _tomarFoto,
                    icon: const Icon(Icons.camera_alt, size: 28),
                    label: const Text('Tomar Foto'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Spacer(),
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
// PANTALLA DE CÁMARA — Tomar 1 foto de la parte trasera
// ============================================================================

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitializing = true;
  String? _error;
  bool _flashOn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      AppLog.addCamera('Cámaras: ${_cameras.length}');

      if (_cameras.isEmpty) throw Exception('No hay cámara');

      final camera = _cameras[0];
      _controller = CameraController(
        camera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      try {
        await _controller!.setFocusMode(FocusMode.auto);
        await _controller!.setFlashMode(FlashMode.off);
      } catch (_) {}

      if (mounted) setState(() => _isInitializing = false);
      AppLog.addCamera('Cámara lista');
    } catch (e) {
      AppLog.addError('Error cámara: $e');
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _error = 'No se pudo iniciar la cámara: $e';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final XFile file = await _controller!.takePicture();
      AppLog.addCamera('Foto: ${file.path}');
      if (mounted) Navigator.of(context).pop(file.path);
    } catch (e) {
      AppLog.addError('Error al tomar foto: $e');
    }
  }

  void _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    _flashOn = !_flashOn;
    try {
      await _controller!.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    } catch (_) {}
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_isInitializing)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white, size: 48),
                    const SizedBox(height: 16),
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 24),
                    ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Volver')),
                  ],
                ),
              ),
            )
          else ...[
            CameraPreview(_controller!),

            // Guía: rectángulo para el código de barras
            Center(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.92,
                height: MediaQuery.of(context).size.height * 0.30,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white70, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_2, color: Colors.white54, size: 36),
                    SizedBox(height: 4),
                    Text('Centra el código PDF417 aquí', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    Text('Parte trasera de la cédula', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
              ),
            ),

            // Botón cerrar
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),

            // Botón flash
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 16,
              child: GestureDetector(
                onTap: _toggleFlash,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _flashOn ? Colors.white : Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _flashOn ? Icons.flash_on : Icons.flash_off,
                    color: _flashOn ? Colors.black : Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),

            // Botón tomar foto
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 32,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    child: IconButton(
                      onPressed: _takePicture,
                      icon: const Icon(Icons.camera, color: Colors.white, size: 34),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// PANTALLA DE PROCESAMIENTO — Analiza la foto buscando PDF417
// ============================================================================

class ProcessPage extends StatefulWidget {
  final String imagePath;

  const ProcessPage({super.key, required this.imagePath});

  @override
  State<ProcessPage> createState() => _ProcessPageState();
}

class _ProcessPageState extends State<ProcessPage> {
  bool _isProcessing = true;
  String? _error;
  CedulaData? _data;
  String _barcodeRaw = '';
  bool _showLogs = true;

  @override
  void initState() {
    super.initState();
    _processImage();
  }

  Future<void> _processImage() async {
    AppLog.addInfo('Procesando imagen: ${widget.imagePath}');
    AppLog.addInfo('Archivo existe: ${File(widget.imagePath).existsSync()}');
    AppLog.addInfo('Tamaño: ${File(widget.imagePath).lengthSync()} bytes');

    try {
      // ============================================================
      // Escanear código de barras PDF417 desde la foto
      // ============================================================
      AppLog.addBarcode('Iniciando escaneo de barcode...');

      final controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
      );

      BarcodeCapture? capture;
      try {
        capture = await controller.analyzeImage(widget.imagePath);
        AppLog.addBarcode('analyzeImage: ${capture != null ? "${capture.barcodes.length} barcode(s)" : "null"}');
      } catch (e) {
        AppLog.addError('Error en analyzeImage: $e');
      }

      controller.dispose();

      // Buscar PDF417
      String rawValue = '';
      if (capture != null) {
        for (final barcode in capture.barcodes) {
          AppLog.addBarcode('Barcode: formato=${barcode.format}, rawLen=${barcode.rawValue?.length ?? 0}');

          // Prioridad 1: PDF417
          if (barcode.format == BarcodeFormat.pdf417 && barcode.rawValue != null) {
            rawValue = barcode.rawValue!;
            AppLog.addSuccess('PDF417 encontrado! ${rawValue.length} caracteres');
            break;
          }
        }

        // Prioridad 2: Cualquier barcode con datos largos
        if (rawValue.isEmpty) {
          for (final barcode in capture.barcodes) {
            final raw = barcode.rawValue;
            if (raw != null && raw.length > 50) {
              rawValue = raw;
              AppLog.addBarcode('Usando barcode ${barcode.format} con ${raw.length} chars');
              break;
            }
          }
        }
      }

      if (rawValue.isEmpty) {
        AppLog.addBarcode('No se encontró barcode en la imagen');
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _error = 'No se detectó el código PDF417.\n\nAsegúrate de:\n- Fotografiar la parte TRASERA\n- Buena iluminación\n- El código debe verse completo\n- Evitar reflejos';
          });
        }
        return;
      }

      // Parsear el contenido
      final data = IdScanParser.parsePdf417(rawValue);

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _data = data;
          _barcodeRaw = rawValue;
        });
      }
    } catch (e) {
      AppLog.addError('Error procesando: $e');
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _error = 'Error al procesar: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resultado'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_showLogs ? Icons.terminal : Icons.terminal_outlined),
            tooltip: 'Logs',
            onPressed: () => setState(() => _showLogs = !_showLogs),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Miniatura de la foto
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: Image.file(File(widget.imagePath), fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Procesando
                  if (_isProcessing) ...[
                    const Center(child: CircularProgressIndicator(color: Colors.black)),
                    const SizedBox(height: 16),
                    const Text(
                      'Leyendo código PDF417...',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ],

                  // Error
                  if (_error != null && !_isProcessing) ...[
                    const Icon(Icons.error_outline, size: 48, color: Colors.black54),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: Colors.black87),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final result = await Navigator.of(context).push<String>(
                          MaterialPageRoute(builder: (_) => const CameraPage()),
                        );
                        if (result != null && result.isNotEmpty && mounted) {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (_) => ProcessPage(imagePath: result)),
                          );
                        }
                      },
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Tomar otra foto'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const HomePage()),
                        (route) => false,
                      ),
                      icon: const Icon(Icons.home),
                      label: const Text('Volver al inicio'),
                    ),
                  ],

                  // Resultados
                  if (_data != null && !_isProcessing) ...[
                    const Icon(Icons.check_circle, size: 40, color: Colors.black),
                    const SizedBox(height: 8),
                    const Text(
                      'Datos del Código PDF417',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),

                    // Campos extraídos
                    ..._data!.toMap().entries.map((entry) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.black12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  entry.value,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: entry.value == 'No detectado' ? Colors.black38 : Colors.black,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),

                    // Datos raw del código (colapsable)
                    if (_barcodeRaw.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                        childrenPadding: const EdgeInsets.all(10),
                        collapsedBackgroundColor: Colors.black.withValues(alpha: 0.04),
                        backgroundColor: Colors.black.withValues(alpha: 0.07),
                        title: const Text(
                          'Contenido raw del código de barras',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        children: [
                          Container(
                            constraints: const BoxConstraints(maxHeight: 180),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                _barcodeRaw.length > 3000 ? '${_barcodeRaw.substring(0, 3000)}...' : _barcodeRaw,
                                style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Botones
                    ElevatedButton.icon(
                      onPressed: () => _copyAll(context),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copiar datos'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final result = await Navigator.of(context).push<String>(
                          MaterialPageRoute(builder: (_) => const CameraPage()),
                        );
                        if (result != null && result.isNotEmpty && mounted) {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (_) => ProcessPage(imagePath: result)),
                          );
                        }
                      },
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Escanear otra cédula'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const HomePage()),
                        (route) => false,
                      ),
                      icon: const Icon(Icons.home),
                      label: const Text('Volver al inicio'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_showLogs) const LogPanel(),
        ],
      ),
    );
  }

  void _copyAll(BuildContext context) {
    final buffer = StringBuffer();
    if (_data != null) {
      for (final entry in _data!.toMap().entries) {
        buffer.writeln('${entry.key}: ${entry.value}');
      }
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Datos copiados'), duration: Duration(seconds: 2)),
    );
  }
}

// ============================================================================
// WIDGET: PANEL DE LOGS
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
        color: const Color(0xFF1a1a1a),
        border: Border.all(color: Colors.black54),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.black,
            child: Row(
              children: [
                const Icon(Icons.terminal, color: Colors.white70, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Logs (${logs.length})',
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
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
                  textColor = Colors.greenAccent;
                } else if (log.contains('BARCODE:')) {
                  textColor = Colors.cyanAccent;
                } else if (log.contains('PARSER:')) {
                  textColor = Colors.orangeAccent;
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
