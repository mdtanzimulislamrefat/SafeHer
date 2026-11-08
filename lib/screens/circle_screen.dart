import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/contacts_store.dart';
import '../data/trusted_contact.dart';
import '../services/permissions.dart';
import '../theme.dart';
import '../widgets/common.dart';

class CircleScreen extends StatelessWidget {
  const CircleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final contacts = context.watch<ContactsStore>().all;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Add someone',
            icon: const Icon(Icons.add, color: SafeColors.plum),
            onPressed: () => openContactForm(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Your circle', style: SafeText.heading(30)),
          const SizedBox(height: 6),
          const Text(
            'People who hear from SafeHer when you need help. Only you can see this list.',
            style: SafeText.small,
          ),
          const SizedBox(height: 14),
          if (contacts.isEmpty)
            _EmptyCircle(onAdd: () => openContactForm(context))
          else
            for (final (i, c) in contacts.indexed) _PersonRow(contact: c, divider: i < contacts.length - 1),
          const SizedBox(height: 12),
          const NoteBox(
            icon: Icons.lock,
            text: "Your contacts don't need SafeHer. Alerts arrive as normal SMS from your number.",
          ),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.contact, required this.divider});

  final TrustedContact contact;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openContactForm(context, existing: contact),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: divider ? const Border(bottom: BorderSide(color: SafeColors.line)) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Avatar(name: contact.name, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(contact.name, style: SafeText.bodyStrong),
                  Text(
                    contact.relation.isEmpty ? contact.maskedPhone : '${contact.relation} · ${contact.maskedPhone}',
                    style: SafeText.caption,
                  ),
                  const SizedBox(height: 4),
                  Text(contact.permissionSummary, style: const TextStyle(fontSize: 13, color: SafeColors.ink)),
                ],
              ),
            ),
            IconButton.outlined(
              tooltip: 'Call ${contact.name}',
              style: IconButton.styleFrom(
                backgroundColor: SafeColors.card,
                side: const BorderSide(color: SafeColors.line),
                minimumSize: const Size(48, 48),
              ),
              icon: const Icon(Icons.phone, color: SafeColors.plum, size: 20),
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: contact.phone)),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCircle extends StatelessWidget {
  const _EmptyCircle({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Nobody here yet.', style: SafeText.bodyStrong),
          const Text('Add at least one person so SOS has someone to reach.', style: SafeText.small),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add someone')),
        ],
      ),
    );
  }
}

Future<void> openContactForm(BuildContext context, {TrustedContact? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SafeColors.paper,
    showDragHandle: true,
    builder: (_) => _ContactForm(existing: existing),
  );
}

class _ContactForm extends StatefulWidget {
  const _ContactForm({this.existing});

  final TrustedContact? existing;

  @override
  State<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<_ContactForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _relation = TextEditingController(text: widget.existing?.relation);
  late bool _sos = widget.existing?.getsSos ?? true;
  late bool _journeys = widget.existing?.getsJourneys ?? true;
  late bool _location = widget.existing?.getsLocation ?? true;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _relation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final store = context.read<ContactsStore>();
    final wasEmpty = store.all.isEmpty;
    final contact = TrustedContact(
      id: widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      phone: normalizePhone(_phone.text)!,
      relation: _relation.text.trim(),
      getsSos: _sos,
      getsJourneys: _journeys,
      getsLocation: _location,
    );
    await store.save(contact);
    if (!mounted) return;
    Navigator.pop(context);
    // Ask for SMS right after the first contact, when the reason is obvious.
    if (wasEmpty) await ensureSmsPermission(context);
  }

  Future<void> _delete() async {
    final c = widget.existing!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${c.name}?'),
        content: const Text('They will stop getting your SOS and journey alerts.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: SafeColors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<ContactsStore>().remove(c.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(editing ? 'Edit ${widget.existing!.name}' : 'Add someone', style: SafeText.heading(24)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name · নাম'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Mobile number', hintText: '01712 345678'),
                validator: (v) => normalizePhone(v ?? '') == null ? 'Enter a valid mobile number' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _relation,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Relation (optional)', hintText: 'Mother, friend…'),
              ),
              const SizedBox(height: 12),
              _PermSwitch(title: 'Gets SOS alerts', value: _sos, onChanged: (v) => setState(() => _sos = v)),
              _PermSwitch(
                title: 'Gets journey check-ins',
                value: _journeys,
                onChanged: (v) => setState(() => _journeys = v),
              ),
              _PermSwitch(
                title: 'Can see my location in alerts',
                value: _location,
                onChanged: (v) => setState(() => _location = v),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _save, child: Text(editing ? 'Save' : 'Add to circle')),
              if (editing) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _delete,
                  style: TextButton.styleFrom(foregroundColor: SafeColors.red),
                  child: const Text('Remove from circle'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PermSwitch extends StatelessWidget {
  const _PermSwitch({required this.title, required this.value, required this.onChanged});

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: SafeText.body),
      value: value,
      onChanged: onChanged,
    );
  }
}
