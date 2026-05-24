import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
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
    // Mantener solo los últimos 200 logs
    if (_logs.length > 200) {
      _logs.removeRange(0, _logs.length - 200);
    }
    // Notificar listeners
    for (final listener in _listeners) {
      listener();
    }
    // También imprimir en consola para debug
    // ignore: avoid_print
    print(entry);
  }

  static void addError(String message) {
    add('ERROR: $message');
  }

  static void addSuccess(String message) {
    add('OK: $message');
  }

  static void addInfo(String message) {
    add('INFO: $message');
  }

  static void addBarcode(String message) {
    add('BARCODE: $message');
  }

  static void addOcr(String message) {
    add('OCR: $message');
  }

  static void addParser(String message) {
    add('PARSER: $message');
  }

  static void addScan(String message) {
    add('SCAN: $message');
  }

  static void addCamera(String message) {
    add('CAM: $message');
  }

  static void clear() {
    _logs.clear();
    for (final listener in _listeners) {
      listener();
    }
  }

  static void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  static void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }
}

// ============================================================================
// MODELO DE DATOS
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
  Map<String, String> fieldSource = {};

  String get fullName {
    final parts = [
      firstName,
      secondName,
      firstLastName,
      secondLastName,
    ].where((p) => p.isNotEmpty);
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

  void mergeFrom(CedulaData other) {
    if (other.documentNumber.isNotEmpty && documentNumber.isEmpty) {
      documentNumber = other.documentNumber;
      fieldSource['documentNumber'] = other.fieldSource['documentNumber'] ?? 'ocr';
    }
    if (other.firstName.isNotEmpty && firstName.isEmpty) {
      firstName = other.firstName;
      fieldSource['firstName'] = other.fieldSource['firstName'] ?? 'ocr';
    }
    if (other.secondName.isNotEmpty && secondName.isEmpty) {
      secondName = other.secondName;
      fieldSource['secondName'] = other.fieldSource['secondName'] ?? 'ocr';
    }
    if (other.firstLastName.isNotEmpty && firstLastName.isEmpty) {
      firstLastName = other.firstLastName;
      fieldSource['firstLastName'] = other.fieldSource['firstLastName'] ?? 'ocr';
    }
    if (other.secondLastName.isNotEmpty && secondLastName.isEmpty) {
      secondLastName = other.secondLastName;
      fieldSource['secondLastName'] = other.fieldSource['secondLastName'] ?? 'ocr';
    }
    if (other.birthDate.isNotEmpty && birthDate.isEmpty) {
      birthDate = other.birthDate;
      fieldSource['birthDate'] = other.fieldSource['birthDate'] ?? 'ocr';
    }
    if (other.gender.isNotEmpty && gender.isEmpty) {
      gender = other.gender;
      fieldSource['gender'] = other.fieldSource['gender'] ?? 'ocr';
    }
    if (other.expeditionDate.isNotEmpty && expeditionDate.isEmpty) {
      expeditionDate = other.expeditionDate;
      fieldSource['expeditionDate'] = other.fieldSource['expeditionDate'] ?? 'ocr';
    }
    if (other.expeditionPlace.isNotEmpty && expeditionPlace.isEmpty) {
      expeditionPlace = other.expeditionPlace;
      fieldSource['expeditionPlace'] = other.fieldSource['expeditionPlace'] ?? 'ocr';
    }
    if (other.bloodType.isNotEmpty && bloodType.isEmpty) {
      bloodType = other.bloodType;
      fieldSource['bloodType'] = other.fieldSource['bloodType'] ?? 'ocr';
    }
  }
}

// ============================================================================
// PARSER DE PDF417 — CÉDULA COLOMBIANA
// ============================================================================

class IdScanParser {
  static CedulaData parsePdf417(String raw) {
    final data = CedulaData();
    data.fieldSource = {};

    if (raw.isEmpty) {
      AppLog.addParser('parsePdf417: raw vacío');
      return data;
    }

    AppLog.addParser('parsePdf417: longitud=${raw.length}, primeros 100 chars="${raw.substring(0, raw.length > 100 ? 100 : raw.length)}"');
    AppLog.addParser('parsePdf417: contiene @=${raw.contains("@")}, LF=${raw.contains("\n")}, CR=${raw.contains("\r")}');

    _parseFormatNew(data, raw);
    if (_isEmptyData(data)) {
      AppLog.addParser('Formato nuevo no funcionó, intentando legacy...');
      _parseFormatLegacy(data, raw);
    }
    if (_isEmptyData(data)) {
      AppLog.addParser('Legacy no funcionó, intentando fallback...');
      _parseFormatFallback(data, raw);
    }

    AppLog.addParser('Resultado: doc=${data.documentNumber}, nombre=${data.firstName} ${data.firstLastName}, nac=${data.birthDate}');
    return data;
  }

