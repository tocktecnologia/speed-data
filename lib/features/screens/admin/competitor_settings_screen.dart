
import 'package:flutter/material.dart';
import 'package:speed_data/features/models/competitor_model.dart';
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
  State<CompetitorSettingsScreen> createState() => _CompetitorSettingsScreenState();
}

class _CompetitorSettingsScreenState extends State<CompetitorSettingsScreen> with SingleTickerProviderStateMixin {
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
         _labelController.text = _lastNameController.text.substring(0, 3).toUpperCase();
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
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _save)
        ],
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
          decoration: const InputDecoration(labelText: 'Number (No)', helperText: 'Max 4 chars'),
          maxLength: 4,
          validator: (val) => val!=null && val.isEmpty ? 'Required' : null,
        ),
        TextFormField(
          controller: _categoryController,
          decoration: const InputDecoration(labelText: 'Category / Class'),
        ),
        TextFormField(
          controller: _vehicleRegController,
          decoration: const InputDecoration(labelText: 'Car/Bike Reg (Chassis)', suffixIcon: Icon(Icons.autorenew)), // Placeholder for auto-gen
        ),
        TextFormField(
          controller: _labelController,
          decoration: const InputDecoration(labelText: 'Label (TLA)', helperText: '3 Letter Abbreviation'),
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
            Expanded(child: TextFormField(
              controller: _firstNameController, 
              decoration: const InputDecoration(labelText: 'First Name'),
              validator: (val) => val!=null && val.isEmpty ? 'Required' : null,
            )),
            const SizedBox(width: 16),
             Expanded(child: TextFormField(
              controller: _lastNameController, 
              decoration: const InputDecoration(labelText: 'Last Name'),
              onChanged: (_) => _autoGenerateLabel(),
            )),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _driverRegController,
           decoration: const InputDecoration(labelText: 'Driver Reg (License)', suffixIcon: Icon(Icons.autorenew)),
        ),
         const SizedBox(height: 24),
         const Text('Linked User (Replaces Transponder)', style: TextStyle(fontWeight: FontWeight.bold)),
         ListTile(
           title: Text(_uid.isNotEmpty ? 'Linked User: $_uid' : 'No User Linked'), // Should use name if possible
           subtitle: Text(_emailController.text),
           trailing: const Icon(Icons.link),
           onTap: () {
             showModalBottomSheet(
                context: context, 
                builder: (context) => DriverPicker(
                  initialSelection: _uid.isNotEmpty ? [_uid] : [],
                  onSelectionChanged: (selected) {
                    if (selected.isNotEmpty) {
                       setState(() {
                         _uid = selected.first;
                         // In a real app we would fetch the user email/name here
                         _emailController.text = 'User selected'; 
                       });
                    }
                  },
                )
              );
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
