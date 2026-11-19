import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/export_service.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/logic/formatting.dart';
import '../theme/app_theme.dart';

/// The data if there is any (also while reloading), otherwise [fallback].
extension AsyncValueOr<T> on AsyncValue<T> {
  T orElse(T fallback) => when(
        skipLoadingOnReload: true,
        data: (value) => value,
        loading: () => fallback,
        error: (_, _) => fallback,
      );
}

// ---------------------------------------------------------------- formatting

String displayDate(DateTime? date) =>
    date == null ? 'No date' : Formatting.displayDate(date);

String displayAmount(Receipt r) {
  final amount = r.amount;
  return amount == null
      ? 'No amount'
      : '${groupedFigures(amount.amountText)} ${amount.currency}';
}

/// "Check date and amount" for a receipt the scan was unsure of and the
/// user has not yet confirmed; null when there is nothing to check.
String? checkLabel(Receipt r) {
  if (r.checkDate && r.checkAmount) return 'Check date and amount';
  if (r.checkDate) return 'Check date';
  if (r.checkAmount) return 'Check amount';
  return null;
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String friendlyError(Object error) {
  if (error is ExportException) return error.message;
  if (error is FileSystemException) return 'Storage error: ${error.message}';
  return 'Something went wrong: $error';
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

// ------------------------------------------------------------------ progress

/// Runs [task] behind a blocking progress dialog. [task] can update the
/// message (e.g. "Downloading Spanish model…"). Errors become a snackbar and
/// a null result.
Future<T?> runWithProgress<T>(
  BuildContext context, {
  required String message,
  required Future<T> Function(void Function(String) update) task,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);
  final status = ValueNotifier<String>(message);
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: status,
                builder: (_, value, _) => Text(value),
              ),
            ),
          ],
        ),
      ),
    ),
  ));
  try {
    return await task((value) => status.value = value);
  } catch (error, stack) {
    debugPrint('runWithProgress failed: $error\n$stack');
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(error))));
    return null;
  } finally {
    navigator.pop();
    status.dispose();
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

// -------------------------------------------------------------------- status

/// Short, list-friendly names for each step of the workflow.
String statusName(ReceiptStatus status) => switch (status) {
      ReceiptStatus.needsClassification => 'Needs details',
      ReceiptStatus.needsTranslation => 'Needs translation',
      ReceiptStatus.ready => 'Ready to submit',
      ReceiptStatus.submitted => 'Submitted',
    };

/// "76337.31" -> "76,337.31": figures people can read at a glance.
String groupedFigures(String amountText) {
  final negative = amountText.startsWith('-');
  final plain = negative ? amountText.substring(1) : amountText;
  final dot = plain.indexOf('.');
  final whole = dot < 0 ? plain : plain.substring(0, dot);
  final fraction = dot < 0 ? '' : plain.substring(dot);
  final out = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) out.write(',');
    out.write(whole[i]);
  }
  return '${negative ? '-' : ''}$out$fraction';
}

