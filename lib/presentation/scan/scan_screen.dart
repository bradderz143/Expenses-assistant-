import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/entities/enums.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/entities/receipt_query.dart';
import '../../domain/entities/trip.dart';
import '../capture/capture_flow.dart';
import '../common/widgets.dart';
import '../providers.dart';
import '../receipts/receipt_screen.dart';
import '../trips/trips_screen.dart';

/// Tab 1: pick the trip, scan a receipt, see what has been scanned so far.
class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  /// The trip new receipts go into: the one chosen, otherwise a trip whose
  /// dates include today (the same rule the scan itself uses).
  static Trip? effectiveTrip(List<Trip> trips, String? activeId) {
    for (final t in trips) {
      if (t.id == activeId) return t;
    }
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    for (final t in trips) {
      if (t.contains(day)) return t;
    }
    return null;
  }

  Future<void> _chooseTrip(
    BuildContext context,
    WidgetRef ref,
    List<Trip> trips,
    Trip? current,
  ) async {
    final commands = ref.read(tripCommandsProvider);
    final revision = ref.read(dataRevisionProvider.notifier);
    const create = '+';
    final byId = {for (final t in trips) t.id: t};
    final value = await showOptionPicker<String>(
      context,
      title: 'Scan into trip',
      options: [...byId.keys, create],
      labelOf: (id) => id == create ? 'New trip…' : byId[id]!.name,
      selected: current?.id,
    );
    if (value == null || !context.mounted) return;
    if (value == create) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const TripEditScreen(),
      ));
      return;
    }
    await commands.setActive(byId[value]);
    revision.bump();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(tripsProvider).orElse(const <Trip>[]);
    final activeId = ref.watch(settingsProvider).when<String?>(skipLoadingOnReload: true, data: (s) => s.activeTripId, loading: () => null, error: (_, _) => null);
    final trip = effectiveTrip(trips, activeId);
    final storage = ref.watch(fileStorageProvider);
    final receipts = ref.watch(receiptSearchProvider(
      const ReceiptQuery(archive: ArchiveScope.any, limit: 1000),
    ));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Scan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.luggage_outlined),
              title: Text(trip?.name ?? 'No trip'),
              subtitle: const Text('New receipts go into this trip'),
              trailing: const Icon(Icons.arrow_drop_down),
              onTap: () => _chooseTrip(context, ref, trips, trip),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 64,
            child: FilledButton.icon(
              onPressed: () => CaptureFlow.start(context, ref),
              icon: const Icon(Icons.photo_camera_outlined, size: 28),
              label: const Text('Scan receipt', style: TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => CaptureFlow.start(
              context,
              ref,
              source: ImageSource.gallery,
            ),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Choose from photos'),
          ),
          const SizedBox(height: 16),
          Text(
            trip == null ? 'Receipts not in a trip' : 'Receipts in this trip',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          receipts.when(
            data: (all) {
              final list = <Receipt>[
                for (final r in all)
                  if (r.tripId == trip?.id) r,
              ];
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'Nothing scanned yet.',
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return Column(
                children: [
                  for (final r in list)
                    ReceiptTile(
                      receipt: r,
                      imagePath: storage.absolute(r.originalImagePath),
                      onTap: () =>
                          Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => ReceiptScreen(receiptId: r.id),
                      )),
                    ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorText(e),
            skipLoadingOnReload: true,
          ),
        ],
      ),
    );
  }
}