  static void _parseFormatNew(CedulaData data, String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
        .trim();

    if (cleaned.contains('@')) {
      final parts = cleaned.split('@').where((p) => p.isNotEmpty).toList();
      AppLog.addParser('Formato @: ${parts.length} campos');
      _assignFieldsFromList(data, parts);
      return;
    }

    if (cleaned.contains('\n') || cleaned.contains('\r')) {
      final parts = cleaned
          .split(RegExp(r'[\r\n]+'))
          .where((p) => p.trim().isNotEmpty)
          .map((p) => p.trim())
          .toList();
      AppLog.addParser('Formato CR/LF: ${parts.length} campos');
      _assignFieldsFromList(data, parts);
      return;
    }

    if (cleaned.contains('|') || cleaned.contains('\t')) {
      final parts = cleaned
          .split(RegExp(r'[|\t]+'))
          .where((p) => p.trim().isNotEmpty)
          .map((p) => p.trim())
          .toList();
      AppLog.addParser('Formato pipe/tab: ${parts.length} campos');
      _assignFieldsFromList(data, parts);
    }
  }

  static void _parseFormatLegacy(CedulaData data, String raw) {
    final lines = raw
        .split(RegExp(r'[\r\n\x00-\x1F]+'))
        .where((l) => l.trim().isNotEmpty)
        .map((l) => l.trim())
        .toList();

    if (lines.length >= 3) {
      for (final line in lines) {
        final numMatch = RegExp(r'(\d{6,12})').firstMatch(line);
        if (numMatch != null && data.documentNumber.isEmpty) {
          data.documentNumber = numMatch.group(1)!;
          data.fieldSource['documentNumber'] = 'barcode';
          break;
        }
      }
      _assignFieldsFromList(data, lines);
    }
  }

  static void _parseFormatFallback(CedulaData data, String raw) {
    final docMatch = RegExp(r'(\d{8,12})').firstMatch(raw);
    if (docMatch != null) {
      data.documentNumber = docMatch.group(1)!;
      data.fieldSource['documentNumber'] = 'barcode';
    }

    final birthMatch = RegExp(r'(\d{2}/\d{2}/\d{4})').firstMatch(raw);
    if (birthMatch != null) {
      data.birthDate = birthMatch.group(1)!;
      data.fieldSource['birthDate'] = 'barcode';
    }

    final genderMatch = RegExp(r'\b([MF])\b').firstMatch(raw);
    if (genderMatch != null) {
      data.gender = genderMatch.group(1)!;
      data.fieldSource['gender'] = 'barcode';
    }

    final bloodMatch = RegExp(r'\b([ABO][+-])\b').firstMatch(raw);
    if (bloodMatch != null) {
      data.bloodType = bloodMatch.group(1)!;
      data.fieldSource['bloodType'] = 'barcode';
    }

    final words = raw.split(RegExp(r'[^A-Za-zÁÉÍÓÚÑÜ]+')).where((w) => w.length > 2).toList();
    final nameWords = <String>[];
    for (final word in words) {
      if (word.toUpperCase() == word && word.length > 2) {
        nameWords.add(word);
      }
    }
    if (nameWords.isNotEmpty) {
      if (nameWords.length >= 4) {
        data.firstLastName = nameWords[0];
        data.secondLastName = nameWords[1];
        data.firstName = nameWords[2];
        data.secondName = nameWords[3];
        data.fieldSource['firstLastName'] = 'barcode';
        data.fieldSource['secondLastName'] = 'barcode';
        data.fieldSource['firstName'] = 'barcode';
        data.fieldSource['secondName'] = 'barcode';
      } else if (nameWords.length >= 2) {
        data.firstLastName = nameWords[0];
        data.firstName = nameWords[1];
        data.fieldSource['firstLastName'] = 'barcode';
        data.fieldSource['firstName'] = 'barcode';
      }
    }
  }

