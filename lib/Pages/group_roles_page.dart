import 'package:flutter/material.dart';
import 'package:login_ui/data/club_roles.dart';
import 'package:login_ui/services/chat_service.dart';
import '../theme/app_theme.dart';

class GroupRolesPage extends StatefulWidget {
  const GroupRolesPage({
    super.key,
    required this.groupId,
    required this.members,
    required this.groupData,
    required this.ownerEmail,
  });

  final String groupId;
  final List<String> members;
  final Map<String, dynamic> groupData;
  final String ownerEmail;

  @override
  State<GroupRolesPage> createState() => _GroupRolesPageState();
}

class _GroupRolesPageState extends State<GroupRolesPage> {
  final ChatService _chatService = ChatService();

  late List<ClubRole> _roles;
  late Map<String, String> _memberRoles;
  late String _selectedRoleId;
  bool _isSaving = false;

  ClubRole get _selectedRole =>
      _roles.firstWhere((role) => role.id == _selectedRoleId);

  @override
  void initState() {
    super.initState();
    final rawRoles = widget.groupData['roles'];
    _roles = rawRoles is List
        ? rawRoles
              .whereType<Map>()
              .map((role) => ClubRole.fromMap(Map<String, dynamic>.from(role)))
              .where((role) => role.id.isNotEmpty)
              .toList()
        : ClubRole.builtInRoles.toList();

    for (final builtIn in ClubRole.builtInRoles) {
      if (!_roles.any((role) => role.id == builtIn.id)) {
        _roles.add(builtIn);
      }
    }

    final rawAssignments = widget.groupData['memberRoles'];
    _memberRoles = rawAssignments is Map
        ? rawAssignments.map(
            (email, roleId) => MapEntry(email.toString(), roleId.toString()),
          )
        : <String, String>{};
    final admins = List<String>.from(widget.groupData['admins'] ?? const []);
    for (final member in widget.members) {
      _memberRoles.putIfAbsent(
        member,
        () => member == widget.ownerEmail
            ? 'president'
            : admins.contains(member)
            ? 'officer'
            : 'member',
      );
      if (!_roles.any((role) => role.id == _memberRoles[member])) {
        _memberRoles[member] = 'member';
      }
    }
    _memberRoles[widget.ownerEmail] = 'president';
    _selectedRoleId = 'president';
  }

  Future<void> _addCustomRole() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create a role'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Role title',
            hintText: 'e.g. Social Media Lead',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;

    final id = 'custom_${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _roles.add(ClubRole(id: id, name: name, permissions: const {}));
      _selectedRoleId = id;
    });
  }

  Future<void> _deleteSelectedRole() async {
    if (_selectedRole.isBuiltIn) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this role?'),
        content: Text(
          'Members with ${_selectedRole.name} will be moved to Member.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove role'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      for (final entry in _memberRoles.entries.toList()) {
        if (entry.value == _selectedRoleId) {
          _memberRoles[entry.key] = 'member';
        }
      }
      _roles.removeWhere((role) => role.id == _selectedRoleId);
      _selectedRoleId = 'member';
    });
  }

  void _togglePermission(String permissionId, bool enabled) {
    final permissions = {..._selectedRole.permissions};
    if (enabled) {
      permissions.add(permissionId);
    } else {
      permissions.remove(permissionId);
    }
    setState(() {
      _roles = _roles
          .map(
            (role) => role.id == _selectedRoleId
                ? role.copyWith(permissions: permissions)
                : role,
          )
          .toList();
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await _chatService.updateGroupRoles(
        widget.groupId,
        roles: _roles,
        memberRoles: _memberRoles,
        members: widget.members,
        ownerEmail: widget.ownerEmail,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save roles: $error')));
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final roleMembers =
        widget.members
            .where((email) => _memberRoles[email] == _selectedRoleId)
            .toList()
          ..sort();
    final categories = ClubPermission.all
        .map((permission) => permission.category)
        .toSet();

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const GradientAppBarBackground(),
        title: const Text('Roles & permissions'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(
            'Choose a role to manage its access and members. The club creator is always President.',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._roles.map(
                (role) => ChoiceChip(
                  label: Text(role.name),
                  selected: role.id == _selectedRoleId,
                  onSelected: (_) => setState(() => _selectedRoleId = role.id),
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('New role'),
                onPressed: _addCustomRole,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedRole.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (!_selectedRole.isBuiltIn)
                        IconButton(
                          tooltip: 'Remove role',
                          onPressed: _deleteSelectedRole,
                          icon: const Icon(Icons.delete_outline),
                        ),
                    ],
                  ),
                  if (_selectedRole.id == 'president')
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.lock_outline),
                      title: Text('Reserved for the club creator'),
                      subtitle: Text('This role cannot be reassigned.'),
                    ),
                  if (_selectedRole.id != 'president')
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      initiallyExpanded: false,
                      title: const Text('Members with this role'),
                      subtitle: Text(
                        '${roleMembers.length} ${roleMembers.length == 1 ? 'member' : 'members'}',
                      ),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: widget.members
                                .where((email) => email != widget.ownerEmail)
                                .map((email) {
                                  final assigned =
                                      _memberRoles[email] == _selectedRoleId;
                                  return FilterChip(
                                    label: Text(_displayName(email)),
                                    selected: assigned,
                                    onSelected: (selected) {
                                      setState(() {
                                        _memberRoles[email] = selected
                                            ? _selectedRoleId
                                            : 'member';
                                      });
                                    },
                                  );
                                })
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('PERMISSIONS', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          ...categories.map((category) {
            final permissions = ClubPermission.all
                .where((permission) => permission.category == category)
                .toList();
            final enabledCount = permissions
                .where(
                  (permission) =>
                      _selectedRole.permissions.contains(permission.id),
                )
                .length;
            return Card(
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                key: ValueKey('$_selectedRoleId-$category'),
                title: Text(category),
                subtitle: Text(
                  '$enabledCount of ${permissions.length} enabled',
                ),
                children: permissions.map((permission) {
                  final isPresident = _selectedRoleId == 'president';
                  return SwitchListTile(
                    title: Text(permission.title),
                    subtitle: Text(permission.description),
                    value:
                        isPresident ||
                        _selectedRole.permissions.contains(permission.id),
                    onChanged: isPresident
                        ? null
                        : (value) => _togglePermission(permission.id, value),
                  );
                }).toList(),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _displayName(String email) =>
      email.contains('@') ? email.split('@').first : email;
}
