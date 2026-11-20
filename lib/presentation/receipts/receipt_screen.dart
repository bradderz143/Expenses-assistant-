import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/enums.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/entities/trip.dart';
import '../../domain/logic/package_naming.dart';
import '../../domain/logic/receipt_notes.dart';
import '../../domain/reference/countries.dart';
import '../../domain/reference/currencies.dart';
import '../../domain/value_objects/money.dart';
import '../common/widgets.dart';
import '../providers.dart';
import '../translate/crop_translate_screen.dart';

/// Check and fix one receipt: date, amount, trip. Translation is optional and
/// only happens when asked for here.
class ReceiptScreen extends ConsumerStatefulWidget {
  const ReceiptScreen({
    required this.receiptId,
    this.readNote,
    super.key,
  });

  final String receiptId;

  /// Shown at the top straight after a scan that went badly.
  final String? readNote;

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  Receipt? _receipt;
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _merchant = TextEditingController();
  DateTime? _date;
  String _currency = 'USD';
  String? _tripId;

  /// What the scan was unsure of and has not been changed on this screen.
  List<ScanCheck> _toCheck = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final receipt =
        await ref.read(receiptRepositoryProvider).getById(widget.receiptId);
    if (!mounted) return;
    setState(() {
      _receipt = receipt;
      if (receipt == null) return;
      final amount = receipt.amount;
      _amount.text = amount?.amountText ?? '';
      _merchant.text = receipt.merchant ?? '';
      _date = receipt.transactionDate;
      _currency = receipt.currency;
      _tripId = receipt.tripId;
      _toCheck = receipt.toCheck;
    });
  }

  /// The user has dealt with the date (or the amount) themselves.
  void _settle(bool Function(ScanCheck) which) =>
      _toCheck = [for (final c in _toCheck) if (!which(c)) c];

  int? get _amountMinor => Money.parseMinor(
        _amount.text,
        exponent: Currencies.exponentOf(_currency),
      );

  bool get _amountInvalid =>
      _amount.text.trim().isNotEmpty && _amountMinor == null;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    // The same range the scan accepts, so a flagged old date can be fixed.
    final first = DateTime(2010);
    final last = DateTime(now.year + 1, 12, 31);
    var initial = _date ?? now;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) {
      setState(() {
        _date = DateTime(picked.year, picked.month, picked.day);
        _settle((c) => c.isDate);
      });
    }
  }

  Future<void> _pickCurrency() async {
    final country = _receipt?.country ?? Countries.defaultCountry;
    final value = await showOptionPicker<String>(
      context,
      title: 'Currency',
      options: [
        ...Currencies.common,
        if (!Currencies.common.contains(_currency)) _currency,
      ],
      labelOf: (c) => c,
      recent: [Countries.currencyFor(country), 'USD'],
      selected: _currency,
      allowCustom: true,
      fromCustom: (text) => text.toUpperCase(),
    );
    if (value != null && Currencies.isValidCode(value)) {
      setState(() => _currency = value);
    }
  }

  Future<void> _pickTrip(List<Trip> trips) async {
    final byId = {for (final t in trips) t.id: t};
    const none = '';
    final value = await showOptionPicker<String>(
      context,
      title: 'Trip',
      options: [none, ...byId.keys],
      labelOf: (id) => id == none ? 'No trip' : byId[id]!.name,
      selected: _tripId ?? none,
    );
    if (value == null) return;
    setState(() => _tripId = value == none ? null : value);
  }

  /// Saves the edits. Returns the saved receipt, or null if it could not be
  /// saved (the reason is already shown). [confirmed]: the user pressed Save
  /// with the scan's doubts in front of them, so those are settled.
  Future<Receipt?> _save({bool confirmed = false}) async {
    final original = _receipt;
    if (original == null) return null;
    if (_amountInvalid) {
      showMessage(context, 'The amount is not a number.');
      return null;
    }
    final trips = ref.read(tripsProvider).orElse(const <Trip>[]);
    String country = original.country;
    if (_tripId != null && _tripId != original.tripId) {
      for (final t in trips) {
        if (t.id == _tripId) country = t.country;
      }
    }
    final merchant = _merchant.text.trim();
    final edited = original.copyWith(
      merchant: merchant.isEmpty ? null : merchant,
      transactionDate: _date,
      amountMinor: _amountMinor,
      currency: _currency,
      country: country,
      tripId: _tripId,
      toCheck: confirmed ? const [] : _toCheck,
    );
    final commands = ref.read(receiptCommandsProvider);
    final saved = await runWithProgress<Receipt>(
      context,
      message: 'Saving…',
      task: (_) => commands.saveDetails(edited),
    );
    if (!mounted) return null;
    ref.read(dataRevisionProvider.notifier).bump();
    if (saved != null) {
      setState(() {
        _receipt = saved;
        _toCheck = saved.toCheck;
      });
    }
    return saved;
  }

  Future<void> _saveAndClose() async {
    final navigator = Navigator.of(context);
    final saved = await _save(confirmed: true);
    if (saved != null) navigator.pop();
  }

  Future<void> _translate() async {
    final saved = await _save();
    if (saved == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CropTranslateScreen(receiptId: saved.id),
    ));
    if (!mounted) return;
    ref.read(dataRevisionProvider.notifier).bump();
    await _load();
  }

  /// Useful things printed on the receipt (invoice deadline, tip, offers,
  /// Wi-Fi). For the user only: not part of the export.
  List<Widget> _goodToKnow(BuildContext context) {
    final text = _receipt?.rawOcrText ?? '';
    if (text.trim().isEmpty) return const [];
    final notes = ReceiptNotes.find(text.split('\n'));
    if (notes.isEmpty) return const [];
    final theme = Theme.of(context);
    return [
      const SizedBox(height: 16),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text('Good to know', style: theme.textTheme.titleSmall),
              ),
              for (final note in notes)
                ListTile(
                  leading: Icon(_noteIcon(note.kind)),
                  title: Text(note.title),
                  subtitle: note.detail == null ? null : Text(note.detail!),
                  onTap: () => _showNote(note),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  'Read from the receipt, for you only. Not in the export.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  static IconData _noteIcon(ReceiptNoteKind kind) => switch (kind) {
        ReceiptNoteKind.invoice => Icons.receipt_long_outlined,
        ReceiptNoteKind.tip => Icons.payments_outlined,
        ReceiptNoteKind.offer => Icons.local_offer_outlined,
        ReceiptNoteKind.wifi => Icons.wifi,
        ReceiptNoteKind.toilet => Icons.wc,
        ReceiptNoteKind.returns => Icons.assignment_return_outlined,
      };

  /// The note with the wording it came from, and a way to copy it.
  Future<void> _showNote(ReceiptNote note) async {
    final copyable = [
      for (final line in (note.detail ?? '').split('\n'))
        if (line.contains(': ')) line.substring(line.indexOf(': ') + 2),
    ];
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(note.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (note.detail != null) SelectableText(note.detail!),
              if (note.printed != null) ...[
                const SizedBox(height: 12),
                Text('On the receipt',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                SelectableText(
                  note.printed!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (copyable.isNotEmpty)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: copyable.join('\n')));
                Navigator.pop(context);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Copied')),
                );
              },
              child: const Text('Copy'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// The raw text the scan read, for checking why a field came out wrong.
  Future<void> _showScannedText() async {
    final text = _receipt?.rawOcrText.trim() ?? '';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scanned text'),
        content: SingleChildScrollView(
          child: SelectableText(
            text.isEmpty ? 'The scan found no text.' : text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete() async {
    final receipt = _receipt;
    if (receipt == null) return;
    final ok = await confirm(
      context,
      title: 'Delete receipt?',
      message: 'This removes the photo and any translation from this phone. '
          'Exported ZIPs are not affected.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final navigator = Navigator.of(context);
    final commands = ref.read(receiptCommandsProvider);
    final revision = ref.read(dataRevisionProvider.notifier);
    await commands.delete(receipt);
    revision.bump();
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;
    if (receipt == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Receipt')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final storage = ref.watch(fileStorageProvider);
    final trips = ref.watch(tripsProvider).orElse(const <Trip>[]);
    String? tripName;
    for (final t in trips) {
      if (t.id == _tripId) tripName = t.name;
    }
    final imagePath = storage.absolute(receipt.originalImagePath);
    final translated = receipt.translationStatus == TranslationStatus.complete;
    final scheme = Theme.of(context).colorScheme;
    final fileBase = PackageNaming.receiptFileBase(
      date: _date,
      amountMinor: _amountMinor,
      currency: _currency,
    );
    final String? dateWarning;
    if (_date == null) {
      dateWarning = 'Please pick the date';
    } else if (_toCheck.contains(ScanCheck.dateNotRead)) {
      dateWarning = 'Not read from the receipt. This is the day you scanned '
          'it, so please check';
    } else if (_toCheck.contains(ScanCheck.dateUnsure)) {
      dateWarning = 'Hard to read. Please check';
    } else {
      dateWarning = null;
    }
    final String? amountWarning;
    if (_amountInvalid) {
      amountWarning = 'Not a number';
    } else if (!_toCheck.any((c) => c.isAmount)) {
      amountWarning = null;
    } else if (_amount.text.trim().isEmpty) {
      amountWarning = 'Not read. Please enter it';
    } else {
      amountWarning = 'Hard to read. Please check';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt'),
        actions: [
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.readNote != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(widget.readNote!,
                  style: TextStyle(color: scheme.error)),
            ),
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) =>
                  ImageViewerScreen(path: imagePath, title: 'Receipt'),
            )),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 220,
                child: Image.file(
                  File(imagePath),
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  width: double.infinity,
                  cacheWidth: 900,
                  errorBuilder: (_, _, _) => Container(
                    color: scheme.surfaceContainerHigh,
                    child: const Center(child: Icon(Icons.receipt_long)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          PickerField(
            label: 'Date',
            value: _date == null ? null : displayDate(_date),
            icon: Icons.event,
            warning: dateWarning,
            onTap: _pickDate,
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  onChanged: (_) => setState(() => _settle((c) => c.isAmount)),
                  decoration: InputDecoration(
                    labelText: 'Amount paid (including tip)',
                    prefixIcon: const Icon(Icons.payments_outlined),
                    errorText: amountWarning,
                    errorMaxLines: 3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: PickerField(
                  label: 'Currency',
                  value: _currency,
                  onTap: _pickCurrency,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          PickerField(
            label: 'Trip',
            value: tripName ?? 'No trip',
            icon: Icons.luggage_outlined,
            onTap: () => _pickTrip(trips),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _merchant,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Merchant (optional, for your reference)',
              prefixIcon: Icon(Icons.storefront_outlined),
            ),
          ),
          ..._goodToKnow(context),
          const SizedBox(height: 16),
          Text(
            'Saved in the export as\n$fileBase.jpg'
            '${translated ? '\n${fileBase}_translated.pdf' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _showScannedText,
              icon: const Icon(Icons.text_snippet_outlined),
              label: const Text('Show scanned text'),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _translate,
            icon: const Icon(Icons.translate),
            label: Text(translated ? 'Edit translation' : 'Translate to English'),
          ),
          if (!translated)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Optional. Only receipts you translate get a translated sheet.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(onPressed: _saveAndClose, child: const Text('Save')),
        ),
      ),
    );
  }
}
