import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';
// path_provider is used transitively via camera package

// ============================================================================
// MODELO DE DATOS
// ============================================================================

/// Representa los datos extraídos de una cédula colombiana.
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

  /// Fuente de cada campo: 'barcode' o 'ocr'
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

  /// Copia datos no vacíos de otra instancia, respetando la fuente.
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
  /// Parsea el contenido del código PDF417 de la cédula colombiana.
  ///
  /// El PDF417 colombiano contiene campos separados por caracteres de control.
  /// Existen varias generaciones del formato:
  /// - Formato antiguo: campos separados por CR/LF
  /// - Formato nuevo (dación 2015+): campos delimitados con @ o con posiciones fijas
  /// - Formato con prefijo nacional: empieza con código de país
  static CedulaData parsePdf417(String raw) {
    final data = CedulaData();
    data.fieldSource = {};

    if (raw.isEmpty) return data;

    // Intentar múltiples estrategias de parsing
    _parseFormatNew(data, raw);
    if (_isEmptyData(data)) {
      _parseFormatLegacy(data, raw);
    }
    if (_isEmptyData(data)) {
      _parseFormatFallback(data, raw);
    }

    return data;
  }

  /// Formato nuevo (cédulas 2015+): campos separados por @ o con estructura fija.
  /// El payload típicamente empieza con un código de país o tiene campos
  /// delimitados por caracteres especiales.
  static void _parseFormatNew(CedulaData data, String raw) {
    // Limpiar caracteres de control
    final cleaned = raw
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
        .trim();

    // Intentar separar por @ (formato común en cédulas nuevas)
    if (cleaned.contains('@')) {
      final parts = cleaned.split('@').where((p) => p.isNotEmpty).toList();
      _assignFieldsFromList(data, parts);
      return;
    }

    // Intentar separar por CR/LF
    if (cleaned.contains('\n') || cleaned.contains('\r')) {
      final parts = cleaned
          .split(RegExp(r'[\r\n]+'))
          .where((p) => p.trim().isNotEmpty)
          .map((p) => p.trim())
          .toList();
      _assignFieldsFromList(data, parts);
      return;
    }

    // Intentar separar por pipes o tabs
    if (cleaned.contains('|') || cleaned.contains('\t')) {
      final parts = cleaned
          .split(RegExp(r'[|\t]+'))
          .where((p) => p.trim().isNotEmpty)
          .map((p) => p.trim())
          .toList();
      _assignFieldsFromList(data, parts);
    }
  }

  /// Formato legacy (cédulas anteriores a 2015): campos en posiciones fijas o
  /// separados por caracteres de control ANSI.
  static void _parseFormatLegacy(CedulaData data, String raw) {
    // Algunas cédulas antiguas usan el formato:
    // tipo_doc\nnumero\napellidos\nnombres\n...
    final lines = raw
        .split(RegExp(r'[\r\n\x00-\x1F]+'))
        .where((l) => l.trim().isNotEmpty)
        .map((l) => l.trim())
        .toList();

    if (lines.length >= 3) {
      // Buscar el número de documento (primera secuencia numérica larga)
      for (final line in lines) {
        final numMatch = RegExp(r'(\d{6,12})').firstMatch(line);
        if (numMatch != null && data.documentNumber.isEmpty) {
          data.documentNumber = numMatch.group(1)!;
          data.fieldSource['documentNumber'] = 'barcode';
          break;
        }
      }

      // Asignar nombres/apellidos de las líneas restantes
      _assignFieldsFromList(data, lines);
    }
  }

  /// Fallback: buscar patrones específicos en el texto crudo.
  static void _parseFormatFallback(CedulaData data, String raw) {
    // Buscar número de documento
    final docMatch = RegExp(r'(\d{8,12})').firstMatch(raw);
    if (docMatch != null) {
      data.documentNumber = docMatch.group(1)!;
      data.fieldSource['documentNumber'] = 'barcode';
    }

    // Buscar fecha de nacimiento (DD/MM/YYYY)
    final birthMatch =
        RegExp(r'(\d{2}/\d{2}/\d{4})').firstMatch(raw);
    if (birthMatch != null) {
      data.birthDate = birthMatch.group(1)!;
      data.fieldSource['birthDate'] = 'barcode';
    }

    // Buscar género (M o F aislado)
    final genderMatch = RegExp(r'\b([MF])\b').firstMatch(raw);
    if (genderMatch != null) {
      data.gender = genderMatch.group(1)!;
      data.fieldSource['gender'] = 'barcode';
    }

    // Buscar tipo de sangre
    final bloodMatch = RegExp(r'\b([ABO][+-])\b').firstMatch(raw);
    if (bloodMatch != null) {
      data.bloodType = bloodMatch.group(1)!;
      data.fieldSource['bloodType'] = 'barcode';
    }

    // Buscar nombre: secuencia de palabras mayúsculas sin números
    final words = raw.split(RegExp(r'[^A-Za-zÁÉÍÓÚÑÜ]+')).where((w) => w.length > 2).toList();
    final nameWords = <String>[];
    for (final word in words) {
      if (word.toUpperCase() == word && word.length > 2) {
        nameWords.add(word);
      }
    }
    if (nameWords.isNotEmpty) {
      // Intentar asignar: primeros son apellidos, últimos son nombres
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

  /// Asigna campos desde una lista de partes según el orden típico de la cédula.
  static void _assignFieldsFromList(CedulaData data, List<String> parts) {
    if (parts.isEmpty) return;

    // Orden típico del PDF417 colombiano:
    // [0] tipo/indicador, [1] número documento, [2] primer apellido,
    // [3] segundo apellido, [4] primer nombre, [5] segundo nombre,
    // [6] fecha nacimiento, [7] género, [8] fecha expedición,
    // [9] lugar expedición, [10] RH/tipo sangre
    //
    // Pero el formato puede variar, así que intentamos heurística

    int offset = 0;

    // Si el primer elemento es un código corto (tipo de documento), saltarlo
    if (parts.isNotEmpty && parts[0].length <= 3 && !RegExp(r'^\d{6,}').hasMatch(parts[0])) {
      offset = 1;
    }

    // Número de documento: buscar la primera secuencia numérica larga
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
      // Si no se encontró con formato estricto, buscar en los primeros elementos
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

    // Nombres y apellidos: buscar secuencias de texto mayúsculas
    final nameParts = <String>[];
    for (int i = offset; i < parts.length; i++) {
      final part = parts[i].trim();
      // Si es una fecha, detenerse (los nombres vienen antes)
      if (RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(part)) break;
      // Si es un número puro, saltar
      if (RegExp(r'^\d+$').hasMatch(part)) continue;
      // Si es M o F, saltar
      if (part == 'M' || part == 'F') continue;
      // Si es tipo de sangre, saltar
      if (RegExp(r'^[ABO][+-]$').hasMatch(part)) continue;
      // Es un nombre/apellido
      if (part.length > 1 && RegExp(r'^[A-Za-zÁÉÍÓÚÑÜ]+$').hasMatch(part)) {
        nameParts.add(part.toUpperCase());
      }
    }

    // Asignar nombres y apellidos
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

    // Buscar fechas (DD/MM/YYYY)
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

    // Buscar género
    if (data.gender.isEmpty) {
      for (final part in parts) {
        if (part.trim() == 'M' || part.trim() == 'F') {
          data.gender = part.trim();
          data.fieldSource['gender'] = 'barcode';
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
          data.fieldSource['bloodType'] = 'barcode';
          break;
        }
      }
    }

    // Buscar lugar de expedición: último campo alfabético después de las fechas
    if (data.expeditionPlace.isEmpty && nameParts.length > 2) {
      // A veces el lugar de expedición viene al final
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

  /// Obtiene el valor de un campo por nombre.
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

  /// Verifica si los datos extraídos están vacíos.
  static bool _isEmptyData(CedulaData data) {
    return data.documentNumber.isEmpty &&
        data.firstName.isEmpty &&
        data.firstLastName.isEmpty &&
        data.birthDate.isEmpty;
  }

  /// Parsea texto OCR del frente de la cédula colombiana.
  static CedulaData parseOcrFront(String text) {
    final data = CedulaData();
    data.fieldSource = {};

    if (text.isEmpty) return data;

    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // Buscar número de cédula: secuencia numérica larga (8-12 dígitos)
    for (final line in lines) {
      final numMatch = RegExp(r'(\d{8,12})').firstMatch(line);
      if (numMatch != null) {
        data.documentNumber = numMatch.group(1)!;
        data.fieldSource['documentNumber'] = 'ocr';
        break;
      }
    }

    // Buscar fecha de nacimiento
    for (final line in lines) {
      final dateMatch = RegExp(r'(\d{2}[./-]\d{2}[./-]\d{4})').firstMatch(line);
      if (dateMatch != null) {
        data.birthDate = dateMatch.group(1)!.replaceAll('.', '/').replaceAll('-', '/');
        data.fieldSource['birthDate'] = 'ocr';
        break;
      }
    }

    // Buscar nombres: líneas con texto mayúscula sin números
    final textLines = <String>[];
    for (final line in lines) {
      // Filtrar líneas que parecen nombres (mayúsculas, sin números mayormente)
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

    // La primera línea suele ser apellidos, la segunda nombres
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
  }

  Future<void> initializeController({int cameraIndex = 0}) async {
    if (_cameras.isEmpty) await discoverCameras();
    if (_cameras.isEmpty) throw Exception('No se encontró ninguna cámara en el dispositivo.');

    final camera = _cameras[cameraIndex < _cameras.length ? cameraIndex : 0];
    _controller = CameraController(
      camera,
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await _controller!.initialize();
  }

  Future<String> takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      throw Exception('La cámara no está inicializada.');
    }
    final XFile file = await _controller!.takePicture();
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
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            // Logo/Ícono
            const Icon(
              Icons.badge,
              size: 80,
              color: Colors.black,
            ),
            const SizedBox(height: 16),
            const Text(
              'Escáner de Cédula',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Colombiana — PDF417 y OCR',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 40),
            // Estado del permiso
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
                          const Text(
                            'Permiso de cámara',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          Text(
                            _statusText(),
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            // Botón solicitar permiso
            if (!_isChecking && _cameraStatus != PermissionStatus.granted)
              ElevatedButton.icon(
                onPressed: _requestPermission,
                icon: const Icon(Icons.videocam),
                label: const Text('Solicitar permiso de cámara'),
              ),
            // Botón abrir configuración si denegado permanentemente
            if (!_isChecking && _cameraStatus == PermissionStatus.permanentlyDenied)
              OutlinedButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.settings),
                label: const Text('Abrir configuración del sistema'),
              ),
            const SizedBox(height: 24),
            // Botón abrir cámara
            if (!_isChecking && _cameraStatus == PermissionStatus.granted)
              ElevatedButton.icon(
                onPressed: _openCamera,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Abrir Cámara'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// FEAT-7: PANTALLA DE ESCANEO INTELIGENTE (modo automático)
// FEAT-2: PREVIEW DE CÁMARA
// FEAT-4: ESCANEO PDF417 EN TIEMPO REAL
// ============================================================================

class SmartScanPage extends StatefulWidget {
  const SmartScanPage({super.key});

  @override
  State<SmartScanPage> createState() => _SmartScanPageState();
}

class _SmartScanPageState extends State<SmartScanPage> {
  final MobileScannerController _scannerController = MobileScannerController(
    formats: [BarcodeFormat.pdf417],
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _barcodeDetected = false;
  bool _isProcessing = false;
  String _modeIndicator = 'Escaneando...';
  bool _autoModeTimedOut = false;
  CedulaData? _barcodeData;

  @override
  void initState() {
    super.initState();
    _startAutoModeTimeout();
  }

  void _startAutoModeTimeout() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && !_barcodeDetected && !_isProcessing) {
        setState(() => _autoModeTimedOut = true);
      }
    });
  }

  void _onBarcodeDetect(BarcodeCapture capture) {
    if (_barcodeDetected || _isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final Barcode barcode = barcodes.first;
    final String? rawValue = barcode.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    setState(() {
      _barcodeDetected = true;
      _isProcessing = true;
      _modeIndicator = 'Leyendo código de barras...';
    });

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
          barcodeRaw: '',
        ),
      ),
    );
  }

  void _openCameraForPhoto() async {
    if (!mounted) return;

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

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Scanner preview
          MobileScanner(
            controller: _scannerController,
            onDetect: _onBarcodeDetect,
          ),

          // Overlay con guía rectangular
          _buildScannerOverlay(),

          // Indicador de modo
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.black54,
              child: Text(
                _modeIndicator,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          // Botón cancelar
          Positioned(
            top: MediaQuery.of(context).padding.top + 56,
            left: 16,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                backgroundColor: Colors.black54,
                shape: const CircleBorder(),
              ),
              child: const Icon(Icons.close, color: Colors.white),
            ),
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
                            // El scanner ya está activo para PDF417
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
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Código PDF417 detectado',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ],
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
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(
        Colors.transparent,
        BlendMode.srcOver,
      ),
      child: Stack(
        children: [
          // Sombra superior
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.2,
              color: Colors.black54,
            ),
          ),
          // Sombra inferior
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.25,
              color: Colors.black54,
            ),
          ),
          // Sombra izquierda
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.1,
              height: MediaQuery.of(context).size.height * 0.55,
              color: Colors.black54,
            ),
          ),
          // Sombra derecha
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.1,
              height: MediaQuery.of(context).size.height * 0.55,
              color: Colors.black54,
            ),
          ),
          // Marco guía
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.8,
              height: MediaQuery.of(context).size.height * 0.55,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.badge,
                    color: Colors.white54,
                    size: 48,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _barcodeDetected ? 'Código detectado' : 'Centra la cédula aquí',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
          // Camera preview
          if (_isInitializing)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          else if (_errorMessage != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Volver'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // Preview
            CameraPreview(_cameraService.controller!),

            // Overlay guía
            _buildCameraOverlay(),

            // Controles
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Botón cancelar
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.black54,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                  // Botón tomar foto
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
                  // Espacio vacío para balancear
                  const SizedBox(width: 80),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCameraOverlay() {
    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        height: MediaQuery.of(context).size.height * 0.5,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.badge, color: Colors.white54, size: 48),
            SizedBox(height: 8),
            Text(
              'Centra la cédula aquí',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// FEAT-3: PANTALLA DE REVISIÓN DE FOTO
// FEAT-4 & FEAT-5: PROCESAMIENTO DE BARCODE Y OCR
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisar Foto'),
        centerTitle: true,
      ),
      body: Stack(
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
                    Text(
                      'Procesando imagen...',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
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
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),

          // Botones
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 24,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _scanImage,
                  icon: const Icon(Icons.search),
                  label: const Text('Escanear esta foto'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isProcessing
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Volver a tomar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _scanImage() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      CedulaData barcodeData = CedulaData();
      CedulaData ocrData = CedulaData();
      String barcodeRaw = '';

      // Intentar escaneo de código de barras desde la imagen
      try {
        final controller = MobileScannerController(
          formats: [BarcodeFormat.pdf417],
          detectionSpeed: DetectionSpeed.normal,
        );

        final capture = await controller.analyzeImage(widget.imagePath);
        controller.dispose();

        if (capture != null && capture.barcodes.isNotEmpty) {
          final rawValue = capture.barcodes.first.rawValue;
          if (rawValue != null && rawValue.isNotEmpty) {
            barcodeRaw = rawValue;
            barcodeData = IdScanParser.parsePdf417(rawValue);
          }
        }
      } catch (e) {
        // Barcode scan failed, continue with OCR only
        debugPrint('Barcode scan from image failed: $e');
      }

      // OCR de la imagen
      try {
        final inputImage = InputImage.fromFilePath(widget.imagePath);
        final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
        final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
        textRecognizer.close();

        ocrData = IdScanParser.parseOcrFront(recognizedText.text);
      } catch (e) {
        debugPrint('OCR failed: $e');
      }

      // Combinar datos: barcode tiene prioridad, OCR complementa
      final mergedData = CedulaData();
      mergedData.mergeFrom(barcodeData);
      mergedData.mergeFrom(ocrData);

      // Verificar si obtuvimos algún dato
      if (mergedData.documentNumber.isEmpty &&
          mergedData.firstName.isEmpty &&
          mergedData.firstLastName.isEmpty) {
        setState(() {
          _isProcessing = false;
          _errorMessage =
              'No se detectó código de barras ni texto legible. Intenta con mejor iluminación o acerca más la cámara.';
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
            // Header
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
                    // Ícono de fuente
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
                    // Etiqueta
                    Expanded(
                      flex: 2,
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    // Valor
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

            const SizedBox(height: 24),

            // Botón copiar todo
            ElevatedButton.icon(
              onPressed: () => _copyAll(context),
              icon: const Icon(Icons.copy),
              label: const Text('Copiar todo'),
            ),
            const SizedBox(height: 12),

            // Botón escanear otra cédula
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

            // Botón nueva foto
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
      const SnackBar(
        content: Text('Datos copiados al portapapeles'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
