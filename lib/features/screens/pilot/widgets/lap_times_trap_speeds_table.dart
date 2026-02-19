import 'package:flutter/material.dart';
import 'package:speed_data/features/models/lap_analysis_model.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_formatters.dart';

class LapTimesTrapSpeedsTable extends StatelessWidget {
  final List<LapAnalysisModel> laps;
  final int minLapTimeMs;

  const LapTimesTrapSpeedsTable({
    super.key,
    required this.laps,
    this.minLapTimeMs = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (laps.isEmpty) {
      return const Center(child: Text('No trap speed data available'));
    }

    final sorted = List<LapAnalysisModel>.from(laps)
      ..sort((a, b) => b.number.compareTo(a.number));
    final reference = selectReferenceLap(sorted, minLapTimeMs: minLapTimeMs);
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
                color: WidgetStatePropertyAll(
                  isLapValid(lap, minLapTimeMs: minLapTimeMs)
                      ? Colors.transparent
                      : scheme.error.withValues(alpha: 0.08),
                ),
                cells: [
                  DataCell(Text('L${lap.number}')),
                  DataCell(
                    Text(formatSpeedMps(deriveSpeedHigh(lap))),
                  ),
                  for (int i = 0; i < maxTrapCount; i++)
                    DataCell(
                      Text(
                        i < lap.trapSpeedsMps.length
                            ? formatSpeedMps(lap.trapSpeedsMps[i])
                            : '-',
                        style: TextStyle(
                          color: _trapDeltaColor(
                            scheme: scheme,
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

  Color _trapDeltaColor({
    required ColorScheme scheme,
    required double? currentValue,
    required double? referenceValue,
  }) {
    if (currentValue == null || referenceValue == null) {
      return scheme.onSurface;
    }
    if (currentValue <= 0 || referenceValue <= 0) {
      return scheme.onSurfaceVariant;
    }
    if (currentValue >= referenceValue) {
      return Colors.green.shade400;
    }
    return Colors.red.shade400;
  }
}
