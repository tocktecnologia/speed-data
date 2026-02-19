import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:speed_data/features/models/crossing_model.dart';
import 'package:speed_data/features/models/lap_analysis_model.dart';
import 'package:speed_data/features/models/session_analysis_summary_model.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_formatters.dart';

class LapTimesInformationPanel extends StatelessWidget {
  final List<LapAnalysisModel> laps;
  final List<CrossingModel> crossings;
  final SessionAnalysisSummaryModel? summary;
  final int minLapTimeMs;

  const LapTimesInformationPanel({
    super.key,
    required this.laps,
    required this.crossings,
    this.summary,
    this.minLapTimeMs = 0,
  });

  @override
  Widget build(BuildContext context) {
    final sortedCrossings = sortCrossingsByTime(crossings);
    final validLaps = laps
        .where((lap) => isLapValid(lap, minLapTimeMs: minLapTimeMs))
        .toList(growable: false);
    final bestLap = selectReferenceLap(laps, minLapTimeMs: minLapTimeMs);
    final avgLapMs = validLaps.isEmpty
        ? null
        : validLaps.fold<int>(0, (sum, lap) => sum + lap.totalLapTimeMs) ~/
            validLaps.length;
    final allTrapSpeeds =
        laps.expand((lap) => lap.trapSpeedsMps).where((v) => v > 0).toList();
    final topTrap =
        allTrapSpeeds.isEmpty ? null : allTrapSpeeds.reduce(math.max);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildInfoCard(
          context,
          title: 'Session Summary',
          lines: [
            'Best lap: ${formatDurationMs(summary?.bestLapMs ?? bestLap?.totalLapTimeMs)}',
            'Optimal lap: ${formatDurationMs(summary?.optimalLapMs)}',
            'Valid laps: ${summary?.validLapsCount ?? validLaps.length}',
            'Total laps: ${summary?.totalLapsCount ?? laps.length}',
          ],
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          context,
          title: 'Lap Statistics',
          lines: [
            'Average valid lap: ${formatDurationMs(avgLapMs)}',
            'Best lap number: ${bestLap?.number ?? '-'}',
            'Fastest trap speed: ${formatSpeedMps(topTrap)}',
            'Crossings recorded: ${crossings.length}',
          ],
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          context,
          title: 'Crossing Snapshot',
          lines: [
            'First crossing: ${_formatCrossingTime(sortedCrossings.isEmpty ? null : sortedCrossings.first.crossedAtMs)}',
            'Last crossing: ${_formatCrossingTime(sortedCrossings.isEmpty ? null : sortedCrossings.last.crossedAtMs)}',
            'Unique checkpoints: ${_countUniqueCheckpoints(crossings)}',
          ],
        ),
      ],
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required String title,
    required List<String> lines,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(line),
              ),
          ],
        ),
      ),
    );
  }

  String _formatCrossingTime(int? crossedAtMs) {
    if (crossedAtMs == null || crossedAtMs <= 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(crossedAtMs).toLocal();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    final ms = dt.millisecond.toString().padLeft(3, '0');
    return '$hh:$mm:$ss.$ms';
  }

  int _countUniqueCheckpoints(List<CrossingModel> values) {
    return values.map((c) => c.checkpointIndex).toSet().length;
  }
}
