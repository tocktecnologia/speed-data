import 'package:flutter/material.dart';
import 'package:speed_data/pages/public_event/public_event_details_page_widget.dart';

class PublicEventInscriptionEntryPageWidget extends StatelessWidget {
  const PublicEventInscriptionEntryPageWidget({
    super.key,
    required this.eventId,
  });

  static String routeName = 'PublicEventInscriptionEntry';
  static String routePath = '/inscricao';

  final String eventId;

  @override
  Widget build(BuildContext context) {
    final normalizedEventId = eventId.trim();
    if (normalizedEventId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Inscricao')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Link de inscricao invalido. Verifique o evento e tente novamente.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return PublicEventDetailsPageWidget(eventId: normalizedEventId);
  }
}
