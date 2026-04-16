import '/auth/firebase_auth/auth_util.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/main.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speed_data/features/models/user_role.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import '/pages/public_event/public_event_details_page_widget.dart';
import 'home_page_model.dart';
export 'home_page_model.dart';

class HomePageWidget extends StatefulWidget {
  const HomePageWidget({super.key});

  static String routeName = 'HomePage';
  static String routePath = '/homePage';

  @override
  State<HomePageWidget> createState() => _HomePageWidgetState();
}

class _HomePageWidgetState extends State<HomePageWidget> {
  late HomePageModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final TextEditingController _raceSearchController = TextEditingController();
  final TextEditingController _eventSearchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  int _selectedTabIndex = 0;
  DateTimeRange? _raceDateRange;
  DateTimeRange? _eventDateRange;
  bool _onlyMyEvents = false;
  bool _loadingMyEvents = false;
  bool _myEventsLoaded = false;
  bool _savingProfile = false;
  bool _uploadingProfilePhoto = false;
  bool _profileDraftInitialized = false;

  Set<String> _myEventIds = <String>{};
  String _myEventsLoadedUid = '';

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => HomePageModel());
  }

  @override
  void dispose() {
    _raceSearchController.dispose();
    _eventSearchController.dispose();
    _nameController.dispose();
    _model.dispose();
    super.dispose();
  }

  UserRole _resolveRole(Map<String, dynamic> userData) {
    return UserRole.fromString(userData['role'] as String?);
  }

  String _roleLabel(UserRole role) {
    switch (role) {
      case UserRole.pilot:
        return 'Piloto';
      case UserRole.admin:
      case UserRole.root:
        return 'Adm';
      case UserRole.teamMember:
        return 'Equipe';
      case UserRole.unknown:
        return 'Sem perfil';
    }
  }

  String _normalizeText(dynamic value) {
    if (value is! String) return '';
    return value.trim();
  }

  String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = _normalizeText(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  bool _hasGoogleProvider() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    return user.providerData
        .any((provider) => provider.providerId == 'google.com');
  }

  String _resolveDisplayName(Map<String, dynamic> userData) {
    return _firstNonEmpty([
      userData['name'],
      userData['display_name'],
      currentUserDisplayName,
      currentUserEmail.split('@').first,
      'Usuário',
    ]);
  }

  String _resolveEmail(Map<String, dynamic> userData) {
    return _firstNonEmpty([
      userData['email'],
      currentUserEmail,
      'Sem e-mail',
    ]);
  }

  String _resolvePhotoUrl(Map<String, dynamic> userData) {
    final firestorePhoto = _firstNonEmpty([
      userData['photo_url'],
      userData['photoUrl'],
      userData['avatar_url'],
    ]);
    final authPhoto = _firstNonEmpty([currentUserPhoto]);
    if (_hasGoogleProvider() && authPhoto.isNotEmpty) {
      return authPhoto;
    }
    if (firestorePhoto.isNotEmpty) {
      return firestorePhoto;
    }
    return authPhoto;
  }

  void _initProfileDraftIfNeeded(Map<String, dynamic> userData) {
    if (_profileDraftInitialized) return;
    _nameController.text = _resolveDisplayName(userData);
    _profileDraftInitialized = true;
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

  DateTime? _extractRaceDate(Map<String, dynamic> data) {
    const preferredKeys = [
      'date',
      'start_date',
      'scheduled_date',
      'created_at',
      'updated_at',
    ];
    for (final key in preferredKeys) {
      final parsed = _asDateTime(data[key]);
      if (parsed != null) return parsed;
    }
    return null;
  }

  DateTime? _extractPublicEventStartDate(Map<String, dynamic> data) {
    const preferredKeys = [
      'start_date',
      'startDate',
      'date',
      'created_at',
      'updated_at',
    ];
    for (final key in preferredKeys) {
      final parsed = _asDateTime(data[key]);
      if (parsed != null) return parsed;
    }
    return null;
  }

  DateTime? _extractPublicEventEndDate(Map<String, dynamic> data) {
    const preferredKeys = [
      'end_date',
      'endDate',
      'date',
      'start_date',
      'startDate',
    ];
    for (final key in preferredKeys) {
      final parsed = _asDateTime(data[key]);
      if (parsed != null) return parsed;
    }
    return null;
  }

  double? _asDoubleOrNull(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.trim().replaceAll(',', '.'));
    }
    return null;
  }

  String _normalizeEventStatus(dynamic value) {
    final raw = (value as String?)?.trim().toLowerCase() ?? '';
    if (raw == 'live') return 'live';
    if (raw == 'finished') return 'finished';
    return 'upcoming';
  }

  String _eventStatusLabel(String status) {
    switch (status) {
      case 'live':
        return 'AO VIVO';
      case 'finished':
        return 'FINALIZADO';
      case 'upcoming':
      default:
        return 'PROXIMO';
    }
  }

  Color _eventStatusColor(String status, _ConsolePalette palette) {
    switch (status) {
      case 'live':
        return palette.success;
      case 'finished':
        return palette.textSecondary;
      case 'upcoming':
      default:
        return palette.warning;
    }
  }

  String _formatDateRange(DateTime? start, DateTime? end) {
    if (start == null && end == null) return 'Data não informada';
    if (start == null) return _formatDate(end);
    if (end == null) return _formatDate(start);
    final sameDay = start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    if (sameDay) {
      return DateFormat('dd/MM/yyyy').format(start);
    }
    return '${DateFormat('dd/MM').format(start)} - ${DateFormat('dd/MM/yyyy').format(end)}';
  }

  bool _containsQuery(String text, String query) {
    if (query.trim().isEmpty) return true;
    return text.toLowerCase().contains(query.trim().toLowerCase());
  }

  bool _isDateInRange(DateTime? date, DateTimeRange? range) {
    if (range == null || date == null) return true;
    final start =
        DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
      23,
      59,
      59,
      999,
    );
    return !date.isBefore(start) && !date.isAfter(end);
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Data não informada';
    return DateFormat('dd/MM/yyyy HH:mm').format(date);
  }

  Future<void> _pickDateRange({
    required DateTimeRange? currentRange,
    required ValueChanged<DateTimeRange?> onChanged,
  }) async {
    final now = DateTime.now();
    final DateTimeRange initial = currentRange ??
        DateTimeRange(
          start: DateTime(now.year, now.month, now.day)
              .subtract(const Duration(days: 7)),
          end: now,
        );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 3),
      initialDateRange: initial,
    );
    if (!mounted) return;
    onChanged(picked);
  }

  Future<void> _loadMyEventIds(String uid) async {
    final normalizedUid = uid.trim();
    if (_loadingMyEvents || normalizedUid.isEmpty) return;

    setState(() => _loadingMyEvents = true);

    try {
      final ids = await _loadMyEventIdsByEventTraversal(normalizedUid);
      if (!mounted) return;
      setState(() {
        _myEventIds = ids;
        _myEventsLoaded = true;
        _myEventsLoadedUid = normalizedUid;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao carregar inscrições: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingMyEvents = false);
      }
    }
  }

  Future<Set<String>> _loadMyEventIdsByEventTraversal(String uid) async {
    final eventIds = <String>{};
    final eventsSnapshot = await _db.collection('events_public').get();

    final checks = eventsSnapshot.docs.map((eventDoc) async {
      final inscriptionDoc =
          await eventDoc.reference.collection('inscriptions').doc(uid).get();
      if (inscriptionDoc.exists) {
        return eventDoc.id;
      }
      return null;
    });

    final results = await Future.wait(checks);
    for (final eventId in results) {
      if (eventId != null) {
        eventIds.add(eventId);
      }
    }

    return eventIds;
  }

  Future<void> _toggleMyEventsOnly(
      bool value, UserRole role, String uid) async {
    if (role != UserRole.pilot) return;
    setState(() => _onlyMyEvents = value);
    if (value) {
      final normalizedUid = uid.trim();
      if (!_myEventsLoaded || _myEventsLoadedUid != normalizedUid) {
        await _loadMyEventIds(normalizedUid);
      }
    }
  }

  Future<void> _saveProfile(String uid) async {
    if (_savingProfile) return;
    setState(() => _savingProfile = true);

    final cleanName = _nameController.text.trim();

    try {
      final payload = <String, dynamic>{
        'name': cleanName,
        'display_name': cleanName,
        'updated_at': FieldValue.serverTimestamp(),
      };

      await _db
          .collection('users')
          .doc(uid)
          .set(payload, SetOptions(merge: true));

      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser != null) {
        if (cleanName.isNotEmpty &&
            cleanName != (authUser.displayName ?? '').trim()) {
          await authUser.updateDisplayName(cleanName);
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil salvo com sucesso.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao salvar perfil: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _savingProfile = false);
      }
    }
  }

  Future<void> _pickAndUploadProfilePhoto(String uid) async {
    if (_uploadingProfilePhoto) return;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1600,
    );
    if (pickedFile == null) return;

    setState(() => _uploadingProfilePhoto = true);

    try {
      final bytes = await pickedFile.readAsBytes();
      final fileName = pickedFile.name.trim();
      final ext = fileName.contains('.') ? fileName.split('.').last : 'jpg';
      final contentType = (pickedFile.mimeType ?? '').trim();

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('users')
          .child(uid)
          .child('profile')
          .child('avatar_${DateTime.now().millisecondsSinceEpoch}.$ext');

      await storageRef.putData(
        bytes,
        SettableMetadata(
          contentType: contentType.isEmpty ? 'image/jpeg' : contentType,
        ),
      );

      final downloadUrl = await storageRef.getDownloadURL();

      await _db.collection('users').doc(uid).set({
        'photo_url': downloadUrl,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser != null &&
          downloadUrl.trim() != (authUser.photoURL ?? '').trim()) {
        await authUser.updatePhotoURL(downloadUrl);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto atualizada com sucesso.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao enviar foto: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _uploadingProfilePhoto = false);
      }
    }
  }

  Future<void> _signOut() async {
    if (!mounted) return;
    final router = GoRouter.of(context);
    router.prepareAuthEvent();
    await authManager.signOut();
    if (!mounted) return;
    router.clearRedirectLocation();
    if (!mounted) return;
    context.goNamedAuth('Login', context.mounted, ignoreRedirect: true);
  }

  @override
  Widget build(BuildContext context) {
    if (!loggedIn || currentUserUid.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final uid = currentUserUid;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        final userData = snapshot.data?.data() ?? <String, dynamic>{};
        final role = _resolveRole(userData);
        final displayName = _resolveDisplayName(userData);
        final email = _resolveEmail(userData);
        final photoUrl = _resolvePhotoUrl(userData);
        final roleText = _roleLabel(role);

        _initProfileDraftIfNeeded(userData);

        final palette = _ConsolePalette.of(context);

        return Scaffold(
          key: scaffoldKey,
          backgroundColor: palette.pageBackground,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final metrics = _ResponsiveMetrics.fromConstraints(constraints);
                if (metrics.isDesktopLayout) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildResponsiveBackdrop(
                        palette: palette,
                        metrics: metrics,
                      ),
                      _buildDesktopLayout(
                        palette: palette,
                        metrics: metrics,
                        displayName: displayName,
                        email: email,
                        roleText: roleText,
                        photoUrl: photoUrl,
                        showHeader: _selectedTabIndex != 2,
                        role: role,
                        uid: uid,
                      ),
                    ],
                  );
                }

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildResponsiveBackdrop(
                      palette: palette,
                      metrics: metrics,
                    ),
                    Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: metrics.outerHorizontalPadding,
                          vertical: metrics.outerVerticalPadding,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: metrics.shellWidth,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(metrics.shellRadius),
                              border: metrics.showDesktopFrame
                                  ? Border.all(
                                      color:
                                          palette.border.withValues(alpha: 0.9),
                                    )
                                  : null,
                              boxShadow: metrics.showDesktopFrame
                                  ? [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.16),
                                        blurRadius: 34,
                                        offset: const Offset(0, 18),
                                      ),
                                    ]
                                  : null,
                              gradient: metrics.showDesktopFrame
                                  ? LinearGradient(
                                      colors: [
                                        palette.surfaceAlt,
                                        palette.surface,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                            ),
                            child: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(metrics.shellRadius),
                              child: ColoredBox(
                                color: palette.pageBackground,
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    metrics.contentPadding,
                                    metrics.contentPadding - 2,
                                    metrics.contentPadding,
                                    metrics.contentPadding - 2,
                                  ),
                                  child: Column(
                                    children: [
                                      if (_selectedTabIndex != 2) ...[
                                        _buildHeader(
                                          palette: palette,
                                          metrics: metrics,
                                          displayName: displayName,
                                          email: email,
                                          roleText: roleText,
                                          photoUrl: photoUrl,
                                        ),
                                        SizedBox(height: metrics.sectionGap),
                                      ],
                                      Expanded(
                                        child: AnimatedSwitcher(
                                          duration:
                                              const Duration(milliseconds: 220),
                                          child: _buildTabContent(
                                            key: ValueKey<int>(
                                                _selectedTabIndex),
                                            palette: palette,
                                            metrics: metrics,
                                            profilePhotoUrl: photoUrl,
                                            role: role,
                                            uid: uid,
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: metrics.sectionGap),
                                      _buildBottomNavigation(
                                        palette: palette,
                                        metrics: metrics,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopLayout({
    required _ConsolePalette palette,
    required _ResponsiveMetrics metrics,
    required String displayName,
    required String email,
    required String roleText,
    required String photoUrl,
    required bool showHeader,
    required UserRole role,
    required String uid,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.outerHorizontalPadding,
        vertical: metrics.outerVerticalPadding,
      ),
      child: Column(
        children: [
          if (showHeader) ...[
            _buildHeader(
              palette: palette,
              metrics: metrics,
              displayName: displayName,
              email: email,
              roleText: roleText,
              photoUrl: photoUrl,
            ),
            SizedBox(height: metrics.sectionGap + 4),
          ],
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSideNavigation(
                  palette: palette,
                  metrics: metrics,
                ),
                SizedBox(width: metrics.sectionGap + 6),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _buildTabContent(
                      key: ValueKey<int>(_selectedTabIndex),
                      palette: palette,
                      metrics: metrics,
                      profilePhotoUrl: photoUrl,
                      role: role,
                      uid: uid,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveBackdrop({
    required _ConsolePalette palette,
    required _ResponsiveMetrics metrics,
  }) {
    if (!metrics.showDesktopFrame) {
      return const SizedBox.shrink();
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            palette.pageBackground,
            palette.surfaceAlt.withValues(alpha: 0.45),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -120,
            top: -80,
            child: _buildGlowOrb(
              color: palette.accent.withValues(alpha: 0.1),
              size: 320,
            ),
          ),
          Positioned(
            right: -110,
            bottom: -120,
            child: _buildGlowOrb(
              color: palette.success.withValues(alpha: 0.09),
              size: 280,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlowOrb({required Color color, required double size}) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }

  Widget _buildHeader({
    required _ConsolePalette palette,
    required _ResponsiveMetrics metrics,
    required String displayName,
    required String email,
    required String roleText,
    required String photoUrl,
  }) {
    return Container(
      padding: EdgeInsets.all(metrics.cardPadding),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(metrics.cardRadius),
        border: Border.all(color: palette.border),
        gradient: LinearGradient(
          colors: [palette.surface, palette.surfaceAlt],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: metrics.avatarRadius,
            backgroundColor: palette.accent.withValues(alpha: 0.14),
            backgroundImage: photoUrl.isEmpty ? null : NetworkImage(photoUrl),
            child: photoUrl.isEmpty
                ? Text(
                    displayName.isEmpty ? '?' : displayName[0].toUpperCase(),
                    style: TextStyle(
                      color: palette.accent,
                      fontSize: metrics.titleFontSize,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          ),
          SizedBox(width: metrics.inlineGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: metrics.titleFontSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: metrics.bodyFontSize,
                  ),
                ),
                SizedBox(height: metrics.inlineGap - 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: palette.accent.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    roleText,
                    style: TextStyle(
                      color: palette.accent,
                      fontSize: metrics.bodyFontSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: _signOut,
            icon: Icon(Icons.logout_rounded, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation({
    required _ConsolePalette palette,
    required _ResponsiveMetrics metrics,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(metrics.cardRadius),
        border: Border.all(color: palette.border),
      ),
      child: NavigationBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        height: metrics.navBarHeight,
        indicatorColor: palette.accent.withValues(alpha: 0.15),
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedTabIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag_rounded),
            label: 'Corridas',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note_rounded),
            label: 'Eventos',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  Widget _buildSideNavigation({
    required _ConsolePalette palette,
    required _ResponsiveMetrics metrics,
  }) {
    return Container(
      width: metrics.sidebarWidth,
      padding: EdgeInsets.all(metrics.cardPadding - 2),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(metrics.cardRadius),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSideNavButton(
            index: 0,
            icon: Icons.flag_rounded,
            label: 'Corridas',
            palette: palette,
            metrics: metrics,
          ),
          const SizedBox(height: 8),
          _buildSideNavButton(
            index: 1,
            icon: Icons.event_note_rounded,
            label: 'Eventos',
            palette: palette,
            metrics: metrics,
          ),
          const SizedBox(height: 8),
          _buildSideNavButton(
            index: 2,
            icon: Icons.person_rounded,
            label: 'Perfil',
            palette: palette,
            metrics: metrics,
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Menu',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: metrics.bodyFontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideNavButton({
    required int index,
    required IconData icon,
    required String label,
    required _ConsolePalette palette,
    required _ResponsiveMetrics metrics,
  }) {
    final selected = _selectedTabIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _selectedTabIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? palette.accent.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? palette.accent.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? palette.accent : palette.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color:
                        selected ? palette.textPrimary : palette.textSecondary,
                    fontSize: metrics.titleFontSize - 1,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent({
    required Key key,
    required _ConsolePalette palette,
    required _ResponsiveMetrics metrics,
    required String profilePhotoUrl,
    required UserRole role,
    required String uid,
  }) {
    switch (_selectedTabIndex) {
      case 1:
        return _buildEventsTab(
          key: key,
          palette: palette,
          metrics: metrics,
          role: role,
          uid: uid,
        );
      case 2:
        return _buildProfileTab(
          key: key,
          palette: palette,
          metrics: metrics,
          profilePhotoUrl: profilePhotoUrl,
          uid: uid,
        );
      case 0:
      default:
        return _buildRacesTab(
          key: key,
          palette: palette,
          metrics: metrics,
        );
    }
  }

  Widget _buildFilterShell({
    required _ConsolePalette palette,
    required _ResponsiveMetrics metrics,
    required Widget child,
  }) {
    return Container(
      padding: EdgeInsets.all(metrics.cardPadding - 2),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(metrics.cardRadius - 2),
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
  }

  Widget _buildRacesTab({
    required Key key,
    required _ConsolePalette palette,
    required _ResponsiveMetrics metrics,
  }) {
    final query = _raceSearchController.text.trim();

    return Column(
      key: key,
      children: [
        _buildFilterShell(
          palette: palette,
          metrics: metrics,
          child: Column(
            children: [
              TextField(
                controller: _raceSearchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Buscar corrida por nome',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDateRange(
                        currentRange: _raceDateRange,
                        onChanged: (value) =>
                            setState(() => _raceDateRange = value),
                      ),
                      icon: const Icon(Icons.date_range_rounded),
                      label: Text(
                        _raceDateRange == null
                            ? 'Período'
                            : '${DateFormat('dd/MM').format(_raceDateRange!.start)} - ${DateFormat('dd/MM').format(_raceDateRange!.end)}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Limpar filtros',
                    onPressed: () {
                      setState(() {
                        _raceSearchController.clear();
                        _raceDateRange = null;
                      });
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: metrics.sectionGap),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestoreService.getOpenRaces(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text('Erro ao carregar corridas: ${snapshot.error}'),
                );
              }

              final docs = snapshot.data?.docs ?? const [];
              final races = docs.map((doc) {
                final data =
                    doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
                return _RaceRow(
                  id: doc.id,
                  name: _firstNonEmpty([data['name'], 'Corrida sem nome']),
                  date: _extractRaceDate(data),
                  status: _firstNonEmpty([data['status'], 'open']),
                );
              }).where((race) {
                return _containsQuery(race.name, query) &&
                    _isDateInRange(race.date, _raceDateRange);
              }).toList()
                ..sort((a, b) {
                  final left = a.date?.millisecondsSinceEpoch ?? 0;
                  final right = b.date?.millisecondsSinceEpoch ?? 0;
                  return right.compareTo(left);
                });

              if (races.isEmpty) {
                return _buildEmptyState(
                  palette: palette,
                  text: 'Nenhuma corrida encontrada com os filtros atuais.',
                );
              }

              if (metrics.isDesktopLayout) {
                return GridView.builder(
                  itemCount: races.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: metrics.desktopListColumns,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: metrics.desktopCardAspectRatio,
                  ),
                  itemBuilder: (context, index) {
                    final race = races[index];
                    return _buildDataCard(
                      palette: palette,
                      metrics: metrics,
                      title: race.name,
                      subtitle: _formatDate(race.date),
                      badge: race.status.toUpperCase(),
                      badgeColor: palette.warning,
                    );
                  },
                );
              }

              return ListView.separated(
                itemCount: races.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final race = races[index];
                  return _buildDataCard(
                    palette: palette,
                    metrics: metrics,
                    title: race.name,
                    subtitle: _formatDate(race.date),
                    badge: race.status.toUpperCase(),
                    badgeColor: palette.warning,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openPublicEventDetails(_PublicEventRow event) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PublicEventDetailsPageWidget(eventId: event.id),
      ),
    );
  }

  Widget _buildPublicEventCard({
    required _ConsolePalette palette,
    required _ResponsiveMetrics metrics,
    required _PublicEventRow event,
  }) {
    final statusColor = _eventStatusColor(event.status, palette);
    final locationLabel = [
      if (event.location.isNotEmpty) event.location,
      if (event.state.isNotEmpty) event.state,
    ].join(' - ');
    final priceLabel = event.registrationPrice != null
        ? 'Inscrição: R\$ ${event.registrationPrice!.toStringAsFixed(2)}'
        : 'Inscrição: consultar organização';
    final dateLabel = _formatDateRange(event.startDate, event.endDate);

    if (metrics.isDesktopLayout) {
      return InkWell(
        borderRadius: BorderRadius.circular(metrics.cardRadius - 2),
        onTap: () => _openPublicEventDetails(event),
        child: Container(
          padding: EdgeInsets.all(metrics.cardPadding),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(metrics.cardRadius - 2),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    _eventStatusLabel(event.status),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                event.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: metrics.titleFontSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                dateLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: metrics.bodyFontSize + 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                locationLabel.isEmpty ? 'Local não informado' : locationLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: metrics.bodyFontSize + 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                priceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: metrics.bodyFontSize + 1,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(metrics.cardRadius - 2),
        border: Border.all(color: palette.border),
      ),
      child: ListTile(
        onTap: () => _openPublicEventDetails(event),
        minVerticalPadding: 12,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        title: Text(
          event.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dateLabel,
                style: TextStyle(color: palette.textSecondary),
              ),
              const SizedBox(height: 2),
              Text(
                locationLabel.isEmpty ? 'Local não informado' : locationLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.textSecondary),
              ),
              const SizedBox(height: 2),
              Text(
                priceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.textSecondary),
              ),
            ],
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: statusColor.withValues(alpha: 0.4)),
          ),
          child: Text(
            _eventStatusLabel(event.status),
            style: TextStyle(
              color: statusColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEventsTab({
    required Key key,
    required _ConsolePalette palette,
    required _ResponsiveMetrics metrics,
    required UserRole role,
    required String uid,
  }) {
    final query = _eventSearchController.text.trim();

    return Column(
      key: key,
      children: [
        _buildFilterShell(
          palette: palette,
          metrics: metrics,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _eventSearchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Buscar evento por nome',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDateRange(
                        currentRange: _eventDateRange,
                        onChanged: (value) =>
                            setState(() => _eventDateRange = value),
                      ),
                      icon: const Icon(Icons.date_range_rounded),
                      label: Text(
                        _eventDateRange == null
                            ? 'Período'
                            : '${DateFormat('dd/MM').format(_eventDateRange!.start)} - ${DateFormat('dd/MM').format(_eventDateRange!.end)}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Limpar filtros',
                    onPressed: () {
                      setState(() {
                        _eventSearchController.clear();
                        _eventDateRange = null;
                        _onlyMyEvents = false;
                      });
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (role == UserRole.pilot) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('Somente inscritas'),
                      selected: _onlyMyEvents,
                      onSelected: (value) =>
                          _toggleMyEventsOnly(value, role, uid),
                    ),
                    if (_loadingMyEvents)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: metrics.sectionGap),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db.collection('events_public').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text('Erro ao carregar eventos: ${snapshot.error}'),
                );
              }

              final docs = snapshot.data?.docs ?? const [];
              final events = docs.map((doc) {
                final data = doc.data();
                return _PublicEventRow(
                  id: doc.id,
                  name: _firstNonEmpty([data['name'], 'Evento sem nome']),
                  startDate: _extractPublicEventStartDate(data),
                  endDate: _extractPublicEventEndDate(data),
                  location: _firstNonEmpty(
                      [data['location'], data['track_display_name']]),
                  state: _firstNonEmpty([data['state']]),
                  status: _normalizeEventStatus(data['status']),
                  categories: data['categories'] is List
                      ? List<String>.from(
                          (data['categories'] as List)
                              .whereType<dynamic>()
                              .map((e) => e.toString()),
                        )
                      : const <String>[],
                  registrationPrice: _asDoubleOrNull(
                    data['registration_price'] ?? data['registrationPrice'],
                  ),
                  ticketPrice: _asDoubleOrNull(
                    data['ticket_price'] ?? data['ticketPrice'],
                  ),
                  rawData: data,
                );
              }).where((event) {
                if (!_containsQuery(event.name, query)) return false;
                if (!_isDateInRange(event.startDate, _eventDateRange)) {
                  return false;
                }
                if (_onlyMyEvents && role == UserRole.pilot) {
                  return _myEventIds.contains(event.id);
                }
                return true;
              }).toList()
                ..sort((a, b) {
                  final left = a.startDate?.millisecondsSinceEpoch ?? 0;
                  final right = b.startDate?.millisecondsSinceEpoch ?? 0;
                  return right.compareTo(left);
                });

              if (events.isEmpty) {
                return _buildEmptyState(
                  palette: palette,
                  text: _onlyMyEvents
                      ? 'Nenhum evento inscrito com os filtros selecionados.'
                      : 'Nenhum evento encontrado com os filtros atuais.',
                );
              }

              if (metrics.isDesktopLayout) {
                return GridView.builder(
                  itemCount: events.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: metrics.desktopListColumns,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: metrics.desktopCardAspectRatio,
                  ),
                  itemBuilder: (context, index) {
                    final event = events[index];
                    return _buildPublicEventCard(
                      palette: palette,
                      metrics: metrics,
                      event: event,
                    );
                  },
                );
              }

              return ListView.separated(
                itemCount: events.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final event = events[index];
                  return _buildPublicEventCard(
                    palette: palette,
                    metrics: metrics,
                    event: event,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProfileTab({
    required Key key,
    required _ConsolePalette palette,
    required _ResponsiveMetrics metrics,
    required String profilePhotoUrl,
    required String uid,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final resolvedPhotoUrl = profilePhotoUrl.trim();

    return Align(
      key: key,
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: metrics.isDesktopLayout ? 640 : double.infinity,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
                child: Text(
                  'Editar Perfil',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: metrics.titleFontSize + 5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _buildFilterShell(
                palette: palette,
                metrics: metrics,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dados pessoais',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: metrics.bodyFontSize + 1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: CircleAvatar(
                        radius: 44,
                        backgroundColor: palette.accent.withValues(alpha: 0.14),
                        backgroundImage: resolvedPhotoUrl.isEmpty
                            ? null
                            : NetworkImage(resolvedPhotoUrl),
                        child: resolvedPhotoUrl.isEmpty
                            ? Icon(
                                Icons.person_rounded,
                                color: palette.accent,
                                size: 32,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _uploadingProfilePhoto
                            ? null
                            : () => _pickAndUploadProfilePhoto(uid),
                        icon: _uploadingProfilePhoto
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.upload_rounded),
                        label: Text(
                          _uploadingProfilePhoto
                              ? 'Enviando foto...'
                              : 'Upload da foto do dispositivo',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nome',
                        prefixIcon: Icon(Icons.badge_outlined),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.contrast_rounded, color: palette.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tema',
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Switch(
                          value: isDarkMode,
                          onChanged: (value) {
                            final mode =
                                value ? ThemeMode.dark : ThemeMode.light;
                            MyApp.of(context).setThemeMode(mode);
                          },
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        isDarkMode ? 'Tema escuro' : 'Tema claro',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: metrics.bodyFontSize + 1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            _savingProfile ? null : () => _saveProfile(uid),
                        icon: _savingProfile
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                            _savingProfile ? 'Salvando...' : 'Salvar perfil'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataCard({
    required _ConsolePalette palette,
    required _ResponsiveMetrics metrics,
    required String title,
    required String subtitle,
    required String badge,
    required Color badgeColor,
  }) {
    if (metrics.isDesktopLayout) {
      return Container(
        padding: EdgeInsets.all(metrics.cardPadding),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(metrics.cardRadius - 2),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: metrics.titleFontSize,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: metrics.bodyFontSize + 1,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(metrics.cardRadius - 2),
        border: Border.all(color: palette.border),
      ),
      child: ListTile(
        minVerticalPadding: 12,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            subtitle,
            style: TextStyle(color: palette.textSecondary),
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
          ),
          child: Text(
            badge,
            style: TextStyle(
              color: badgeColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required _ConsolePalette palette,
    required String text,
  }) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.textSecondary),
        ),
      ),
    );
  }
}

class _ResponsiveMetrics {
  const _ResponsiveMetrics({
    required this.isDesktopLayout,
    required this.showDesktopFrame,
    required this.shellWidth,
    required this.sidebarWidth,
    required this.desktopListColumns,
    required this.desktopCardAspectRatio,
    required this.outerHorizontalPadding,
    required this.outerVerticalPadding,
    required this.shellRadius,
    required this.contentPadding,
    required this.sectionGap,
    required this.cardPadding,
    required this.cardRadius,
    required this.avatarRadius,
    required this.inlineGap,
    required this.titleFontSize,
    required this.bodyFontSize,
    required this.navBarHeight,
  });

  final bool isDesktopLayout;
  final bool showDesktopFrame;
  final double shellWidth;
  final double sidebarWidth;
  final int desktopListColumns;
  final double desktopCardAspectRatio;
  final double outerHorizontalPadding;
  final double outerVerticalPadding;
  final double shellRadius;
  final double contentPadding;
  final double sectionGap;
  final double cardPadding;
  final double cardRadius;
  final double avatarRadius;
  final double inlineGap;
  final double titleFontSize;
  final double bodyFontSize;
  final double navBarHeight;

  static _ResponsiveMetrics fromConstraints(BoxConstraints constraints) {
    final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 390.0;
    final height =
        constraints.maxHeight.isFinite ? constraints.maxHeight : 800.0;
    final isDesktop = width >= 1024;
    final isTablet = width >= 700 && width < 1024;
    final showDesktopFrame = width >= 860;

    final outerHorizontalPadding = isDesktop ? 28.0 : (isTablet ? 20.0 : 8.0);
    final outerVerticalPadding = isDesktop ? 18.0 : 8.0;
    final availableWidth =
        (width - (outerHorizontalPadding * 2)).clamp(280.0, 1600.0).toDouble();

    final baseByHeight =
        (height - (outerVerticalPadding * 2)) * (isDesktop ? 0.55 : 0.62);
    double targetWidth;
    if (isDesktop) {
      targetWidth = baseByHeight.clamp(470.0, 620.0).toDouble();
    } else if (isTablet) {
      targetWidth = baseByHeight.clamp(440.0, 560.0).toDouble();
    } else {
      targetWidth = availableWidth;
    }

    final shellWidth =
        targetWidth > availableWidth ? availableWidth : targetWidth;

    return _ResponsiveMetrics(
      isDesktopLayout: isDesktop,
      showDesktopFrame: showDesktopFrame,
      shellWidth: shellWidth,
      sidebarWidth: isDesktop ? 230 : 0,
      desktopListColumns: isDesktop ? 3 : 1,
      desktopCardAspectRatio: isDesktop ? 1.72 : 2.3,
      outerHorizontalPadding: outerHorizontalPadding,
      outerVerticalPadding: outerVerticalPadding,
      shellRadius: showDesktopFrame ? 30 : 0,
      contentPadding: isDesktop ? 18 : (isTablet ? 16 : 12),
      sectionGap: isDesktop ? 12 : 10,
      cardPadding: isDesktop ? 16 : 14,
      cardRadius: isDesktop ? 24 : 20,
      avatarRadius: isDesktop ? 30 : 26,
      inlineGap: isDesktop ? 14 : 12,
      titleFontSize: isDesktop ? 17 : 16,
      bodyFontSize: 12,
      navBarHeight: isDesktop ? 76 : 72,
    );
  }
}

class _RaceRow {
  _RaceRow({
    required this.id,
    required this.name,
    required this.date,
    required this.status,
  });

  final String id;
  final String name;
  final DateTime? date;
  final String status;
}

class _PublicEventRow {
  _PublicEventRow({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.location,
    required this.state,
    required this.status,
    required this.categories,
    required this.registrationPrice,
    required this.ticketPrice,
    required this.rawData,
  });

  final String id;
  final String name;
  final DateTime? startDate;
  final DateTime? endDate;
  final String location;
  final String state;
  final String status;
  final List<String> categories;
  final double? registrationPrice;
  final double? ticketPrice;
  final Map<String, dynamic> rawData;
}

class _ConsolePalette {
  const _ConsolePalette({
    required this.pageBackground,
    required this.surface,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.accent,
    required this.success,
    required this.warning,
  });

  final Color pageBackground;
  final Color surface;
  final Color surfaceAlt;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color accent;
  final Color success;
  final Color warning;

  static _ConsolePalette of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return const _ConsolePalette(
        pageBackground: Color(0xFF000000),
        surface: Color(0xFF1A1A1A),
        surfaceAlt: Color(0xFF161619),
        textPrimary: Color(0xFFF0F0F2),
        textSecondary: Color(0xFF9898A0),
        border: Color(0xFF2A2A30),
        accent: Color(0xFFFF4500),
        success: Color(0xFF00FF66),
        warning: Color(0xFFFFD700),
      );
    }
    return const _ConsolePalette(
      pageBackground: Color(0xFFF5F6F8),
      surface: Color(0xFFFFFFFF),
      surfaceAlt: Color(0xFFF7F8FA),
      textPrimary: Color(0xFF17181B),
      textSecondary: Color(0xFF5A606B),
      border: Color(0xFFDADDE4),
      accent: Color(0xFFFF4500),
      success: Color(0xFF128049),
      warning: Color(0xFFB28704),
    );
  }
}
