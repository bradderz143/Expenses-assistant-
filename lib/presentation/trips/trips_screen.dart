import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/receipt.dart';
import '../../domain/entities/receipt_query.dart';
import '../../domain/entities/trip.dart';
import '../../domain/reference/countries.dart';
import '../../domain/value_objects/money.dart';
import '../common/widgets.dart';
import '../providers.dart';
import '../receipts/receipt_screen.dart';

String _dateRange(Trip t) {
  if (t.startDate == null && t.endDate == null) return 'No dates';
  return '${displayDate(t.startDate)} – ${displayDate(t.endDate)}';
}

String _totals(TripSummary s) => s.totals.entries
    .map((e) => Money(e.value, e.key).toString())
    .join(' + ');

class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(tripsProvider);
    final summaries = ref.watch(tripSummariesProvider).when(
          data: (m) => m,
          loading: () => const <String, TripSummary>{},
          error: (_, _) => const <String, TripSummary>{},
        );
    final activeId = ref.watch(settingsProvider).when<String?>(
          data: (s) => s.activeTripId,
          loading: () => null,
          error: (_, _) => null,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Trips')),
      body: trips.when(
        data: (list) => list.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Create a trip (e.g. "Caracas ACS Workshop"). New scans are '
                    'filed under the trip you pick on the Scan tab.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final trip = list[i];
                  final summary = summaries[trip.id] ?? TripSummary.empty;
                  return ListTile(
                    leading: Icon(
                      trip.id == activeId ? Icons.flight : Icons.luggage_outlined,
                      color: trip.id == activeId
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(trip.name),
                    subtitle: Text(
                      '${trip.country} · ${_dateRange(trip)}\n'
                      '${summary.receiptCount} receipts'
                      '${summary.totals.isEmpty ? '' : ' · ${_totals(summary)}'}',
                    ),
                    isThreeLine: true,
                    trailing: trip.id == activeId
                        ? const Chip(label: Text('Active'))
                        : (trip.isFavourite ? const Icon(Icons.star) : null),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => TripDetailScreen(tripId: trip.id),
                    )),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorText(e),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const TripEditScreen(),
        )),
        icon: const Icon(Icons.add),
        label: const Text('New trip'),
      ),
    );
  }
}

enum _TripAction { edit, toggleActive, delete }

/// Pick receipts that are in no trip and file them under [trip]. The ones
/// dated within the trip's dates start ticked.
class AddReceiptsScreen extends ConsumerStatefulWidget {
  const AddReceiptsScreen({required this.trip, super.key});

  final Trip trip;

  @override
  ConsumerState<AddReceiptsScreen> createState() => _AddReceiptsScreenState();
}

class _AddReceiptsScreenState extends ConsumerState<AddReceiptsScreen> {
  List<Receipt>? _loose;
  final Set<String> _picked = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loose = await ref.read(tripCommandsProvider).looseReceipts();
    if (!mounted) return;
    final trip = widget.trip;
    setState(() {
      _loose = loose;
      _picked
        ..clear()
        ..addAll([
          for (final r in loose)
            if (r.transactionDate != null && trip.contains(r.transactionDate!))
              r.id,
        ]);
    });
  }

  Future<void> _add() async {
    final loose = _loose;
    if (loose == null || _picked.isEmpty) return;
    final chosen = [for (final r in loose) if (_picked.contains(r.id)) r];
    final commands = ref.read(tripCommandsProvider);
    final revision = ref.read(dataRevisionProvider.notifier);
    final navigator = Navigator.of(context);
    await runWithProgress<void>(
      context,
      message: 'Adding receipts…',
      task: (_) => commands.assignReceipts(widget.trip, chosen),
    );
    revision.bump();
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final loose = _loose;
    final storage = ref.watch(fileStorageProvider);
    final count = _picked.length;
    return Scaffold(
      appBar: AppBar(title: Text('Add to ${widget.trip.name}')),
      body: loose == null
          ? const Center(child: CircularProgressIndicator())
          : loose.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Every receipt is already in a trip.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Text(
                        'Receipts not in a trip. Those dated within the '
                        "trip's dates are ticked; tap to change.",
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    for (final r in loose)
                      ReceiptTile(
                        receipt: r,
                        imagePath: storage.absolute(r.originalImagePath),
                        selected: _picked.contains(r.id),
                        onTap: () => setState(() {
                          if (!_picked.remove(r.id)) _picked.add(r.id);
                        }),
                      ),
                  ],
                ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: count == 0 ? null : _add,
            child: Text(count == 1 ? 'Add 1 receipt' : 'Add $count receipts'),
          ),
        ),
      ),
    );
  }
}