  static void _assignFieldsFromList(CedulaData data, List<String> parts) {
    if (parts.isEmpty) return;

    int offset = 0;

    if (parts.isNotEmpty && parts[0].length <= 3 && !RegExp(r'^\d{6,}').hasMatch(parts[0])) {
      offset = 1;
    }

    if (data.documentNumber.isEmpty) {
      for (int i = offset; i < parts.length && i < offset + 2; i++) {
        final numMatch = RegExp(r'^(\d{6,12})$').firstMatch(parts[i]);
        if (numMatch != null) {
          data.documentNumber = numMatch.group(1)!;
          data.fieldSource['documentNumber'] = 'barcode';
          offset = i + 1;
          break;
        }
      }
      if (data.documentNumber.isEmpty) {
        for (int i = 0; i < parts.length && i < 3; i++) {
          final numMatch = RegExp(r'(\d{6,12})').firstMatch(parts[i]);
          if (numMatch != null) {
            data.documentNumber = numMatch.group(1)!;
            data.fieldSource['documentNumber'] = 'barcode';
            offset = i + 1;
            break;
          }
        }
      }
    }

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

    if (nameParts.length >= 4) {
      data.firstLastName = nameParts[0];
      data.secondLastName = nameParts[1];
      data.firstName = nameParts[2];
      data.secondName = nameParts[3];
    } else if (nameParts.length == 3) {
      data.firstLastName = nameParts[0];
      data.secondLastName = '';
      data.firstName = nameParts[1];
      data.secondName = nameParts[2];
    } else if (nameParts.length == 2) {
      data.firstLastName = nameParts[0];
      data.firstName = nameParts[1];
    } else if (nameParts.length == 1) {
      data.firstName = nameParts[0];
    }
    for (final key in ['firstLastName', 'secondLastName', 'firstName', 'secondName']) {
      final value = _getFieldValue(data, key);
      if (value.isNotEmpty) data.fieldSource[key] = 'barcode';
    }

    final dates = <String>[];
    for (final part in parts) {
      final dateMatch = RegExp(r'(\d{2}/\d{2}/\d{4})').firstMatch(part);
      if (dateMatch != null) {
        dates.add(dateMatch.group(1)!);
      }
    }
    if (dates.isNotEmpty && data.birthDate.isEmpty) {
      data.birthDate = dates[0];
      data.fieldSource['birthDate'] = 'barcode';
    }
    if (dates.length > 1 && data.expeditionDate.isEmpty) {
      data.expeditionDate = dates[1];
      data.fieldSource['expeditionDate'] = 'barcode';
    }

    if (data.gender.isEmpty) {
      for (final part in parts) {
        if (part.trim() == 'M' || part.trim() == 'F') {
          data.gender = part.trim();
          data.fieldSource['gender'] = 'barcode';
          break;
        }
      }
    }

    if (data.bloodType.isEmpty) {
      for (final part in parts) {
        final bloodMatch = RegExp(r'^([ABO][+-])$').firstMatch(part.trim());
        if (bloodMatch != null) {
          data.bloodType = bloodMatch.group(1)!;
          data.fieldSource['bloodType'] = 'barcode';
          break;
        }
      }
    }

    if (data.expeditionPlace.isEmpty && nameParts.length > 2) {
      for (int i = parts.length - 1; i >= 0; i--) {
        final part = parts[i].trim();
        if (part.length > 2 &&
            RegExp(r'^[A-Za-zÁÉÍÓÚÑÜ\s]+$').hasMatch(part) &&
            !nameParts.contains(part.toUpperCase())) {
          data.expeditionPlace = part.toUpperCase();
          data.fieldSource['expeditionPlace'] = 'barcode';
          break;
        }
      }
    }
  }

  static String _getFieldValue(CedulaData data, String fieldName) {
    switch (fieldName) {
      case 'firstLastName':
        return data.firstLastName;
      case 'secondLastName':
        return data.secondLastName;
      case 'firstName':
        return data.firstName;
      case 'secondName':
        return data.secondName;
      default:
        return '';
    }
  }

  static bool _isEmptyData(CedulaData data) {
    return data.documentNumber.isEmpty &&
        data.firstName.isEmpty &&
        data.firstLastName.isEmpty &&
        data.birthDate.isEmpty;
  }

  static CedulaData parseOcrFront(String text) {
    final data = CedulaData();
    data.fieldSource = {};

    if (text.isEmpty) {
      AppLog.addOcr('parseOcrFront: texto vacío');
      return data;
    }

    AppLog.addOcr('parseOcrFront: longitud=${text.length}');
    AppLog.addOcr('Texto OCR primeros 200 chars: "${text.substring(0, text.length > 200 ? 200 : text.length)}"');

    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    AppLog.addOcr('Líneas OCR: ${lines.length}');
    for (int i = 0; i < lines.length && i < 10; i++) {
      AppLog.addOcr('  Línea $i: "${lines[i]}"');
    }

    for (final line in lines) {
      final numMatch = RegExp(r'(\d{8,12})').firstMatch(line);
      if (numMatch != null) {
        data.documentNumber = numMatch.group(1)!;
        data.fieldSource['documentNumber'] = 'ocr';
        break;
      }
    }

    for (final line in lines) {
      final dateMatch = RegExp(r'(\d{2}[./-]\d{2}[./-]\d{4})').firstMatch(line);
      if (dateMatch != null) {
        data.birthDate = dateMatch.group(1)!.replaceAll('.', '/').replaceAll('-', '/');
        data.fieldSource['birthDate'] = 'ocr';
        break;
      }
    }

    final textLines = <String>[];
    for (final line in lines) {
      final cleaned = line.replaceAll(RegExp(r'[^\w\sÁÉÍÓÚÑÜ]'), '').trim();
      if (cleaned.isNotEmpty &&
          cleaned.length > 2 &&
          RegExp(r'^[A-Za-zÁÉÍÓÚÑÜ\s]+$').hasMatch(cleaned) &&
          !cleaned.toUpperCase().contains('REPÚBLICA') &&
          !cleaned.toUpperCase().contains('COLOMBIA') &&
          !cleaned.toUpperCase().contains('CÉDULA') &&
          !cleaned.toUpperCase().contains('CIUDADANÍA') &&
          !cleaned.toUpperCase().contains('IDENTIFICACIÓN')) {
        textLines.add(cleaned.toUpperCase());
      }
    }

    if (textLines.length >= 2) {
      final lastNames = textLines[0].split(RegExp(r'\s+'));
      final names = textLines[1].split(RegExp(r'\s+'));

      if (lastNames.isNotEmpty) data.firstLastName = lastNames[0];
      if (lastNames.length > 1) data.secondLastName = lastNames[1];
      if (names.isNotEmpty) data.firstName = names[0];
      if (names.length > 1) data.secondName = names[1];

      data.fieldSource['firstLastName'] = 'ocr';
      data.fieldSource['secondLastName'] = 'ocr';
      data.fieldSource['firstName'] = 'ocr';
      data.fieldSource['secondName'] = 'ocr';
    } else if (textLines.length == 1) {
      final parts = textLines[0].split(RegExp(r'\s+'));
      if (parts.length >= 4) {
        data.firstLastName = parts[0];
        data.secondLastName = parts[1];
        data.firstName = parts[2];
        data.secondName = parts[3];
      } else if (parts.length >= 2) {
        data.firstLastName = parts[0];
        data.firstName = parts[1];
      }
      data.fieldSource['firstLastName'] = 'ocr';
      data.fieldSource['firstName'] = 'ocr';
    }

    AppLog.addOcr('Resultado OCR: doc=${data.documentNumber}, nombre=${data.firstName} ${data.firstLastName}');
    return data;
  }
}

