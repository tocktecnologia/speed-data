import 'package:flutter/material.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/theme/speed_data_theme.dart';

class ControlFlags extends StatelessWidget {
  final Function(RaceFlag) onFlagSelected;
  final RaceFlag currentFlag;

  const ControlFlags({
    Key? key, 
    required this.onFlagSelected, 
    this.currentFlag = RaceFlag.green
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: SpeedDataTheme.bgSurface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildFlagButton(RaceFlag.green, SpeedDataTheme.flagGreen),
          _buildFlagButton(RaceFlag.warmup, SpeedDataTheme.flagPurple),
          _buildFlagButton(RaceFlag.yellow, SpeedDataTheme.flagYellow),
          _buildFlagButton(RaceFlag.red, SpeedDataTheme.flagRed),
          _buildFlagButton(RaceFlag.checkered, SpeedDataTheme.flagCheckered, isCheckered: true),
        ],
      ),
    );
  }

  Widget _buildFlagButton(RaceFlag flag, Color color, {bool isCheckered = false}) {
    final isSelected = currentFlag == flag;
    
    return GestureDetector(
      onTap: () => onFlagSelected(flag),
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: isCheckered 
              ? (isSelected ? SpeedDataTheme.textPrimary : SpeedDataTheme.textDisabled) 
              : (isSelected ? color : color.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: SpeedDataTheme.textPrimary, width: 2) : null,
          gradient: isCheckered ? const LinearGradient(
            colors: [SpeedDataTheme.bgBase, SpeedDataTheme.textPrimary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.5, 0.5],
            tileMode: TileMode.repeated
          ) : null,
        ),
        child: isCheckered 
          ? const Icon(Icons.flag, color: SpeedDataTheme.bgBase, size: 30) // Simplified Checkered
          : Icon(Icons.flag, color: isSelected ? SpeedDataTheme.textPrimary : SpeedDataTheme.textSecondary, size: 30),
      ),
    );
  }
}
