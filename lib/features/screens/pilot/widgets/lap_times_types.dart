enum LapTimesMode {
  sectors,
  splits,
  trapSpeeds,
  highLow,
  information,
}

extension LapTimesModeLabel on LapTimesMode {
  String get label {
    switch (this) {
      case LapTimesMode.sectors:
        return 'Sectors';
      case LapTimesMode.splits:
        return 'Splits';
      case LapTimesMode.trapSpeeds:
        return 'Trap Speeds';
      case LapTimesMode.highLow:
        return 'High/Low';
      case LapTimesMode.information:
        return 'Information';
    }
  }
}

enum LapTimesResultMode {
  absolute,
  difference,
}

extension LapTimesResultModeLabel on LapTimesResultMode {
  String get label {
    switch (this) {
      case LapTimesResultMode.absolute:
        return 'Absolute';
      case LapTimesResultMode.difference:
        return 'Difference';
    }
  }
}
