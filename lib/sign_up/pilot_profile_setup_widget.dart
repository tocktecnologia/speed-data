import '/auth/firebase_auth/auth_util.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import '/index.dart';

class PilotProfileSetupWidget extends StatefulWidget {
  const PilotProfileSetupWidget({super.key});

  static String routeName = 'PilotProfileSetup';
  static String routePath = '/pilotProfileSetup';

  @override
  State<PilotProfileSetupWidget> createState() =>
      _PilotProfileSetupWidgetState();
}

class _PilotProfileSetupWidgetState extends State<PilotProfileSetupWidget> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final _formKey = GlobalKey<FormState>();

  TextEditingController? _nameController;
  late FocusNode _nameFocusNode;

  int _selectedColor = 0xFFFFFFFF; // Default white

  final List<int> _palette = [
    0xFFF44336, // Red
    0xFFE91E63, // Pink
    0xFF9C27B0, // Purple
    0xFF673AB7, // Deep Purple
    0xFF3F51B5, // Indigo
    0xFF2196F3, // Blue
    0xFF03A9F4, // Light Blue
    0xFF00BCD4, // Cyan
    0xFF009688, // Teal
    0xFF4CAF50, // Green
    0xFF8BC34A, // Light Green
    0xFFCDDC39, // Lime
    0xFFFFEB3B, // Yellow
    0xFFFFC107, // Amber
    0xFFFF9800, // Orange
    0xFFFF5722, // Deep Orange
    0xFF795548, // Brown
    0xFF9E9E9E, // Grey
    0xFF607D8B, // Blue Grey
    0xFF000000, // Black
    0xFFFFFFFF, // White
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _nameFocusNode = FocusNode();

    // Pre-fill name if available
    if (currentUserDisplayName.isNotEmpty) {
      _nameController!.text = currentUserDisplayName;
    }
  }

  @override
  void dispose() {
    _nameController?.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
          automaticallyImplyLeading: false,
          title: Text(
            'Pilot Profile',
            style: FlutterFlowTheme.of(context).headlineMedium,
          ),
          elevation: 0,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Complete your profile',
                      style: FlutterFlowTheme.of(context).labelLarge,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Pilot Name',
                      style: FlutterFlowTheme.of(context).bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      focusNode: _nameFocusNode,
                      decoration: InputDecoration(
                        hintText: 'Enter your pilot name',
                        hintStyle: FlutterFlowTheme.of(context)
                            .bodyLarge
                            .override(
                              font: GoogleFonts.inter(),
                              color: FlutterFlowTheme.of(context).secondaryText,
                            ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: FlutterFlowTheme.of(context).alternate,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: FlutterFlowTheme.of(context).primary,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor:
                            FlutterFlowTheme.of(context).secondaryBackground,
                      ),
                      style: FlutterFlowTheme.of(context).bodyLarge,
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return 'Field is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Car Color',
                      style: FlutterFlowTheme.of(context).bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: _palette.map((colorVal) {
                        final isSelected = _selectedColor == colorVal;
                        return InkWell(
                          onTap: () {
                            setState(() {
                              _selectedColor = colorVal;
                            });
                          },
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Color(colorVal),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? FlutterFlowTheme.of(context).primary
                                    : FlutterFlowTheme.of(context).alternate,
                                width: isSelected ? 4 : 1,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: FlutterFlowTheme.of(context)
                                            .primary
                                            .withOpacity(0.3),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      )
                                    ]
                                  : [],
                            ),
                            child: isSelected
                                ? Icon(
                                    Icons.check,
                                    color: colorVal == 0xFFFFFFFF
                                        ? Colors.black
                                        : Colors.white,
                                    size: 24,
                                  )
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 48),
                    FFButtonWidget(
                      onPressed: () async {
                        if (!_formKey.currentState!.validate()) return;

                        final user = currentUser;
                        if (user != null) {
                          await FirestoreService().updatePilotProfile(
                            user.uid!,
                            _nameController!.text,
                            _selectedColor,
                          );

                          if (context.mounted) {
                            context.goNamedAuth(
                              HomePageWidget.routeName,
                              context.mounted,
                            );
                          }
                        }
                      },
                      text: 'Save & Continue',
                      options: FFButtonOptions(
                        width: double.infinity,
                        height: 50,
                        color: FlutterFlowTheme.of(context).primary,
                        textStyle:
                            FlutterFlowTheme.of(context).titleSmall.override(
                                  font: GoogleFonts.inter(),
                                  color: Colors.white,
                                ),
                        elevation: 2,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
