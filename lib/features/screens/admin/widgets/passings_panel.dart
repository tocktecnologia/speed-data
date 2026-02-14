
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:intl/intl.dart';
import 'package:speed_data/theme/speed_data_theme.dart';

class PassingsPanel extends StatelessWidget {
  final String raceId;
  final SessionType sessionType;

  const PassingsPanel({Key? key, required this.raceId, required this.sessionType}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('races')
          .doc(raceId)
          .collection('participants')
          .orderBy('current.last_updated', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;
        
        return Container(
          color: SpeedDataTheme.bgSurface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
               // Table Header
               Container(
                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                 color: SpeedDataTheme.bgElevated,
                 child: Row(
                   children: const [
                     SizedBox(width: 80, child: Text('TIME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                     SizedBox(width: 50, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                     Expanded(child: Text('NAME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                     SizedBox(width: 80, child: Text('LAP TIME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                     SizedBox(width: 60, child: Text('S1', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                     SizedBox(width: 60, child: Text('S2', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                     SizedBox(width: 60, child: Text('S3', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                   ],
                 ),
               ),
               const Divider(height: 1, color: SpeedDataTheme.borderColor),
              Expanded(
                child: ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, color: SpeedDataTheme.borderSubtle),
                  itemBuilder: (context, index) {
                    final Map<String, dynamic> data = (docs[index].data() as Map<String, dynamic>?) ?? {};
                    final name = data['display_name'] as String? ?? 'Unknown';
                    final carNumber = data['color']?.toString() ?? '?'; // Using color as placeholder for car number if not present
                    final current = data['current'] as Map<String, dynamic>?;
                    final timestamp = (current?['timestamp'] as num?)?.toInt() ?? 0;
                    final timeStr = timestamp > 0 
                        ? DateFormat('HH:mm:ss.SSS').format(DateTime.fromMillisecondsSinceEpoch(timestamp))
                        : '--:--:--';
                    
                    // Mock data for lap time and sectors for now
                    // TODO: Calculate actual lap times and best lap status
                    final lapTime = '1:23.456'; 
                    final s1 = '23.4';
                    final s2 = '34.5';
                    final s3 = '25.5';

                    // Mock status for color coding
                    bool isOverallBest = index == 2; // Mock
                    bool isPersonalBest = index == 5; // Mock
                    bool isInvalid = false;

                    Color backgroundColor = Colors.transparent;
                    if (isOverallBest) backgroundColor = Colors.purple.withOpacity(0.3);
                    else if (isPersonalBest) backgroundColor = Colors.green.withOpacity(0.3);

                    return Container(
                      color: backgroundColor,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(width: 80, child: Text(timeStr, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                          SizedBox(width: 50, child: Text(carNumber, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Expanded(child: Text(name, style: TextStyle(fontSize: 12, color: isInvalid ? SpeedDataTheme.flagRed : SpeedDataTheme.textPrimary))),
                          SizedBox(width: 80, child: Text(lapTime, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                          SizedBox(width: 60, child: Text(s1, style: const TextStyle(fontSize: 11, color: SpeedDataTheme.textSecondary))),
                          SizedBox(width: 60, child: Text(s2, style: const TextStyle(fontSize: 11, color: SpeedDataTheme.textSecondary))),
                          SizedBox(width: 60, child: Text(s3, style: const TextStyle(fontSize: 11, color: SpeedDataTheme.textSecondary))),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