// ============================================================================
// SERVICIO DE CÁMARA
// ============================================================================

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];

  List<CameraDescription> get cameras => _cameras;
  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  Future<void> discoverCameras() async {
    _cameras = await availableCameras();
    AppLog.addCamera('Cámaras encontradas: ${_cameras.length}');
  }

  Future<void> initializeController({int cameraIndex = 0}) async {
    if (_cameras.isEmpty) await discoverCameras();
    if (_cameras.isEmpty) throw Exception('No se encontró ninguna cámara en el dispositivo.');

    final camera = _cameras[cameraIndex < _cameras.length ? cameraIndex : 0];
    AppLog.addCamera('Inicializando cámara: ${camera.name} (${camera.lensDirection})');

    _controller = CameraController(
      camera,
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await _controller!.initialize();
    AppLog.addCamera('Cámara inicializada OK');

    // Configurar modo de enfoque para mejor captura de barcode
    try {
      await _controller!.setFocusMode(FocusMode.auto);
      await _controller!.setFlashMode(FlashMode.off);
      AppLog.addCamera('FocusMode.auto + FlashMode.off OK');
    } catch (e) {
      AppLog.addCamera('No se pudo configurar enfoque/flash: $e');
    }
  }

  Future<String> takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      throw Exception('La cámara no está inicializada.');
    }
    AppLog.addCamera('Tomando foto...');
    final XFile file = await _controller!.takePicture();
    AppLog.addCamera('Foto guardada: ${file.path}');
    return file.path;
  }

  void dispose() {
    _controller?.dispose();
    _controller = null;
  }
}

