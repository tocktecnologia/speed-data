import 'package:flutter/material.dart';
import 'package:speed_data/features/models/lap_analysis_model.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_formatters.dart';

class LapTimesSplitsTable extends StatelessWidget {
  final List<LapAnalysisModel> laps;
  final int minLapTimeMs;

  const LapTimesSplitsTable({
    super.key,
    required this.laps,
    this.minLapTimeMs = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (laps.isEmpty) {
      return const Center(child: Text('No split data available'));
    }

    final sorted = List<LapAnalysisModel>.from(laps)
      ..sort((a, b) => b.number.compareTo(a.number));
    final reference = selectReferenceLap(sorted, minLapTimeMs: minLapTimeMs);
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
                color: WidgetStatePropertyAll(
                  isLapValid(lap, minLapTimeMs: minLapTimeMs)
                      ? Colors.transparent
                      : scheme.error.withValues(alpha: 0.08),
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
                  DataCell(Text(formatDurationMs(lap.totalLapTimeMs))),
                  for (int i = 0; i < maxSplitCount; i++)
                    DataCell(
                      Text(
                        i < lap.splitsMs.length
                            ? formatDurationMs(lap.splitsMs[i])
                            : '-',
                        style: TextStyle(
                          color: _splitDeltaColor(
                            scheme: scheme,
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

  Color _splitDeltaColor({
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
