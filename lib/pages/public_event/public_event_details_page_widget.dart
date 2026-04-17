import '/auth/firebase_auth/auth_util.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:speed_data/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'package:speed_data/pages/public_event/public_event_inscription_page_widget.dart';

class PublicEventDetailsPageWidget extends StatefulWidget {
  const PublicEventDetailsPageWidget({
    super.key,
    required this.eventId,
  });

  final String eventId;

  @override
  State<PublicEventDetailsPageWidget> createState() =>
      _PublicEventDetailsPageWidgetState();
}

class _PublicEventDetailsPageWidgetState
    extends State<PublicEventDetailsPageWidget> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  void _goToHome() {
    if (!mounted) return;
    context.goNamedAuth(
      HomePageWidget.routeName,
      context.mounted,
      ignoreRedirect: true,
    );
  }

  DateTime? _asDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate().toLocal();
    if (value is DateTime) return value.toLocal();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal();
    }
    if (value is String) {
      final parsedInt = int.tryParse(value);
      if (parsedInt != null) {
        return DateTime.fromMillisecondsSinceEpoch(parsedInt).toLocal();
      }
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }

  String _formatDateRange(DateTime? start, DateTime? end) {
    if (start == null && end == null) return 'Data não informada';
    if (start == null) return DateFormat('dd/MM/yyyy HH:mm').format(end!);
    if (end == null) return DateFormat('dd/MM/yyyy HH:mm').format(start);
    final sameDay = start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    if (sameDay) {
      return DateFormat('dd/MM/yyyy').format(start);
    }
    return '${DateFormat('dd/MM/yyyy').format(start)} - ${DateFormat('dd/MM/yyyy').format(end)}';
  }

  String _normalizeStatus(dynamic value) {
    final raw = (value as String?)?.trim().toLowerCase() ?? '';
    if (raw == 'live') return 'AO VIVO';
    if (raw == 'finished') return 'FINALIZADO';
    return 'PROXIMO';
  }

  String _normalizePaymentStatus(dynamic value) {
    final raw = (value as String?)?.trim().toLowerCase() ?? '';
    if (raw == 'done' ||
        raw == 'paid' ||
        raw == 'confirmed' ||
        raw == 'feito') {
      return 'done';
    }
    return 'pending';
  }

  String _paymentStatusLabel(String status) {
    if (status == 'done') return 'PAGAMENTO FEITO';
    return 'PAGAMENTO PENDENTE';
  }

  Color _paymentStatusColor(String status) {
    if (status == 'done') return const Color(0xFF2E7D32);
    return const Color(0xFFFF8F00);
  }

  Future<void> _openInscriptionForm({
    required String eventName,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PublicEventInscriptionPageWidget(
          eventId: widget.eventId,
          eventName: eventName,
        ),
      ),
    );
  }

  Widget _buildEventCard({
    required String name,
    required String location,
    required String state,
    required DateTime? startDate,
    required DateTime? endDate,
    required String statusLabel,
    required List<String> categories,
    required bool hasInscription,
    required String paymentStatus,
  }) {
    final paymentColor = _paymentStatusColor(paymentStatus);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (hasInscription)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: paymentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: paymentColor.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(
                      _paymentStatusLabel(paymentStatus),
                      style: TextStyle(
                        color: paymentColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_formatDateRange(startDate, endDate)),
            const SizedBox(height: 4),
            Text(
              location.isEmpty && state.isEmpty
                  ? 'Local não informado'
                  : [location, state]
                      .where((entry) => entry.trim().isNotEmpty)
                      .join(' - '),
            ),
            const SizedBox(height: 4),
            Text('Status: $statusLabel'),
            if (categories.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Categorias: ${categories.join(', ')}'),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: hasInscription
                    ? ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      )
                    : null,
                onPressed: () => _openInscriptionForm(eventName: name),
                icon: Icon(
                  hasInscription
                      ? Icons.edit_note_rounded
                      : Icons.app_registration_rounded,
                ),
                label: Text(hasInscription ? 'Ver inscrição' : 'Se inscrever'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _goToHome,
                icon: const Icon(Icons.home_rounded),
                label: const Text('Voltar para home'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = currentUserUid.trim();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _goToHome();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Voltar para home',
            onPressed: _goToHome,
          ),
          title: const Text('Detalhes do Evento'),
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream:
              _db.collection('events_public').doc(widget.eventId).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text('Erro ao carregar evento: ${snapshot.error}'),
              );
            }

            final data = snapshot.data?.data();
            if (data == null) {
              return const Center(
                child: Text('Evento não encontrado.'),
              );
            }

            final name = (data['name'] as String?)?.trim().isNotEmpty == true
                ? data['name'] as String
                : 'Evento';
            final location = (data['location'] as String?)?.trim() ?? '';
            final state = (data['state'] as String?)?.trim() ?? '';
            final startDate =
                _asDateTime(data['start_date'] ?? data['startDate']);
            final endDate = _asDateTime(data['end_date'] ?? data['endDate']);
            final categories = data['categories'] is List
                ? List<String>.from(
                    (data['categories'] as List)
                        .whereType<dynamic>()
                        .map((e) => e.toString()),
                  )
                : const <String>[];
            final statusLabel = _normalizeStatus(data['status']);

            if (uid.isEmpty) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _buildEventCard(
                  name: name,
                  location: location,
                  state: state,
                  startDate: startDate,
                  endDate: endDate,
                  statusLabel: statusLabel,
                  categories: categories,
                  hasInscription: false,
                  paymentStatus: 'pending',
                ),
              );
            }

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db
                  .collection('events_public')
                  .doc(widget.eventId)
                  .collection('inscriptions')
                  .where('user_uid', isEqualTo: uid)
                  .limit(1)
                  .snapshots(),
              builder: (context, inscriptionSnapshot) {
                final inscriptionDocs = inscriptionSnapshot.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                final hasInscription = inscriptionDocs.isNotEmpty;
                final inscriptionData =
                    hasInscription ? inscriptionDocs.first.data() : null;
                final paymentStatus = _normalizePaymentStatus(
                  inscriptionData?['payment_status'],
                );

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _buildEventCard(
                    name: name,
                    location: location,
                    state: state,
                    startDate: startDate,
                    endDate: endDate,
                    statusLabel: statusLabel,
                    categories: categories,
                    hasInscription: hasInscription,
                    paymentStatus: paymentStatus,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
