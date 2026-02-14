
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DriverPicker extends StatefulWidget {
  final List<String> initialSelection;
  final Function(List<String>) onSelectionChanged;

  const DriverPicker({
    Key? key, 
    required this.initialSelection, 
    required this.onSelectionChanged
  }) : super(key: key);

  @override
  State<DriverPicker> createState() => _DriverPickerState();
}

class _DriverPickerState extends State<DriverPicker> {
  List<String> _selectedIds = [];
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _selectedIds = List.from(widget.initialSelection);
  }

  void _toggleSelection(String uid) {
    setState(() {
      if (_selectedIds.contains(uid)) {
        _selectedIds.remove(uid);
      } else {
        _selectedIds.add(uid);
      }
      widget.onSelectionChanged(_selectedIds);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text(
            'Select Drivers',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db.collection('users').orderBy('email').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                final users = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final data = users[index].data() as Map<String, dynamic>;
                    final uid = users[index].id;
                    final email = data['email'] ?? 'No Email';
                    final name = data['display_name'] ?? 'No Name';
                    final isSelected = _selectedIds.contains(uid);

                    return CheckboxListTile(
                      title: Text(name),
                      subtitle: Text(email),
                      value: isSelected,
                      onChanged: (val) => _toggleSelection(uid),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
