import 'package:flutter/material.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

const _vehicleClasses = ['ECONOMY', 'COMFORT', 'PREMIUM', 'LUXURY'];

/// Ride category CRUD (SWIFT/EASE/LUXE/ELITE and beyond) — the "Category |
/// Base | Distance | Time | Min Fare | Commission" table from the pricing
/// spec, backed by the real RideCategory table. Writes are "pricing:write",
/// so Operations Managers (not just Super Admins) can manage these.
class RideCategoriesScreen extends StatefulWidget {
  const RideCategoriesScreen({super.key});

  @override
  State<RideCategoriesScreen> createState() => _RideCategoriesScreenState();
}

class _RideCategoriesScreenState extends State<RideCategoriesScreen> {
  bool _loading = true;
  String? _error;
  List<RideCategory> _categories = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cats = await AdminApi.rideCategories();
      cats.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openForm({RideCategory? category}) async {
    final saved = await showModalBottomSheet<RideCategory>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      builder: (context) => _RideCategoryForm(category: category),
    );
    if (saved == null) return;
    setState(() {
      if (category == null) {
        _categories = [..._categories, saved]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      } else {
        _categories = [for (final c in _categories) if (c.id == saved.id) saved else c]
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      }
    });
  }

  Future<void> _toggleActive(RideCategory c) async {
    try {
      final updated = await AdminApi.updateRideCategory(c.id, active: !c.active);
      if (!mounted) return;
      setState(() => _categories = [for (final x in _categories) if (x.id == c.id) updated else x]);
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException && e.statusCode == 403
          ? 'You don\'t have permission to change ride categories.'
          : (e is ApiException ? e.message : e.toString());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ride Categories')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null ? _errView() : _body()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('New category'),
      ),
    );
  }

  Widget _errView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );

  Widget _body() {
    if (_categories.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: const [
            SizedBox(height: 60),
            Center(child: Text('No ride categories yet.', style: TextStyle(color: AppColors.textSecondary))),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _categoryCard(_categories[i]),
      ),
    );
  }

  Widget _categoryCard(RideCategory c) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      onTap: () => _openForm(category: c),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: AppComponents.cardDecoration(borderColor: c.active ? null : AppColors.border),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(width: 8),
                      Text('#${c.sortOrder}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                Switch(value: c.active, onChanged: (_) => _toggleActive(c)),
                IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _openForm(category: c)),
              ],
            ),
            if (c.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 8),
                child: Text(c.description, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              ),
            if (c.benefit != null && c.benefit!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppComponents.badge(c.benefit!, color: AppColors.info),
              ),
            // "Category | Base | Distance | Time | Min Fare | Commission" — the
            // spec's own table layout, one row per category.
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1.1),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1.1),
              },
              children: [
                const TableRow(children: [
                  _ColLabel('Base'),
                  _ColLabel('Per km'),
                  _ColLabel('Per min'),
                  _ColLabel('Min fare'),
                ]),
                TableRow(children: [
                  _ColValue(Currency.format(c.baseFare, decimals: 0)),
                  _ColValue(Currency.format(c.perKm, decimals: 0)),
                  _ColValue(Currency.format(c.perMinute, decimals: 0)),
                  _ColValue(Currency.format(c.minimumFare, decimals: 0)),
                ]),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.percent, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  c.commissionRate == null
                      ? 'Commission: inherits RIDE default'
                      : 'Commission: ${(c.commissionRate! * 100).toStringAsFixed(1)}% (override)',
                  style: TextStyle(
                    fontSize: 12,
                    color: c.commissionRate == null ? AppColors.textSecondary : AppColors.textPrimary,
                    fontWeight: c.commissionRate == null ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (c.eligibleVehicleClasses.isEmpty)
                  AppComponents.badge('No vehicle restriction', color: AppColors.textSecondary)
                else
                  for (final v in c.eligibleVehicleClasses) AppComponents.badge(v, color: AppColors.primary),
              ],
            ),
            if (!c.active)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Inactive — hidden from riders', style: TextStyle(fontSize: 11, color: AppColors.warning)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ColLabel extends StatelessWidget {
  final String text;
  const _ColLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(text, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
      );
}

class _ColValue extends StatelessWidget {
  final String text;
  const _ColValue(this.text);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600));
}

/// Create/edit form for a single ride category, reused for both POST and
/// PATCH — mirrors the pricing_surge_screen.dart create-dialog pattern, just
/// as a bottom sheet since this form has more fields.
class _RideCategoryForm extends StatefulWidget {
  final RideCategory? category;
  const _RideCategoryForm({this.category});

  @override
  State<_RideCategoryForm> createState() => _RideCategoryFormState();
}

class _RideCategoryFormState extends State<_RideCategoryForm> {
  late final _keyCtrl = TextEditingController(text: widget.category?.key ?? '');
  late final _nameCtrl = TextEditingController(text: widget.category?.name ?? '');
  late final _descCtrl = TextEditingController(text: widget.category?.description ?? '');
  late final _benefitCtrl = TextEditingController(text: widget.category?.benefit ?? '');
  late final _baseCtrl = TextEditingController(text: widget.category?.baseFare.toStringAsFixed(0) ?? '');
  late final _perKmCtrl = TextEditingController(text: widget.category?.perKm.toStringAsFixed(0) ?? '');
  late final _perMinCtrl = TextEditingController(text: widget.category?.perMinute.toStringAsFixed(0) ?? '');
  late final _minFareCtrl = TextEditingController(text: widget.category?.minimumFare.toStringAsFixed(0) ?? '0');
  late final _sortOrderCtrl = TextEditingController(text: '${widget.category?.sortOrder ?? 0}');
  late final _commissionCtrl = TextEditingController(
    text: widget.category?.commissionRate == null ? '' : (widget.category!.commissionRate! * 100).toStringAsFixed(1),
  );
  late bool _active = widget.category?.active ?? true;
  late final Set<String> _selectedVehicleClasses = {...(widget.category?.eligibleVehicleClasses ?? const [])};

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.category != null;

