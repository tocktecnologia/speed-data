import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PublicEventInscriptionPageWidget extends StatefulWidget {
  const PublicEventInscriptionPageWidget({
    super.key,
    required this.eventId,
    required this.eventName,
  });

  final String eventId;
  final String eventName;

  @override
  State<PublicEventInscriptionPageWidget> createState() =>
      _PublicEventInscriptionPageWidgetState();
}

enum _InscriptionFieldType {
  text,
  number,
  singleChoice,
  multipleChoice,
}

class _InscriptionFieldDefinition {
  _InscriptionFieldDefinition({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.required,
    required this.placeholder,
    required this.options,
    required this.allowOther,
  });

  final String id;
  final _InscriptionFieldType type;
  final String title;
  final String subtitle;
  final bool required;
  final String placeholder;
  final List<String> options;
  final bool allowOther;
}

class _InscriptionConfigPayload {
  _InscriptionConfigPayload({
    required this.organizationId,
    required this.title,
    required this.subtitle,
    required this.helperText,
    required this.fields,
    required this.prefillResponses,
    required this.inscriptionData,
  });

  final String organizationId;
  final String title;
  final String subtitle;
  final String helperText;
  final List<_InscriptionFieldDefinition> fields;
  final Map<String, dynamic> prefillResponses;
  final Map<String, dynamic> inscriptionData;
}

