import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../../domain/services/services.dart';

/// On-device OCR (Latin script). No image leaves the phone.
class MlKitOcrService implements OcrService {
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  @override
  Future<OcrResult> recognise(String imagePath) async {
    final result =
        await _recognizer.processImage(InputImage.fromFilePath(imagePath));
    final lines = <OcrLine>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final box = line.boundingBox;
        lines.add(OcrLine(
          text: line.text,
          left: box.left,
          top: box.top,
          right: box.right,
          bottom: box.bottom,
        ));
      }
    }
    return OcrResult(text: result.text, lines: lines);
  }

  @override
  Future<void> dispose() => _recognizer.close();
}

/// On-device language identification and translation. Models (~30 MB per
/// language) are downloaded once, then translation works offline.
class MlKitTranslationService implements TranslationService {
  final OnDeviceTranslatorModelManager _models =
      OnDeviceTranslatorModelManager();
  final LanguageIdentifier _identifier =
      LanguageIdentifier(confidenceThreshold: 0.5);
  final Map<String, OnDeviceTranslator> _translators = {};

  TranslateLanguage? _language(String code) {
    for (final language in TranslateLanguage.values) {
      if (language.bcpCode == code) return language;
    }
    return null;
  }

  @override
  bool supports(String languageCode) => _language(languageCode) != null;

  @override
  Future<String?> identifyLanguage(String text) async {
    if (text.trim().length < 4) return null;
    final code = await _identifier.identifyLanguage(text);
    return code == _identifier.undeterminedLanguageCode ? null : code;
  }

  @override
  Future<bool> isModelDownloaded(String languageCode) =>
      _models.isModelDownloaded(languageCode);

  @override
  Future<bool> downloadModel(String languageCode, {bool wifiOnly = false}) =>
      _models.downloadModel(languageCode, isWifiRequired: wifiOnly);

  @override
  Future<bool> deleteModel(String languageCode) async {
    final removed = await _models.deleteModel(languageCode);
    final stale = _translators.keys
        .where((key) => key.startsWith('$languageCode>') ||
            key.endsWith('>$languageCode'))
        .toList();
    for (final key in stale) {
      await _translators.remove(key)?.close();
    }
    return removed;
  }

  @override
  Future<List<String>> translateAll(
    List<String> texts, {
    required String from,
    String to = 'en',
  }) async {
    final source = _language(from);
    final target = _language(to);
    if (source == null || target == null) {
      throw UnsupportedError('No on-device model for $from -> $to');
    }
    final translator = _translators.putIfAbsent(
      '$from>$to',
      () => OnDeviceTranslator(sourceLanguage: source, targetLanguage: target),
    );
    final results = <String>[];
    for (final text in texts) {
      results.add(text.trim().isEmpty ? '' : await translator.translateText(text));
    }
    return results;
  }

  @override
  Future<void> dispose() async {
    for (final translator in _translators.values) {
      await translator.close();
    }
    _translators.clear();
    await _identifier.close();
  }
}
