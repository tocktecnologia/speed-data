import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:speed_data/features/models/lap_analysis_model.dart';
import 'package:speed_data/features/models/session_analysis_summary_model.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_formatters.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_types.dart';

class LapTimesSectorsTable extends StatelessWidget {
  final List<LapAnalysisModel> laps;
  final SessionAnalysisSummaryModel? summary;
  final LapAnalysisModel? comparisonLap;
  final String? selectedLapId;
  final LapTimesResultMode resultMode;
  final ValueChanged<LapAnalysisModel>? onSelectLap;
  final int minLapTimeMs;

  const LapTimesSectorsTable({
    super.key,
    required this.laps,
    this.summary,
    this.comparisonLap,
    this.selectedLapId,
    this.resultMode = LapTimesResultMode.absolute,
    this.onSelectLap,
    this.minLapTimeMs = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (laps.isEmpty) {
      return const Center(child: Text('No lap data available'));
    }

    final sortedLaps = List<LapAnalysisModel>.from(laps)
      ..sort((a, b) => b.number.compareTo(a.number));
    final referenceLap = comparisonLap ??
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
                      DataCell(
                        Text(
                          resultMode == LapTimesResultMode.absolute
                              ? formatDurationMs(optimalTotal)
                              : formatDeltaDurationMs(
                                  referenceLap == null
                                      ? null
                                      : (optimalTotal -
                                          referenceLap.totalLapTimeMs),
                                ),
                        ),
                      ),
                      for (int i = 0; i < sectorCount; i++)
                        DataCell(
                          Text(
                            () {
                              final value = i < optimalSectors.length
                                  ? optimalSectors[i]
                                  : null;
                              if (resultMode == LapTimesResultMode.absolute) {
                                return formatDurationMs(value);
                              }
                              final refValue = referenceLap != null &&
                                      i < referenceLap.sectorsMs.length
                                  ? referenceLap.sectorsMs[i]
                                  : null;
                              return formatDeltaDurationMs(
                                value != null && refValue != null
                                    ? value - refValue
                                    : null,
                              );
                            }(),
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
    final isComparison = referenceLap != null && referenceLap.id == lap.id;
    final isSelected = selectedLapId != null && selectedLapId == lap.id;
    Color rowColor = Colors.transparent;
    if (!lapIsValid) {
      rowColor = Theme.of(context).colorScheme.error.withValues(alpha: 0.08);
    }
    if (isComparison) {
      rowColor = Colors.blue.withValues(alpha: 0.10);
    }
    if (isSelected) {
      rowColor = scheme.primaryContainer.withValues(alpha: 0.16);
    }

    return DataRow(
      onSelectChanged: onSelectLap == null ? null : (_) => onSelectLap!(lap),
      color: WidgetStatePropertyAll(rowColor),
      cells: [
        DataCell(
          Text(
            'L${lap.number}${lapIsValid ? '' : ' (INV)'}',
            style: TextStyle(
              fontWeight: isComparison ? FontWeight.w700 : FontWeight.w600,
              color: lapIsValid ? null : scheme.error,
            ),
          ),
        ),
        DataCell(
          Text(
            resultMode == LapTimesResultMode.absolute
                ? formatDurationMs(lap.totalLapTimeMs)
                : formatDeltaDurationMs(referenceLap == null
                    ? null
                    : lap.totalLapTimeMs - referenceLap.totalLapTimeMs),
            style: TextStyle(color: lapIsValid ? null : scheme.error),
          ),
        ),
        for (int i = 0; i < sectorCount; i++)
          DataCell(
            Text(
              () {
                final value =
                    i < lap.sectorsMs.length ? lap.sectorsMs[i] : null;
                if (resultMode == LapTimesResultMode.absolute) {
                  return formatDurationMs(value);
                }
                final refValue =
                    referenceLap != null && i < referenceLap.sectorsMs.length
                        ? referenceLap.sectorsMs[i]
                        : null;
                return formatDeltaDurationMs(
                  value != null && refValue != null ? value - refValue : null,
                );
              }(),
              style: TextStyle(
                color: durationDeltaColor(
                  scheme,
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
}
