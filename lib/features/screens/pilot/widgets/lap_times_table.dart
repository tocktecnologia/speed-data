import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:speed_data/features/models/lap_analysis_model.dart';
import 'package:speed_data/features/models/session_analysis_summary_model.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_formatters.dart';

class LapTimesSectorsTable extends StatelessWidget {
  final List<LapAnalysisModel> laps;
  final SessionAnalysisSummaryModel? summary;
  final int minLapTimeMs;

  const LapTimesSectorsTable({
    super.key,
    required this.laps,
    this.summary,
    this.minLapTimeMs = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (laps.isEmpty) {
      return const Center(child: Text('No lap data available'));
    }

    final sortedLaps = List<LapAnalysisModel>.from(laps)
      ..sort((a, b) => b.number.compareTo(a.number));
    final referenceLap =
        selectReferenceLap(sortedLaps, minLapTimeMs: minLapTimeMs);
    final optimalSectors = deriveOptimalSectors(
      sortedLaps,
      summary: summary,
      minLapTimeMs: minLapTimeMs,
    );
    final sectorCount = math.max(
      optimalSectors.length,
      maxListLength(
          sortedLaps.map((lap) => lap.sectorsMs).toList(growable: false)),
    );
    final optimalTotal =
        optimalSectors.fold<int>(0, (sum, value) => sum + value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            referenceLap != null
                ? 'Reference lap: L${referenceLap.number} (${formatDurationMs(referenceLap.totalLapTimeMs)})'
                : 'Reference lap: none (valid laps required)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                columns: [
                  const DataColumn(label: Text('Lap')),
                  const DataColumn(label: Text('Total')),
                  for (int i = 0; i < sectorCount; i++)
                    DataColumn(label: Text('S${i + 1}')),
                ],
                rows: [
                  DataRow(
                    color: WidgetStatePropertyAll(
                      Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.08),
                    ),
                    cells: [
                      const DataCell(Text('OPT',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(formatDurationMs(optimalTotal))),
                      for (int i = 0; i < sectorCount; i++)
                        DataCell(
                          Text(
                            i < optimalSectors.length
                                ? formatDurationMs(optimalSectors[i])
                                : '-',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  for (final lap in sortedLaps)
                    _buildLapRow(
                      context,
                      lap: lap,
                      referenceLap: referenceLap,
                      sectorCount: sectorCount,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  DataRow _buildLapRow(
    BuildContext context, {
    required LapAnalysisModel lap,
    required LapAnalysisModel? referenceLap,
    required int sectorCount,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final lapIsValid = isLapValid(lap, minLapTimeMs: minLapTimeMs);
    final rowColor = lapIsValid
        ? Colors.transparent
        : Theme.of(context).colorScheme.error.withValues(alpha: 0.08);

    return DataRow(
      color: WidgetStatePropertyAll(rowColor),
      cells: [
        DataCell(
          Text(
            'L${lap.number}${lapIsValid ? '' : ' (INV)'}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: lapIsValid ? null : scheme.error,
            ),
          ),
        ),
        DataCell(
          Text(
            formatDurationMs(lap.totalLapTimeMs),
            style: TextStyle(color: lapIsValid ? null : scheme.error),
          ),
        ),
        for (int i = 0; i < sectorCount; i++)
          DataCell(
            Text(
              i < lap.sectorsMs.length
                  ? formatDurationMs(lap.sectorsMs[i])
                  : '-',
              style: TextStyle(
                color: _sectorDeltaColor(
                  scheme: scheme,
                  currentValue:
                      i < lap.sectorsMs.length ? lap.sectorsMs[i] : null,
                  referenceValue:
                      referenceLap != null && i < referenceLap.sectorsMs.length
                          ? referenceLap.sectorsMs[i]
                          : null,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Color? _sectorDeltaColor({
    required ColorScheme scheme,
    required int? currentValue,
    required int? referenceValue,
  }) {
    if (currentValue == null || referenceValue == null) {
      return scheme.onSurface;
    }
    if (currentValue <= 0 || referenceValue <= 0) {
      return scheme.onSurfaceVariant;
    }
    if (currentValue <= referenceValue) {
      return Colors.green.shade400;
    }
    return Colors.red.shade400;
  }
}
