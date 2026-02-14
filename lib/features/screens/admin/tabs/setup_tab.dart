
import 'package:flutter/material.dart';
import 'package:speed_data/features/screens/admin/create_race_screen.dart';

class SetupTab extends StatelessWidget {
  const SetupTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('HARDWARE / GPS STATUS'),
        const GPSStatusWidget(),
        const SizedBox(height: 24),
        _buildSectionHeader('TRACK CONFIGURATION'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.map, size: 40, color: Colors.blue),
            title: const Text('Track Wizard', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Create or edit track layouts and checkpoints.'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CreateRaceScreen()),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }
}

class GPSStatusWidget extends StatelessWidget {
  const GPSStatusWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Placeholder for actual GPS telemetry monitoring
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatusIndicator('Server', true),
                _buildStatusIndicator('GPS Signal', true),
                _buildStatusIndicator('Noise Level', false), // Simulated "Low" noise as good
              ],
            ),
            const Divider(height: 32),
            const Text(
              'System ready. 0 active decoders connected.',
              style: TextStyle(color: Colors.green),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(String label, bool isOk) {
    return Column(
      children: [
        Icon(
          isOk ? Icons.check_circle : Icons.warning,
          color: isOk ? Colors.green : Colors.orange,
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
