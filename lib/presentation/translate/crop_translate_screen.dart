import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path/path.dart' as p;

import '../../application/translate_items.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/expense_package.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/entities/translation_line.dart';
import '../../domain/reference/countries.dart';
import '../common/widgets.dart';
import '../providers.dart';

/// Crop the purchased-items area, then review the English translation.
class CropTranslateScreen extends ConsumerStatefulWidget {
  const CropTranslateScreen({required this.receiptId, super.key});

  final String receiptId;

  @override
  ConsumerState<CropTranslateScreen> createState() =>
      _CropTranslateScreenState();
}

class _EditableLine {
  _EditableLine({
    required String original,
    required String translated,
    required this.engine,
    required this.category,
    this.quantity,
    this.amountText,
  })  : original = TextEditingController(text: original),
        translated = TextEditingController(text: translated),
        _initialOriginal = original,
        _initialTranslated = translated;

  factory _EditableLine.from(TranslationLine line) => _EditableLine(
        original: line.originalText,
        translated: line.translatedText,
        engine: line.engine,
        category: line.category,
        quantity: line.quantity,
        amountText: line.amountText,
      );

  final TextEditingController original;
  final TextEditingController translated;

  /// Kept with the line but not shown: the receipt image has the prices.
  final String? quantity;
  final String? amountText;
  final TranslationEngine engine;
  ItemCategory category;
  final String _initialOriginal;
  final String _initialTranslated;

  bool get isBlank =>
      original.text.trim().isEmpty && translated.text.trim().isEmpty;

  TranslationLine toLine(int lineNo, String language) {
    final edited = original.text.trim() != _initialOriginal.trim() ||
        translated.text.trim() != _initialTranslated.trim();
    return TranslationLine(
      lineNo: lineNo,
      quantity: quantity,
      originalText: original.text.trim(),
      translatedText: translated.text.trim(),
      amountText: amountText,
      sourceLanguage: language,
      category: category,
      // A user correction is "manual", and is learned into the glossary.
      engine: edited ? TranslationEngine.manual : engine,
    );
  }

  void dispose() {
    original.dispose();
    translated.dispose();
  }
}

class _CropTranslateScreenState extends ConsumerState<CropTranslateScreen> {
  Receipt? _receipt;
  List<_EditableLine> _lines = [];
  String _language = 'es';
  String? _warning;
  bool _loading = true;
  bool _hasDraft = false;
  int _cropVersion = 0;

  /// Items (meals) or the whole receipt's text (everything else).
  TranslationMode _mode = TranslationMode.items;