class _PublicEventInscriptionPageWidgetState
    extends State<PublicEventInscriptionPageWidget> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, String> _singleChoiceValues = {};
  final Map<String, Set<String>> _multiChoiceValues = {};
  final Map<String, TextEditingController> _otherControllers = {};
  late Future<_InscriptionConfigPayload?> _formFuture;
  bool _submitting = false;
  bool _prefillApplied = false;
  DocumentReference<Map<String, dynamic>>? _inscriptionRef;

  static const String _otherOptionKey = '__other_option__';

  @override
  void initState() {
    super.initState();
    _formFuture = _loadConfig();
  }

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    for (final controller in _otherControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  _InscriptionFieldType _parseFieldType(dynamic value) {
    final normalized = (value as String?)?.trim().toLowerCase() ?? '';
    if (normalized == 'number') return _InscriptionFieldType.number;
    if (normalized == 'single_choice') {
      return _InscriptionFieldType.singleChoice;
    }
    if (normalized == 'multiple_choice') {
      return _InscriptionFieldType.multipleChoice;
    }
    return _InscriptionFieldType.text;
  }

  Map<String, dynamic> _toStringKeyedMap(dynamic rawValue) {
    if (rawValue is Map<String, dynamic>) {
      return Map<String, dynamic>.from(rawValue);
    }
    if (rawValue is Map) {
      return Map<String, dynamic>.from(
        rawValue.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _extractStoredResponses(Map<String, dynamic> data) {
    const responseKeys = <String>[
      'responses',
      'answers',
      'form_answers',
      'formResponses',
      'form_responses',
    ];

    final merged = <String, dynamic>{};
    for (final key in responseKeys) {
      final source = _toStringKeyedMap(data[key]);
      for (final entry in source.entries) {
        merged.putIfAbsent(entry.key, () => entry.value);
      }
    }
    return merged;
  }

  String _normalizeLookupKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
  }

  dynamic _lookupByNormalizedKey(
    Map<String, dynamic> source,
    Iterable<String> keys,
  ) {
    if (source.isEmpty) return null;

    final normalizedKeys =
        keys.map(_normalizeLookupKey).where((key) => key.isNotEmpty).toSet();
    if (normalizedKeys.isEmpty) return null;

    for (final entry in source.entries) {
      final normalizedEntryKey = _normalizeLookupKey(entry.key);
      if (!normalizedKeys.contains(normalizedEntryKey)) continue;
      if (entry.value == null) continue;
      return entry.value;
    }
    return null;
  }

  bool _containsKeyword(
    _InscriptionFieldDefinition field,
    List<String> keywords,
  ) {
    final haystack = '${field.id} ${field.title}'.toLowerCase();
    return keywords.any((keyword) => haystack.contains(keyword));
  }

  dynamic _firstNonEmptyValue(List<dynamic> values) {
    for (final value in values) {
      if (value == null) continue;
      if (value is String) {
        final text = value.trim();
        if (text.isNotEmpty) return text;
        continue;
      }
      if (value is List && value.isNotEmpty) {
        return value;
      }
      if (value is Map && value.isNotEmpty) {
        return value;
      }
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  dynamic _resolveFallbackByFieldMeaning(
    _InscriptionFieldDefinition field,
    Map<String, dynamic> inscriptionData,
  ) {
    if (_containsKeyword(field, const ['nome', 'name', 'piloto'])) {
      return _firstNonEmptyValue([
        inscriptionData['competitor_name'],
        inscriptionData['pilot_name'],
        inscriptionData['user_name'],
        inscriptionData['name'],
      ]);
    }
    if (_containsKeyword(field, const ['numero', 'number', 'carro'])) {
      return _firstNonEmptyValue([
        inscriptionData['competitor_number'],
        inscriptionData['car_number'],
        inscriptionData['number'],
      ]);
    }
    if (_containsKeyword(field, const ['categoria', 'category'])) {
      return _firstNonEmptyValue([inscriptionData['category']]);
    }
    if (_containsKeyword(field, const ['email', 'mail'])) {
      return _firstNonEmptyValue([
        inscriptionData['user_email'],
        inscriptionData['email'],
      ]);
    }
    return null;
  }

  dynamic _unwrapResponseValue(dynamic rawValue) {
    if (rawValue is Map<String, dynamic>) {
      for (final key in const ['value', 'answer', 'text']) {
        if (rawValue.containsKey(key)) {
          return rawValue[key];
        }
      }
    } else if (rawValue is Map) {
      for (final key in const ['value', 'answer', 'text']) {
        if (rawValue.containsKey(key)) {
          return rawValue[key];
        }
      }
    }
    return rawValue;
  }

  dynamic _resolvePrefillValue({
    required _InscriptionFieldDefinition field,
    required Map<String, dynamic> responses,
    required Map<String, dynamic> inscriptionData,
  }) {
    final lookupKeys = <String>{
      field.id,
      field.title,
      field.id.replaceAll('-', '_'),
      field.id.replaceAll('_', '-'),
      field.title.replaceAll(' ', '_'),
      field.title.replaceAll(' ', '-'),
    };

    final fromResponses = _lookupByNormalizedKey(responses, lookupKeys);
    if (fromResponses != null) return fromResponses;

    final fromInscription = _lookupByNormalizedKey(inscriptionData, lookupKeys);
    if (fromInscription != null) return fromInscription;

    return _resolveFallbackByFieldMeaning(field, inscriptionData);
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _loadExistingInscription(
    String uid,
  ) async {
    final inscriptions = _db
        .collection('events_public')
        .doc(widget.eventId)
        .collection('inscriptions');

    final byDocumentId = await inscriptions.doc(uid).get();
    if (byDocumentId.exists) {
      return byDocumentId;
    }

    Future<DocumentSnapshot<Map<String, dynamic>>?> queryByField(
      String field,
    ) async {
      final snapshot =
          await inscriptions.where(field, isEqualTo: uid).limit(1).get();
      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.first;
      }
      return null;
    }

    final byUserUid = await queryByField('user_uid');
    if (byUserUid != null) {
      return byUserUid;
    }

    final byUid = await queryByField('uid');
    if (byUid != null) {
      return byUid;
    }

    return queryByField('user_id');
  }

  Future<_InscriptionConfigPayload?> _loadConfig() async {
    final eventSnapshot =
        await _db.collection('events_public').doc(widget.eventId).get();
    if (!eventSnapshot.exists || eventSnapshot.data() == null) {
      return null;
    }

    final eventData = eventSnapshot.data()!;
    final configSnapshot = await _db
        .collection('events_public')
        .doc(widget.eventId)
        .collection('inscription_config')
        .doc('default')
        .get();
    if (!configSnapshot.exists || configSnapshot.data() == null) {
      return null;
    }

    Map<String, dynamic> prefillResponses = <String, dynamic>{};
    Map<String, dynamic> inscriptionData = <String, dynamic>{};
    _inscriptionRef = null;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final inscriptionSnapshot = await _loadExistingInscription(user.uid);
      if (inscriptionSnapshot != null &&
          inscriptionSnapshot.exists &&
          inscriptionSnapshot.data() != null) {
        _inscriptionRef = inscriptionSnapshot.reference;
        inscriptionData = _toStringKeyedMap(inscriptionSnapshot.data()!);
        prefillResponses = _extractStoredResponses(inscriptionData);
      }
    }

    final configData = configSnapshot.data()!;
    final rawFields = configData['fields'] is List
        ? (configData['fields'] as List)
        : const [];

    final fields = <_InscriptionFieldDefinition>[];
    for (final raw in rawFields) {
      if (raw is! Map<String, dynamic>) continue;
      final title = (raw['title'] as String?)?.trim() ?? '';
      if (title.isEmpty) continue;

      final id = (raw['id'] as String?)?.trim().isNotEmpty == true
          ? (raw['id'] as String).trim()
          : 'field_${fields.length + 1}';
      final options = raw['options'] is List
          ? List<String>.from(
              (raw['options'] as List)
                  .map((entry) => entry.toString().trim())
                  .where((entry) => entry.isNotEmpty),
            )
          : const <String>[];

      fields.add(
        _InscriptionFieldDefinition(
          id: id,
          type: _parseFieldType(raw['type']),
          title: title,
          subtitle: (raw['subtitle'] as String?)?.trim() ?? '',
          required: raw['required'] == true,
          placeholder: (raw['placeholder'] as String?)?.trim() ?? '',
          options: options,
          allowOther: raw['allowOther'] == true || raw['allow_other'] == true,
        ),
      );
    }

    return _InscriptionConfigPayload(
      organizationId: (eventData['organization_id'] as String?)?.trim() ?? '',
      title: (configData['title'] as String?)?.trim().isNotEmpty == true
          ? (configData['title'] as String).trim()
          : 'Formulário de inscrição',
      subtitle: (configData['subtitle'] as String?)?.trim() ?? '',
      helperText:
          ((configData['helper_text'] ?? configData['helperText']) as String?)
                  ?.trim() ??
              '',
      fields: fields,
      prefillResponses: prefillResponses,
      inscriptionData: inscriptionData,
    );
  }

  void _syncControllers(List<_InscriptionFieldDefinition> fields) {
    final validIds = fields.map((field) => field.id).toSet();

    for (final field in fields) {
      if (field.type == _InscriptionFieldType.text ||
          field.type == _InscriptionFieldType.number) {
        _textControllers.putIfAbsent(field.id, () => TextEditingController());
      }
      if (field.allowOther) {
        _otherControllers.putIfAbsent(field.id, () => TextEditingController());
      }
      if (field.type == _InscriptionFieldType.multipleChoice) {
        _multiChoiceValues.putIfAbsent(field.id, () => <String>{});
      }
    }

    final textToRemove = _textControllers.keys
        .where((id) => !validIds.contains(id))
        .toList(growable: false);
    for (final id in textToRemove) {
      _textControllers.remove(id)?.dispose();
      _singleChoiceValues.remove(id);
      _multiChoiceValues.remove(id);
    }

    final otherToRemove = _otherControllers.keys
        .where((id) => !validIds.contains(id))
        .toList(growable: false);
    for (final id in otherToRemove) {
      _otherControllers.remove(id)?.dispose();
    }
  }

  List<String> _coerceValueList(dynamic rawValue) {
    rawValue = _unwrapResponseValue(rawValue);
    if (rawValue == null) return const <String>[];
    if (rawValue is List) {
      return rawValue
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    }
    final text = rawValue.toString().trim();
    if (text.isEmpty) return const <String>[];
    if (text.contains(',')) {
      return text
          .split(',')
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    }
    return <String>[text];
  }

  void _applyPrefillAnswers(
    List<_InscriptionFieldDefinition> fields,
    Map<String, dynamic> responses,
    Map<String, dynamic> inscriptionData,
  ) {
    for (final field in fields) {
      final raw = _resolvePrefillValue(
        field: field,
        responses: responses,
        inscriptionData: inscriptionData,
      );
      if (raw == null) continue;
      final normalizedRaw = _unwrapResponseValue(raw);
      if (normalizedRaw == null) continue;

      switch (field.type) {
        case _InscriptionFieldType.text:
        case _InscriptionFieldType.number:
          _textControllers[field.id]?.text = normalizedRaw.toString().trim();
          break;
        case _InscriptionFieldType.singleChoice:
          final value = normalizedRaw.toString().trim();
          if (value.isEmpty) break;
          if (field.options.contains(value)) {
            _singleChoiceValues[field.id] = value;
          } else if (field.allowOther) {
            _singleChoiceValues[field.id] = _otherOptionKey;
            _otherControllers[field.id]?.text = value;
          }
          break;
        case _InscriptionFieldType.multipleChoice:
          final values = _coerceValueList(normalizedRaw);
          if (values.isEmpty) break;

          final selected = <String>{};
          final otherValues = <String>[];
          for (final value in values) {
            if (field.options.contains(value)) {
              selected.add(value);
            } else if (field.allowOther) {
              selected.add(_otherOptionKey);
              otherValues.add(value);
            }
          }

          _multiChoiceValues[field.id] = selected;
          if (field.allowOther && otherValues.isNotEmpty) {
            _otherControllers[field.id]?.text = otherValues.join(', ');
          }
          break;
      }
    }
  }

  String? _resolveStringAnswer(_InscriptionFieldDefinition field) {
    switch (field.type) {
      case _InscriptionFieldType.text:
      case _InscriptionFieldType.number:
        return _textControllers[field.id]?.text.trim() ?? '';
      case _InscriptionFieldType.singleChoice:
        final selected = _singleChoiceValues[field.id] ?? '';
        if (selected == _otherOptionKey) {
          return _otherControllers[field.id]?.text.trim() ?? '';
        }
        return selected;
      case _InscriptionFieldType.multipleChoice:
        final values = _multiChoiceValues[field.id] ?? <String>{};
        if (values.isEmpty) return '';
        final normalized = <String>[];
        for (final value in values) {
          if (value == _otherOptionKey) {
            final other = _otherControllers[field.id]?.text.trim() ?? '';
            if (other.isNotEmpty) normalized.add(other);
          } else {
            normalized.add(value);
          }
        }
        return normalized.join(', ');
    }
  }

  String _findPrimaryValue({
    required List<_InscriptionFieldDefinition> fields,
    required Map<String, dynamic> responses,
    required List<String> keywords,
    required String fallback,
  }) {
    for (final field in fields) {
      final haystack = '${field.id} ${field.title}'.toLowerCase();
      final matches = keywords.any((keyword) => haystack.contains(keyword));
      if (!matches) continue;
      final value = (responses[field.id] as String?)?.trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return fallback;
  }

  Future<void> _submitInscription(_InscriptionConfigPayload payload) async {
    if (_submitting) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sessão expirada. Faça login novamente.')),
      );
      return;
    }

    final errors = <String>[];
    final responses = <String, dynamic>{};

    for (final field in payload.fields) {
      final answer = _resolveStringAnswer(field)?.trim() ?? '';
      if (field.required && answer.isEmpty) {
        errors.add('Preencha o campo: ${field.title}');
      }
      responses[field.id] = answer;
    }

    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errors.first)),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      String userName = (user.displayName ?? '').trim();
      if (userName.isEmpty) {
        final userDoc = await _db.collection('users').doc(user.uid).get();
        final userData = userDoc.data();
        userName = ((userData?['name'] ?? userData?['display_name']) as String?)
                ?.trim() ??
            '';
      }
      if (userName.isEmpty) {
        userName = (user.email ?? user.uid).trim();
      }

      final competitorName = _findPrimaryValue(
        fields: payload.fields,
        responses: responses,
        keywords: const ['piloto', 'nome', 'name'],
        fallback: userName,
      );
      final competitorNumber = _findPrimaryValue(
        fields: payload.fields,
        responses: responses,
        keywords: const ['numero', 'number'],
        fallback: '',
      );
      final competitorCategory = _findPrimaryValue(
        fields: payload.fields,
        responses: responses,
        keywords: const ['categoria', 'category'],
        fallback: '',
      );

      final inscriptionRef = _inscriptionRef ??
          _db
              .collection('events_public')
              .doc(widget.eventId)
              .collection('inscriptions')
              .doc(user.uid);
      final existing = await inscriptionRef.get();

      final existingPaymentConfirmed =
          existing.data()?['payment_confirmed'] == true;
      final existingPaymentStatus =
          (existing.data()?['payment_status'] as String?)?.trim();

      final payloadData = <String, dynamic>{
        'event_id': widget.eventId,
        'event_name': widget.eventName,
        'organization_id': payload.organizationId,
        'user_uid': user.uid,
        'uid': user.uid,
        'user_id': user.uid,
        'user_email': (user.email ?? '').trim(),
        'user_name': userName,
        'competitor_name': competitorName,
        'competitor_number': competitorNumber,
        'category': competitorCategory,
        'responses': responses,
        'payment_confirmed': existingPaymentConfirmed,
        'payment_status': existingPaymentStatus?.isNotEmpty == true
            ? existingPaymentStatus
            : (existingPaymentConfirmed ? 'done' : 'pending'),
        'updated_at': FieldValue.serverTimestamp(),
      };
      if (!existing.exists) {
        payloadData['created_at'] = FieldValue.serverTimestamp();
      }

      await inscriptionRef.set(payloadData, SetOptions(merge: true));
      _inscriptionRef = inscriptionRef;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inscrição salva com sucesso.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível enviar inscrição: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Widget _buildSingleChoiceField(_InscriptionFieldDefinition field) {
    final selected = _singleChoiceValues[field.id] ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...field.options.map(
          (option) => RadioListTile<String>(
            dense: true,
            title: Text(option),
            value: option,
            groupValue: selected,
            onChanged: (value) {
              setState(() {
                _singleChoiceValues[field.id] = value ?? '';
              });
            },
          ),
        ),
        if (field.allowOther)
          RadioListTile<String>(
            dense: true,
            title: const Text('Outro'),
            value: _otherOptionKey,
            groupValue: selected,
            onChanged: (value) {
              setState(() {
                _singleChoiceValues[field.id] = value ?? '';
              });
            },
          ),
        if (field.allowOther && selected == _otherOptionKey)
          TextField(
            controller: _otherControllers[field.id],
            decoration: const InputDecoration(
              hintText: 'Digite sua resposta',
              isDense: true,
            ),
          ),
      ],
    );
  }

  Widget _buildMultipleChoiceField(_InscriptionFieldDefinition field) {
    final values = _multiChoiceValues[field.id] ?? <String>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...field.options.map(
          (option) => CheckboxListTile(
            dense: true,
            value: values.contains(option),
            title: Text(option),
            onChanged: (checked) {
              setState(() {
                final set = _multiChoiceValues[field.id] ?? <String>{};
                if (checked == true) {
                  set.add(option);
                } else {
                  set.remove(option);
                }
                _multiChoiceValues[field.id] = set;
              });
            },
          ),
        ),
        if (field.allowOther)
          CheckboxListTile(
            dense: true,
            value: values.contains(_otherOptionKey),
            title: const Text('Outro'),
            onChanged: (checked) {
              setState(() {
                final set = _multiChoiceValues[field.id] ?? <String>{};
                if (checked == true) {
                  set.add(_otherOptionKey);
                } else {
                  set.remove(_otherOptionKey);
                }
                _multiChoiceValues[field.id] = set;
              });
            },
          ),
        if (field.allowOther && values.contains(_otherOptionKey))
          TextField(
            controller: _otherControllers[field.id],
            decoration: const InputDecoration(
              hintText: 'Digite sua resposta',
              isDense: true,
            ),
          ),
      ],
    );
  }

  Widget _buildFieldInput(_InscriptionFieldDefinition field) {
    switch (field.type) {
      case _InscriptionFieldType.text:
        return TextField(
          controller: _textControllers[field.id],
          decoration: InputDecoration(
            hintText:
                field.placeholder.isEmpty ? 'Sua resposta' : field.placeholder,
            isDense: true,
          ),
        );
      case _InscriptionFieldType.number:
        return TextField(
          controller: _textControllers[field.id],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: field.placeholder.isEmpty
                ? 'Digite um numero'
                : field.placeholder,
            isDense: true,
          ),
        );
      case _InscriptionFieldType.singleChoice:
        return _buildSingleChoiceField(field);
      case _InscriptionFieldType.multipleChoice:
        return _buildMultipleChoiceField(field);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Inscrição - ${widget.eventName}'),
      ),
      body: FutureBuilder<_InscriptionConfigPayload?>(
        future: _formFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Erro ao carregar formulario: ${snapshot.error}'),
            );
          }

          final payload = snapshot.data;
          if (payload == null || payload.fields.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Este evento ainda não possui formulário de inscrição.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          _syncControllers(payload.fields);
          if (!_prefillApplied) {
            _applyPrefillAnswers(
              payload.fields,
              payload.prefillResponses,
              payload.inscriptionData,
            );
            _prefillApplied = true;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        payload.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (payload.subtitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(payload.subtitle),
                      ],
                      if (payload.helperText.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(payload.helperText),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ...payload.fields.map((field) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          field.required ? '${field.title} *' : field.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (field.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            field.subtitle,
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ],
                        const SizedBox(height: 10),
                        _buildFieldInput(field),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                      _submitting ? null : () => _submitInscription(payload),
                  icon: _submitting
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label:
                      Text(_submitting ? 'Enviando...' : 'Confirmar inscrição'),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Ao salvar, sua inscrição será atualizada neste evento.',
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}
