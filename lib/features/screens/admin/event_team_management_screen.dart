import 'package:flutter/material.dart';
import 'package:speed_data/features/models/competitor_model.dart';
import 'package:speed_data/features/models/event_model.dart';
import 'package:speed_data/features/models/team_model.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:uuid/uuid.dart';

class EventTeamManagementScreen extends StatefulWidget {
  final RaceEvent event;

  const EventTeamManagementScreen({
    super.key,
    required this.event,
  });

  @override
  State<EventTeamManagementScreen> createState() =>
      _EventTeamManagementScreenState();
}

class _EventTeamManagementScreenState extends State<EventTeamManagementScreen> {
  final FirestoreService _firestore = FirestoreService();
  final TextEditingController _teamNameController = TextEditingController();
  final TextEditingController _memberEmailController = TextEditingController();
  final Uuid _uuid = const Uuid();

  String? _selectedTeamId;
  bool _saving = false;

  @override
  void dispose() {
    _teamNameController.dispose();
    _memberEmailController.dispose();
    super.dispose();
  }

  Future<void> _createTeam() async {
    final rawName = _teamNameController.text.trim();
    if (rawName.isEmpty) return;

    setState(() => _saving = true);
    try {
      final team = TeamModel(
        id: _uuid.v4(),
        name: rawName,
      );
      await _firestore.saveEventTeam(widget.event.id, team);
      if (!mounted) return;
      setState(() {
        _selectedTeamId = team.id;
        _teamNameController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao criar equipe: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteTeam(TeamModel team) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir equipe?'),
        content: Text(
          'A equipe "${team.name}" será removida e os vínculos de pilotos serão limpos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Excluir',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      final competitors = await _firestore.getCompetitors(widget.event.id);
      final writes = <Future<void>>[];
      for (final competitor in competitors) {
        if (competitor.teamId == team.id) {
          writes.add(
            _firestore.assignCompetitorToTeam(
              eventId: widget.event.id,
              competitorId: competitor.id,
              teamId: '',
              teamName: '',
            ),
          );
        }
      }
      await Future.wait(writes);
      await _firestore.deleteEventTeam(widget.event.id, team.id);

      if (!mounted) return;
      setState(() {
        if (_selectedTeamId == team.id) {
          _selectedTeamId = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao excluir equipe: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addMember(TeamModel team) async {
    final email = _memberEmailController.text.trim();
    if (email.isEmpty) return;

    setState(() => _saving = true);
    try {
      final user = await _firestore.getUserByEmail(email);
      if (user == null || (user['uid'] as String?)?.trim().isEmpty != false) {
        throw Exception('Usuário não encontrado para este e-mail.');
      }

      final member = TeamMember(
        uid: (user['uid'] as String).trim(),
        role: 'staff',
        name: (user['name'] as String?)?.trim() ?? '',
        email: (user['email'] as String?)?.trim().toLowerCase() ?? email,
      );

      await _firestore.upsertEventTeamMember(
        widget.event.id,
        team.id,
        member,
      );

      if (!mounted) return;
      _memberEmailController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao adicionar membro: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeMember(TeamModel team, TeamMember member) async {
    try {
      await _firestore.removeEventTeamMember(
          widget.event.id, team.id, member.uid);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao remover membro: $e')),
      );
    }
  }

  Future<void> _assignCompetitor(Competitor competitor, TeamModel? team) async {
    try {
      await _firestore.assignCompetitorToTeam(
        eventId: widget.event.id,
        competitorId: competitor.id,
        teamId: team?.id ?? '',
        teamName: team?.name ?? '',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao vincular piloto: $e')),
      );
    }
  }

  Widget _buildCreateTeamCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _teamNameController,
                decoration: const InputDecoration(
                  labelText: 'Nome da equipe',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _saving ? null : _createTeam,
              icon: const Icon(Icons.add),
              label: const Text('Criar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMembersCard(TeamModel team) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Integrantes da equipe: ${team.name}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _memberEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-mail do integrante',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _addMember(team),
                  icon: const Icon(Icons.person_add),
                  label: const Text('Adicionar'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            StreamBuilder<List<TeamMember>>(
              stream: _firestore.getEventTeamMembersStream(
                  widget.event.id, team.id),
              builder: (context, snapshot) {
                final members = snapshot.data ?? const <TeamMember>[];
                if (members.isEmpty) {
                  return const Text(
                    'Nenhum integrante cadastrado.',
                    style: TextStyle(color: Colors.grey),
                  );
                }
                return Column(
                  children: members
                      .map(
                        (member) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.person),
                          title: Text(
                            member.name.isEmpty ? member.uid : member.name,
                          ),
                          subtitle: Text(member.email),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            onPressed: () => _removeMember(team, member),
                          ),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentsCard(List<TeamModel> teams) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vincular pilotos a equipes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<Competitor>>(
              stream: _firestore.getCompetitorsStream(widget.event.id),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  );
                }
                final competitors = snapshot.data!;
                if (competitors.isEmpty) {
                  return const Text(
                    'Nenhum piloto cadastrado neste evento.',
                    style: TextStyle(color: Colors.grey),
                  );
                }

                return Column(
                  children: competitors.map((competitor) {
                    final currentTeam = teams.cast<TeamModel?>().firstWhere(
                          (team) => team?.id == competitor.teamId,
                          orElse: () => null,
                        );
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        child: Text(competitor.number.isEmpty
                            ? '?'
                            : competitor.number),
                      ),
                      title: Text(competitor.name.isEmpty
                          ? competitor.id
                          : competitor.name),
                      subtitle: Text(
                        competitor.uid.isNotEmpty
                            ? 'UID: ${competitor.uid}'
                            : 'Piloto sem conta vinculada',
                      ),
                      trailing: SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          value: currentTeam?.id ?? '',
                          isDense: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: '',
                              child: Text('Sem equipe'),
                            ),
                            ...teams.map(
                              (team) => DropdownMenuItem<String>(
                                value: team.id,
                                child: Text(team.name),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            final selected =
                                teams.cast<TeamModel?>().firstWhere(
                                      (team) => team?.id == value,
                                      orElse: () => null,
                                    );
                            _assignCompetitor(competitor, selected);
                          },
                        ),
                      ),
                    );
                  }).toList(growable: false),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Equipes - ${widget.event.name}'),
      ),
      body: StreamBuilder<List<TeamModel>>(
        stream: _firestore.getEventTeamsStream(widget.event.id),
        builder: (context, snapshot) {
          final teams = snapshot.data ?? const <TeamModel>[];

          if (_selectedTeamId == null && teams.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _selectedTeamId = teams.first.id);
            });
          }

          final selectedTeam = teams.cast<TeamModel?>().firstWhere(
                (team) => team?.id == _selectedTeamId,
                orElse: () => null,
              );

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _buildCreateTeamCard(),
              if (teams.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nenhuma equipe cadastrada ainda.'),
                  ),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedTeam?.id ?? teams.first.id,
                            decoration: const InputDecoration(
                              labelText: 'Equipe selecionada',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: teams
                                .map(
                                  (team) => DropdownMenuItem<String>(
                                    value: team.id,
                                    child: Text(team.name),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (value) =>
                                setState(() => _selectedTeamId = value),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Excluir equipe',
                          onPressed: selectedTeam == null || _saving
                              ? null
                              : () => _deleteTeam(selectedTeam),
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                ),
              if (selectedTeam != null) _buildMembersCard(selectedTeam),
              _buildAssignmentsCard(teams),
            ],
          );
        },
      ),
    );
  }
}