  @override
  void dispose() {
    _keyCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _benefitCtrl.dispose();
    _baseCtrl.dispose();
    _perKmCtrl.dispose();
    _perMinCtrl.dispose();
    _minFareCtrl.dispose();
    _sortOrderCtrl.dispose();
    _commissionCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final key = _keyCtrl.text.trim().toUpperCase();
    final name = _nameCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final base = double.tryParse(_baseCtrl.text.trim());
    final perKm = double.tryParse(_perKmCtrl.text.trim());
    final perMin = double.tryParse(_perMinCtrl.text.trim());
    final minFare = double.tryParse(_minFareCtrl.text.trim()) ?? 0;
    final sortOrder = int.tryParse(_sortOrderCtrl.text.trim()) ?? 0;
    final commissionText = _commissionCtrl.text.trim();
    final commissionPercent = commissionText.isEmpty ? null : double.tryParse(commissionText);

    if (key.isEmpty || !RegExp(r'^[A-Z0-9_]+$').hasMatch(key)) {
      setState(() => _error = 'Key must be upper-case letters, numbers and underscores only.');
      return;
    }
    if (name.isEmpty || desc.isEmpty || base == null || perKm == null || perMin == null) {
      setState(() => _error = 'Enter a name, description, and numeric base/per-km/per-minute rates.');
      return;
    }
    if (base < 0 || perKm < 0 || perMin < 0 || minFare < 0) {
      setState(() => _error = 'Rates cannot be negative.');
      return;
    }
    if (commissionText.isNotEmpty && (commissionPercent == null || commissionPercent < 0 || commissionPercent > 100)) {
      setState(() => _error = 'Commission override must be a percentage between 0 and 100, or left blank to inherit.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final commissionRate = commissionPercent == null ? null : commissionPercent / 100;
      final saved = _isEdit
          ? await AdminApi.updateRideCategory(
              widget.category!.id,
              name: name,
              description: desc,
              benefit: _benefitCtrl.text.trim(),
              baseFare: base,
              perKm: perKm,
              perMinute: perMin,
              minimumFare: minFare,
              commissionRate: commissionRate,
              clearCommissionRate: commissionRate == null,
              sortOrder: sortOrder,
              eligibleVehicleClasses: _selectedVehicleClasses.toList(),
              active: _active,
            )
          : await AdminApi.createRideCategory(
              key: key,
              name: name,
              description: desc,
              benefit: _benefitCtrl.text.trim().isEmpty ? null : _benefitCtrl.text.trim(),
              baseFare: base,
              perKm: perKm,
              perMinute: perMin,
              minimumFare: minFare,
              commissionRate: commissionRate,
              sortOrder: sortOrder,
              eligibleVehicleClasses: _selectedVehicleClasses.toList(),
              active: _active,
            );
      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.statusCode == 403
            ? 'You don\'t have permission to save ride categories.'
            : (e is ApiException ? e.message : e.toString());
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sym = Currency.symbol;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            Text(_isEdit ? 'Edit ${widget.category!.name}' : 'New ride category',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 16),
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
              ),
            TextField(
              controller: _keyCtrl,
              enabled: !_isEdit,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Key',
                helperText: _isEdit ? 'Key can\'t be changed after creation' : 'e.g. SWIFT — upper case, letters/numbers/underscores',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _benefitCtrl,
              decoration: const InputDecoration(labelText: 'Benefit (optional badge, e.g. "Fastest pickup")', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _baseCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(prefixText: '$sym ', labelText: 'Base fare', border: const OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _perKmCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(prefixText: '$sym ', labelText: 'Per km', border: const OutlineInputBorder()),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _perMinCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(prefixText: '$sym ', labelText: 'Per minute', border: const OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _minFareCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(prefixText: '$sym ', labelText: 'Minimum fare', border: const OutlineInputBorder()),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _commissionCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Commission override (optional)',
                suffixText: '%',
                helperText: 'Leave blank to inherit the platform RIDE commission rate',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _sortOrderCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Sort order',
                helperText: 'Lower numbers show first in the rider app',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Eligible vehicle classes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 4),
            const Text(
              'Leave none selected for "no restriction" — any driver vehicle class can serve this category.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in _vehicleClasses)
                  FilterChip(
                    label: Text(v),
                    selected: _selectedVehicleClasses.contains(v),
                    onSelected: (sel) => setState(() {
                      if (sel) {
                        _selectedVehicleClasses.add(v);
                      } else {
                        _selectedVehicleClasses.remove(v);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Visible to riders when off', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            const SizedBox(height: 8),
            AppComponents.primaryButton(
              text: _saving ? 'Saving…' : (_isEdit ? 'Save changes' : 'Create category'),
              onPressed: _saving ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
