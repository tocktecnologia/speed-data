enum UserRole {
  pilot,
  admin,
  root,
  unknown;

  static UserRole fromString(String? role) {
    switch (role?.toLowerCase()) {
      case 'pilot':
      case 'piloto':
        return UserRole.pilot;
      case 'admin':
      case 'administrador':
        return UserRole.admin;
      case 'root':
        return UserRole.root;
      default:
        return UserRole.unknown;
    }
  }

  String toStringValue() {
    switch (this) {
      case UserRole.pilot:
        return 'pilot';
      case UserRole.admin:
        return 'admin';
      case UserRole.root:
        return 'root';
      default:
        return 'unknown';
    }
  }
}