// ============================================================================
// APP PRINCIPAL
// ============================================================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppLog.addInfo('App iniciada');
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
// WIDGET: PANEL DE LOGS DESLIZABLE
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
    // Auto-scroll al final
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
      constraints: const BoxConstraints(maxHeight: 200),
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
                } else if (log.contains('OCR:')) {
                  textColor = Colors.yellowAccent;
                } else if (log.contains('PARSER:')) {
                  textColor = Colors.orangeAccent;
                } else if (log.contains('SCAN:')) {
                  textColor = Colors.lightBlueAccent;
                }
                return Text(
                  log,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 9,
                    fontFamily: 'monospace',
                    height: 1.3,
                  ),
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
// FEAT-1: PANTALLA PRINCIPAL CON PERMISOS
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
    AppLog.addInfo('Permiso cámara: $status');
  }

  Future<void> _requestPermission() async {
    setState(() => _isChecking = true);
    final status = await Permission.camera.request();
    setState(() {
      _cameraStatus = status;
      _isChecking = false;
    });
    AppLog.addInfo('Permiso cámara solicitado: $status');
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  String _statusText() {
    switch (_cameraStatus) {
      case PermissionStatus.granted:
        return 'Permiso concedido';
      case PermissionStatus.denied:
        return 'Permiso denegado';
      case PermissionStatus.permanentlyDenied:
        return 'Permiso denegado permanentemente';
      case PermissionStatus.restricted:
        return 'Permiso restringido';
      case PermissionStatus.limited:
        return 'Permiso limitado';
      case PermissionStatus.provisional:
        return 'Permiso provisional';
    }
  }

  IconData _statusIcon() {
    switch (_cameraStatus) {
      case PermissionStatus.granted:
        return Icons.check_circle;
      case PermissionStatus.denied:
      case PermissionStatus.permanentlyDenied:
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  void _openCamera() async {
    if (_cameraStatus != PermissionStatus.granted) {
      await _requestPermission();
      if (_cameraStatus != PermissionStatus.granted) return;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SmartScanPage()),
    ).then((_) => _checkPermission());
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
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  const Icon(Icons.badge, size: 80, color: Colors.black),
                  const SizedBox(height: 16),
                  const Text(
                    'Escáner de Cédula',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Colombiana — PDF417 y OCR',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                  const SizedBox(height: 40),
                  if (_isChecking)
                    const Center(child: CircularProgressIndicator(color: Colors.black))
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(_statusIcon(), color: _cameraStatus == PermissionStatus.granted ? Colors.black : Colors.black54),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Permiso de cámara', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                Text(_statusText(), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (!_isChecking && _cameraStatus != PermissionStatus.granted)
                    ElevatedButton.icon(
                      onPressed: _requestPermission,
                      icon: const Icon(Icons.videocam),
                      label: const Text('Solicitar permiso de cámara'),
                    ),
                  if (!_isChecking && _cameraStatus == PermissionStatus.permanentlyDenied)
                    OutlinedButton.icon(
                      onPressed: _openSettings,
                      icon: const Icon(Icons.settings),
                      label: const Text('Abrir configuración del sistema'),
                    ),
                  const SizedBox(height: 24),
                  if (!_isChecking && _cameraStatus == PermissionStatus.granted)
                    ElevatedButton.icon(
                      onPressed: _openCamera,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Abrir Cámara'),
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
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
// FEAT-7 + FEAT-2 + FEAT-4: ESCANEO INTELIGENTE + PREVIEW + PDF417
// ============================================================================

class SmartScanPage extends StatefulWidget {
  const SmartScanPage({super.key});

  @override
  State<SmartScanPage> createState() => _SmartScanPageState();
}

class _SmartScanPageState extends State<SmartScanPage> {
  // IMPORTANTE: No filtrar por formato — usar TODOS los formatos para que
  // ML Kit detecte PDF417. Filtrar en el callback.
  // Algunos dispositivos no detectan PDF417 si se filtra solo ese formato.
  late final MobileScannerController _scannerController;

  bool _barcodeDetected = false;
  bool _isProcessing = false;
  String _modeIndicator = 'Escaneando PDF417...';
  bool _autoModeTimedOut = false;
  CedulaData? _barcodeData;
  String _lastBarcodeRaw = '';
  bool _showLogs = true;
  bool _torchOn = false;
  int _scanAttempts = 0;
  double _zoomFactor = 1.0;

  @override
  void initState() {
    super.initState();
    AppLog.addScan('SmartScanPage: iniciando scanner');
    AppLog.addInfo('isMinifyEnabled=false en build.gradle — R8 no debería romper ML Kit');

    // Crear controller con todos los formatos (no filtrar)
    // y detection speed normal para mejor compatibilidad
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );

    // Escuchar errores del scanner
    _scannerController.error.addListener(_onScannerError);

    _startAutoModeTimeout();
  }

  void _onScannerError() {
    final error = _scannerController.error.value;
    if (error != null) {
      AppLog.addError('Scanner error: $error');
      setState(() {
        _modeIndicator = 'Error: ${error.toString().substring(0, error.toString().length > 60 ? 60 : error.toString().length)}';
      });
    }
  }

  void _startAutoModeTimeout() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && !_barcodeDetected && !_isProcessing) {
        setState(() => _autoModeTimedOut = true);
        AppLog.addScan('Auto-timeout: mostrando botones manuales');
      }
    });
  }

  void _onBarcodeDetect(BarcodeCapture capture) {
    _scanAttempts++;
    final List<Barcode> barcodes = capture.barcodes;

    if (barcodes.isEmpty) return;

    AppLog.addScan('Detección #$_scanAttempts: ${barcodes.length} barcode(s) encontrado(s)');

    for (int i = 0; i < barcodes.length; i++) {
      final barcode = barcodes[i];
      final format = barcode.format;
      final rawValue = barcode.rawValue;

      AppLog.addBarcode('  Barcode[$i]: formato=$format, rawValue=${rawValue != null ? '"${rawValue.length > 80 ? '${rawValue.substring(0, 80)}...' : rawValue}"' : 'null'}');

      // Filtrar: solo aceptar PDF417 o formatos que contengan datos útiles
      // PDF417 = formato 2 en ML Kit
      if (format == BarcodeFormat.pdf417) {
        AppLog.addBarcode('  -> PDF417 detectado!');
      } else {
        AppLog.addBarcode('  -> Formato no PDF417 ($format), ignorando');
      }
    }

    if (_barcodeDetected || _isProcessing) return;

    // Buscar un PDF417 primero
    Barcode? pdf417Barcode;
    for (final barcode in barcodes) {
      if (barcode.format == BarcodeFormat.pdf417) {
        pdf417Barcode = barcode;
        break;
      }
    }

    // Si no hay PDF417, intentar con cualquier barcode que tenga datos largos
    // (puede que el formato sea detectado como "unknown" en algunos dispositivos)
    if (pdf417Barcode == null) {
      for (final barcode in barcodes) {
        final raw = barcode.rawValue;
        if (raw != null && raw.length > 50) {
          AppLog.addBarcode('  -> Usando barcode no-PDF417 con datos largos (${raw.length} chars)');
          pdf417Barcode = barcode;
          break;
        }
      }
    }

    if (pdf417Barcode == null) {
      AppLog.addScan('Ningún barcode útil en esta detección');
      return;
    }

    final String? rawValue = pdf417Barcode.rawValue;
    if (rawValue == null || rawValue.isEmpty) {
      AppLog.addScan('Barcode sin rawValue, ignorando');
      return;
    }

    setState(() {
      _barcodeDetected = true;
      _isProcessing = true;
      _modeIndicator = 'PDF417 detectado! Procesando...';
      _lastBarcodeRaw = rawValue;
    });

    AppLog.addSuccess('PDF417 capturado! Longitud=${rawValue.length} caracteres');

    // Parsear el PDF417
    final data = IdScanParser.parsePdf417(rawValue);
    setState(() {
      _barcodeData = data;
    });

    // Navegar a la pantalla de resultados
    _navigateToResults();
  }

  void _navigateToResults() {
    if (!mounted) return;

    final result = _barcodeData ?? CedulaData();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResultPage(
          data: result,
          barcodeRaw: _lastBarcodeRaw,
        ),
      ),
    );
  }

  void _openCameraForPhoto() async {
    if (!mounted) return;

    AppLog.addScan('Abriendo cámara para foto...');
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const CameraPage()),
    );

    if (result != null && result.isNotEmpty) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ReviewPage(imagePath: result),
        ),
      );
    }
  }

  void _toggleTorch() {
    _torchOn = !_torchOn;
    _scannerController.toggleTorch();
    AppLog.addScan('Flash: ${_torchOn ? "ON" : "OFF"}');
    setState(() {});
  }

  void _zoomIn() {
    _zoomFactor = (_zoomFactor + 0.5).clamp(1.0, 5.0);
    _scannerController.setZoomScale(_zoomFactor);
    AppLog.addScan('Zoom: ${_zoomFactor}x');
    setState(() {});
  }

  void _zoomOut() {
    _zoomFactor = (_zoomFactor - 0.5).clamp(1.0, 5.0);
    _scannerController.setZoomScale(_zoomFactor);
    AppLog.addScan('Zoom: ${_zoomFactor}x');
    setState(() {});
  }

  @override
  void dispose() {
    _scannerController.error.removeListener(_onScannerError);
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Scanner preview
          MobileScanner(
            controller: _scannerController,
            onDetect: _onBarcodeDetect,
            errorBuilder: (context, error, child) {
              AppLog.addError('MobileScanner errorBuilder: $error');
              return Container(
                color: Colors.black,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          'Error del escáner:\n$error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Volver'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // Overlay con guía rectangular
          _buildScannerOverlay(),

          // Barra superior con indicador de modo
          Positioned(
            top: topPad + 8,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.black54,
              child: Row(
                children: [
                  // Botón cerrar
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  // Indicador de modo
                  Expanded(
                    child: Text(
                      _modeIndicator,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _barcodeDetected ? Colors.greenAccent : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Botón logs
                  GestureDetector(
                    onTap: () => setState(() => _showLogs = !_showLogs),
                    child: Icon(
                      _showLogs ? Icons.terminal : Icons.terminal_outlined,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Controles de zoom y flash
          Positioned(
            top: topPad + 52,
            right: 12,
            child: Column(
              children: [
                // Flash
                GestureDetector(
                  onTap: _toggleTorch,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _torchOn ? Colors.white : Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _torchOn ? Icons.flash_on : Icons.flash_off,
                      color: _torchOn ? Colors.black : Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Zoom +
                GestureDetector(
                  onTap: _zoomIn,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.add, color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(height: 4),
                // Zoom indicator
                Text('${_zoomFactor}x', style: const TextStyle(color: Colors.white70, fontSize: 10)),
                const SizedBox(height: 4),
                // Zoom -
                GestureDetector(
                  onTap: _zoomOut,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.remove, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),

          // Panel de logs (si está visible)
          if (_showLogs)
            Positioned(
              top: topPad + 52,
              left: 12,
              right: 56,
              child: const LogPanel(),
            ),

          // Botones inferiores
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 24,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Botón "Tomar foto"
                ElevatedButton.icon(
                  onPressed: _openCameraForPhoto,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Tomar Foto'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                  ),
                ),
                const SizedBox(height: 12),

                // Botones manuales si el modo automático falló
                if (_autoModeTimedOut && !_barcodeDetected) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() => _modeIndicator = 'Leyendo código de barras...');
                          },
                          icon: const Icon(Icons.qr_code_2),
                          label: const Text('Es la parte trasera'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _openCameraForPhoto,
                          icon: const Icon(Icons.text_fields),
                          label: const Text('Es el frente'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                // Indicador de detección
                if (_barcodeDetected)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.greenAccent),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Código PDF417 detectado!',
                          style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),

                // Intento counter
                if (!_barcodeDetected && _scanAttempts > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Intentos: $_scanAttempts',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerOverlay() {
    final h = MediaQuery.of(context).size.height;
    final w = MediaQuery.of(context).size.width;

    // Rectángulo de guía: más ancho para la cédula horizontal
    final guideW = w * 0.9;
    final guideH = h * 0.35;
    final guideLeft = (w - guideW) / 2;
    final guideTop = (h - guideH) / 2 - 20;

    return Stack(
      children: [
        // Sombra completa
        Container(color: Colors.black45),
        // Área clara (cutout)
        Positioned(
          left: guideLeft,
          top: guideTop,
          child: Container(
            width: guideW,
            height: guideH,
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border.all(
                color: _barcodeDetected ? Colors.greenAccent : Colors.white,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        // BlendMode para hacer el cutout
        Positioned(
          left: guideLeft + 2,
          top: guideTop + 2,
          child: Container(
            width: guideW - 4,
            height: guideH - 4,
            color: Colors.transparent,
          ),
        ),
        // Texto guía
        Positioned(
          left: 0,
          right: 0,
          top: guideTop + guideH / 2 - 30,
          child: Column(
            children: [
              Icon(
                _barcodeDetected ? Icons.check_circle : Icons.crop_free,
                color: _barcodeDetected ? Colors.greenAccent : Colors.white54,
                size: 36,
              ),
              const SizedBox(height: 4),
              Text(
                _barcodeDetected ? 'Código detectado!' : 'Apunta al código PDF417',
                style: TextStyle(
                  color: _barcodeDetected ? Colors.greenAccent : Colors.white54,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Parte trasera de la cédula',
                style: TextStyle(
                  color: _barcodeDetected ? Colors.greenAccent : Colors.white38,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// FEAT-2 & FEAT-3: CÁMARA CON CAPTURA DE FOTO
// ============================================================================

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  final CameraService _cameraService = CameraService();
  bool _isInitializing = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      await _cameraService.discoverCameras();
      await _cameraService.initializeController();
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      AppLog.addError('CameraPage init error: $e');
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = 'No se pudo inicializar la cámara: $e';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraService.controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _takePicture() async {
    try {
      final path = await _cameraService.takePicture();
      if (mounted) {
        Navigator.of(context).pop(path);
      }
    } catch (e) {
      AppLog.addError('Error al tomar foto: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al tomar foto: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraService.dispose();
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
          else if (_errorMessage != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white, size: 48),
                    const SizedBox(height: 16),
                    Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 24),
                    ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Volver')),
                  ],
                ),
              ),
            )
          else ...[
            CameraPreview(_cameraService.controller!),
            // Guía
            Center(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.35,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.badge, color: Colors.white54, size: 36),
                    SizedBox(height: 4),
                    Text('Centra la cédula aquí', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ),
              ),
            ),
            // Controles
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.black54,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Cancelar', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    child: IconButton(
                      onPressed: _takePicture,
                      icon: const Icon(Icons.camera, color: Colors.white, size: 32),
                    ),
                  ),
                  const SizedBox(width: 80),
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
// FEAT-3 + FEAT-4 + FEAT-5: REVISIÓN + BARCODE + OCR
// ============================================================================

class ReviewPage extends StatefulWidget {
  final String imagePath;

  const ReviewPage({super.key, required this.imagePath});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  bool _isProcessing = false;
  String? _errorMessage;
  bool _showLogs = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisar Foto'),
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Imagen capturada
                Image.file(
                  File(widget.imagePath),
                  fit: BoxFit.contain,
                ),

                // Indicador de carga
                if (_isProcessing)
                  Container(
                    color: Colors.white70,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.black),
                          SizedBox(height: 16),
                          Text('Procesando imagen...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),

                // Error
                if (_errorMessage != null && !_isProcessing)
                  Container(
                    color: Colors.white70,
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 48),
                          const SizedBox(height: 16),
                          Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),
                  ),

                // Botones
                if (!_isProcessing && _errorMessage == null)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _scanImage,
                          icon: const Icon(Icons.search),
                          label: const Text('Escanear esta foto'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Volver a tomar'),
                        ),
                      ],
                    ),
                  ),

                // Botón de re-escaneo si hay error
                if (_errorMessage != null && !_isProcessing)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _scanImage,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Intentar de nuevo'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Volver a tomar'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (_showLogs) const LogPanel(),
        ],
      ),
    );
  }

  Future<void> _scanImage() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    AppLog.addScan('ReviewPage: iniciando escaneo de imagen');
    AppLog.addScan('Imagen: ${widget.imagePath}');

    try {
      CedulaData barcodeData = CedulaData();
      CedulaData ocrData = CedulaData();
      String barcodeRaw = '';

      // ====================================================================
      // PASO 1: Intentar escaneo de código de barras desde la imagen
      // ====================================================================
      AppLog.addBarcode('Iniciando escaneo de barcode desde imagen...');

      try {
        final controller = MobileScannerController(
          detectionSpeed: DetectionSpeed.normal,
        );

        AppLog.addBarcode('MobileScannerController creado para analyzeImage');
        AppLog.addBarcode('Imagen path: ${widget.imagePath}');
        AppLog.addBarcode('Imagen existe: ${File(widget.imagePath).existsSync()}');
        AppLog.addBarcode('Imagen tamaño: ${File(widget.imagePath).lengthSync()} bytes');

        final capture = await controller.analyzeImage(widget.imagePath);

        AppLog.addBarcode('analyzeImage retornó: ${capture != null ? "capture con ${capture.barcodes.length} barcode(s)" : "null"}');

        controller.dispose();

        if (capture != null) {
          AppLog.addBarcode('analyzeImage OK: ${capture.barcodes.length} barcode(s) encontrado(s)');

          for (int i = 0; i < capture.barcodes.length; i++) {
            final bc = capture.barcodes[i];
            final rawVal = bc.rawValue;
            AppLog.addBarcode('  Barcode[$i]: formato=${bc.format}, raw=${rawVal != null ? '"${rawVal.length > 80 ? '${rawVal.substring(0, 80)}...' : rawVal}"' : 'null'}');

            // Buscar PDF417 primero
            if (bc.format == BarcodeFormat.pdf417 && bc.rawValue != null) {
              barcodeRaw = bc.rawValue!;
              AppLog.addSuccess('PDF417 encontrado en imagen!');
              break;
            }

            // Si no es PDF417 pero tiene datos largos, usarlo
            if (barcodeRaw.isEmpty && rawVal != null && rawVal.length > 50) {
              barcodeRaw = rawVal;
              AppLog.addBarcode('Usando barcode no-PDF417 con ${rawVal.length} chars');
            }
          }

          if (barcodeRaw.isNotEmpty) {
            barcodeData = IdScanParser.parsePdf417(barcodeRaw);
          } else {
            AppLog.addBarcode('No se encontró barcode útil en la imagen');
          }
        } else {
          AppLog.addBarcode('analyzeImage retornó null — no se detectó ningún barcode');
        }
      } catch (e) {
        AppLog.addError('Error en barcode scan: $e');
      }

      // ====================================================================
      // PASO 2: OCR de la imagen
      // ====================================================================
      AppLog.addOcr('Iniciando OCR de la imagen...');

      try {
        final inputImage = InputImage.fromFilePath(widget.imagePath);
        final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
        final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
        textRecognizer.close();

        AppLog.addOcr('OCR completado: ${recognizedText.text.length} caracteres');
        ocrData = IdScanParser.parseOcrFront(recognizedText.text);
      } catch (e) {
        AppLog.addError('Error en OCR: $e');
      }

      // ====================================================================
      // PASO 3: Combinar datos
      // ====================================================================
      final mergedData = CedulaData();
      mergedData.mergeFrom(barcodeData);
      mergedData.mergeFrom(ocrData);

      AppLog.addInfo('Datos combinados: doc=${mergedData.documentNumber}, nombre=${mergedData.fullName}');

      // Verificar si obtuvimos algún dato
      if (mergedData.documentNumber.isEmpty &&
          mergedData.firstName.isEmpty &&
          mergedData.firstLastName.isEmpty) {
        setState(() {
          _isProcessing = false;
          _errorMessage =
              'No se detectó código de barras ni texto legible.\n\nConsejos:\n- Mejor iluminación\n- Acercar más la cámara\n- Evitar reflejos\n- La parte trasera tiene el código PDF417';
        });
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultPage(
            data: mergedData,
            barcodeRaw: barcodeRaw,
          ),
        ),
      );
    } catch (e) {
      AppLog.addError('Error general en escaneo: $e');
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Error al procesar la imagen: $e';
        });
      }
    }
  }
}

// ============================================================================
// FEAT-6: PANTALLA DE RESULTADOS
// ============================================================================

class ResultPage extends StatelessWidget {
  final CedulaData data;
  final String barcodeRaw;

  const ResultPage({super.key, required this.data, required this.barcodeRaw});

  @override
  Widget build(BuildContext context) {
    final fields = data.toMap();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resultados'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.badge, size: 48, color: Colors.black),
            const SizedBox(height: 8),
            const Text(
              'Datos de la Cédula',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            // Tarjetas de datos
            ...fields.entries.map((entry) {
              final fieldKey = _fieldKeyFromLabel(entry.key);
              final source = data.fieldSource[fieldKey] ?? '';
              final isBarcode = source == 'barcode';
              final isOcr = source == 'ocr';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    if (isBarcode)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.qr_code_2, size: 18, color: Colors.black54),
                      )
                    else if (isOcr)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.text_fields, size: 18, color: Colors.black54),
                      )
                    else
                      const SizedBox.shrink(),
                    Expanded(
                      flex: 2,
                      child: Text(
                        entry.key,
                        style: const TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w500),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        entry.value,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: entry.value == 'No detectado' ? Colors.black38 : Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),

            // Raw barcode data (colapsable)
            if (barcodeRaw.isNotEmpty) ...[
              const SizedBox(height: 16),
              ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                childrenPadding: const EdgeInsets.all(12),
                collapsedBackgroundColor: Colors.black.withValues(alpha: 0.05),
                backgroundColor: Colors.black.withValues(alpha: 0.08),
                title: const Text(
                  'Datos raw del código de barras',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                children: [
                  Container(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        barcodeRaw.length > 2000 ? '${barcodeRaw.substring(0, 2000)}...' : barcodeRaw,
                        style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // Botones
            ElevatedButton.icon(
              onPressed: () => _copyAll(context),
              icon: const Icon(Icons.copy),
              label: const Text('Copiar todo'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomePage()),
                  (route) => false,
                );
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Escanear otra cédula'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final result = await Navigator.of(context).push<String>(
                  MaterialPageRoute(builder: (_) => const CameraPage()),
                );
                if (result != null && result.isNotEmpty) {
                  if (context.mounted) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => ReviewPage(imagePath: result),
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.camera_alt),
              label: const Text('Nueva foto'),
            ),
          ],
        ),
      ),
    );
  }

  String _fieldKeyFromLabel(String label) {
    const map = {
      'Número de cédula': 'documentNumber',
      'Primer nombre': 'firstName',
      'Segundo nombre': 'secondName',
      'Primer apellido': 'firstLastName',
      'Segundo apellido': 'secondLastName',
      'Nombre completo': 'fullName',
      'Fecha de nacimiento': 'birthDate',
      'Género': 'gender',
      'Fecha de expedición': 'expeditionDate',
      'Lugar de expedición': 'expeditionPlace',
      'Tipo de sangre': 'bloodType',
    };
    return map[label] ?? '';
  }

  void _copyAll(BuildContext context) {
    final fields = data.toMap();
    final buffer = StringBuffer();
    for (final entry in fields.entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Datos copiados al portapapeles'), duration: Duration(seconds: 2)),
    );
  }
}
