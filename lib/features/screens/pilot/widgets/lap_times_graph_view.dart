import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:speed_data/features/models/lap_analysis_model.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_types.dart';

class LapTimesGraphView extends StatelessWidget {
  final LapTimesMode mode;
  final LapAnalysisModel selectedLap;
  final LapAnalysisModel? comparisonLap;
  final LapTimesResultMode resultMode;

  const LapTimesGraphView({
    super.key,
    required this.mode,
    required this.selectedLap,
    this.comparisonLap,
    this.resultMode = LapTimesResultMode.absolute,
  });

  @override
  Widget build(BuildContext context) {
    final selectedSeries = _seriesForLap(selectedLap);
    final comparisonSeries = comparisonLap != null
        ? _seriesForLap(comparisonLap!)
        : const <double>[];
    if (selectedSeries.isEmpty) {
      return const Center(child: Text('No graph data available for this lap'));
    }

    final chartSelected = _applyResultMode(
      selectedSeries,
      reference: comparisonSeries,
    );
    final chartComparison = resultMode == LapTimesResultMode.absolute
        ? comparisonSeries
        : List<double>.filled(chartSelected.length, 0.0);
    final maxX = math
            .max(
              chartSelected.length,
              chartComparison.length,
            )
            .toDouble() -
        1;
    final allValues = [...chartSelected, ...chartComparison];
    final minY = allValues.reduce(math.min);
    final maxY = allValues.reduce(math.max);
    final yPadding = (maxY - minY).abs() * 0.1 + 1;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              'Graph: Lap ${selectedLap.number}'
              '${comparisonLap != null ? ' vs Lap ${comparisonLap!.number}' : ''}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: minY - yPadding,
                maxY: maxY + yPadding,
                minX: 0,
                maxX: math.max(0, maxX),
                gridData: const FlGridData(show: true),
                borderData: FlBorderData(show: true),
                lineTouchData: const LineTouchData(enabled: true),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _xLabel(idx),
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      getTitlesWidget: (value, meta) => Text(
                        value.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: _spotsFromSeries(chartSelected),
                    isCurved: false,
                    barWidth: 3,
                    color: Theme.of(context).colorScheme.primary,
                    dotData: const FlDotData(show: false),
                  ),
                  if (chartComparison.isNotEmpty)
                    LineChartBarData(
                      spots: _spotsFromSeries(chartComparison),
                      isCurved: false,
                      barWidth: 2,
                      color: Theme.of(context)
                          .colorScheme
                          .secondary
                          .withValues(alpha: 0.55),
                      dotData: const FlDotData(show: false),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          _buildLegend(context),
        ],
      ),
    );
  }

  Widget _buildLegend(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart,
                size: 14, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 4),
            Text('Selected', style: baseStyle),
          ],
        ),
        if (comparisonLap != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.show_chart,
                size: 14,
                color: Theme.of(context)
                    .colorScheme
                    .secondary
                    .withValues(alpha: 0.7),
              ),
              const SizedBox(width: 4),
              Text('Comparison', style: baseStyle),
            ],
          ),
      ],
    );
  }

  List<double> _seriesForLap(LapAnalysisModel lap) {
    switch (mode) {
      case LapTimesMode.sectors:
        return lap.sectorsMs.map((v) => v.toDouble()).toList(growable: false);
      case LapTimesMode.splits:
        return lap.splitsMs.map((v) => v.toDouble()).toList(growable: false);
      case LapTimesMode.trapSpeeds:
        return lap.trapSpeedsMps.toList(growable: false);
      case LapTimesMode.highLow:
        if (lap.trapSpeedsMps.isNotEmpty) {
          return lap.trapSpeedsMps.toList(growable: false);
        }
        final low = lap.speedStats?.minMps ?? 0;
        final avg = lap.speedStats?.avgMps ?? 0;
        final high = lap.speedStats?.maxMps ?? 0;
        return [low, avg, high];
      case LapTimesMode.information:
        return [lap.totalLapTimeMs.toDouble()];
    }
  }

  List<double> _applyResultMode(
    List<double> values, {
    required List<double> reference,
  }) {
    if (resultMode == LapTimesResultMode.absolute || reference.isEmpty) {
      return values;
    }
    final maxLen = math.max(values.length, reference.length);
    return List<double>.generate(maxLen, (i) {
      final current = i < values.length ? values[i] : 0.0;
      final ref = i < reference.length ? reference[i] : 0.0;
      return current - ref;
    });
  }

  List<FlSpot> _spotsFromSeries(List<double> values) {
    final result = <FlSpot>[];
    for (int i = 0; i < values.length; i++) {
      result.add(FlSpot(i.toDouble(), values[i]));
    }
    return result;
  }

  String _xLabel(int index) {
    if (index < 0) return '';
    switch (mode) {
      case LapTimesMode.sectors:
        return 'S${index + 1}';
      case LapTimesMode.splits:
        return 'SP${index + 1}';
      case LapTimesMode.trapSpeeds:
        return 'TP${index + 1}';
      case LapTimesMode.highLow:
        return 'P${index + 1}';
      case LapTimesMode.information:
        return 'Lap';
    }
  }
}
