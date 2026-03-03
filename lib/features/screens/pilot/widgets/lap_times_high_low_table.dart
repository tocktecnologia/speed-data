import 'package:flutter/material.dart';
import 'package:speed_data/features/models/lap_analysis_model.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_formatters.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_types.dart';

class LapTimesHighLowTable extends StatelessWidget {
  final List<LapAnalysisModel> laps;
  final LapAnalysisModel? comparisonLap;
  final String? selectedLapId;
  final LapTimesResultMode resultMode;
  final ValueChanged<LapAnalysisModel>? onSelectLap;

  const LapTimesHighLowTable({
    super.key,
    required this.laps,
    this.comparisonLap,
    this.selectedLapId,
    this.resultMode = LapTimesResultMode.absolute,
    this.onSelectLap,
  });

  @override
  Widget build(BuildContext context) {
    if (laps.isEmpty) {
      return const Center(child: Text('No speed profile data available'));
    }

    final sorted = List<LapAnalysisModel>.from(laps)
      ..sort((a, b) => b.number.compareTo(a.number));
    final reference = comparisonLap ?? selectReferenceLap(sorted);
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Lap')),
            DataColumn(label: Text('Low (km/h)')),
            DataColumn(label: Text('High (km/h)')),
            DataColumn(label: Text('Avg (km/h)')),
            DataColumn(label: Text('Range (km/h)')),
          ],
          rows: [
            for (final lap in sorted)
              DataRow(
                onSelectChanged:
                    onSelectLap == null ? null : (_) => onSelectLap!(lap),
                color: WidgetStatePropertyAll(
                  () {
                    final isComparison =
                        reference != null && reference.id == lap.id;
                    final isSelected =
                        selectedLapId != null && selectedLapId == lap.id;
                    if (isSelected) {
                      return scheme.primaryContainer.withValues(alpha: 0.16);
                    }
                    if (isComparison) {
                      return Colors.blue.withValues(alpha: 0.10);
                    }
                    return Colors.transparent;
                  }(),
                ),
                cells: [
                  DataCell(Text('L${lap.number}')),
                  DataCell(
                    Text(
                      _formatSpeedMetric(
                        current: deriveSpeedLow(lap),
                        reference: reference != null
                            ? deriveSpeedLow(reference)
                            : null,
                      ),
                      style: TextStyle(
                        color: speedDeltaColor(
                          scheme,
                          currentValue: deriveSpeedLow(lap),
                          referenceValue: reference != null
                              ? deriveSpeedLow(reference)
                              : null,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      _formatSpeedMetric(
                        current: deriveSpeedHigh(lap),
                        reference: reference != null
                            ? deriveSpeedHigh(reference)
                            : null,
                      ),
                      style: TextStyle(
                        color: speedDeltaColor(
                          scheme,
                          currentValue: deriveSpeedHigh(lap),
                          referenceValue: reference != null
                              ? deriveSpeedHigh(reference)
                              : null,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      _formatSpeedMetric(
                        current: deriveSpeedAvg(lap),
                        reference: reference != null
                            ? deriveSpeedAvg(reference)
                            : null,
                      ),
                      style: TextStyle(
                        color: speedDeltaColor(
                          scheme,
                          currentValue: deriveSpeedAvg(lap),
                          referenceValue: reference != null
                              ? deriveSpeedAvg(reference)
                              : null,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      _formatRange(
                        deriveSpeedLow(lap),
                        deriveSpeedHigh(lap),
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

  String _formatSpeedMetric({double? current, double? reference}) {
    if (resultMode == LapTimesResultMode.absolute) {
      return formatSpeedMps(current);
    }
    if (current == null || reference == null) {
      return '-';
    }
    return formatDeltaSpeedMps(current - reference);
  }

  String _formatRange(double? low, double? high) {
    if (low == null || high == null || high < low) return '-';
    final rangeKmh = (high - low) * 3.6;
    return rangeKmh.toStringAsFixed(1);
  }
}
