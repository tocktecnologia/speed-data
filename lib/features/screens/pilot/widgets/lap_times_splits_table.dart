import 'package:flutter/material.dart';
import 'package:speed_data/features/models/lap_analysis_model.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_formatters.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_types.dart';

class LapTimesSplitsTable extends StatelessWidget {
  final List<LapAnalysisModel> laps;
  final LapAnalysisModel? comparisonLap;
  final String? selectedLapId;
  final LapTimesResultMode resultMode;
  final ValueChanged<LapAnalysisModel>? onSelectLap;
  final int minLapTimeMs;

  const LapTimesSplitsTable({
    super.key,
    required this.laps,
    this.comparisonLap,
    this.selectedLapId,
    this.resultMode = LapTimesResultMode.absolute,
    this.onSelectLap,
    this.minLapTimeMs = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (laps.isEmpty) {
      return const Center(child: Text('No split data available'));
    }

    final sorted = List<LapAnalysisModel>.from(laps)
      ..sort((a, b) => b.number.compareTo(a.number));
    final reference =
        comparisonLap ?? selectReferenceLap(sorted, minLapTimeMs: minLapTimeMs);
    final maxSplitCount = maxListLength(
        sorted.map((lap) => lap.splitsMs).toList(growable: false));
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: [
            const DataColumn(label: Text('Lap')),
            const DataColumn(label: Text('Total')),
            for (int i = 0; i < maxSplitCount; i++)
              DataColumn(label: Text('SP${i + 1}')),
          ],
          rows: [
            for (final lap in sorted)
              DataRow(
                onSelectChanged:
                    onSelectLap == null ? null : (_) => onSelectLap!(lap),
                color: WidgetStatePropertyAll(
                  () {
                    final isValid = isLapValid(lap, minLapTimeMs: minLapTimeMs);
                    final isComparison =
                        reference != null && reference.id == lap.id;
                    final isSelected =
                        selectedLapId != null && selectedLapId == lap.id;
                    Color color = Colors.transparent;
                    if (!isValid) {
                      color = scheme.error.withValues(alpha: 0.08);
                    }
                    if (isComparison) {
                      color = Colors.blue.withValues(alpha: 0.10);
                    }
                    if (isSelected) {
                      color = scheme.primaryContainer.withValues(alpha: 0.16);
                    }
                    return color;
                  }(),
                ),
                cells: [
                  DataCell(
                    Text(
                      'L${lap.number}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isLapValid(lap, minLapTimeMs: minLapTimeMs)
                            ? scheme.onSurface
                            : scheme.error,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      resultMode == LapTimesResultMode.absolute
                          ? formatDurationMs(lap.totalLapTimeMs)
                          : formatDeltaDurationMs(reference == null
                              ? null
                              : lap.totalLapTimeMs - reference.totalLapTimeMs),
                    ),
                  ),
                  for (int i = 0; i < maxSplitCount; i++)
                    DataCell(
                      Text(
                        () {
                          final current =
                              i < lap.splitsMs.length ? lap.splitsMs[i] : null;
                          if (resultMode == LapTimesResultMode.absolute) {
                            return formatDurationMs(current);
                          }
                          final ref =
                              reference != null && i < reference.splitsMs.length
                                  ? reference.splitsMs[i]
                                  : null;
                          return formatDeltaDurationMs(
                            current != null && ref != null
                                ? current - ref
                                : null,
                          );
                        }(),
                        style: TextStyle(
                          color: durationDeltaColor(
                            scheme,
                            currentValue: i < lap.splitsMs.length
                                ? lap.splitsMs[i]
                                : null,
                            referenceValue: reference != null &&
                                    i < reference.splitsMs.length
                                ? reference.splitsMs[i]
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