/// A coloured dot and the step name. Colour alone never carries meaning.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final ReceiptStatus status;

  @override
  Widget build(BuildContext context) {
    final color = StatusColors.read(context).of(status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          statusName(status),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- receipt tile

class ReceiptThumbnail extends StatelessWidget {
  const ReceiptThumbnail({required this.path, this.size = 56, super.key});

  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          cacheWidth: (size * 3).round(),
          errorBuilder: (_, _, _) => Container(
            width: size,
            height: size,
            color: scheme.surfaceContainerHigh,
            child: Icon(Icons.receipt_long, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// One receipt in a list: what, when, how much, and what it still needs.
class ReceiptTile extends StatelessWidget {
  const ReceiptTile({
    required this.receipt,
    required this.imagePath,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
    this.tripName,
    super.key,
  });

  final Receipt receipt;
  final String imagePath;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final String? tripName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final amount = receipt.amount;
    final detail = [
      displayDate(receipt.transactionDate),
      if (tripName != null) tripName!,
    ].join(', ');

    return Material(
      color: selected ? scheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              if (selected)
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CircleAvatar(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    child: const Icon(Icons.check),
                  ),
                )
              else
                ReceiptThumbnail(path: imagePath),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      receipt.merchant ?? 'Merchant not read',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                    if (checkLabel(receipt) case final String check) ...[
                      const SizedBox(height: 6),
                      // One line of text with the icon inside it, so it
                      // shortens with an ellipsis instead of overflowing.
                      Text.rich(
                        TextSpan(children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Icon(Icons.error_outline,
                                size: 14, color: scheme.error),
                          ),
                          TextSpan(text: ' $check'),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelSmall?.copyWith(color: scheme.error),
                      ),
                    ],
                    if (receipt.translationStatus == TranslationStatus.complete) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.translate,
                              size: 14, color: scheme.primary),
                          const SizedBox(width: 4),
                          Text('Translated',
                              style: text.labelSmall
                                  ?.copyWith(color: scheme.primary)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amount == null ? 'No amount' : groupedFigures(amount.amountText),
                    style: amount == null
                        ? text.bodySmall
                        : AppTheme.amount(context),
                  ),
                  if (amount != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      amount.currency,
                      style: text.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- option picker

/// Searchable bottom-sheet picker with a "Recent" section. Used for category,
/// currency, country and trip, where dropdowns of 30+ items are slow to use.
Future<T?> showOptionPicker<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required String Function(T) labelOf,
  List<T> recent = const [],
  T? selected,
  bool allowCustom = false,
  T Function(String text)? fromCustom,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _OptionPickerSheet<T>(
      title: title,
      options: options,
      labelOf: labelOf,
      recent: recent,
      selected: selected,
      allowCustom: allowCustom,
      fromCustom: fromCustom,
    ),
  );
}

class _OptionPickerSheet<T> extends StatefulWidget {
  const _OptionPickerSheet({
    required this.title,
    required this.options,
    required this.labelOf,
    required this.recent,
    required this.selected,
    required this.allowCustom,
    required this.fromCustom,
    super.key,
  });

  final String title;
  final List<T> options;
  final String Function(T) labelOf;
  final List<T> recent;
  final T? selected;
  final bool allowCustom;
  final T Function(String text)? fromCustom;

  @override
  State<_OptionPickerSheet<T>> createState() => _OptionPickerSheetState<T>();
}

class _OptionPickerSheetState<T> extends State<_OptionPickerSheet<T>> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final query = _filter.trim().toLowerCase();
    bool matches(T option) =>
        query.isEmpty || widget.labelOf(option).toLowerCase().contains(query);
    final recent =
        query.isEmpty ? widget.recent.where(widget.options.contains).toList() : <T>[];
    final all = widget.options.where(matches).toList();
    final custom = widget.allowCustom &&
        widget.fromCustom != null &&
        query.isNotEmpty &&
        !widget.options.any((o) => widget.labelOf(o).toLowerCase() == query);

    Widget tile(T option) => ListTile(
          title: Text(widget.labelOf(option)),
          trailing: option == widget.selected ? const Icon(Icons.check) : null,
          onTap: () => Navigator.pop(context, option),
        );

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(widget.title,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: false,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search',
                ),
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  if (custom)
                    ListTile(
                      leading: const Icon(Icons.add),
                      title: Text('Use "${_filter.trim()}"'),
                      onTap: () => Navigator.pop(
                          context, widget.fromCustom!(_filter.trim())),
                    ),
                  if (recent.isNotEmpty) ...[
                    const _SectionLabel('Recent'),
                    ...recent.map(tile),
                    const Divider(),
                    const _SectionLabel('All'),
                  ],
                  ...all.map(tile),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

/// A form-style tile that opens a picker when tapped.
class PickerField extends StatelessWidget {
  const PickerField({
    required this.label,
    required this.value,
    required this.onTap,
    this.icon,
    this.warning,
    super.key,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;
  final IconData? icon;

  /// Shown under the field in the error colour, e.g. "Check against the
  /// receipt".
  final String? warning;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon == null ? null : Icon(icon),
          suffixIcon: const Icon(Icons.arrow_drop_down),
          errorText: warning,
          errorMaxLines: 3,
        ),
        isEmpty: value == null,
        child: value == null ? null : Text(value!),
      ),
    );
  }
}

/// Tappable recent values under a text field ("Recently used values").
class SuggestionChips extends StatelessWidget {
  const SuggestionChips({
    required this.suggestions,
    required this.onSelected,
    this.current = '',
    super.key,
  });

  final List<String> suggestions;
  final ValueChanged<String> onSelected;
  final String current;

  @override
  Widget build(BuildContext context) {
    final query = current.trim().toLowerCase();
    final visible = suggestions
        .where((s) =>
            s.toLowerCase() != query &&
            (query.isEmpty || s.toLowerCase().contains(query)))
        .take(6)
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 0,
        children: [
          for (final s in visible)
            ActionChip(
              label: Text(s, overflow: TextOverflow.ellipsis),
              visualDensity: VisualDensity.compact,
              onPressed: () => onSelected(s),
            ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- image viewer

class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({required this.path, required this.title, super.key});

  final String path;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: InteractiveViewer(
        maxScale: 6,
        child: Center(child: Image.file(File(path))),
      ),
    );
  }
}

/// Small helper so screens can show AsyncValue errors consistently.
class ErrorText extends StatelessWidget {
  const ErrorText(this.error, {super.key});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(friendlyError(error), textAlign: TextAlign.center),
      ),
    );
  }
}