class TripDetailScreen extends ConsumerWidget {
  const TripDetailScreen({required this.tripId, super.key});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripsProvider).when<Trip?>(
          skipLoadingOnReload: true,
          data: (list) {
            for (final t in list) {
              if (t.id == tripId) return t;
            }
            return null;
          },
          loading: () => null,
          error: (_, _) => null,
        );
    if (trip == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final activeId = ref.watch(settingsProvider).when<String?>(
          data: (s) => s.activeTripId,
          loading: () => null,
          error: (_, _) => null,
        );
    final isActive = activeId == trip.id;
    final receipts = ref.watch(
      receiptSearchProvider(ReceiptQuery(tripId: trip.id, limit: 1000)),
    );
    final summary = ref.watch(tripSummariesProvider).when(
          data: (m) => m[trip.id] ?? TripSummary.empty,
          loading: () => TripSummary.empty,
          error: (_, _) => TripSummary.empty,
        );
    final storage = ref.watch(fileStorageProvider);

    Future<void> onAction(_TripAction action) async {
      // Read providers before any await: ref dies with this widget.
      final commands = ref.read(tripCommandsProvider);
      final revision = ref.read(dataRevisionProvider.notifier);
      switch (action) {
        case _TripAction.edit:
          await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => TripEditScreen(trip: trip),
          ));
        case _TripAction.toggleActive:
          await commands.setActive(isActive ? null : trip);
          revision.bump();
        case _TripAction.delete:
          final ok = await confirm(
            context,
            title: 'Delete trip?',
            message: 'Receipts in this trip are kept, but no longer filed '
                'under a trip.',
            confirmLabel: 'Delete trip',
            destructive: true,
          );
          if (!ok || !context.mounted) return;
          final navigator = Navigator.of(context);
          await runWithProgress<void>(
            context,
            message: 'Deleting trip…',
            task: (_) => commands.delete(trip),
          );
          revision.bump();
          navigator.pop();
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(trip.name),
        actions: [
          PopupMenuButton<_TripAction>(
            onSelected: onAction,
            itemBuilder: (_) => [
              const PopupMenuItem(value: _TripAction.edit, child: Text('Edit trip')),
              PopupMenuItem(
                value: _TripAction.toggleActive,
                child: Text(isActive ? 'Scanning into this trip' : 'Scan into this trip'),
              ),
              const PopupMenuItem(value: _TripAction.delete, child: Text('Delete trip')),
            ],
          ),
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            title: Text('${trip.country} · ${_dateRange(trip)}'),
            subtitle: Text(
              '${summary.receiptCount} receipts'
              '${summary.totals.isEmpty ? '' : '\n${_totals(summary)}'}',
            ),
            trailing: isActive ? const Chip(label: Text('Active')) : null,
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('Add receipts to this trip'),
            subtitle: const Text('Ones scanned before the trip was set up'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => AddReceiptsScreen(trip: trip),
            )),
          ),
          const Divider(height: 24),
          receipts.when(
            data: (list) => Column(
              children: [
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No receipts in this trip yet.'),
                  ),
                for (final Receipt r in list)
                  ReceiptTile(
                    receipt: r,
                    imagePath: storage.absolute(r.originalImagePath),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => ReceiptScreen(receiptId: r.id),
                    )),
                  ),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorText(e),
          ),
        ],
      ),
    );
  }
}

