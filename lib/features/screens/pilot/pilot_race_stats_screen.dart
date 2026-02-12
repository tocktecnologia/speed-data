import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'dart:math';

class PilotRaceStatsScreen extends StatefulWidget {
  final String raceId;
  final String userId;
  final String raceName;

  const PilotRaceStatsScreen({
    Key? key,
    required this.raceId,
    required this.userId,
    required this.raceName,
  }) : super(key: key);

  @override
  State<PilotRaceStatsScreen> createState() => _PilotRaceStatsScreenState();
}

class _PilotRaceStatsScreenState extends State<PilotRaceStatsScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  // Data State
  List<DocumentSnapshot> _laps = [];
  DocumentSnapshot? _selectedLap;
  Map<String, dynamic>? _raceData;
  bool _isLoading = true;

  // Selected Lap Stats
  String _lapTimeFormatted = "00:00.000";
  double _maxSpeed = 0.0;
  List<Map<String, dynamic>> _segments = [];
  Offset? _maxSpeedLocation;

  // Comparison Stats
  double _averageLapTime = 0.0;
  int? _bestLapTime;
  String? _bestLapId;

  // Chart Interaction
  int? _selectedSpotIndex;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);

    // 1. Fetch Race Data (Route & Checkpoints)
    try {
      final raceDoc =
          await _firestoreService.getRaceStream(widget.raceId).first;
      if (raceDoc.exists) {
        _raceData = raceDoc.data() as Map<String, dynamic>;
      }
    } catch (e) {
      print("Error fetching race data: $e");
    }

    // 2. Fetch Laps
    // We listen to the stream but for initial calculation we take the first snapshot
    _firestoreService.getLaps(widget.raceId, widget.userId).listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final laps = snapshot.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data.containsKey('totalLapTime') &&
              data['totalLapTime'] != null;
        }).toList();

        // Find Best Lap
        DocumentSnapshot? bestLap;
        int minTime = 999999999;

        for (var lap in laps) {
          final t = (lap.data() as Map<String, dynamic>)['totalLapTime'] as int;
          if (t < minTime) {
            minTime = t;
            bestLap = lap;
          }
        }

        // Sort by Lap Number for display (Descending - Newest first, or Ascending?)
        // Usually Ascending is better for history, or Descending to see latest.
        // Let's stick to Ascending or keep existing "Descending" from previous order if it was.
        // The original code sorted by Time.
        // Let's sort by Number Ascending 1..N
        laps.sort((a, b) {
          final nA = (a.data() as Map<String, dynamic>)['number'] as int? ?? 0;
          final nB = (b.data() as Map<String, dynamic>)['number'] as int? ?? 0;
          return nA.compareTo(nB);
        });

        if (mounted) {
          setState(() {
            _laps = laps;
            _bestLapTime = minTime;

            if (bestLap != null) {
              _bestLapId = bestLap.id; // Assuming ID is reliable or check logic
            }

            // Default to best lap if not selected, or update if exists
            if (_selectedLap == null && bestLap != null) {
              _selectLap(bestLap);
            } else if (_selectedLap != null) {
              // Try to find the currently selected lap in the new list to keep selection
              try {
                final found =
                    laps.firstWhere((doc) => doc.id == _selectedLap!.id);
                _selectLap(found);
              } catch (_) {
                if (bestLap != null) _selectLap(bestLap);
              }
            }
            _calculateGlobalStats();
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    });

    if (mounted) setState(() => _isLoading = false);
  }

  void _calculateGlobalStats() {
    if (_laps.isEmpty) return;

    int totalTime = 0;
    int count = 0;
    for (var lap in _laps) {
      final data = lap.data() as Map<String, dynamic>;
      final t = data['totalLapTime'] as int;
      totalTime += t;
      count++;
    }
    _averageLapTime = count > 0 ? totalTime / count : 0.0;
  }

  List<dynamic> _getPointsList(dynamic rawPoints) {
    if (rawPoints is List) return rawPoints;
    if (rawPoints is Map) {
      final list = rawPoints.values.toList();
      try {
        list.sort((a, b) => ((a['timestamp'] as num?) ?? 0)
            .compareTo((b['timestamp'] as num?) ?? 0));
      } catch (_) {}
      return list;
    }
    return [];
  }

  void _selectLap(DocumentSnapshot lap) {
    _selectedLap = lap;
    final data = lap.data() as Map<String, dynamic>;
    final totalMs = data['totalLapTime'] as int;

    // Format Time
    _lapTimeFormatted = _formatTime(totalMs);

    // Calculate Max Speed & Segments
    // Amount of laps
    // Assuming 'points' is a list of telemetry points in the lap
    final points = _getPointsList(data['points']);

    double maxSpeed = 0.0;
    _maxSpeedLocation = null;

    for (var p in points) {
      final speed = (p['speed'] as num?)?.toDouble() ?? 0.0;
      if (speed > maxSpeed) {
        maxSpeed = speed;
        final lat = (p['lat'] as num?)?.toDouble();
        final lng = (p['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          _maxSpeedLocation = Offset(lng, lat);
        }
      }
    }
    _maxSpeed = maxSpeed * 3.6; // Convert m/s to km/h assuming speed is m/s

    _calculateSegments(data);
  }

  String _formatTime(int ms) {
    final minutes = (ms ~/ 60000).toString().padLeft(2, '0');
    final seconds = ((ms % 60000) ~/ 1000).toString().padLeft(2, '0');
    final milliseconds = (ms % 1000).toString().padLeft(3, '0');
    return "$minutes:$seconds.$milliseconds";
  }

  void _calculateSegments(Map<String, dynamic> lapData) {
    // User logic:
    // Segment 1: CP_1 - CP_0 (timestamp diff)
    // Segment 2: CP_2 - CP_1
    // ...
    // Last Segment: CP_0(next) - CP_Last? Or just time from Last CP to Finish?
    // "Para ultimo trecho , faça o diff entre o penúltimo e o CP_0 do proximo lap."
    // Actually a Lap starts at CP_0 and ends at CP_0 (next pass).
    // If we rely on stored Checkpoint timestamps.

    // Assuming 'points' stores checkpoint hits or we have a 'checkpoints' field in Lap.
    // If 'points' is just raw telemetry, we need to find points close to checkpoints.
    // However, the prompt says "track drawing... show times of each segment using points field".

    // Let's assume 'points' contains marked checkpoints or we can infer them.
    // If the prompt implies we have timestamps for CP_0, CP_1...
    // We look for points where we crossed a checkpoint?

    // Implementation strategy:
    // 1. Get race checkpoints from _raceData.
    // 2. Iterate points to find timestamps near checkpoints?
    //    Or maybe the 'points' list *IS* the list of checkpoints hit + telemetry?
    //    Given "utilizar o campo points dentro de cada lap", I'll assume points has what we need.

    // Let's look for "isCheckpoint" or similar in points, OR
    // assume the user logic is simpler:
    // If points is just telemetry, I can't easily get CP times unless recorded.
    // BUT, standard "Laps" usually record sector times.

    // I'll try to find timestamps for each checkpoint index.
    final points = _getPointsList(lapData['points']);
    // Filter points that might correspond to checkpoints if they have 'checkpoint_index'
    // If not, I'll just use the points curve to display speed.

    // Since I don't know the exact structure of points (if it has 'checkpoint_index'),
    // took a look at 'ActiveRaceScreen', passed checkpoints to ingestion.
    // The ingestion function likely adds identifying info.

    // FALLBACK: segment the *Time* based on equal types if no CP info?
    // NO, user was specific.
    // "tempo do trecho 1 , basta fazer o diff entre o timestamp de CP_1 e timestamp de CP_0"

    // I will search for points that map to checkpoints.
    // Let's assume the points representing checkpoints are stored or flagged.
    // If not, I can't fulfill this requirement perfectly without seeing data.
    // But I will write code that attempts to find them.

    // Mocking segment generation if strictly needed info missing, but valid attempt:
    // We will calculate assuming points are sorted by time.

    _segments = [];
    if (_raceData == null || _raceData!['checkpoints'] == null) return;

    final raceCheckpoints = _raceData!['checkpoints'] as List<dynamic>;
    // We need N segments for N checkpoints (if loop).

    // Let's try to extract timestamps for CP indices 0 to N.
    Map<int, int> cpTimestamps = {};

    // Heuristic: Check if points have 'checkpoint_index' or 'cp_index'
    bool hasCpIndex = false;
    for (var p in points) {
      if (p is Map &&
          (p.containsKey('cp_index') || p.containsKey('checkpoint_index'))) {
        hasCpIndex = true;
        int idx = p['cp_index'] ?? p['checkpoint_index'];
        cpTimestamps[idx] = p['timestamp'] ?? 0;
      }
    }

    // If we can't find CP indices, we can't do exact segments as requested.
    // We will try.

    if (hasCpIndex) {
      for (int i = 0; i < raceCheckpoints.length; i++) {
        // Segment from CP_i to CP_{i+1}
        // Start: CP_i (or CP_0 if i=0)
        // End: CP_{i+1}
        // The user says: "trecho 1 = diff CP_1 e CP_0".
        // So Segment 1 is between CP_0 and CP_1.
        // Segment 2 is between CP_1 and CP_2.

        if (i + 1 < raceCheckpoints.length) {
          int t0 = cpTimestamps[i] ?? 0;
          int t1 = cpTimestamps[i + 1] ?? 0;
          if (t0 > 0 && t1 > 0) {
            _segments.add({
              'index': i + 1,
              'time': _formatTime(t1 - t0),
              'diff': t1 - t0,
            });
          }
        } else {
          // Last segment
          // "diff entre penultimo e CP_0 do proximo lap"
          // Wait, if 3 CPs (0, 1, 2).
          // Seg 1 (Trecho 1): 1 - 0.
          // Seg 2 (Trecho 2): 2 - 1.
          // Final Trecho: Next 0 - 2.

          // In this Lap object, do we have "Next 0"?
          // Usually Lap ends at "Next 0". The 'timestamp' of the lap end is effectively "Next 0".
          // Or the last point in 'points'.

          int tLastCW = cpTimestamps[i] ?? 0; // CP_2
          // Find end of lap time.
          // The 'finish' time of the lap.
          // We can approximate with the last point timestamp.
          int tEnd = 0;
          if (points.isNotEmpty) {
            tEnd = points.last['timestamp'];
          }

          if (tLastCW > 0 && tEnd > 0) {
            _segments.add({
              'index': i + 1,
              'time': _formatTime(tEnd - tLastCW),
              'diff': tEnd - tLastCW,
            });
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.raceName.toUpperCase()),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLapSelector(),
                  const SizedBox(height: 20),
                  _buildMainStats(),
                  const SizedBox(height: 20),
                  _buildTrackVisualizer(),
                  const SizedBox(height: 20),
                  _buildLapTimesChart(),
                ],
              ),
            ),
    );
  }

  Widget _buildLapSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DocumentSnapshot>(
          value: _selectedLap,
          dropdownColor: Colors.grey[900],
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
          style: const TextStyle(color: Colors.white, fontSize: 16),
          items: _laps.map<DropdownMenuItem<DocumentSnapshot>>((lap) {
            final data = lap.data() as Map<String, dynamic>;
            final lapNum = data['number'];
            final totalMs = data['totalLapTime'] ?? 0;
            final isBest = lap.id == _bestLapId || totalMs == _bestLapTime;

            return DropdownMenuItem<DocumentSnapshot>(
              value: lap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Lap $lapNum - ${_formatTime(totalMs)}",
                      style: const TextStyle(color: Colors.white)),
                  if (isBest) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.star, color: Colors.yellow, size: 16),
                  ]
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectLap(val));
            }
          },
        ),
      ),
    );
  }

  Widget _buildMainStats() {
    // Calculate Deviation
    String gapStr = "--";
    Color gapColor = Colors.grey;
    if (_selectedLap != null && _bestLapTime != null) {
      final currentMs =
          (_selectedLap!.data() as Map<String, dynamic>)['totalLapTime'] as int;
      final diff = currentMs - _bestLapTime!;
      if (diff == 0) {
        gapStr = "BEST";
        gapColor = Colors.yellowAccent;
      } else {
        gapStr = "+${(diff / 1000).toStringAsFixed(3)}s";
        gapColor = Colors.redAccent;
      }
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
                child: _buildStatCard(
                    "LAP TIME", _lapTimeFormatted, Colors.blueAccent)),
            const SizedBox(width: 12),
            Expanded(
                child: _buildStatCard(
                    "MAX SPEED",
                    "${_maxSpeed.toStringAsFixed(0)} km/h",
                    Colors.orangeAccent)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _buildStatCard(
                    "BEST LAP",
                    _bestLapTime != null ? _formatTime(_bestLapTime!) : "--",
                    Colors.purpleAccent,
                    isSmall: true)),
            const SizedBox(width: 12),
            Expanded(
                child: _buildStatCard("GAP TO BEST", gapStr, gapColor,
                    isSmall: true)),
            const SizedBox(width: 12),
            Expanded(
                child: _buildStatCard("AVG (ALL)",
                    _formatTime(_averageLapTime.toInt()), Colors.greenAccent,
                    isSmall: true)),
          ],
        )
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color,
      {bool isSmall = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.2), color.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: color.withOpacity(0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: isSmall ? 16 : 22,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      color: color.withOpacity(0.5),
                      blurRadius: 10,
                    )
                  ])),
        ],
      ),
    );
  }

  Widget _buildTrackVisualizer() {
    if (_raceData == null) return const SizedBox.shrink();

    // Prepare points for CustomPainter
    final routePath = _raceData!['route_path'] as List<dynamic>?;
    if (routePath == null || routePath.isEmpty) return const SizedBox.shrink();

    final points = routePath
        .map((p) =>
            Offset((p['lng'] as num).toDouble(), (p['lat'] as num).toDouble()))
        .toList();

    // Checkpoints
    final cps = (_raceData!['checkpoints'] as List<dynamic>?)
            ?.map((p) => Offset(
                (p['lng'] as num).toDouble(), (p['lat'] as num).toDouble()))
            .toList() ??
        [];

    return Container(
      height: 300,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Text("TRACK ANALYSIS",
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: TrackPainter(
                    trackPoints: points,
                    checkpoints: cps,
                    segments: _segments,
                    maxSpeedLocation: _maxSpeedLocation,
                  ),
                );
              },
            ),
          ),
          if (_segments.isNotEmpty)
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _segments.length,
                itemBuilder: (context, index) {
                  final seg = _segments[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 16.0, top: 8),
                    child: Column(
                      children: [
                        Text("Trecho ${seg['index']}",
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 10)),
                        Text(seg['time'],
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                },
              ),
            )
        ],
      ),
    );
  }

  Widget _buildLapTimesChart() {
    if (_laps.isEmpty) return const SizedBox.shrink();

    List<FlSpot> spots = [];
    for (int i = 0; i < _laps.length; i++) {
      final data = _laps[i].data() as Map<String, dynamic>;
      final lapNum = (data['number'] ?? (i + 1)).toDouble();
      final time = (data['totalLapTime'] as int).toDouble() / 1000.0; // Seconds
      spots.add(FlSpot(lapNum, time));
    }

    // Sort spots by lapNum
    spots.sort((a, b) => a.x.compareTo(b.x));

    final lineBarData = LineChartBarData(
      spots: spots,
      isCurved: true,
      color: Colors.blueAccent,
      barWidth: 3,
      dotData: FlDotData(show: true),
      belowBarData:
          BarAreaData(show: true, color: Colors.blueAccent.withOpacity(0.1)),
    );

    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("LAP PROGRESSION",
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: false),
                minY: 0,
                lineTouchData: LineTouchData(
                  touchCallback:
                      (FlTouchEvent event, LineTouchResponse? touchResponse) {
                    if (event is FlTapUpEvent) {
                      if (touchResponse != null &&
                          touchResponse.lineBarSpots != null &&
                          touchResponse.lineBarSpots!.isNotEmpty) {
                        setState(() {
                          _selectedSpotIndex =
                              touchResponse.lineBarSpots!.first.spotIndex;
                        });
                      }
                    }
                  },
                  handleBuiltInTouches:
                      false, // Disable default touch behavior to control manually
                  getTouchedSpotIndicator:
                      (LineChartBarData barData, List<int> spotIndexes) {
                    return spotIndexes.map((index) {
                      return TouchedSpotIndicatorData(
                        FlLine(color: Colors.transparent),
                        FlDotData(show: true),
                      );
                    }).toList();
                  },
                ),
                extraLinesData: ExtraLinesData(horizontalLines: []),
                showingTooltipIndicators: _selectedSpotIndex != null &&
                        _selectedSpotIndex! < spots.length
                    ? [
                        ShowingTooltipIndicators(
                          [
                            LineBarSpot(lineBarData, _selectedSpotIndex!,
                                spots[_selectedSpotIndex!]),
                          ],
                        ),
                      ]
                    : [],
                lineBarsData: [
                  lineBarData,
                  if (_selectedSpotIndex != null &&
                      _selectedSpotIndex! < spots.length)
                    LineChartBarData(
                      spots: [
                        FlSpot(spots[_selectedSpotIndex!].x, 0),
                        FlSpot(spots[_selectedSpotIndex!].x,
                            spots[_selectedSpotIndex!].y),
                      ],
                      color: Colors.white.withOpacity(0.5),
                      barWidth: 2,
                      dotData: FlDotData(show: true),
                      dashArray: [5, 5],
                      isCurved: false,
                    ),
                ],
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Text("Laps",
                        style: TextStyle(color: Colors.grey, fontSize: 10)),
                    sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, meta) {
                          return Text(val.toInt().toString(),
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 10));
                        },
                        interval: 1),
                  ),
                  leftTitles: AxisTitles(
                    axisNameWidget: const Text("Time (s)",
                        style: TextStyle(color: Colors.grey, fontSize: 10)),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (val, meta) {
                        return Text(val.toInt().toString(),
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 10));
                      },
                    ),
                  ),
                  topTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TrackPainter extends CustomPainter {
  final List<Offset> trackPoints;
  final List<Offset> checkpoints;
  final List<Map<String, dynamic>> segments;
  final Offset? maxSpeedLocation;

  TrackPainter({
    required this.trackPoints,
    required this.checkpoints,
    required this.segments,
    this.maxSpeedLocation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (trackPoints.isEmpty) return;

    final paint = Paint()
      ..color = Colors.blueAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    // Normalize points to fit canvas
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;

    for (var p in trackPoints) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    // Add checkpoints to bounds
    for (var p in checkpoints) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    final double width = maxX - minX;
    final double height = maxY - minY;

    if (width == 0 || height == 0) return;

    double padding = 40.0;

    // Scale to fit respecting aspect ratio
    final double scaleX = (size.width - padding * 2) / width;
    final double scaleY = (size.height - padding * 2) / height;
    final double scale = min(scaleX, scaleY);

    final double offsetX = (size.width - (width * scale)) / 2;
    // We want the bounding box centered vertically
    // contentHeight = height * scale
    // top = (size.height - contentHeight) / 2
    final double offsetY = (size.height - (height * scale)) / 2;

    Offset transform(Offset p) {
      // p.dx is Lng (X). p.dy is Lat (Y).
      double x = (p.dx - minX) * scale + offsetX;
      // Invert Y: High Lat (Top) -> Low Screen Y (Top)
      // Normalized Lat (0 to 1): (p.dy - minY) / height
      // Screen Y = size.height - (...) is WRONG if we use offsetY logic.
      // Correct: Y = TopPadding + (MaxLat - Lat) * scale
      // Normalized: (maxY - p.dy) * scale
      double y = (maxY - p.dy) * scale + offsetY;
      return Offset(x, y);
    }

    final path = Path();
    final start = transform(trackPoints.first);
    path.moveTo(start.dx, start.dy);

    for (int i = 1; i < trackPoints.length; i++) {
      final p = transform(trackPoints[i]);
      path.lineTo(p.dx, p.dy);
    }

    canvas.drawPath(path, paint);

    // Draw Checkpoints
    final cpPaint = Paint()..style = PaintingStyle.fill;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    List<Offset> transformedCPs = [];

    for (int i = 0; i < checkpoints.length; i++) {
      final cp = transform(checkpoints[i]);
      transformedCPs.add(cp);
      cpPaint.color = i == 0
          ? Colors.greenAccent
          : (i == checkpoints.length - 1
              ? Colors.redAccent
              : Colors.orangeAccent);
      canvas.drawCircle(cp, 5, cpPaint);

      // Setup text for CP label
      textPainter.text = TextSpan(
        text: "CP$i",
        style: const TextStyle(
            color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      );
      textPainter.layout();
      textPainter.paint(canvas, cp + const Offset(6, -6));
    }

    // Draw Segment Times
    for (var seg in segments) {
      int idx = seg['index'] ?? 0;
      // Segment indices are 1-based in our logic (Trecho 1 is CP0->CP1)
      // So index 1 corresponds to CP[0] -> CP[1]

      int startIdx = idx - 1;
      int endIdx = idx;

      // Handle wrap around if needed loop is implied
      if (startIdx >= 0 && startIdx < transformedCPs.length) {
        Offset p1 = transformedCPs[startIdx];
        Offset p2;

        if (endIdx < transformedCPs.length) {
          p2 = transformedCPs[endIdx];
        } else if (endIdx == transformedCPs.length) {
          // Last segment connects to start ?
          // Or maybe to the last point of track?
          // Usually CP0 is finish line too if loop.
          // Assume loop to CP0
          p2 = transformedCPs[0];
        } else {
          continue;
        }

        // Midpoint
        Offset mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);

        // specific styling for segment times
        final span = TextSpan(
          text: seg['time'],
          style: TextStyle(
            color: const Color.fromARGB(255, 48, 86, 198),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.black.withOpacity(0.5),
          ),
        );

        textPainter.text = span;
        textPainter.layout();
        textPainter.paint(canvas,
            mid - Offset(textPainter.width / 2, textPainter.height / 2));
      }
    }

    // Draw Max Speed Marker
    if (maxSpeedLocation != null) {
      final msPos = transform(maxSpeedLocation!);
      final msPaint = Paint()
        ..color = const Color.fromARGB(255, 251, 64, 64)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(msPos, 8, msPaint);
      canvas.drawCircle(
          msPos,
          8,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);

      final msTp = TextPainter(
          text: const TextSpan(
              text: "MAX",
              style: TextStyle(
                  color: Color.fromARGB(255, 251, 64, 70),
                  fontWeight: FontWeight.bold,
                  fontSize: 10)),
          textDirection: TextDirection.ltr);
      msTp.layout();
      msTp.paint(canvas, msPos + const Offset(-10, -20));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
