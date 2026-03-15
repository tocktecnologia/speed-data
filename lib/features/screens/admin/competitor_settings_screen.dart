import 'package:flutter/material.dart';
import 'package:speed_data/features/models/competitor_model.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/features/screens/admin/widgets/driver_picker.dart';
import 'package:uuid/uuid.dart';

class CompetitorSettingsScreen extends StatefulWidget {
  final Competitor? competitor;
  final String groupId;
  final Function(Competitor) onSave;

  const CompetitorSettingsScreen({
    Key? key,
    this.competitor,
    required this.groupId,
    required this.onSave,
  }) : super(key: key);

  @override
  State<CompetitorSettingsScreen> createState() =>
      _CompetitorSettingsScreenState();
}

class _CompetitorSettingsScreenState extends State<CompetitorSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();

  // Driver
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _driverRegController = TextEditingController();
  final _emailController = TextEditingController();
  String _uid = '';

  // Vehicle
  final _numberController = TextEditingController();
  final _categoryController = TextEditingController();
  final _vehicleRegController = TextEditingController();
  final _labelController = TextEditingController();

  // Additional
  final Map<String, TextEditingController> _additionalControllers = {
    'Sponsor': TextEditingController(),
    'Team': TextEditingController(),
    'City': TextEditingController(),
    'State': TextEditingController(),
    'Country': TextEditingController(),
    'Club': TextEditingController(),
    'License Type': TextEditingController(),
    'Blood Type': TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    if (widget.competitor != null) {
      final c = widget.competitor!;
      _firstNameController.text = c.firstName;
      _lastNameController.text = c.lastName;
      _driverRegController.text = c.driverReg;
      _emailController.text = c.email;
      _uid = c.uid;

      _numberController.text = c.number;
      _categoryController.text = c.category;
      _vehicleRegController.text = c.vehicleReg;
      _labelController.text = c.label;

      c.additionalFields.forEach((key, value) {
        if (_additionalControllers.containsKey(key)) {
          _additionalControllers[key]!.text = value;
        } else {
          // If dynamic fields were allowed, we'd add controllers here.
          // For now, fixed set.
          _additionalControllers[key] = TextEditingController(text: value);
        }
      });
    }
  }

  void _autoGenerateLabel() {
    if (_labelController.text.isEmpty && _lastNameController.text.length >= 3) {
      setState(() {
        _labelController.text =
            _lastNameController.text.substring(0, 3).toUpperCase();
      });
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final additionalData = <String, String>{};
    _additionalControllers.forEach((key, controller) {
      if (controller.text.isNotEmpty) {
        additionalData[key] = controller.text;
      }
    });

    final newCompetitor = Competitor(
      id: widget.competitor?.id ?? const Uuid().v4(),
      groupId: widget.groupId,
      teamId: widget.competitor?.teamId ?? '',
      teamName: widget.competitor?.teamName ?? (additionalData['Team'] ?? ''),
      firstName: _firstNameController.text,
      lastName: _lastNameController.text,
      number: _numberController.text,
      driverReg: _driverRegController.text,
      email: _emailController.text,
      uid: _uid,
      category: _categoryController.text,
      vehicleReg: _vehicleRegController.text,
      label: _labelController.text,
      additionalFields: additionalData,
    );

    widget.onSave(newCompetitor);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Competitor Settings'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Vehicle'),
            Tab(text: 'Competitor'),
            Tab(text: 'Additional'),
          ],
        ),
        actions: [IconButton(icon: const Icon(Icons.check), onPressed: _save)],
      ),
      body: Form(
        key: _formKey,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildVehicleTab(),
            _buildCompetitorTab(),
            _buildAdditionalTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextFormField(
          controller: _numberController,
          decoration: const InputDecoration(
              labelText: 'Number (No)', helperText: 'Max 4 chars'),
          maxLength: 4,
          validator: (val) => val != null && val.isEmpty ? 'Required' : null,
        ),
        TextFormField(
          controller: _categoryController,
          decoration: const InputDecoration(labelText: 'Category / Class'),
        ),
        TextFormField(
          controller: _vehicleRegController,
          decoration: const InputDecoration(
              labelText: 'Car/Bike Reg (Chassis)',
              suffixIcon: Icon(Icons.autorenew)), // Placeholder for auto-gen
        ),
        TextFormField(
          controller: _labelController,
          decoration: const InputDecoration(
              labelText: 'Label (TLA)', helperText: '3 Letter Abbreviation'),
          maxLength: 3,
        ),
      ],
    );
  }

  Widget _buildCompetitorTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
                child: TextFormField(
              controller: _firstNameController,
              decoration: const InputDecoration(labelText: 'First Name'),
              validator: (val) =>
                  val != null && val.isEmpty ? 'Required' : null,
            )),
            const SizedBox(width: 16),
            Expanded(
                child: TextFormField(
              controller: _lastNameController,
              decoration: const InputDecoration(labelText: 'Last Name'),
              onChanged: (_) => _autoGenerateLabel(),
            )),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _driverRegController,
          decoration: const InputDecoration(
              labelText: 'Driver Reg (License)',
              suffixIcon: Icon(Icons.autorenew)),
        ),
        const SizedBox(height: 24),
        const SizedBox(height: 24),
        const Text('Linked User (Replaces Transponder)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'User Email',
                  hintText: 'Search user by email to link',
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () async {
                if (_emailController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Please enter an email address')));
                  return;
                }

                // Show loading
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Row(
                  children: [
                    SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 12),
                    Text('Searching...'),
                  ],
                )));

                final fs = FirestoreService();
                final userData =
                    await fs.getUserByEmail(_emailController.text.trim());

                if (mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  if (userData != null) {
                    setState(() {
                      _uid = userData['uid'] ?? '';
                      // If we have a name, we can also pre-fill if empty
                      if (_firstNameController.text.isEmpty &&
                          userData.containsKey('name')) {
                        final nameParts =
                            (userData['name'] as String).split(' ');
                        _firstNameController.text = nameParts.first;
                        if (nameParts.length > 1) {
                          _lastNameController.text =
                              nameParts.sublist(1).join(' ');
                        }
                        _autoGenerateLabel();
                      }
                    });
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            'User linked: ${userData['name'] ?? userData['email']}')));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('User not found with this email')));
                  }
                }
              },
              child: const Text('SEARCH'),
            ),
          ],
        ),
        if (_uid.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: ListTile(
              leading: const Icon(Icons.link, color: Colors.green),
              title: const Text('Linked Account Active'),
              subtitle: Text('UID: $_uid'),
              trailing: IconButton(
                icon: const Icon(Icons.link_off),
                onPressed: () => setState(() => _uid = ''),
                tooltip: 'Unlink User',
              ),
              tileColor: Colors.green.withOpacity(0.05),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        const SizedBox(height: 16),
        ListTile(
          title: const Text('Browse All Users'),
          leading: const Icon(Icons.people),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            showModalBottomSheet(
                context: context,
                builder: (context) => DriverPicker(
                      initialSelection: _uid.isNotEmpty ? [_uid] : [],
                      onSelectionChanged: (selected) {
                        if (selected.isNotEmpty) {
                          setState(() {
                            _uid = selected.first;
                            // Ideally we'd fetch the email here too, but the picker only returns IDs
                          });
                        }
                      },
                    ));
          },
        )
      ],
    );
  }

  Widget _buildAdditionalTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: _additionalControllers.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: TextFormField(
            controller: entry.value,
            decoration: InputDecoration(labelText: entry.key),
          ),
        );
      }).toList(),
    );
  }
}
