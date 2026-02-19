import 'package:flutter/material.dart';
import 'package:speed_data/features/models/lap_analysis_model.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_formatters.dart';

class LapTimesHighLowTable extends StatelessWidget {
  final List<LapAnalysisModel> laps;

  const LapTimesHighLowTable({
    super.key,
    required this.laps,
  });

  @override
  Widget build(BuildContext context) {
    if (laps.isEmpty) {
      return const Center(child: Text('No speed profile data available'));
    }

    final sorted = List<LapAnalysisModel>.from(laps)
      ..sort((a, b) => b.number.compareTo(a.number));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Lap')),
            DataColumn(label: Text('Low')),
            DataColumn(label: Text('High')),
            DataColumn(label: Text('Avg')),
            DataColumn(label: Text('Range')),
          ],
          rows: [
            for (final lap in sorted)
              DataRow(
                cells: [
                  DataCell(Text('L${lap.number}')),
                  DataCell(Text(formatSpeedMps(deriveSpeedLow(lap)))),
                  DataCell(Text(formatSpeedMps(deriveSpeedHigh(lap)))),
                  DataCell(Text(formatSpeedMps(deriveSpeedAvg(lap)))),
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

  String _formatRange(double? low, double? high) {
    if (low == null || high == null || high < low) return '-';
    return '${(high - low).toStringAsFixed(1)} m/s';
  }
}
