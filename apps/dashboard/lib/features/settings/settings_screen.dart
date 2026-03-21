import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Einstellungen', style: theme.textTheme.headlineMedium),
            Text('System und Restaurant konfigurieren', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 20),

            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: AppColors.primary,
              unselectedLabelColor: theme.textTheme.bodyMedium?.color,
              indicatorColor: AppColors.primary,
              dividerColor: theme.colorScheme.outline,
              tabs: const [
                Tab(text: 'Restaurant'),
                Tab(text: 'Drucker'),
                Tab(text: 'Steuern'),
                Tab(text: 'Benutzerverwaltung'),
              ],
            ),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _RestaurantTab(),
                  _PrinterTab(),
                  _TaxTab(),
                  _UsersTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Restaurant info
// ---------------------------------------------------------------------------

class _RestaurantTab extends StatefulWidget {
  const _RestaurantTab();

  @override
  State<_RestaurantTab> createState() => _RestaurantTabState();
}

class _RestaurantTabState extends State<_RestaurantTab> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController(text: 'Restaurant Muster');
  final _streetCtrl = TextEditingController(text: 'Musterstrasse 1');
  final _cityCtrl = TextEditingController(text: '8001 Zürich');
  final _phoneCtrl = TextEditingController(text: '+41 44 123 45 67');
  final _emailCtrl = TextEditingController(text: 'info@restaurant-muster.ch');
  final _mwstCtrl = TextEditingController(text: 'CHE-123.456.789 MWST');
  bool _saved = false;

  @override
  void dispose() {
    for (final c in [_nameCtrl, _streetCtrl, _cityCtrl, _phoneCtrl, _emailCtrl, _mwstCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Restaurant-Informationen', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Field('Restaurantname', _nameCtrl, required: true),
                      _Field('Strasse und Hausnummer', _streetCtrl, required: true),
                      _Field('PLZ und Ort', _cityCtrl, required: true),
                      _Field('Telefon', _phoneCtrl),
                      _Field('E-Mail', _emailCtrl,
                          keyboardType: TextInputType.emailAddress),
                      _Field('MWST-Nummer', _mwstCtrl,
                          hint: 'CHE-xxx.xxx.xxx MWST'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              if (_saved)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.success.withAlpha(26),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline, color: AppColors.success, size: 16),
                        SizedBox(width: 8),
                        Text('Gespeichert', style: TextStyle(color: AppColors.success, fontSize: 13)),
                      ],
                    ),
                  ),
                ),

              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    setState(() => _saved = true);
                    Future.delayed(const Duration(seconds: 3), () {
                      if (mounted) setState(() => _saved = false);
                    });
                  }
                },
                child: const Text('Änderungen speichern'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool required;
  final String? hint;
  final TextInputType? keyboardType;

  const _Field(
    this.label,
    this.controller, {
    this.required = false,
    this.hint,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
        ),
        validator: required ? (v) => v?.isEmpty == true ? '$label ist erforderlich' : null : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Printer config
// ---------------------------------------------------------------------------

class _PrinterTab extends StatefulWidget {
  const _PrinterTab();

  @override
  State<_PrinterTab> createState() => _PrinterTabState();
}

class _PrinterTabState extends State<_PrinterTab> {
  String _receiptPrinter = 'EPSON TM-T88VI';
  String _kitchenPrinter = 'EPSON TM-T88V';
  bool _printReceipt = true;
  bool _printKitchen = true;
  bool _printDuplicates = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Druckereinstellungen', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bondrucker', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _receiptPrinter,
                      decoration: const InputDecoration(labelText: 'Gerät'),
                      items: ['EPSON TM-T88VI', 'EPSON TM-T88V', 'Star TSP143', 'Bixolon SRP-350']
                          .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                          .toList(),
                      onChanged: (v) => setState(() => _receiptPrinter = v!),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: const Text('Bon automatisch drucken'),
                      value: _printReceipt,
                      onChanged: (v) => setState(() => _printReceipt = v),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      title: const Text('Doppelten Bon drucken'),
                      value: _printDuplicates,
                      onChanged: (v) => setState(() => _printDuplicates = v),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Küchendrucker', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _kitchenPrinter,
                      decoration: const InputDecoration(labelText: 'Gerät'),
                      items: ['EPSON TM-T88V', 'EPSON TM-T88VI', 'Star TSP650', 'Deaktiviert']
                          .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                          .toList(),
                      onChanged: (v) => setState(() => _kitchenPrinter = v!),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: const Text('Küchenticket automatisch drucken'),
                      value: _printKitchen,
                      onChanged: (v) => setState(() => _printKitchen = v),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Druckereinstellungen gespeichert')),
                );
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tax settings
// ---------------------------------------------------------------------------

class _TaxTab extends StatefulWidget {
  const _TaxTab();

  @override
  State<_TaxTab> createState() => _TaxTabState();
}

class _TaxTabState extends State<_TaxTab> {
  bool _inclusiveTax = true;
  String _defaultTaxGroup = 'reduced';
  bool _enableRounding = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Steuereinstellungen (CH)', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MWST-Sätze (Schweiz 2024)', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    _TaxRateRow('Standard', '8.1%', 'Alkohol, Tabak, andere'),
                    _TaxRateRow('Reduziert', '3.8%', 'Lebensmittel, Getränke (nicht Alkohol)'),
                    _TaxRateRow('Beherbergung', '2.6%', 'Hotelübernachtungen'),
                    _TaxRateRow('Befreit', '0%', 'Medikamente, Bildung'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Preise inkl. MWST'),
                      subtitle: const Text('Preise werden als Bruttopreise angezeigt'),
                      value: _inclusiveTax,
                      onChanged: (v) => setState(() => _inclusiveTax = v),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const Divider(),
                    SwitchListTile(
                      title: const Text('Runden auf 5 Rappen'),
                      subtitle: const Text('Gemäss Schweizer Praxis'),
                      value: _enableRounding,
                      onChanged: (v) => setState(() => _enableRounding = v),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Standard-Steuergruppe'),
                      subtitle: const Text('Für neue Produkte ohne explizite Zuordnung'),
                      trailing: DropdownButton<String>(
                        value: _defaultTaxGroup,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 'reduced', child: Text('Reduziert (3.8%)')),
                          DropdownMenuItem(value: 'standard', child: Text('Standard (8.1%)')),
                        ],
                        onChanged: (v) => setState(() => _defaultTaxGroup = v!),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Steuereinstellungen gespeichert')),
                );
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaxRateRow extends StatelessWidget {
  final String name;
  final String rate;
  final String description;

  const _TaxRateRow(this.name, this.rate, this.description);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(26),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                rate,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                Text(description, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// User management
// ---------------------------------------------------------------------------

class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  final _users = [
    _UserData(id: '1', name: 'Admin Demo', email: 'admin@demo.ch', role: 'admin', active: true),
    _UserData(id: '2', name: 'Maria Müller', email: 'maria@demo.ch', role: 'manager', active: true),
    _UserData(id: '3', name: 'Tom Huber', email: 'tom@demo.ch', role: 'waiter', active: true),
    _UserData(id: '4', name: 'Sara Keller', email: 'sara@demo.ch', role: 'waiter', active: false),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            Text('Benutzerverwaltung', style: theme.textTheme.titleLarge),
            const Spacer(),
            ElevatedButton.icon(
              icon: const Icon(Icons.person_add_outlined, size: 16),
              label: const Text('Benutzer hinzufügen'),
              onPressed: () => _showAddUserDialog(context),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Card(
            child: ListView.separated(
              itemCount: _users.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final user = _users[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: CircleAvatar(
                    backgroundColor: user.active
                        ? AppColors.primary.withAlpha(26)
                        : Colors.grey.withAlpha(26),
                    child: Text(
                      user.name[0].toUpperCase(),
                      style: TextStyle(
                        color: user.active ? AppColors.primary : Colors.grey,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(user.name,
                      style: TextStyle(color: user.active ? null : Colors.grey)),
                  subtitle: Text(user.email),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _RoleBadge(role: user.role),
                      const SizedBox(width: 8),
                      Switch(
                        value: user.active,
                        onChanged: (v) => setState(() => _users[i] = _UserData(
                              id: user.id,
                              name: user.name,
                              email: user.email,
                              role: user.role,
                              active: v,
                            )),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () {},
                        tooltip: 'Bearbeiten',
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _showAddUserDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const _AddUserDialog(),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;

  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (role) {
      'admin' => ('Admin', AppColors.error),
      'manager' => ('Manager', AppColors.warning),
      'waiter' => ('Kellner', AppColors.primary),
      _ => (role, Colors.grey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _UserData {
  final String id;
  final String name;
  final String email;
  final String role;
  final bool active;

  const _UserData({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.active,
  });
}

class _AddUserDialog extends StatefulWidget {
  const _AddUserDialog();

  @override
  State<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<_AddUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String _role = 'waiter';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Benutzer hinzufügen', style: theme.textTheme.titleLarge),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) => v?.isEmpty == true ? 'Erforderlich' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'E-Mail'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v?.isEmpty == true) return 'Erforderlich';
                    if (!v!.contains('@')) return 'Ungültige E-Mail';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _role,
                  decoration: const InputDecoration(labelText: 'Rolle'),
                  items: const [
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'manager', child: Text('Manager')),
                    DropdownMenuItem(value: 'waiter', child: Text('Kellner')),
                  ],
                  onChanged: (v) => setState(() => _role = v!),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Abbrechen'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Benutzer hinzugefügt')),
                          );
                        }
                      },
                      child: const Text('Hinzufügen'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
