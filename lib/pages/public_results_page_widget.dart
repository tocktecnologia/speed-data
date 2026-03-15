import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:speed_data/features/services/firestore_service.dart';

class PublicResultsPageWidget extends StatefulWidget {
  const PublicResultsPageWidget({super.key});

  static String routeName = 'PublicResultsPage';
  static String routePath = '/publicResults';

  @override
  State<PublicResultsPageWidget> createState() =>
      _PublicResultsPageWidgetState();
}

class _PublicResultsPageWidgetState extends State<PublicResultsPageWidget> {
  final FirestoreService _firestore = FirestoreService();
  final TextEditingController _eventIdController = TextEditingController();
  final TextEditingController _sessionIdController = TextEditingController();
  Future<Map<String, dynamic>>? _resultsFuture;
  bool _queryInitialized = false;

  @override
  void dispose() {
    _eventIdController.dispose();
    _sessionIdController.dispose();
    super.dispose();
  }

  String _formatDuration(int? ms) {
    if (ms == null || ms <= 0) return '--:--.---';
    final minutes = (ms ~/ 60000).toString().padLeft(2, '0');
    final seconds = ((ms % 60000) ~/ 1000).toString().padLeft(2, '0');
    final millis = (ms % 1000).toString().padLeft(3, '0');
    return '$minutes:$seconds.$millis';
  }

  void _loadResults() {
    final eventId = _eventIdController.text.trim();
    final sessionId = _sessionIdController.text.trim();
    if (eventId.isEmpty || sessionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe eventId e sessionId.')),
      );
      return;
    }
    setState(() {
      _resultsFuture = _firestore.getPublicSessionResults(
        eventId: eventId,
        sessionId: sessionId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_queryInitialized) {
      final query = GoRouterState.of(context).uri.queryParameters;
      final queryEventId = query['eventId']?.trim() ?? '';
      final querySessionId = query['sessionId']?.trim() ?? '';
      if (queryEventId.isNotEmpty && querySessionId.isNotEmpty) {
        _eventIdController.text = queryEventId;
        _sessionIdController.text = querySessionId;
        _resultsFuture = _firestore.getPublicSessionResults(
          eventId: queryEventId,
          sessionId: querySessionId,
        );
      }
      _queryInitialized = true;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resultados Públicos'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _eventIdController,
                      decoration: const InputDecoration(
                        labelText: 'eventId',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _sessionIdController,
                      decoration: const InputDecoration(
                        labelText: 'sessionId',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _loadResults,
                    icon: const Icon(Icons.search),
                    label: const Text('Carregar'),
                  ),
                ],
              ),
            ),
          ),
          if (_resultsFuture == null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Informe eventId e sessionId para visualizar os resultados públicos.',
                ),
              ),
            )
          else
            FutureBuilder<Map<String, dynamic>>(
              future: _resultsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                          'Erro ao carregar resultados: ${snapshot.error}'),
                    ),
                  );
                }

                final data = snapshot.data ?? const <String, dynamic>{};
                final resultsRaw = data['results'];
                final results = (resultsRaw is List)
                    ? resultsRaw
                        .whereType<Map>()
                        .map((row) => Map<String, dynamic>.from(row))
                        .toList(growable: false)
                    : const <Map<String, dynamic>>[];

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['event_name']?.toString() ?? 'Evento',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Sessão: ${data['session_name']?.toString() ?? data['session_id']?.toString() ?? '-'}',
                        ),
                        const SizedBox(height: 8),
                        if (results.isEmpty)
                          const Text('Sem resultados disponíveis.')
                        else
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Pos')),
                                DataColumn(label: Text('#')),
                                DataColumn(label: Text('Piloto')),
                                DataColumn(label: Text('Equipe')),
                                DataColumn(label: Text('Voltas')),
                                DataColumn(label: Text('Melhor Volta')),
                              ],
                              rows: results
                                  .map(
                                    (row) => DataRow(
                                      cells: [
                                        DataCell(
                                          Text('${row['position'] ?? '-'}'),
                                        ),
                                        DataCell(
                                          Text(row['car_number']?.toString() ??
                                              '-'),
                                        ),
                                        DataCell(
                                          Text(
                                              row['display_name']?.toString() ??
                                                  '-'),
                                        ),
                                        DataCell(
                                          Text(row['team_name']?.toString() ??
                                              '-'),
                                        ),
                                        DataCell(
                                          Text(
                                              '${row['laps'] ?? row['valid_laps'] ?? 0}'),
                                        ),
                                        DataCell(
                                          Text(
                                            _formatDuration(
                                              (row['best_lap_ms'] is num)
                                                  ? (row['best_lap_ms'] as num)
                                                      .toInt()
                                                  : null,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
