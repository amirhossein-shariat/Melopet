import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../utils/units.dart';

import 'package:flutter/services.dart';

import '../theme.dart';
import '../utils/format.dart';

bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + .05 : lb + .05) / (la > lb ? lb + .05 : la + .05);
}

/// Brand/status colours are chosen for decoration; this returns a version of [color] that is
/// legible as TEXT or ICON on the active theme's surface (>= 4.8:1), staying as close to the
/// original hue as possible.
Color readable(BuildContext c, Color color) {
  final dark = isDark(c);
  // glass cards sit on tinted blobs, so assume the worst-case surface of each theme
  final surface = dark ? const Color(0xFF62505A) : const Color(0xFFEBDFF3);
  final target = dark ? Colors.white : Colors.black;
  for (var t = 0.0; t <= .9; t += .04) {
    final cand = Color.lerp(color, target, t)!;
    if (_contrast(cand, surface) >= 4.8) return cand;
  }
  return target;
}

/// Secondary text colour: clearly softer than body text but always readable.
Color muted(BuildContext c) => Theme.of(c).colorScheme.onSurface.withValues(alpha: isDark(c) ? .78 : .76);

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

/// Frosted glass surface with hover (web/tablet) and press feedback.
class Glass extends StatefulWidget {
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
  State<Glass> createState() => _GlassState();
}

class _GlassState extends State<Glass> {
  bool _hover = false;
  bool _down = false;
  Timer? _downTimer;

  @override
  void dispose() {
    _downTimer?.cancel();
    super.dispose();
  }

  // The press effect starts after a short delay and is cancelled as soon as the touch
  // turns into a scroll, so scrolling never makes cards flash or pop.
  void _pointerDown() {
    _downTimer?.cancel();
    _downTimer = Timer(const Duration(milliseconds: 110), () {
      if (mounted) setState(() => _down = true);
    });
  }

  void _pointerEnd() {
    _downTimer?.cancel();
    if (_down && mounted) setState(() => _down = false);
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final cs = Theme.of(context).colorScheme;
    final tappable = widget.onTap != null;
    final br = BorderRadius.circular(widget.radius);
    final hovered = _hover && tappable;
    final base = dark ? Colors.white.withValues(alpha: hovered ? .12 : .07) : Colors.white.withValues(alpha: hovered ? .86 : .72);
    final edge = dark
        ? Colors.white.withValues(alpha: hovered ? .26 : .12)
        : (hovered ? cs.primary.withValues(alpha: .38) : MP.pinkDeep.withValues(alpha: .16));
    return Padding(
      padding: widget.margin ?? EdgeInsets.zero,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: tappable ? SystemMouseCursors.click : MouseCursor.defer,
        child: AnimatedScale(
          scale: !tappable ? 1 : (_down ? .976 : (hovered ? 1.012 : 1)),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: ClipRRect(
            borderRadius: br,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
              child: Material(
                animationDuration: const Duration(milliseconds: 180),
                color: widget.tint ?? base,
                shape: RoundedRectangleBorder(
                  borderRadius: br,
                  side: BorderSide(color: edge, width: 1.1),
                ),
                child: InkWell(
                  onTap: widget.onTap,
                  onTapDown: tappable ? (_) => _pointerDown() : null,
                  onTapUp: tappable ? (_) => _pointerEnd() : null,
                  onTapCancel: tappable ? _pointerEnd : null,
                  borderRadius: br,
                  splashColor: cs.primary.withValues(alpha: .10),
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  child: Padding(padding: widget.padding, child: widget.child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An icon on a glowing colour orb inside a tinted rounded square.
///
/// The glow is a pre-computed radial gradient (no live blur filter), so it looks identical
/// while scrolling — a live blur is re-cached when a scroll starts and made the colour jump.
/// The square is tinted with the icon's own colour and outlined, so it stands out from the
/// card behind it in both themes.
class GlassIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const GlassIcon(this.icon, {super.key, this.color = MP.pinkDeep, this.size = 52});

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final glyph = dark ? Color.lerp(color, Colors.white, .32)! : readable(context, color);
    final radius = BorderRadius.circular(size * .32);
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -size * .14,
              bottom: -size * .16,
              child: Container(
                width: size * 1.0,
                height: size * 1.0,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      color.withValues(alpha: dark ? .55 : .62),
                      color.withValues(alpha: dark ? .22 : .26),
                      color.withValues(alpha: 0),
                    ],
                    stops: const [0, .55, 1],
                  ),
                ),
              ),
            ),
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: radius,
                color: dark
                    ? Color.alphaBlend(color.withValues(alpha: .20), const Color(0xFF2A1D27).withValues(alpha: .86))
                    : Color.alphaBlend(color.withValues(alpha: .15), Colors.white.withValues(alpha: .93)),
                border: Border.all(color: color.withValues(alpha: dark ? .45 : .55), width: 1.2),
              ),
              child: Icon(icon, color: glyph, size: size * .48),
            ),
          ],
        ),
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
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Badge(
            isLabelVisible: badge > 0,
            label: Text(faNum(badge)),
            child: GlassIcon(icon, color: color, size: 48),
          ),
          const SizedBox(height: 8),
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

class GradientButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final Gradient gradient;
  const GradientButton({super.key, required this.label, this.icon, this.onPressed, this.loading = false, this.gradient = MP.brandGradient});

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : .78,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: AnimatedScale(
          scale: enabled ? (_down ? .97 : (_hover ? 1.015 : 1)) : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              gradient: widget.gradient,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: MP.pink.withValues(alpha: _hover && enabled ? .65 : .42),
                  blurRadius: _hover && enabled ? 26 : 18,
                  offset: Offset(0, _down ? 4 : 8),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: enabled ? widget.onPressed : null,
                onHighlightChanged: (v) => setState(() => _down = v),
                splashColor: Colors.white.withValues(alpha: .3),
                highlightColor: Colors.transparent,
                child: SizedBox(
                  height: 54,
                  child: Center(
                    child: widget.loading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: MP.plum))
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.icon != null) ...[Icon(widget.icon, color: MP.plum), const SizedBox(width: 8)],
                              Text(
                                widget.label,
                                style: const TextStyle(color: MP.plum, fontWeight: FontWeight.w800, fontSize: 15.5),
                              ),
                            ],
                          ),
                  ),
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
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .78)),
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

/// Copies text and tells the user honestly whether it worked (a denied clipboard must not say "copied").
Future<void> copyText(BuildContext context, String text, {String done = 'کپی شد'}) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) toast(context, done);
  } catch (_) {
    if (context.mounted) toast(context, 'کپی انجام نشد؛ متن را نگه دارید و دستی کپی کنید', error: true);
  }
}

void toast(BuildContext context, String msg, {bool error = false}) {
  final dark = isDark(context);
  // solid colours chosen to stand out from the pastel/dark background in both themes
  final bg = error ? const Color(0xFFB3263E) : (dark ? const Color(0xFF3B2A36) : const Color(0xFF3D1630));
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: bg,
        duration: const Duration(milliseconds: 2600),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        content: Row(
          children: [
            Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded, color: error ? Colors.white : MP.mint, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'تایید', String cancel = 'انصراف'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Text(body),
      actionsAlignment: MainAxisAlignment.end,
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(c, false), child: Text(cancel)),
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
                  // a transparent Material so ListTile ink/splashes inside the sheet stay visible
                  Flexible(
                    child: Material(type: MaterialType.transparency, child: builder(c)),
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

/// Minimal gift mark (brand gradient) — replaces the gift emoji.
class GiftMark extends StatelessWidget {
  final double size;
  const GiftMark({super.key, this.size = 30});

  @override
  Widget build(BuildContext context) => ShaderMask(
    shaderCallback: (r) => MP.brandGradient.createShader(r),
    blendMode: BlendMode.srcIn,
    child: Icon(Icons.card_giftcard_rounded, size: size, color: Colors.white),
  );
}

/// Small vector hand that waves a few times when it appears — replaces the 👋 emoji.
class WavingHand extends StatefulWidget {
  final double size;
  const WavingHand({super.key, this.size = 22});

  @override
  State<WavingHand> createState() => _WavingHandState();
}

class _WavingHandState extends State<WavingHand> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        // three quick waves that fade out
        final t = _c.value;
        final angle = sin(t * pi * 6) * .38 * (1 - t);
        return Transform.rotate(angle: angle, alignment: Alignment.bottomRight, child: child);
      },
      child: ShaderMask(
        shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFFFB27A), Color(0xFFF08AAE)]).createShader(r),
        blendMode: BlendMode.srcIn,
        child: Icon(Icons.waving_hand_rounded, size: widget.size, color: Colors.white),
      ),
    );
  }
}

/// Fades and slides its child in once, with a small delay per [index] (staggered lists).
class Reveal extends StatefulWidget {
  final int index;
  final Widget child;
  const Reveal({super.key, this.index = 0, required this.child});

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final _curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(Duration(milliseconds: 40 + min(widget.index, 9) * 70), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, .07), end: Offset.zero).animate(_curve),
        child: widget.child,
      ),
    );
  }
}

/// Result value with its high/low arrow, optically aligned: the digits' ink sits higher than the
/// centre of Vazirmatn's text box, so the arrow is lifted by the measured offset (≈1.8px at 13px text).
class FlaggedValue extends StatelessWidget {
  final String value;
  final bool? high; // true = high, false = low, null = no arrow
  final Color color;
  final double fontSize;
  const FlaggedValue({super.key, required this.value, required this.high, required this.color, this.fontSize = 13});

  @override
  Widget build(BuildContext context) {
    final iconSize = fontSize + 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: fontSize, color: color),
        ),
        if (high != null)
          Transform.translate(
            offset: Offset(0, -fontSize * .14),
            child: Icon(high! ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: iconSize, color: color),
          ),
      ],
    );
  }
}

/// A lab unit ("×10³/µL", "mg/dL") with a real superscript, always laid out left-to-right and
/// aligned to the start edge of its cell.
class UnitText extends StatelessWidget {
  final String unit;
  final TextStyle? style;
  const UnitText(this.unit, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    final size = base.fontSize ?? 14;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Text.rich(
          TextSpan(
            style: base,
            children: [
              for (final p in parseUnit(unit))
                if (p.sup)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: Transform.translate(
                      offset: Offset(0, -size * .38),
                      child: Text(p.text, style: base.copyWith(fontSize: size * .68)),
                    ),
                  )
                else
                  TextSpan(text: p.text),
            ],
          ),
        ),
      ),
    );
  }
}

/// Numbers and ranges ("5.5 - 19.5") keep their left-to-right order inside right-to-left screens.
class LtrText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const LtrText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Text(text, textDirection: TextDirection.ltr, style: style),
  );
}
