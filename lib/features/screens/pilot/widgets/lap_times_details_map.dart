import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:speed_data/features/models/crossing_model.dart';
import 'package:speed_data/features/models/lap_analysis_model.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_formatters.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_types.dart';

class LapTimesDetailsMap extends StatelessWidget {
  final LapTimesMode mode;
  final LapAnalysisModel selectedLap;
  final LapAnalysisModel? comparisonLap;
  final List<CrossingModel> crossings;

  const LapTimesDetailsMap({
    super.key,
    required this.mode,
    required this.selectedLap,
    required this.crossings,
    this.comparisonLap,
  });

  @override
  Widget build(BuildContext context) {
    final selectedCrossings = _lapCrossings(selectedLap.number);
    if (selectedCrossings.length < 2) {
      return const Center(
        child: Text('Not enough crossing points to render details map'),
      );
    }

    final comparisonCrossings = comparisonLap != null
        ? _lapCrossings(comparisonLap!.number)
        : const <CrossingModel>[];
    final comparisonByCheckpoint = {
      for (final c in comparisonCrossings) c.checkpointIndex: c,
    };

    final polylines = <Polyline>{
      if (comparisonCrossings.length >= 2)
        Polyline(
          polylineId: const PolylineId('comparison'),
          points: comparisonCrossings
              .map((c) => LatLng(c.lat, c.lng))
              .toList(growable: false),
          color: Colors.black.withValues(alpha: 0.35),
          width: 5,
          geodesic: true,
        ),
      ..._buildSelectedPolylines(selectedCrossings, comparisonByCheckpoint),
    };

    final markers = <Marker>{
      for (final crossing in selectedCrossings)
        Marker(
          markerId: MarkerId('selected_cp_${crossing.checkpointIndex}'),
          position: LatLng(crossing.lat, crossing.lng),
          infoWindow: InfoWindow(
            title: 'CP ${crossing.checkpointIndex}',
            snippet: 'L${selectedLap.number}',
          ),
        ),
    };

    final cameraTarget =
        LatLng(selectedCrossings.first.lat, selectedCrossings.first.lng);

    return Stack(
      children: [
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: cameraTarget,
              zoom: 16,
            ),
            myLocationEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            zoomControlsEnabled: false,
            markers: markers,
            polylines: polylines,
          ),
        ),
        Positioned(
          left: 8,
          right: 8,
          top: 8,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                'Details: ${mode.label} | Lap ${selectedLap.number}'
                '${comparisonLap != null ? ' vs Lap ${comparisonLap!.number}' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<CrossingModel> _lapCrossings(int lapNumber) {
    final values = crossings.where((c) => c.lapNumber == lapNumber).toList();
    values.sort((a, b) => a.crossedAtMs.compareTo(b.crossedAtMs));
    return values;
  }

  Set<Polyline> _buildSelectedPolylines(
    List<CrossingModel> selected,
    Map<int, CrossingModel> comparisonByCheckpoint,
  ) {
    final result = <Polyline>{};
    for (int i = 1; i < selected.length; i++) {
      final a = selected[i - 1];
      final b = selected[i];
      final color = _segmentColor(
        a,
        b,
        comparisonByCheckpoint[b.checkpointIndex],
      );
      result.add(
        Polyline(
          polylineId:
              PolylineId('seg_${a.checkpointIndex}_${b.checkpointIndex}_$i'),
          points: [LatLng(a.lat, a.lng), LatLng(b.lat, b.lng)],
          color: color,
          width: 7,
          geodesic: true,
        ),
      );
    }
    return result;
  }

  Color _segmentColor(
    CrossingModel from,
    CrossingModel to,
    CrossingModel? comparisonCheckpoint,
  ) {
    switch (mode) {
      case LapTimesMode.sectors:
        final current = to.sectorTimeMs;
        final reference = comparisonCheckpoint?.sectorTimeMs;
        if (current == null || reference == null) {
          return Colors.blueGrey;
        }
        return current <= reference ? Colors.green : Colors.red;
      case LapTimesMode.splits:
        final confidence = to.confidence;
        if (confidence >= 0.85) return Colors.green;
        if (confidence >= 0.65) return Colors.yellow.shade700;
        if (confidence >= 0.45) return Colors.orange;
        return Colors.red;
      case LapTimesMode.trapSpeeds:
        return speedGradientColor(to.speedMps);
      case LapTimesMode.highLow:
        final dtMs = (to.crossedAtMs - from.crossedAtMs).clamp(1, 3600000);
        final accel = (to.speedMps - from.speedMps) / (dtMs / 1000.0);
        if (accel > 0.2) return Colors.green;
        if (accel < -0.2) return Colors.red;
        return Colors.grey;
      case LapTimesMode.information:
        return Colors.blue;
    }
  }
}
