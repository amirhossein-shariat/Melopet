import 'dart:ui';

import 'package:flutter/material.dart';

import '../utils/format.dart';
import 'glass.dart';

class NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int badge;
  const NavItem(this.icon, this.activeIcon, this.label, {this.badge = 0});
}

/// Floating frosted-glass bottom navigation.
class GlassNavBar extends StatelessWidget {
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onTap;
  const GlassNavBar({super.key, required this.items, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = isDark(context);
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: dark ? Colors.white.withValues(alpha: .08) : Colors.white.withValues(alpha: .7),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withValues(alpha: dark ? .12 : .9)),
            ),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => onTap(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              color: i == index ? cs.primary.withValues(alpha: .16) : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Badge(
                              isLabelVisible: items[i].badge > 0,
                              label: Text(faNum(items[i].badge)),
                              child: Icon(
                                i == index ? items[i].activeIcon : items[i].icon,
                                color: i == index ? cs.primary : cs.onSurface.withValues(alpha: .55),
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            items[i].label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: i == index ? FontWeight.w800 : FontWeight.w500,
                              color: i == index ? cs.primary : cs.onSurface.withValues(alpha: .6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
