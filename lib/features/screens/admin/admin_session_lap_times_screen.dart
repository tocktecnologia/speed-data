import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:speed_data/features/models/competitor_model.dart';
import 'package:speed_data/features/models/event_model.dart';
import 'package:speed_data/features/models/lap_analysis_model.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/features/screens/pilot/lap_times_screen.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_formatters.dart';
import 'package:speed_data/features/services/firestore_service.dart';

class AdminSessionLapTimesScreen extends StatefulWidget {
  final RaceEvent event;
  final RaceSession session;

  const AdminSessionLapTimesScreen({
    super.key,
    required this.event,
    required this.session,
  });

  @override
  State<AdminSessionLapTimesScreen> createState() =>
      _AdminSessionLapTimesScreenState();
}

class _AdminSessionLapTimesScreenState
    extends State<AdminSessionLapTimesScreen> {
  final FirestoreService _firestore = FirestoreService();

  String? _selectedParticipantUid;
  String? _compareAUid;
  String? _compareBUid;
  String? _compareALapId;
  String? _compareBLapId;

  String _sessionTitle(RaceSession value) {
    if (value.name.trim().isNotEmpty) return value.name.trim();
    return value.type.name.toUpperCase();
  }

  String _competitorName(Competitor competitor) {
    final name = competitor.name.trim();
    if (name.isNotEmpty) return name;
    final label = competitor.label.trim();
    if (label.isNotEmpty) return label;
    final number = competitor.number.trim();
    if (number.isNotEmpty) return 'Car #$number';
    return 'Competitor';
  }

  String _participantNumber(Competitor? competitor) {
    if (competitor == null) return '';
    return competitor.number.trim();
  }

  String _participantLabel(_ParticipantLapEntry entry) {
    final number = _participantNumber(entry.competitor);
    final name = entry.competitor == null
        ? 'UID ${entry.uid.substring(0, math.min(6, entry.uid.length))}'
        : _competitorName(entry.competitor!);
    if (number.isEmpty) return name;
    return '#$number $name';
  }

  int _parseNumberSortValue(Competitor? competitor) {
    if (competitor == null) return 1 << 20;
    final number = competitor.number.trim();
    if (number.isEmpty) return 1 << 20;
    return int.tryParse(number) ?? 1 << 20;
  }

  List<LapAnalysisModel> _sortedLaps(List<LapAnalysisModel> laps) {
    final sorted = List<LapAnalysisModel>.from(laps)
      ..sort((a, b) => b.number.compareTo(a.number));
    return sorted;
  }

  List<LapAnalysisModel> _validLaps(List<LapAnalysisModel> laps) {
    final minLapMs = widget.session.minLapTimeSeconds * 1000;
    return laps
        .where((lap) => isLapValid(lap, minLapTimeMs: minLapMs))
        .toList(growable: false);
  }

  LapAnalysisModel? _bestValidLap(List<LapAnalysisModel> laps) {
    return selectReferenceLap(
      laps,
      minLapTimeMs: widget.session.minLapTimeSeconds * 1000,
    );
  }

  int? _averageValidLapMs(List<LapAnalysisModel> laps) {
    final valid = _validLaps(laps);
    if (valid.isEmpty) return null;
    final sum = valid.fold<int>(0, (acc, lap) => acc + lap.totalLapTimeMs);
    return (sum / valid.length).round();
  }

  int _maxSectorCount(List<LapAnalysisModel> laps) {
    int maxSectors = 0;
    for (final lap in laps) {
      maxSectors = math.max(maxSectors, lap.sectorsMs.length);
    }
    return maxSectors;
  }

  void _syncSelections(List<_ParticipantLapEntry> entries) {
    if (entries.isEmpty) {
      if (_selectedParticipantUid == null &&
          _compareAUid == null &&
          _compareBUid == null &&
          _compareALapId == null &&
          _compareBLapId == null) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selectedParticipantUid = null;
          _compareAUid = null;
          _compareBUid = null;
          _compareALapId = null;
          _compareBLapId = null;
        });
      });
      return;
    }

    final ids = entries.map((entry) => entry.uid).toSet();
    String? nextSelectedUid = _selectedParticipantUid;
    String? nextCompareAUid = _compareAUid;
    String? nextCompareBUid = _compareBUid;
    String? nextCompareALapId = _compareALapId;
    String? nextCompareBLapId = _compareBLapId;

    if (nextSelectedUid == null || !ids.contains(nextSelectedUid)) {
      nextSelectedUid = entries.first.uid;
    }
    if (nextCompareAUid == null || !ids.contains(nextCompareAUid)) {
      nextCompareAUid = entries.first.uid;
      nextCompareALapId = null;
    }
    if (nextCompareBUid == null || !ids.contains(nextCompareBUid)) {
      nextCompareBUid = entries.length > 1 ? entries[1].uid : entries.first.uid;
      nextCompareBLapId = null;
    }

    final compareAEntry = entries.cast<_ParticipantLapEntry?>().firstWhere(
          (entry) => entry?.uid == nextCompareAUid,
          orElse: () => null,
        );
    final compareBEntry = entries.cast<_ParticipantLapEntry?>().firstWhere(
          (entry) => entry?.uid == nextCompareBUid,
          orElse: () => null,
        );
    if (nextCompareALapId != null &&
        compareAEntry != null &&
        !compareAEntry.laps.any((lap) => lap.id == nextCompareALapId)) {
      nextCompareALapId = null;
    }
    if (nextCompareBLapId != null &&
        compareBEntry != null &&
        !compareBEntry.laps.any((lap) => lap.id == nextCompareBLapId)) {
      nextCompareBLapId = null;
    }

    if (nextSelectedUid == _selectedParticipantUid &&
        nextCompareAUid == _compareAUid &&
        nextCompareBUid == _compareBUid &&
        nextCompareALapId == _compareALapId &&
        nextCompareBLapId == _compareBLapId) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedParticipantUid = nextSelectedUid;
        _compareAUid = nextCompareAUid;
        _compareBUid = nextCompareBUid;
        _compareALapId = nextCompareALapId;
        _compareBLapId = nextCompareBLapId;
      });
    });
  }

  _ParticipantLapEntry? _entryByUid(
    List<_ParticipantLapEntry> entries,
    String? uid,
  ) {
    if (uid == null || uid.isEmpty) return null;
    return entries.cast<_ParticipantLapEntry?>().firstWhere(
          (entry) => entry?.uid == uid,
          orElse: () => null,
        );
  }

  LapAnalysisModel? _resolveComparisonLap(
    _ParticipantLapEntry? entry,
    String? selectedLapId,
  ) {
    if (entry == null) return null;
    if (selectedLapId != null && selectedLapId.isNotEmpty) {
      final selected = entry.laps.cast<LapAnalysisModel?>().firstWhere(
            (lap) => lap?.id == selectedLapId,
            orElse: () => null,
          );
      if (selected != null) return selected;
    }
    return _bestValidLap(entry.laps) ??
        (entry.laps.isNotEmpty ? entry.laps.first : null);
  }

  Widget _buildBestLapArea(
    BuildContext context,
    List<_ParticipantLapEntry> entries,
  ) {
    final ranked = entries
        .map((entry) => _BestLapRow(
              entry: entry,
              bestLap: _bestValidLap(entry.laps),
              validCount: _validLaps(entry.laps).length,
              totalCount: entry.laps.length,
            ))
        .toList(growable: false)
      ..sort((a, b) {
        if (a.bestLap == null && b.bestLap == null) return 0;
        if (a.bestLap == null) return 1;
        if (b.bestLap == null) return -1;
        final byTime = a.bestLap!.totalLapTimeMs.compareTo(
          b.bestLap!.totalLapTimeMs,
        );
        if (byTime != 0) return byTime;
        return a.entry.uid.compareTo(b.entry.uid);
      });

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Best Lap (valid) by competitor',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (ranked.isEmpty)
              const Text('No participants found for this session.')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Pos')),
                    DataColumn(label: Text('#')),
                    DataColumn(label: Text('Competitor')),
                    DataColumn(label: Text('Best Lap')),
                    DataColumn(label: Text('Lap')),
                    DataColumn(label: Text('Valid/Total')),
                  ],
                  rows: [
                    for (int i = 0; i < ranked.length; i++)
                      DataRow(
                        cells: [
                          DataCell(Text('${i + 1}')),
                          DataCell(
                            Text(
                                _participantNumber(ranked[i].entry.competitor)),
                          ),
                          DataCell(
                            Text(_participantLabel(ranked[i].entry)),
                          ),
                          DataCell(
                            Text(
                              formatDurationMs(
                                ranked[i].bestLap?.totalLapTimeMs,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              ranked[i].bestLap == null
                                  ? '-'
                                  : 'L${ranked[i].bestLap!.number}',
                            ),
                          ),
                          DataCell(
                            Text(
                              '${ranked[i].validCount}/${ranked[i].totalCount}',
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndividualArea(
    BuildContext context,
    List<_ParticipantLapEntry> entries,
  ) {
    final entry = _entryByUid(entries, _selectedParticipantUid);
    final laps = entry == null ? const <LapAnalysisModel>[] : entry.laps;
    final validCount = _validLaps(laps).length;
    final bestLap = _bestValidLap(laps);
    final avgLap = _averageValidLapMs(laps);
    final maxSectors = _maxSectorCount(laps);
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 300,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedParticipantUid,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Participant',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final item in entries)
                        DropdownMenuItem<String>(
                          value: item.uid,
                          child: Text(
                            _participantLabel(item),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedParticipantUid = value),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: entry == null
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LapTimesScreen(
                                raceId: widget.event.trackId,
                                userId: entry.uid,
                                raceName:
                                    '${widget.event.name} - ${_participantLabel(entry)}',
                                eventId: widget.event.id,
                                initialSessionId: widget.session.id,
                                fixedSessionLabel:
                                    _sessionTitle(widget.session),
                                lockSessionSelection: true,
                                sessionIdsStreamOverride:
                                    Stream<List<String>>.value(
                                  <String>[widget.session.id],
                                ),
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open full analysis'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Text('Best: ${formatDurationMs(bestLap?.totalLapTimeMs)}'),
                Text('Avg(valid): ${formatDurationMs(avgLap)}'),
                Text('Valid/Total: $validCount/${laps.length}'),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: laps.isEmpty
                  ? const Center(
                      child: Text('No laps recorded for this participant.'),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          columns: [
                            const DataColumn(label: Text('Lap')),
                            const DataColumn(label: Text('Total')),
                            const DataColumn(label: Text('Valid')),
                            for (int i = 0; i < maxSectors; i++)
                              DataColumn(label: Text('S${i + 1}')),
                          ],
                          rows: [
                            for (final lap in laps)
                              DataRow(
                                color: WidgetStatePropertyAll(
                                  isLapValid(
                                    lap,
                                    minLapTimeMs:
                                        widget.session.minLapTimeSeconds * 1000,
                                  )
                                      ? Colors.transparent
                                      : colorScheme.error
                                          .withValues(alpha: 0.1),
                                ),
                                cells: [
                                  DataCell(Text('L${lap.number}')),
                                  DataCell(
                                    Text(formatDurationMs(lap.totalLapTimeMs)),
                                  ),
                                  DataCell(
                                    Icon(
                                      isLapValid(
                                        lap,
                                        minLapTimeMs:
                                            widget.session.minLapTimeSeconds *
                                                1000,
                                      )
                                          ? Icons.check_circle
                                          : Icons.cancel,
                                      color: isLapValid(
                                        lap,
                                        minLapTimeMs:
                                            widget.session.minLapTimeSeconds *
                                                1000,
                                      )
                                          ? Colors.green
                                          : Colors.red,
                                      size: 18,
                                    ),
                                  ),
                                  for (int i = 0; i < maxSectors; i++)
                                    DataCell(
                                      Text(
                                        formatDurationMs(
                                          i < lap.sectorsMs.length
                                              ? lap.sectorsMs[i]
                                              : null,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonArea(
    BuildContext context,
    List<_ParticipantLapEntry> entries,
  ) {
    final entryA = _entryByUid(entries, _compareAUid);
    final entryB = _entryByUid(entries, _compareBUid);
    final lapA = _resolveComparisonLap(entryA, _compareALapId);
    final lapB = _resolveComparisonLap(entryB, _compareBLapId);
    final maxSectors = math.max(
      lapA?.sectorsMs.length ?? 0,
      lapB?.sectorsMs.length ?? 0,
    );
    final deltaTotal = (lapA != null && lapB != null)
        ? lapA.totalLapTimeMs - lapB.totalLapTimeMs
        : null;

    Color deltaColor(int? delta) {
      if (delta == null || delta == 0) {
        return Theme.of(context).colorScheme.onSurface;
      }
      return delta < 0 ? Colors.green : Colors.red;
    }

    List<DropdownMenuItem<String?>> lapItems(_ParticipantLapEntry? entry) {
      final items = <DropdownMenuItem<String?>>[
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Best valid (auto)'),
        ),
      ];
      if (entry == null) return items;
      for (final lap in entry.laps) {
        items.add(
          DropdownMenuItem<String?>(
            value: lap.id,
            child: Text(
              'L${lap.number} - ${formatDurationMs(lap.totalLapTimeMs)}${lap.valid ? '' : ' (INV)'}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
      return items;
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Participant Comparison',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 250,
                  child: DropdownButtonFormField<String>(
                    initialValue: _compareAUid,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Participant A',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final item in entries)
                        DropdownMenuItem<String>(
                          value: item.uid,
                          child: Text(
                            _participantLabel(item),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _compareAUid = value;
                      _compareALapId = null;
                    }),
                  ),
                ),
                SizedBox(
                  width: 250,
                  child: DropdownButtonFormField<String>(
                    initialValue: _compareBUid,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Participant B',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final item in entries)
                        DropdownMenuItem<String>(
                          value: item.uid,
                          child: Text(
                            _participantLabel(item),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _compareBUid = value;
                      _compareBLapId = null;
                    }),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _compareALapId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Lap A',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: lapItems(entryA),
                    onChanged: (value) =>
                        setState(() => _compareALapId = value),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _compareBLapId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Lap B',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: lapItems(entryB),
                    onChanged: (value) =>
                        setState(() => _compareBLapId = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Text('A: ${formatDurationMs(lapA?.totalLapTimeMs)}'),
                Text('B: ${formatDurationMs(lapB?.totalLapTimeMs)}'),
                Text(
                  'Delta A-B: ${formatDeltaDurationMs(deltaTotal)}',
                  style: TextStyle(color: deltaColor(deltaTotal)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: (lapA == null && lapB == null)
                  ? const Center(
                      child: Text('Select participants to compare laps.'),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Metric')),
                            DataColumn(label: Text('A')),
                            DataColumn(label: Text('B')),
                            DataColumn(label: Text('Delta A-B')),
                          ],
                          rows: [
                            DataRow(
                              cells: [
                                const DataCell(Text('Total')),
                                DataCell(
                                  Text(formatDurationMs(lapA?.totalLapTimeMs)),
                                ),
                                DataCell(
                                  Text(formatDurationMs(lapB?.totalLapTimeMs)),
                                ),
                                DataCell(
                                  Text(
                                    formatDeltaDurationMs(deltaTotal),
                                    style: TextStyle(
                                      color: deltaColor(deltaTotal),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            for (int i = 0; i < maxSectors; i++)
                              () {
                                final aSector =
                                    i < (lapA?.sectorsMs.length ?? 0)
                                        ? lapA!.sectorsMs[i]
                                        : null;
                                final bSector =
                                    i < (lapB?.sectorsMs.length ?? 0)
                                        ? lapB!.sectorsMs[i]
                                        : null;
                                final delta =
                                    (aSector != null && bSector != null)
                                        ? aSector - bSector
                                        : null;
                                return DataRow(
                                  cells: [
                                    DataCell(Text('S${i + 1}')),
                                    DataCell(Text(formatDurationMs(aSector))),
                                    DataCell(Text(formatDurationMs(bSector))),
                                    DataCell(
                                      Text(
                                        formatDeltaDurationMs(delta),
                                        style:
                                            TextStyle(color: deltaColor(delta)),
                                      ),
                                    ),
                                  ],
                                );
                              }(),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionTitle = _sessionTitle(widget.session);

    return Scaffold(
      appBar: AppBar(
        title: Text('Lap Times Analysis - $sessionTitle'),
      ),
      body: StreamBuilder<List<Competitor>>(
        stream: _firestore.getCompetitorsStream(widget.event.id),
        builder: (context, competitorsSnapshot) {
          if (!competitorsSnapshot.hasData &&
              competitorsSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final competitors = (competitorsSnapshot.data ?? const <Competitor>[])
              .where((competitor) => competitor.uid.trim().isNotEmpty)
              .toList(growable: false);

          return StreamBuilder<Map<String, List<LapAnalysisModel>>>(
            stream: _firestore.getSessionParticipantsLapsModels(
              widget.event.trackId,
              sessionId: widget.session.id,
              eventId: widget.event.id,
            ),
            builder: (context, lapsSnapshot) {
              if (!lapsSnapshot.hasData &&
                  lapsSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final lapsByUid =
                  lapsSnapshot.data ?? const <String, List<LapAnalysisModel>>{};
              final competitorByUid = <String, Competitor>{
                for (final competitor in competitors)
                  if (competitor.uid.trim().isNotEmpty)
                    competitor.uid: competitor,
              };
              final allUids = <String>{
                ...competitorByUid.keys,
                ...lapsByUid.keys.where((uid) => uid.trim().isNotEmpty),
              };

              final entries = allUids
                  .map(
                    (uid) => _ParticipantLapEntry(
                      uid: uid,
                      competitor: competitorByUid[uid],
                      laps: _sortedLaps(lapsByUid[uid] ?? const []),
                    ),
                  )
                  .toList(growable: false)
                ..sort((a, b) {
                  final byBestLap = () {
                    final bestA = _bestValidLap(a.laps)?.totalLapTimeMs;
                    final bestB = _bestValidLap(b.laps)?.totalLapTimeMs;
                    if (bestA == null && bestB == null) return 0;
                    if (bestA == null) return 1;
                    if (bestB == null) return -1;
                    return bestA.compareTo(bestB);
                  }();
                  if (byBestLap != 0) return byBestLap;
                  final byNumber = _parseNumberSortValue(a.competitor)
                      .compareTo(_parseNumberSortValue(b.competitor));
                  if (byNumber != 0) return byNumber;
                  return _participantLabel(a).compareTo(_participantLabel(b));
                });

              _syncSelections(entries);

              if (entries.isEmpty) {
                return const Center(
                  child:
                      Text('No participants with laps found in this session.'),
                );
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 1180;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${widget.event.name} - Session $sessionTitle',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                      _buildBestLapArea(context, entries),
                      Expanded(
                        child: compact
                            ? ListView(
                                children: [
                                  SizedBox(
                                    height: 520,
                                    child:
                                        _buildIndividualArea(context, entries),
                                  ),
                                  SizedBox(
                                    height: 520,
                                    child:
                                        _buildComparisonArea(context, entries),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    child:
                                        _buildIndividualArea(context, entries),
                                  ),
                                  Expanded(
                                    child:
                                        _buildComparisonArea(context, entries),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _ParticipantLapEntry {
  final String uid;
  final Competitor? competitor;
  final List<LapAnalysisModel> laps;

  const _ParticipantLapEntry({
    required this.uid,
    required this.competitor,
    required this.laps,
  });
}

class _BestLapRow {
  final _ParticipantLapEntry entry;
  final LapAnalysisModel? bestLap;
  final int validCount;
  final int totalCount;

  const _BestLapRow({
    required this.entry,
    required this.bestLap,
    required this.validCount,
    required this.totalCount,
  });
}
