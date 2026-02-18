import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speed_data/features/models/lap_analysis_model.dart';
import 'package:speed_data/features/models/crossing_model.dart';
import 'package:speed_data/features/models/session_analysis_summary_model.dart';
import 'package:speed_data/features/services/firestore_service.dart';

class LapTimesScreen extends StatefulWidget {
  final String raceId;
  final String userId;
  final String raceName;
  final String? eventId;

  const LapTimesScreen({
    super.key,
    required this.raceId,
    required this.userId,
    required this.raceName,
    this.eventId,
  });

  @override
  State<LapTimesScreen> createState() => _LapTimesScreenState();
}

class _LapTimesScreenState extends State<LapTimesScreen> {
  final FirestoreService _firestore = FirestoreService();
  String? _selectedSessionId; // null = legado

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Lap Times - ${widget.raceName}'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSessionSelector(),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildLapsCard()),
                if (_selectedSessionId != null) ...[
                  Expanded(child: _buildCrossingsCard()),
                  Expanded(child: _buildSummaryCard()),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionSelector() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.getPilotSessions(widget.raceId, widget.userId,
          eventId: widget.eventId),
      builder: (context, snapshot) {
        final items = <DropdownMenuItem<String?>>[
          const DropdownMenuItem(
            value: null,
            child: Text('Sem sessão (legado)'),
          ),
        ];

        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            items.add(DropdownMenuItem(
              value: doc.id,
              child: Text('Sessão: ${doc.id}'),
            ));
          }
          if (_selectedSessionId == null && snapshot.data!.docs.isNotEmpty) {
            _selectedSessionId = snapshot.data!.docs.first.id;
          }
        }

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Text('Sessão:'),
              const SizedBox(width: 12),
              DropdownButton<String?>(
                value: _selectedSessionId,
                items: items,
                onChanged: (v) => setState(() => _selectedSessionId = v),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLapsCard() {
    final lapsStream = _firestore.getLapsModels(
      widget.raceId,
      widget.userId,
      sessionId: _selectedSessionId,
      eventId: widget.eventId,
    );

    return Card(
      margin: const EdgeInsets.all(8),
      child: StreamBuilder<List<LapAnalysisModel>>(
        stream: lapsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final laps = snapshot.data ?? [];
          if (laps.isEmpty) {
            return const Center(child: Text('Nenhuma volta encontrada'));
          }

          return ListView.builder(
            itemCount: laps.length,
            itemBuilder: (context, index) {
              final lap = laps[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: lap.valid ? Colors.green : Colors.red,
                  child: Text(lap.number.toString()),
                ),
                title: Text(_fmtMs(lap.totalLapTimeMs)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Splits: ${_fmtList(lap.splitsMs)}'),
                    Text('Setores: ${_fmtList(lap.sectorsMs)}'),
                    if (lap.trapSpeedsMps.isNotEmpty)
                      Text(
                          'Trap speeds (m/s): ${lap.trapSpeedsMps.map((e) => e.toStringAsFixed(1)).join(", ")}'),
                    if (lap.invalidReasons.isNotEmpty)
                      Text('Inválida: ${lap.invalidReasons.join(", ")}',
                          style: const TextStyle(color: Colors.red)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildCrossingsCard() {
    final stream = _firestore.getSessionCrossings(
      widget.raceId,
      widget.userId,
      _selectedSessionId!,
      eventId: widget.eventId,
    );

    return Card(
      margin: const EdgeInsets.all(8),
      child: StreamBuilder<List<CrossingModel>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final crossings = snapshot.data ?? [];
          if (crossings.isEmpty) {
            return const Center(child: Text('Sem crossings'));
          }
          return ListView.builder(
            itemCount: crossings.length,
            itemBuilder: (context, index) {
              final c = crossings[index];
              return ListTile(
                dense: true,
                title: Text('CP ${c.checkpointIndex} • Lap ${c.lapNumber}'),
                subtitle: Text(
                    't=${_fmtMs(c.crossedAtMs)} | setor=${_fmtMsNullable(c.sectorTimeMs)} | split=${_fmtMsNullable(c.splitTimeMs)} | v=${c.speedMps.toStringAsFixed(1)} m/s'),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard() {
    final stream = _firestore.getSessionAnalysisSummary(
      widget.raceId,
      widget.userId,
      _selectedSessionId!,
      eventId: widget.eventId,
    );
    return Card(
      margin: const EdgeInsets.all(8),
      child: StreamBuilder<SessionAnalysisSummaryModel?>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final summary = snapshot.data;
          if (summary == null) {
            return const Center(child: Text('Sem resumo'));
          }
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Best lap: ${_fmtMsNullable(summary.bestLapMs)}'),
                Text('Optimal: ${_fmtMsNullable(summary.optimalLapMs)}'),
                Text('Best sectors: ${_fmtList(summary.bestSectorsMs)}'),
                Text(
                    'Valid laps: ${summary.validLapsCount}/${summary.totalLapsCount}'),
              ],
            ),
          );
        },
      ),
    );
  }

  String _fmtMs(int ms) {
    final dur = Duration(milliseconds: ms);
    final m = dur.inMinutes;
    final s = dur.inSeconds.remainder(60);
    final msR = dur.inMilliseconds.remainder(1000);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${msR.toString().padLeft(3, '0')}';
  }

  String _fmtMsNullable(int? ms) => ms == null ? '--' : _fmtMs(ms);

  String _fmtList(List<int> values) =>
      values.isEmpty ? '--' : values.map((e) => _fmtMs(e)).join(' | ');
}
