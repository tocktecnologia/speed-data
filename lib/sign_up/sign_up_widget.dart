import '/auth/firebase_auth/auth_util.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'dart:ui';
import '/index.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/speed_data_theme.dart';
import '../theme/speed_data_components.dart';
import 'sign_up_model.dart';
export 'sign_up_model.dart';
import 'package:speed_data/features/models/user_role.dart';
import 'package:speed_data/features/services/firestore_service.dart';

class SignUpWidget extends StatefulWidget {
  const SignUpWidget({super.key});

  static String routeName = 'SignUp';
  static String routePath = '/signUp';

  @override
  State<SignUpWidget> createState() => _SignUpWidgetState();
}

class _SignUpWidgetState extends State<SignUpWidget> {
  late SignUpModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => SignUpModel());

    _model.emailAddressTextController ??= TextEditingController();
    _model.emailAddressFocusNode ??= FocusNode();

    _model.passwordTextController ??= TextEditingController();
    _model.passwordFocusNode ??= FocusNode();

    _model.passwordConfirmTextController ??= TextEditingController();
    _model.passwordConfirmFocusNode ??= FocusNode();
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
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
                                style: SpeedDataTheme.themeData.textTheme.displaySmall,
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
                                    'Create an account',
                                    style: SpeedDataTheme.themeData.textTheme.headlineLarge,
                                  ),
                                  Padding(
                                    padding: const EdgeInsetsDirectional.fromSTEB(
                                        0.0, 12.0, 0.0, 24.0),
                                    child: Text(
                                      'Let\'s get started by filling out the form below.',
                                      style: SpeedDataTheme.themeData.textTheme.bodyMedium?.copyWith(
                                        color: SpeedDataTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.max,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsetsDirectional.fromSTEB(
                                            0.0, 0.0, 0.0, 16.0),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: TextFormField(
                                            controller: _model.emailAddressTextController,
                                            focusNode: _model.emailAddressFocusNode,
                                            autofocus: true,
                                            autofillHints: const [AutofillHints.email],
                                            obscureText: false,
                                            decoration: InputDecoration(
                                              labelText: 'Email',
                                              labelStyle: SpeedDataTheme.themeData.textTheme.bodyMedium?.copyWith(color: SpeedDataTheme.textSecondary),
                                              enabledBorder: OutlineInputBorder(
                                                borderSide: const BorderSide(
                                                  color: SpeedDataTheme.borderSubtle,
                                                  width: 1.0,
                                                ),
                                                borderRadius: BorderRadius.circular(SpeedDataTheme.radiusMd),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderSide: const BorderSide(
                                                  color: SpeedDataTheme.accentPrimary,
                                                  width: 1.0,
                                                ),
                                                borderRadius: BorderRadius.circular(SpeedDataTheme.radiusMd),
                                              ),
                                              errorBorder: OutlineInputBorder(
                                                borderSide: const BorderSide(
                                                  color: SpeedDataTheme.accentDanger,
                                                  width: 1.0,
                                                ),
                                                borderRadius: BorderRadius.circular(SpeedDataTheme.radiusMd),
                                              ),
                                              focusedErrorBorder: OutlineInputBorder(
                                                borderSide: const BorderSide(
                                                  color: SpeedDataTheme.accentDanger,
                                                  width: 1.0,
                                                ),
                                                borderRadius: BorderRadius.circular(SpeedDataTheme.radiusMd),
                                              ),
                                              filled: true,
                                              fillColor: SpeedDataTheme.bgSurface,
                                            ),
                                            style: SpeedDataTheme.themeData.textTheme.bodyMedium,
                                            keyboardType: TextInputType.emailAddress,
                                            validator: _model.emailAddressTextControllerValidator.asValidator(context),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsetsDirectional.fromSTEB(
                                            0.0, 0.0, 0.0, 16.0),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: TextFormField(
                                            controller: _model.passwordTextController,
                                            focusNode: _model.passwordFocusNode,
                                            autofocus: true,
                                            autofillHints: const [AutofillHints.password],
                                            obscureText: !_model.passwordVisibility,
                                            decoration: InputDecoration(
                                              labelText: 'Password',
                                              labelStyle: SpeedDataTheme.themeData.textTheme.bodyMedium?.copyWith(color: SpeedDataTheme.textSecondary),
                                              enabledBorder: OutlineInputBorder(
                                                borderSide: const BorderSide(
                                                  color: SpeedDataTheme.borderSubtle,
                                                  width: 1.0,
                                                ),
                                                borderRadius: BorderRadius.circular(SpeedDataTheme.radiusMd),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderSide: const BorderSide(
                                                  color: SpeedDataTheme.accentPrimary,
                                                  width: 1.0,
                                                ),
                                                borderRadius: BorderRadius.circular(SpeedDataTheme.radiusMd),
                                              ),
                                              errorBorder: OutlineInputBorder(
                                                borderSide: const BorderSide(
                                                  color: SpeedDataTheme.accentDanger,
                                                  width: 1.0,
                                                ),
                                                borderRadius: BorderRadius.circular(SpeedDataTheme.radiusMd),
                                              ),
                                              focusedErrorBorder: OutlineInputBorder(
                                                borderSide: const BorderSide(
                                                  color: SpeedDataTheme.accentDanger,
                                                  width: 1.0,
                                                ),
                                                borderRadius: BorderRadius.circular(SpeedDataTheme.radiusMd),
                                              ),
                                              filled: true,
                                              fillColor: SpeedDataTheme.bgSurface,
                                              suffixIcon: InkWell(
                                                onTap: () async {
                                                  safeSetState(() => _model.passwordVisibility = !_model.passwordVisibility);
                                                },
                                                focusNode: FocusNode(skipTraversal: true),
                                                child: Icon(
                                                  _model.passwordVisibility
                                                      ? Icons.visibility_outlined
                                                      : Icons.visibility_off_outlined,
                                                  color: SpeedDataTheme.textSecondary,
                                                  size: 24.0,
                                                ),
                                              ),
                                            ),
                                            style: SpeedDataTheme.themeData.textTheme.bodyMedium,
                                            validator: _model.passwordTextControllerValidator.asValidator(context),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsetsDirectional.fromSTEB(
                                            0.0, 0.0, 0.0, 16.0),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: TextFormField(
                                            controller: _model.passwordConfirmTextController,
                                            focusNode: _model.passwordConfirmFocusNode,
                                            autofocus: true,
                                            autofillHints: const [AutofillHints.password],
                                            obscureText: !_model.passwordConfirmVisibility,
                                            decoration: InputDecoration(
                                              labelText: 'Confirm Password',
                                              labelStyle: SpeedDataTheme.themeData.textTheme.bodyMedium?.copyWith(color: SpeedDataTheme.textSecondary),
                                              enabledBorder: OutlineInputBorder(
                                                borderSide: const BorderSide(
                                                  color: SpeedDataTheme.borderSubtle,
                                                  width: 1.0,
                                                ),
                                                borderRadius: BorderRadius.circular(SpeedDataTheme.radiusMd),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderSide: const BorderSide(
                                                  color: SpeedDataTheme.accentPrimary,
                                                  width: 1.0,
                                                ),
                                                borderRadius: BorderRadius.circular(SpeedDataTheme.radiusMd),
                                              ),
                                              errorBorder: OutlineInputBorder(
                                                borderSide: const BorderSide(
                                                  color: SpeedDataTheme.accentDanger,
                                                  width: 1.0,
                                                ),
                                                borderRadius: BorderRadius.circular(SpeedDataTheme.radiusMd),
                                              ),
                                              focusedErrorBorder: OutlineInputBorder(
                                                borderSide: const BorderSide(
                                                  color: SpeedDataTheme.accentDanger,
                                                  width: 1.0,
                                                ),
                                                borderRadius: BorderRadius.circular(SpeedDataTheme.radiusMd),
                                              ),
                                              filled: true,
                                              fillColor: SpeedDataTheme.bgSurface,
                                              suffixIcon: InkWell(
                                                onTap: () async {
                                                  safeSetState(() => _model.passwordConfirmVisibility = !_model.passwordConfirmVisibility);
                                                },
                                                focusNode: FocusNode(skipTraversal: true),
                                                child: Icon(
                                                  _model.passwordConfirmVisibility
                                                      ? Icons.visibility_outlined
                                                      : Icons.visibility_off_outlined,
                                                  color: SpeedDataTheme.textSecondary,
                                                  size: 24.0,
                                                ),
                                              ),
                                            ),
                                            style: SpeedDataTheme.themeData.textTheme.bodyMedium,
                                            validator: _model.passwordConfirmTextControllerValidator.asValidator(context),
                                          ),
                                        ),
                                      ),
                                      // Start Role Dropdown
                                      Padding(
                                        padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          decoration: BoxDecoration(
                                            color: SpeedDataTheme.bgSurface,
                                            borderRadius: BorderRadius.circular(SpeedDataTheme.radiusMd),
                                            border: Border.all(
                                              color: SpeedDataTheme.borderSubtle,
                                              width: 1,
                                            ),
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value: _model.selectedRole ?? 'pilot',
                                              items: const [
                                                DropdownMenuItem(
                                                    value: 'pilot',
                                                    child: Text('Pilot')),
                                                DropdownMenuItem(
                                                    value: 'admin',
                                                    child: Text('Admin')),
                                              ],
                                              onChanged: (val) {
                                                if (val != null) {
                                                  safeSetState(() => _model.selectedRole = val);
                                                }
                                              },
                                              dropdownColor: SpeedDataTheme.bgSurface,
                                              style: SpeedDataTheme.themeData.textTheme.bodyMedium,
                                              icon: const Icon(Icons.arrow_drop_down, color: SpeedDataTheme.textSecondary),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // End Role Dropdown

                                      Padding(
                                        padding: const EdgeInsetsDirectional.fromSTEB(
                                            0.0, 0.0, 0.0, 16.0),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: SpeedButton.primary(
                                            onPressed: () async {
                                              GoRouter.of(context).prepareAuthEvent();
                                              if (_model.passwordTextController.text !=
                                                  _model.passwordConfirmTextController.text) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                      content: Text(
                                                          'Passwords don\'t match!')),
                                                );
                                                return;
                                              }

                                              final user = await authManager.createAccountWithEmail(
                                                context,
                                                _model.emailAddressTextController.text,
                                                _model.passwordTextController.text,
                                              );
                                              if (user == null) {
                                                return;
                                              }

                                              // Save Selected Role and Navigate
                                              try {
                                                final roleStr = _model.selectedRole ?? 'pilot';
                                                final roleEnum = UserRole.fromString(roleStr);
                                                final uid = user!.uid!;

                                                await FirestoreService().setUserRole(uid, roleEnum, email: user.email);

                                                if (roleEnum == UserRole.pilot) {
                                                  // Ensure we are mounted before navigating
                                                  if (context.mounted) {
                                                    context.goNamedAuth(
                                                        PilotProfileSetupWidget.routeName,
                                                        context.mounted);
                                                  }
                                                } else {
                                                  if (context.mounted) {
                                                    context.goNamedAuth(
                                                        HomePageWidget.routeName,
                                                        context.mounted);
                                                  }
                                                }
                                              } catch (e) {
                                                print('Error saving role: $e');
                                                // Fallback to home page on error
                                                if (context.mounted) {
                                                  context.goNamedAuth(
                                                      HomePageWidget.routeName,
                                                      context.mounted);
                                                }
                                              }
                                            },
                                            text: 'Create Account',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Align(
                                    alignment: const AlignmentDirectional(0.0, 0.0),
                                    child: Padding(
                                      padding: const EdgeInsetsDirectional.fromSTEB(
                                          0.0, 12.0, 0.0, 12.0),
                                      child: InkWell(
                                        splashColor: Colors.transparent,
                                        focusColor: Colors.transparent,
                                        hoverColor: Colors.transparent,
                                        highlightColor: Colors.transparent,
                                        onTap: () async {
                                          context.pushNamed(LoginWidget.routeName);
                                        },
                                        child: RichText(
                                          textScaler: MediaQuery.of(context).textScaler,
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text: 'Already have an account? ',
                                                style: SpeedDataTheme.themeData.textTheme.bodyMedium,
                                              ),
                                              TextSpan(
                                                text: 'Entrar aqui',
                                                style: SpeedDataTheme.themeData.textTheme.bodyMedium?.copyWith(
                                                  color: SpeedDataTheme.accentPrimary,
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
                        colors: [SpeedDataTheme.bgBase, SpeedDataTheme.bgSurface],
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
                          border: Border.all(color: SpeedDataTheme.borderSubtle),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.speed, size: 64, color: SpeedDataTheme.accentPrimary),
                            const SizedBox(height: 16),
                            Text(
                              'Speed Data',
                              style: SpeedDataTheme.themeData.textTheme.displayMedium,
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
