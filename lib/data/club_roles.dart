class ClubRole {
  const ClubRole({
    required this.id,
    required this.name,
    required this.permissions,
    this.isBuiltIn = false,
  });

  final String id;
  final String name;
  final Set<String> permissions;
  final bool isBuiltIn;

  ClubRole copyWith({
    String? name,
    Set<String>? permissions,
  }) {
    return ClubRole(
      id: id,
      name: name ?? this.name,
      permissions: permissions ?? this.permissions,
      isBuiltIn: isBuiltIn,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'permissions': permissions.toList()..sort(),
    'isBuiltIn': isBuiltIn,
  };

  factory ClubRole.fromMap(Map<String, dynamic> map) {
    return ClubRole(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Role',
      permissions: Set<String>.from(map['permissions'] ?? const <String>[]),
      isBuiltIn: map['isBuiltIn'] as bool? ?? false,
    );
  }

  static const builtInRoles = <ClubRole>[
    ClubRole(
      id: 'president',
      name: 'President',
      isBuiltIn: true,
      permissions: {
        'send_messages',
        'manage_settings',
        'manage_events',
        'post_announcements',
        'manage_messages',
        'manage_check_ins',
      },
    ),
    ClubRole(
      id: 'co_president',
      name: 'Co-President',
      isBuiltIn: true,
      permissions: {
        'send_messages',
        'manage_settings',
        'manage_events',
        'post_announcements',
        'manage_messages',
        'manage_check_ins',
      },
    ),
    ClubRole(
      id: 'officer',
      name: 'Officer',
      isBuiltIn: true,
      permissions: {
        'send_messages',
        'manage_events',
        'post_announcements',
        'manage_check_ins',
      },
    ),
    ClubRole(
      id: 'member',
      name: 'Member',
      isBuiltIn: true,
      permissions: {},
    ),
  ];
}

class ClubPermission {
  const ClubPermission({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
  });

  final String id;
  final String title;
  final String description;
  final String category;

  static const all = <ClubPermission>[
    ClubPermission(
      id: 'send_messages',
      title: 'Post when chat is restricted',
      description: 'Send messages when only officers can post.',
      category: 'Chat',
    ),
    ClubPermission(
      id: 'manage_messages',
      title: 'Moderate messages',
      description: 'Pin and remove messages in the group chat.',
      category: 'Chat',
    ),
    ClubPermission(
      id: 'post_announcements',
      title: 'Post announcements',
      description: 'Publish club-wide updates in the chat.',
      category: 'Events',
    ),
    ClubPermission(
      id: 'manage_events',
      title: 'Manage events',
      description: 'Create and update the club calendar.',
      category: 'Events',
    ),
    ClubPermission(
      id: 'manage_check_ins',
      title: 'Manage attendance',
      description: 'Open check-in and record event attendance.',
      category: 'Events',
    ),
    ClubPermission(
      id: 'manage_settings',
      title: 'Manage group settings',
      description: 'Change visibility, posting rules, and group details.',
      category: 'Group',
    ),
  ];
}
