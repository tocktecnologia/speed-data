import '/auth/firebase_auth/auth_util.dart';
import '/auth/firebase_auth/google_auth.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../theme/speed_data_theme.dart';
import '../theme/speed_data_components.dart';
import 'login_model.dart';
export 'login_model.dart';
import 'package:speed_data/features/models/user_role.dart';
import 'package:speed_data/features/services/firestore_service.dart';

class LoginWidget extends StatefulWidget {
  const LoginWidget({super.key});

  static String routeName = 'Login';
  static String routePath = '/login';

  @override
  State<LoginWidget> createState() => _LoginWidgetState();
}

class _LoginWidgetState extends State<LoginWidget> {
  late LoginModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();
  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => LoginModel());

    _model.emailAddressTextController ??= TextEditingController();
    _model.emailAddressFocusNode ??= FocusNode();

    _model.passwordTextController ??= TextEditingController();
    _model.passwordFocusNode ??= FocusNode();
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  Future<String?> _showRolePickerDialog() async {
    String selectedRole = 'pilot';

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Escolha seu perfil'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Selecione o perfil para este acesso:'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Perfil',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'pilot',
                        child: Text('Piloto'),
                      ),
                      DropdownMenuItem(
                        value: 'team_member',
                        child: Text('Equipe'),
                      ),
                      DropdownMenuItem(
                        value: 'admin',
                        child: Text('Administrador'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => selectedRole = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(selectedRole),
                  child: const Text('Continuar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _showPasswordForGoogleLinkDialog(String email) async {
    final controller = TextEditingController();

    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: true,
        builder: (context) {
          return AlertDialog(
            title: const Text('Vincular login Google'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Para $email, informe a senha atual para vincular ao Google.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Senha',
                  ),
                  onSubmitted: (_) =>
                      Navigator.of(context).pop(controller.text.trim()),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).pop(controller.text.trim()),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController(
      text: _model.emailAddressTextController.text.trim(),
    );

    try {
      final email = await showDialog<String>(
        context: context,
        barrierDismissible: true,
        builder: (context) {
          return AlertDialog(
            title: const Text('Recuperar senha'),
            content: TextField(
              controller: emailController,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
              ),
              onSubmitted: (_) =>
                  Navigator.of(context).pop(emailController.text.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).pop(emailController.text.trim()),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );

      final normalizedEmail = (email ?? '').trim();
      if (normalizedEmail.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe um email valido.')),
        );
        return;
      }

      if (!mounted) return;
      await authManager.resetPassword(
        email: normalizedEmail,
        context: context,
      );
    } finally {
      emailController.dispose();
    }
  }

  bool _isPersistedRole(UserRole role) {
    return role == UserRole.pilot ||
        role == UserRole.teamMember ||
        role == UserRole.admin ||
        role == UserRole.root;
  }

  Future<UserRole> _getRoleByUid(String uid) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      return UserRole.unknown;
    }
    return _firestoreService.getUserRole(normalizedUid);
  }

  Future<UserRole> _getRoleByEmail(String email) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) {
      return UserRole.unknown;
    }

    final userData = await _firestoreService.getUserByEmail(normalizedEmail);
    if (userData == null) {
      return UserRole.unknown;
    }

    return UserRole.fromString(userData['role'] as String?);
  }

  Future<UserRole> _resolveExistingRole({
    required String uid,
    required String email,
  }) async {
    final roleByUid = await _getRoleByUid(uid);
    if (_isPersistedRole(roleByUid)) {
      return roleByUid;
    }

    final roleByEmail = await _getRoleByEmail(email);
    if (_isPersistedRole(roleByEmail)) {
      return roleByEmail;
    }

    return UserRole.unknown;
  }

  Future<void> _ensureRoleIfMissing({
    required String uid,
    required String selectedRole,
    String? email,
  }) async {
    final normalizedEmail = (email ?? '').trim();
    final existingRole = await _resolveExistingRole(
      uid: uid,
      email: normalizedEmail,
    );
    if (_isPersistedRole(existingRole)) {
      if (normalizedEmail.isNotEmpty) {
        await _firestoreService.setUserRole(
          uid,
          existingRole,
          email: normalizedEmail,
        );
      }
      return;
    }

    final role = UserRole.fromString(selectedRole);
    await _firestoreService.setUserRole(
      uid,
      role,
      email: normalizedEmail.isEmpty ? null : normalizedEmail,
    );
  }

  Future<void> _completeGoogleLoginFlow() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      return;
    }

    final uid = authUser.uid.trim();
    if (uid.isEmpty) {
      return;
    }

    final email = (authUser.email ?? '').trim();
    final existingRole = await _resolveExistingRole(uid: uid, email: email);

    if (!_isPersistedRole(existingRole)) {
      if (!mounted) return;
      final selectedRole = await _showRolePickerDialog();
      if (selectedRole == null) {
        await authManager.signOut();
        return;
      }

      await _ensureRoleIfMissing(
        uid: uid,
        selectedRole: selectedRole,
        email: email,
      );
    }

    if (!mounted) return;
    context.goNamedAuth(HomePageWidget.routeName, context.mounted);
  }

  Future<bool> _handleGoogleConflict(
    GoogleSignInAccountConflictException conflict,
  ) async {
    final password = await _showPasswordForGoogleLinkDialog(conflict.email);
    final normalizedPassword = (password ?? '').trim();
    if (normalizedPassword.isEmpty) {
      return false;
    }

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: conflict.email,
        password: normalizedPassword,
      );

      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser == null) {
        return false;
      }

      final hasGoogleProvider = authUser.providerData
          .any((provider) => provider.providerId == 'google.com');
      if (!hasGoogleProvider) {
        await authUser.linkWithCredential(conflict.pendingCredential);
      }
      return true;
    } on FirebaseAuthException catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao vincular Google: ${e.message}')),
      );
      return false;
    }
  }

  Future<void> _handleGoogleLogin() async {
    try {
      GoRouter.of(context).prepareAuthEvent();
      final user = await authManager.signInWithGoogle(context);
      if (user == null) {
        return;
      }
      await _completeGoogleLoginFlow();
    } on GoogleSignInAccountConflictException catch (conflict) {
      final linked = await _handleGoogleConflict(conflict);
      if (!linked) return;
      await _completeGoogleLoginFlow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: SpeedDataTheme.bgBase,
        body: SafeArea(
          top: true,
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                flex: 6,
                child: Container(
                  width: 100.0,
                  height: double.infinity,
                  decoration: const BoxDecoration(
                    color: SpeedDataTheme.bgBase,
                  ),
                  alignment: const AlignmentDirectional(0.0, -1.0),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (responsiveVisibility(
                          context: context,
                          phone: false,
                          tablet: false,
                        ))
                          Container(
                            width: double.infinity,
                            height: 140.0,
                            decoration: const BoxDecoration(
                              color: SpeedDataTheme.bgBase,
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(16.0),
                                bottomRight: Radius.circular(16.0),
                              ),
                            ),
                            alignment: const AlignmentDirectional(-1.0, 0.0),
                            child: Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  24.0, 0.0, 0.0, 0.0),
                              child: Text(
                                'Speed Data',
                                style: SpeedDataTheme
                                    .themeData.textTheme.displaySmall,
                              ),
                            ),
                          ),
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(
                            maxWidth: 430.0,
                          ),
                          decoration: const BoxDecoration(
                            color: SpeedDataTheme.bgBase,
                          ),
                          child: Align(
                            alignment: const AlignmentDirectional(0.0, 0.0),
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.max,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Bem vindo!',
                                    style: SpeedDataTheme
                                        .themeData.textTheme.headlineLarge,
                                  ),
                                  Padding(
                                    padding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                            0.0, 12.0, 0.0, 24.0),
                                    child: Text(
                                      'Let\'s get started by filling out the form below.',
                                      style: SpeedDataTheme
                                          .themeData.textTheme.bodyMedium
                                          ?.copyWith(
                                        color: SpeedDataTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                            0.0, 30.0, 0.0, 0.0),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: SpeedButton.secondary(
                                        onPressed: _handleGoogleLogin,
                                        text: 'Entrar pelo Google',
                                        icon: const FaIcon(
                                          FontAwesomeIcons.google,
                                          size: 20.0,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                            0.0, 24.0, 0.0, 24.0),
                                    child: SizedBox(
                                      width: 370.0,
                                      child: Row(
                                        children: [
                                          const Expanded(
                                              child: Divider(
                                                  color: SpeedDataTheme
                                                      .borderSubtle)),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 16.0),
                                            child: Text(
                                              'OU',
                                              style: SpeedDataTheme.themeData
                                                  .textTheme.bodySmall,
                                            ),
                                          ),
                                          const Expanded(
                                              child: Divider(
                                                  color: SpeedDataTheme
                                                      .borderSubtle)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.max,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsetsDirectional
                                            .fromSTEB(0.0, 0.0, 0.0, 16.0),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: TextFormField(
                                            controller: _model
                                                .emailAddressTextController,
                                            focusNode:
                                                _model.emailAddressFocusNode,
                                            autofocus: true,
                                            autofillHints: const [
                                              AutofillHints.email
                                            ],
                                            obscureText: false,
                                            decoration: InputDecoration(
                                              labelText: 'Email',
                                              labelStyle: SpeedDataTheme
                                                  .themeData
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                      color: SpeedDataTheme
                                                          .textSecondary),
                                              enabledBorder: OutlineInputBorder(
                                                borderSide: const BorderSide(
                                                  color: SpeedDataTheme
                                                      .borderSubtle,
                                                  width: 1.0,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        SpeedDataTheme
                                                            .radiusMd),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderSide: const BorderSide(
                                                  color: SpeedDataTheme
                                                      .accentPrimary,
                                                  width: 1.0,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        SpeedDataTheme
                                                            .radiusMd),
                                              ),
                                              errorBorder: OutlineInputBorder(
                                                borderSide: const BorderSide(
                                                  color: SpeedDataTheme
                                                      .accentDanger,
                                                  width: 1.0,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        SpeedDataTheme
                                                            .radiusMd),
                                              ),
                                              focusedErrorBorder:
                                                  OutlineInputBorder(
                                                borderSide: const BorderSide(
                                                  color: SpeedDataTheme
                                                      .accentDanger,
                                                  width: 1.0,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        SpeedDataTheme
                                                            .radiusMd),
                                              ),
                                              filled: true,
                                              fillColor:
                                                  SpeedDataTheme.bgSurface,
                                            ),
                                            style: SpeedDataTheme
                                                .themeData.textTheme.bodyMedium,
                                            keyboardType:
                                                TextInputType.emailAddress,
                                            validator: _model
                                                .emailAddressTextControllerValidator
                                                .asValidator(context),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsetsDirectional
                                            .fromSTEB(0.0, 0.0, 0.0, 16.0),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: TextFormField(
                                            controller:
                                                _model.passwordTextController,
                                            focusNode: _model.passwordFocusNode,
                                            autofocus: true,
                                            autofillHints: const [
                                              AutofillHints.password
                                            ],
                                            obscureText:
                                                !_model.passwordVisibility,
                                            decoration: InputDecoration(
                                              labelText: 'Password',
                                              labelStyle: SpeedDataTheme
                                                  .themeData
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                      color: SpeedDataTheme
                                                          .textSecondary),
                                              enabledBorder: OutlineInputBorder(
                                                borderSide: const BorderSide(
                                                  color: SpeedDataTheme
                                                      .borderSubtle,
                                                  width: 1.0,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        SpeedDataTheme
                                                            .radiusMd),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderSide: const BorderSide(
                                                  color: SpeedDataTheme
                                                      .accentPrimary,
                                                  width: 1.0,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        SpeedDataTheme
                                                            .radiusMd),
                                              ),
                                              errorBorder: OutlineInputBorder(
                                                borderSide: const BorderSide(
                                                  color: SpeedDataTheme
                                                      .accentDanger,
                                                  width: 1.0,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        SpeedDataTheme
                                                            .radiusMd),
                                              ),
                                              focusedErrorBorder:
                                                  OutlineInputBorder(
                                                borderSide: const BorderSide(
                                                  color: SpeedDataTheme
                                                      .accentDanger,
                                                  width: 1.0,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        SpeedDataTheme
                                                            .radiusMd),
                                              ),
                                              filled: true,
                                              fillColor:
                                                  SpeedDataTheme.bgSurface,
                                              suffixIcon: InkWell(
                                                onTap: () async {
                                                  safeSetState(() => _model
                                                          .passwordVisibility =
                                                      !_model
                                                          .passwordVisibility);
                                                },
                                                focusNode: FocusNode(
                                                    skipTraversal: true),
                                                child: Icon(
                                                  _model.passwordVisibility
                                                      ? Icons
                                                          .visibility_outlined
                                                      : Icons
                                                          .visibility_off_outlined,
                                                  color: SpeedDataTheme
                                                      .textSecondary,
                                                  size: 24.0,
                                                ),
                                              ),
                                            ),
                                            style: SpeedDataTheme
                                                .themeData.textTheme.bodyMedium,
                                            validator: _model
                                                .passwordTextControllerValidator
                                                .asValidator(context),
                                          ),
                                        ),
                                      ),
                                      Align(
                                        alignment: const AlignmentDirectional(
                                            1.0, 0.0),
                                        child: Padding(
                                          padding: const EdgeInsetsDirectional
                                              .fromSTEB(0.0, 0.0, 0.0, 16.0),
                                          child: InkWell(
                                            onTap: _showForgotPasswordDialog,
                                            child: Text(
                                              'Esqueci minha senha',
                                              style: SpeedDataTheme
                                                  .themeData.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: SpeedDataTheme
                                                    .accentPrimary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsetsDirectional
                                            .fromSTEB(0.0, 0.0, 0.0, 16.0),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: SpeedButton.primary(
                                            onPressed: () async {
                                              final currentContext = context;
                                              GoRouter.of(currentContext)
                                                  .prepareAuthEvent();
                                              final user = await authManager
                                                  .signInWithEmail(
                                                currentContext,
                                                _model
                                                    .emailAddressTextController
                                                    .text,
                                                _model.passwordTextController
                                                    .text,
                                              );
                                              if (user == null) {
                                                return;
                                              }
                                              if (!currentContext.mounted) {
                                                return;
                                              }
                                              currentContext.goNamedAuth(
                                                  HomePageWidget.routeName,
                                                  currentContext.mounted);
                                            },
                                            text: 'Entrar',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Align(
                                    alignment:
                                        const AlignmentDirectional(0.0, 0.0),
                                    child: Padding(
                                      padding:
                                          const EdgeInsetsDirectional.fromSTEB(
                                              0.0, 12.0, 0.0, 12.0),
                                      child: InkWell(
                                        splashColor: Colors.transparent,
                                        focusColor: Colors.transparent,
                                        hoverColor: Colors.transparent,
                                        highlightColor: Colors.transparent,
                                        onTap: () async {
                                          context.pushNamed(
                                              SignUpWidget.routeName);
                                        },
                                        child: RichText(
                                          textScaler:
                                              MediaQuery.of(context).textScaler,
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text: 'Ainda não tem conta? ',
                                                style: SpeedDataTheme.themeData
                                                    .textTheme.bodyMedium,
                                              ),
                                              TextSpan(
                                                text: 'Cadastrar',
                                                style: SpeedDataTheme.themeData
                                                    .textTheme.bodyMedium
                                                    ?.copyWith(
                                                  color: SpeedDataTheme
                                                      .accentPrimary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              )
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (responsiveVisibility(
                context: context,
                phone: false,
                tablet: false,
              ))
                Expanded(
                  flex: 8,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          SpeedDataTheme.bgBase,
                          SpeedDataTheme.bgSurface
                        ],
                        stops: [0.0, 1.0],
                        begin: AlignmentDirectional(1.0, -1.0),
                        end: AlignmentDirectional(-1.0, 1.0),
                      ),
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: SpeedDataTheme.bgSurface,
                          borderRadius: BorderRadius.circular(24),
                          border:
                              Border.all(color: SpeedDataTheme.borderSubtle),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.speed,
                                size: 64, color: SpeedDataTheme.accentPrimary),
                            const SizedBox(height: 16),
                            Text(
                              'Speed Data',
                              style: SpeedDataTheme
                                  .themeData.textTheme.displayMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
