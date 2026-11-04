import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/format.dart';

bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

/// Brand/status colours are chosen for light surfaces; this keeps them legible as
/// text or icons on whichever theme is active (lighter in dark mode, darker for pale colours in light mode).
Color readable(BuildContext c, Color color) {
  if (isDark(c)) return Color.lerp(color, Colors.white, .42)!;
  final l = color.computeLuminance();
  return l > .30 ? Color.lerp(color, Colors.black, ((l - .25) * 1.1).clamp(0.0, .55))! : color;
}

/// Soft, blurred colour blobs behind every screen — gives the glass cards
/// something to refract.
class BlobBackground extends StatelessWidget {
  final Widget child;
  const BlobBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final a = dark ? .30 : .55;
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor)),
        _blob(top: -120, right: -80, size: 320, color: MP.pink.withValues(alpha: a)),
        _blob(top: 180, left: -140, size: 300, color: MP.lavender.withValues(alpha: a * .8)),
        _blob(bottom: -120, right: -60, size: 300, color: MP.mint.withValues(alpha: a * .7)),
        Positioned.fill(
          child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60), child: const SizedBox.expand()),
        ),
        Positioned.fill(child: child),
      ],
    );
  }

  Widget _blob({double? top, double? left, double? right, double? bottom, required double size, required Color color}) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

/// Frosted glass surface.
class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final double blur;
  final Color? tint;
  final EdgeInsetsGeometry? margin;

  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.onTap,
    this.blur = 18,
    this.tint,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final br = BorderRadius.circular(radius);
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Material(
            color: tint ?? (dark ? Colors.white.withValues(alpha: .07) : Colors.white.withValues(alpha: .62)),
            shape: RoundedRectangleBorder(
              borderRadius: br,
              side: BorderSide(color: dark ? Colors.white.withValues(alpha: .10) : Colors.white.withValues(alpha: .9)),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: br,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// A "blurred icon": a glowing colour orb behind a frosted rounded square.
class GlassIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const GlassIcon(this.icon, {super.key, this.color = MP.pinkDeep, this.size = 52});

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: size * .02,
            bottom: size * .02,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: size * .16, sigmaY: size * .16),
              child: Container(
                width: size * .62,
                height: size * .62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [color, color.withValues(alpha: .5)]),
                ),
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(size * .32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size * .32),
                  color: dark ? Colors.white.withValues(alpha: .08) : Colors.white.withValues(alpha: .45),
                  border: Border.all(color: Colors.white.withValues(alpha: dark ? .14 : .8)),
                ),
                child: Icon(icon, color: dark ? Color.lerp(color, Colors.white, .35) : color, size: size * .46),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GlassTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final int badge;
  const GlassTile({super.key, required this.icon, required this.label, required this.color, required this.onTap, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    return Glass(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Badge(
            isLabelVisible: badge > 0,
            label: Text(faNum(badge)),
            child: GlassIcon(icon, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final Gradient gradient;
  const GradientButton({super.key, required this.label, this.icon, this.onPressed, this.loading = false, this.gradient = MP.brandGradient});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : .6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: MP.pink.withValues(alpha: .45), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              height: 54,
              child: Center(
                child: loading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: MP.plum))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[Icon(icon, color: MP.plum), const SizedBox(width: 8)],
                          Text(
                            label,
                            style: const TextStyle(color: MP.plum, fontWeight: FontWeight.w800, fontSize: 15.5),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String status;
  final bool dense;
  const StatusChip(this.status, {super.key, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final s = statusInfo(status);
    final fg = readable(context, s.color);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: s.color.withValues(alpha: .35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, size: dense ? 13 : 15, color: fg),
          const SizedBox(width: 4),
          Text(
            s.label,
            style: TextStyle(color: fg, fontSize: dense ? 11 : 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Selectable chip with explicit text/background colours, so its label is readable
/// in both themes on every platform (never relies on inherited default text colours).
class MPChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final Widget? avatar;
  const MPChoiceChip({super.key, required this.label, required this.selected, this.onSelected, this.avatar});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = isDark(context);
    final style = TextStyle(
      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
      color: selected ? cs.onPrimaryContainer : cs.onSurface,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
    );
    return ChoiceChip(
      avatar: avatar,
      label: Text(label, style: style),
      labelStyle: style,
      selected: selected,
      onSelected: onSelected,
      showCheckmark: true,
      checkmarkColor: cs.primary,
      selectedColor: cs.primaryContainer,
      backgroundColor: dark ? Colors.white.withValues(alpha: .07) : Colors.white.withValues(alpha: .85),
      surfaceTintColor: Colors.transparent,
      side: BorderSide(color: selected ? cs.primary.withValues(alpha: .55) : cs.onSurface.withValues(alpha: .2)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionTitle(this.title, {super.key, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 18,
            decoration: BoxDecoration(gradient: MP.brandGradient, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassIcon(icon, size: 84, color: MP.pinkDeep),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .6)),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorView(this.message, {super.key, required this.onRetry});
  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.wifi_off_rounded,
    title: 'مشکلی پیش آمد',
    subtitle: message,
    action: OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('تلاش دوباره')),
  );
}

/// Scaffold with blob background + transparent app bar.
class MPScaffold extends StatelessWidget {
  final String? title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? fab;
  final Widget? bottom;
  final Widget? leading;
  final Widget? titleWidget;
  const MPScaffold({super.key, this.title, required this.body, this.actions, this.fab, this.bottom, this.leading, this.titleWidget});

  @override
  Widget build(BuildContext context) {
    return BlobBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: (title != null || titleWidget != null)
            ? AppBar(title: titleWidget ?? Text(title!), actions: actions, leading: leading)
            : null,
        body: body,
        floatingActionButton: fab,
        bottomNavigationBar: bottom,
      ),
    );
  }
}

void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: error ? const TextStyle(color: Colors.white, fontWeight: FontWeight.w600) : null,
        ),
        backgroundColor: error ? MP.danger : null,
      ),
    );
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'تایید'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

/// Glass bottom sheet wrapper.
Future<T?> showGlassSheet<T>(BuildContext context, Widget Function(BuildContext) builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            color: isDark(c) ? MP.darkSurface.withValues(alpha: .92) : Colors.white.withValues(alpha: .9),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.withValues(alpha: .4), borderRadius: BorderRadius.circular(4)),
                  ),
                  Flexible(child: builder(c)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
