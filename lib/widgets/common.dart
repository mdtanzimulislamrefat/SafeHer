import 'package:flutter/material.dart';

import '../theme.dart';

/// Round initial badge; the colour is stable per name so people are easy to tell apart.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.size = 40, this.ring});

  final String name;
  final double size;
  final Color? ring;

  static const _palette = [
    (Color(0xFFF6D9C6), Color(0xFF7A3A12)),
    (Color(0xFFD8E7F5), Color(0xFF1D4E7A)),
    (Color(0xFFDDEFD9), Color(0xFF2E5E25)),
    (Color(0xFFF3D8E6), Color(0xFF7A1D4E)),
    (Color(0xFFE6E0F5), Color(0xFF3F2A7A)),
  ];

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final letter = trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
    final (bg, fg) = _palette[trimmed.hashCode.abs() % _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: ring == null ? null : Border.all(color: ring!, width: 2),
      ),
      child: Text(
        letter,
        style: TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

/// Overlapping avatars, e.g. the circle preview on Home.
class AvatarStack extends StatelessWidget {
  const AvatarStack({super.key, required this.names, this.size = 28, this.ring = SafeColors.paper});

  final List<String> names;
  final double size;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    final shown = names.take(4).toList();
    return SizedBox(
      width: shown.isEmpty ? 0 : size + (shown.length - 1) * (size - 8),
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * (size - 8),
              child: Avatar(name: shown[i], size: size, ring: ring),
            ),
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text.toUpperCase(), style: SafeText.section),
    );
  }
}

/// Rounded square icon used at the start of list rows.
class LeadIcon extends StatelessWidget {
  const LeadIcon(this.icon, {super.key, this.color = SafeColors.plum, this.background = SafeColors.plumSoft});

  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

/// A plain list row with a divider below, as used across the v2 design.
class SafeRow extends StatelessWidget {
  const SafeRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.divider = true,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: divider ? const Border(bottom: BorderSide(color: SafeColors.line)) : null,
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SafeText.bodyStrong),
                  if (subtitle != null) Text(subtitle!, style: SafeText.caption),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Coloured dot plus a word, used for delivery states.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, required this.label, this.note});

  final Color color;
  final String label;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
        ),
        if (note != null) ...[
          const SizedBox(width: 4),
          Flexible(
            child: Text('· $note', style: SafeText.caption, overflow: TextOverflow.ellipsis),
          ),
        ],
      ],
    );
  }
}

/// Soft-tinted note box with an icon, for honest explanations.
class NoteBox extends StatelessWidget {
  const NoteBox({
    super.key,
    required this.icon,
    required this.text,
    this.color = SafeColors.plum,
    this.background = SafeColors.plumSoft,
  });

  final IconData icon;
  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: SafeText.caption.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}
