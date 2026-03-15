enum UserRole {
  pilot,
  teamMember,
  admin,
  root,
  unknown;

  static UserRole fromString(String? role) {
    switch (role?.toLowerCase()) {
      case 'pilot':
      case 'piloto':
        return UserRole.pilot;
      case 'team_member':
      case 'teammember':
      case 'team':
      case 'integrante':
      case 'integrante_equipe':
        return UserRole.teamMember;
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
      case UserRole.teamMember:
        return 'team_member';
      case UserRole.admin:
        return 'admin';
      case UserRole.root:
        return 'root';
      default:
        return 'unknown';
    }
  }
}