  bool get _wholeText => _mode == TranslationMode.receiptText;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    // Read providers before the first await: ref is unusable once disposed.
    final receiptRepo = ref.read(receiptRepositoryProvider);
    final translationRepo = ref.read(translationRepositoryProvider);
    final storage = ref.read(fileStorageProvider);
    final receipt = await receiptRepo.getById(widget.receiptId);
    final existing = await translationRepo.linesFor(widget.receiptId);
    if (receipt != null) {
      // A crop left over from an abandoned edit is discarded.
      await storage.deleteFileIfExists(p.join(
        p.dirname(receipt.originalImagePath),
        PackageFiles.itemsCropDraft,
      ));
    }
    if (!mounted) return;
    setState(() {
      _receipt = receipt;
      _loading = false;
      if (receipt == null) return;
      _language = (existing.isNotEmpty ? existing.first.sourceLanguage : null) ??
          receipt.detectedLanguage ??
          Countries.languageFor(receipt.country) ??
          'es';
      _mode = existing.isNotEmpty
          ? (existing.every((l) => l.category == ItemCategory.general)
              ? TranslationMode.receiptText
              : TranslationMode.items)
          : TranslateItemsUseCase.modeFor(receipt) ?? TranslationMode.items;
      if (existing.isNotEmpty) {
        _lines = existing.map(_EditableLine.from).toList();
        _hasDraft = true;
      }
    });
    if (receipt != null && existing.isEmpty) {
      // First visit: find the items without the user drawing anything.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoDetect();
      });
    }
  }

  /// The crop being edited: the unsaved draft if there is one.
  String? get _cropPath {
    final receipt = _receipt;
    if (receipt == null) return null;
    final storage = ref.read(fileStorageProvider);
    final dir = p.dirname(receipt.originalImagePath);
    final draft = storage.absolute(p.join(dir, PackageFiles.itemsCropDraft));
    if (File(draft).existsSync()) return draft;
    return storage.absolute(p.join(dir, PackageFiles.itemsCrop));
  }

  Future<void> _crop() async {
    final receipt = _receipt;
    if (receipt == null) return;
    final storage = ref.read(fileStorageProvider);
    final cropped = await ImageCropper().cropImage(
      sourcePath: storage.absolute(receipt.originalImagePath),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 92,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: _wholeText
              ? 'Select the receipt text'
              : 'Select the purchased items',
          lockAspectRatio: false,
          initAspectRatio: CropAspectRatioPreset.original,
          aspectRatioPresets: [CropAspectRatioPreset.original],
        ),
        IOSUiSettings(
          title: _wholeText
              ? 'Select the receipt text'
              : 'Select the purchased items',
          aspectRatioLockEnabled: false,
        ),
      ],
    );
    if (cropped == null || !mounted) return;

    final draft = await runWithProgress<TranslationDraft>(
      context,
      message: 'Reading the text…',
      task: (update) => ref.read(translateItemsProvider).prepare(
            receipt: receipt,
            croppedImagePath: cropped.path,
            onProgress: update,
            mode: _mode,
          ),
    );
    if (draft == null || !mounted) return;
    await _applyDraft(draft);
  }

  /// Finds the item lines on the photo and crops to them automatically.
  Future<void> _autoDetect() async {
    final receipt = _receipt;
    if (receipt == null) return;
    final useCase = ref.read(translateItemsProvider);
    final draft = await runWithProgress<TranslationDraft?>(
      context,
      message: _wholeText ? 'Reading the receipt…' : 'Finding the items…',
      task: (update) =>
          useCase.prepareAutomatically(receipt: receipt, onProgress: update),
    );
    if (!mounted) return;
    if (draft == null) {
      showMessage(
        context,
        _wholeText
            ? 'Could not read the receipt automatically. Select the area by hand.'
            : 'Could not find the items automatically. Select the item area '
                'by hand.',
      );
      return;
    }
    await _applyDraft(draft);
  }

  Future<void> _applyDraft(TranslationDraft draft) async {
    final cropPath = _cropPath;
    if (cropPath != null) await FileImage(File(cropPath)).evict();
    if (!mounted) return;
    final previous = _lines;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final l in previous) {
        l.dispose();
      }
    });
    setState(() {
      _lines = draft.lines.map(_EditableLine.from).toList();
      _language = draft.sourceLanguage;
      _mode = draft.mode;
      _warning = draft.warning;
      _hasDraft = true;
      _cropVersion++;
    });
  }

  Future<void> _markNotRequired() async {
    final receipt = _receipt;
    if (receipt == null) return;
    final revision = ref.read(dataRevisionProvider.notifier);
    final useCase = ref.read(translateItemsProvider);
    await runWithProgress<void>(
      context,
      message: 'Saving…',
      task: (_) => useCase.markNotRequired(receipt),
    );
    revision.bump();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    final receipt = _receipt;
    if (receipt == null) return;
    final kept = _lines.where((l) => !l.isBlank).toList();
    if (kept.any((l) => l.translated.text.trim().isEmpty)) {
      showMessage(context, 'Every item needs an English name.');
      return;
    }
    final lines = [
      for (var i = 0; i < kept.length; i++) kept[i].toLine(i + 1, _language),
    ];
    final revision = ref.read(dataRevisionProvider.notifier);
    final useCase = ref.read(translateItemsProvider);
    final ok = await runWithProgress<bool>(
      context,
      message: 'Generating translated_items.pdf…',
      task: (_) async {
        await useCase.save(
          receipt: receipt,
          sourceLanguage: _language,
          lines: lines,
        );
        return true;
      },
    );
    revision.bump();
    if (ok != true || !mounted) return;
    showMessage(context, 'Translation saved.');
    Navigator.of(context).pop();
  }

  Future<void> _pickLanguage() async {
    final value = await showOptionPicker<String>(
      context,
      title: 'Receipt language',
      options: Languages.downloadable,
      labelOf: Languages.nameOf,
      selected: _language,
    );
    if (value != null) setState(() => _language = value);
  }

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (receipt == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Receipt not found.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_wholeText ? 'Translate receipt' : 'Translate items'),
      ),
      body: _hasDraft ? _editor(context) : _instructions(context, receipt),
      bottomNavigationBar: _hasDraft
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _crop,
                        icon: const Icon(Icons.crop),
                        label: const Text('Re-crop'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.check),
                        label: const Text('Save translation'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _instructions(BuildContext context, Receipt receipt) {
    final storage = ref.watch(fileStorageProvider);
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(storage.absolute(receipt.originalImagePath)),
            height: 280,
            fit: BoxFit.contain,
            cacheWidth: 1000,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _wholeText ? 'Translate the receipt' : 'Translate the purchased items',
          style: text.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          _wholeText
              ? 'This is not a meal, so the main text of the receipt is '
                  'translated: what it is for, the charges and how it was '
                  'paid. Reference numbers, web addresses and the QR code '
                  'are left out.'
              : 'This is a meal, so the app finds the food and drink lines '
                  'and groups them. The address, customer, tax, tip and card '
                  'details are left out.',
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: _autoDetect,
          icon: const Icon(Icons.auto_fix_high),
          label: Text(
            _wholeText ? 'Translate automatically' : 'Find items automatically',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _crop,
          icon: const Icon(Icons.crop),
          label: Text(
            _wholeText ? 'Select the area by hand' : 'Select item area by hand',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _markNotRequired,
          child: const Text('No translation needed'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Do it later'),
        ),
      ],
    );
  }

  Widget _editor(BuildContext context) {
    final cropPath = _cropPath;
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (cropPath != null && File(cropPath).existsSync())
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ImageViewerScreen(
                path: cropPath,
                title: _wholeText ? 'Cropped receipt' : 'Cropped items',
              ),
            )),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(cropPath),
                key: ValueKey(_cropVersion),
                height: 160,
                fit: BoxFit.contain,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.translate, size: 18),
            const SizedBox(width: 6),
            Text('${Languages.nameOf(_language)} to English',
                style: text.titleSmall),
            const Spacer(),
            TextButton(onPressed: _pickLanguage, child: const Text('Change')),
          ],
        ),
        if (_warning != null)
          Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_warning!),
            ),
          ),
        if (_wholeText)
          for (var i = 0; i < _lines.length; i++) _lineCard(i)
        else
          for (final category in ItemCategory.values)
            if (_lines.any((l) => l.category == category)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(category.label, style: text.titleMedium),
              ),
              for (var i = 0; i < _lines.length; i++)
                if (_lines[i].category == category) _lineCard(i),
            ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => setState(() => _lines.add(_EditableLine(
                original: '',
                translated: '',
                engine: TranslationEngine.manual,
                category: _wholeText ? ItemCategory.general : ItemCategory.food,
              ))),
          icon: const Icon(Icons.add),
          label: Text(_wholeText ? 'Add line' : 'Add item'),
        ),
      ],
    );
  }

  Widget _lineCard(int index) {
    final line = _lines[index];
    return Card(
      key: ObjectKey(line),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: line.original,
                    decoration: const InputDecoration(
                      labelText: 'On receipt',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove line',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    final removed = _lines[index];
                    setState(() => _lines.removeAt(index));
                    // Dispose after the frame, once its TextFields are gone.
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => removed.dispose());
                  },
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextField(
                controller: line.translated,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'English',
                  helperText: switch (line.engine) {
                    TranslationEngine.glossary => 'From your glossary',
                    TranslationEngine.onDevice => 'Machine translation: check it',
                    TranslationEngine.manual => null,
                  },
                ),
              ),
            ),
            if (!_wholeText)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<ItemCategory>(
                  showSelectedIcon: false,
                  segments: [
                    for (final c in const [ItemCategory.food, ItemCategory.drink])
                      ButtonSegment(value: c, label: Text(c.label)),
                  ],
                  selected: {line.category},
                  onSelectionChanged: (s) =>
                      setState(() => line.category = s.first),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
