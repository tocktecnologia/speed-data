import 'package:flutter/material.dart';
import 'package:speed_data/features/models/lap_analysis_model.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_formatters.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_types.dart';

class LapTimesTrapSpeedsTable extends StatelessWidget {
  final List<LapAnalysisModel> laps;
  final LapAnalysisModel? comparisonLap;
  final String? selectedLapId;
  final LapTimesResultMode resultMode;
  final ValueChanged<LapAnalysisModel>? onSelectLap;
  final int minLapTimeMs;

  const LapTimesTrapSpeedsTable({
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
      return const Center(child: Text('No trap speed data available'));
    }

    final sorted = List<LapAnalysisModel>.from(laps)
      ..sort((a, b) => b.number.compareTo(a.number));
    final reference =
        comparisonLap ?? selectReferenceLap(sorted, minLapTimeMs: minLapTimeMs);
    final maxTrapCount = maxListLength(
      sorted.map((lap) => lap.trapSpeedsMps).toList(growable: false),
    );
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: [
            const DataColumn(label: Text('Lap')),
            const DataColumn(label: Text('Peak')),
            for (int i = 0; i < maxTrapCount; i++)
              DataColumn(label: Text('TP${i + 1}')),
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
                  DataCell(Text('L${lap.number}')),
                  DataCell(
                    Text(
                      () {
                        final currentPeak = deriveSpeedHigh(lap);
                        if (resultMode == LapTimesResultMode.absolute) {
                          return formatSpeedMps(currentPeak);
                        }
                        final refPeak = reference != null
                            ? deriveSpeedHigh(reference)
                            : null;
                        return formatDeltaSpeedMps(
                          currentPeak != null && refPeak != null
                              ? currentPeak - refPeak
                              : null,
                        );
                      }(),
                    ),
                  ),
                  for (int i = 0; i < maxTrapCount; i++)
                    DataCell(
                      Text(
                        () {
                          final current = i < lap.trapSpeedsMps.length
                              ? lap.trapSpeedsMps[i]
                              : null;
                          if (resultMode == LapTimesResultMode.absolute) {
                            return formatSpeedMps(current);
                          }
                          final ref = reference != null &&
                                  i < reference.trapSpeedsMps.length
                              ? reference.trapSpeedsMps[i]
                              : null;
                          return formatDeltaSpeedMps(
                            current != null && ref != null
                                ? current - ref
                                : null,
                          );
                        }(),
                        style: TextStyle(
                          color: speedDeltaColor(
                            scheme,
                            currentValue: i < lap.trapSpeedsMps.length
                                ? lap.trapSpeedsMps[i]
                                : null,
                            referenceValue: reference != null &&
                                    i < reference.trapSpeedsMps.length
                                ? reference.trapSpeedsMps[i]
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