class TripEditScreen extends ConsumerStatefulWidget {
  const TripEditScreen({this.trip, super.key});

  final Trip? trip;

  @override
  ConsumerState<TripEditScreen> createState() => _TripEditScreenState();
}

class _TripEditScreenState extends ConsumerState<TripEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _notes;
  late String _country;
  DateTime? _start;
  DateTime? _end;
  bool _favourite = false;
  bool _makeActive = true;

  @override
  void initState() {
    super.initState();
    final trip = widget.trip;
    _name = TextEditingController(text: trip?.name ?? '');
    _notes = TextEditingController(text: trip?.referenceNotes ?? '');
    _country = trip?.country ?? Countries.defaultCountry;
    _start = trip?.startDate;
    _end = trip?.endDate;
    _favourite = trip?.isFavourite ?? false;
    _makeActive = trip == null;
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final initial = (start ? _start : _end) ?? _start ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime(DateTime.now().year + 3),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _pickCountry() async {
    final value = await showOptionPicker<String>(
      context,
      title: 'Country',
      options: Countries.names,
      labelOf: (c) => c,
      selected: _country,
      allowCustom: true,
      fromCustom: (t) => t,
    );
    if (value != null) setState(() => _country = value);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showMessage(context, 'Give the trip a name.');
      return;
    }
    final commands = ref.read(tripCommandsProvider);
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    final existing = widget.trip;
    final saved = await runWithProgress<Trip>(
      context,
      message: 'Saving trip…',
      task: (_) async {
        if (existing == null) {
          return commands.create(
            name: name,
            country: _country,
            startDate: _start,
            endDate: _end,
            referenceNotes: notes,
            isFavourite: _favourite,
          );
        }
        final updated = existing.copyWith(
          name: name,
          country: _country,
          startDate: _start,
          endDate: _end,
          referenceNotes: notes,
          isFavourite: _favourite,
        );
        await commands.update(updated);
        return updated;
      },
    );
    if (saved == null || !mounted) return;
    if (_makeActive) await commands.setActive(saved);
    if (!mounted) return;
    final revision = ref.read(dataRevisionProvider.notifier);
    // A trip set up after the fact (or its dates changed): offer the
    // receipts from its dates.
    final datesChanged = existing == null ||
        existing.startDate != saved.startDate ||
        existing.endDate != saved.endDate;
    final loose = datesChanged
        ? await commands.looseReceiptsFor(saved)
        : const <Receipt>[];
    if (loose.isNotEmpty && mounted) {
      final n = loose.length;
      final add = await confirm(
        context,
        title: n == 1 ? 'Add 1 receipt?' : 'Add $n receipts?',
        message: n == 1
            ? "1 receipt from these dates isn't in a trip yet."
            : "$n receipts from these dates aren't in a trip yet.",
        confirmLabel: 'Add to trip',
      );
      if (add && mounted) {
        await runWithProgress<void>(
          context,
          message: 'Adding receipts…',
          task: (_) => commands.assignReceipts(saved, loose),
        );
      }
    }
    revision.bump();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 14);
    return Scaffold(
      appBar: AppBar(title: Text(widget.trip == null ? 'New trip' : 'Edit trip')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Trip name',
              hintText: 'e.g. Caracas ACS Workshop',
            ),
          ),
          gap,
          PickerField(
            label: 'Country',
            value: _country,
            icon: Icons.public,
            onTap: _pickCountry,
          ),
          gap,
          Row(
            children: [
              Expanded(
                child: PickerField(
                  label: 'Start',
                  value: _start == null ? null : displayDate(_start),
                  icon: Icons.event,
                  onTap: () => _pickDate(start: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PickerField(
                  label: 'End',
                  value: _end == null ? null : displayDate(_end),
                  icon: Icons.event,
                  onTap: () => _pickDate(start: false),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Scan into this trip'),
            subtitle: const Text('New receipts are filed under it'),
            value: _makeActive,
            onChanged: (v) => setState(() => _makeActive = v),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(onPressed: _save, child: const Text('Save trip')),
        ),
      ),
    );
  }
}
