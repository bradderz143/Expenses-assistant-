import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../application/export_service.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/entities/receipt_query.dart';
import '../../domain/entities/trip.dart';
import '../common/share.dart';
import '../common/widgets.dart';
import '../providers.dart';

/// Tab 3: build a ZIP for a trip and send it to Files, OneDrive or email.
class ExportScreen extends ConsumerWidget {
  const ExportScreen({super.key});

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    ExportScope scope,
  ) async {
    final exporter = ref.read(exportServiceProvider);
    final revision = ref.read(dataRevisionProvider.notifier);
    final result = await runWithProgress<ExportResult>(
      context,
      message: 'Building ZIP…',
      task: (_) => exporter.export(scope),
    );
    revision.bump();
    if (result == null || !context.mounted) return;
    final translated = result.translatedCount;
    final missing = result.missingAmountCount;
    final unchecked = result.toCheckCount;
    showMessage(
      context,
      '${result.receiptCount} receipts'
      '${translated == 0 ? '' : ', $translated translated'}'
      '${missing == 0 ? '' : '. $missing without an amount (named NoAmount)'}'
      '${unchecked == 0 ? '' : '. $unchecked with a date or amount still to check'}.',
    );
    await sendExport(
      context,
      result.file,
      subject: p.basenameWithoutExtension(result.file.path),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(tripsProvider).orElse(const <Trip>[]);
    final summaries = ref.watch(tripSummariesProvider).orElse(const <String, TripSummary>{});
    final all = ref.watch(receiptSearchProvider(
      const ReceiptQuery(archive: ArchiveScope.any, limit: 100000),
    ));
    final unassigned = all
        .orElse(const <Receipt>[])
        .where((r) => r.tripId == null)
        .length;
    final exports = ref.watch(exportFilesProvider).orElse(const <File>[]);
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'One ZIP per trip: the original receipt photos, plus a translated '
            'sheet for the ones you translated.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (trips.isEmpty && unassigned == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text('Scan some receipts first.', textAlign: TextAlign.center),
            ),
          for (final trip in trips)
            _ExportCard(
              title: trip.name,
              subtitle:
                  '${summaries[trip.id]?.receiptCount ?? 0} receipts',
              enabled: (summaries[trip.id]?.receiptCount ?? 0) > 0,
              onExport: () => _run(context, ref, TripScope(trip.id)),
            ),
          if (unassigned > 0)
            _ExportCard(
              title: 'Receipts not in a trip',
              subtitle: '$unassigned receipts',
              enabled: true,
              onExport: () => _run(context, ref, const UnassignedScope()),
            ),
          if (exports.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Earlier exports', style: labelStyle),
            for (final file in exports)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_zip_outlined),
                title: Text(p.basename(file.path)),
                trailing: const Icon(Icons.ios_share),
                onTap: () => sendExport(
                  context,
                  file,
                  subject: p.basenameWithoutExtension(file.path),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onExport,
  });

  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.luggage_outlined),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: FilledButton(
          onPressed: enabled ? onExport : null,
          child: const Text('Export'),
        ),
      ),
    );
  }
}
