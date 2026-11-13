import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Adaptive Android 17 frosted-glass container responding to [NotasVisualTokens].
class FrostedGlassSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? baseColor;
  final Color? borderColor;
  final double borderWidth;
  final List<BoxShadow>? boxShadow;

  const FrostedGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.padding,
    this.baseColor,
    this.borderColor,
    this.borderWidth = 1.0,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.visualTokens;
    final isDark = theme.brightness == Brightness.dark;

    final effectiveBase = baseColor ??
        (isDark ? theme.colorScheme.surfaceContainerHigh : theme.colorScheme.surfaceContainerLowest);
    final effectiveBorder = borderColor ??
        (isDark
            ? Colors.white.withValues(alpha: tokens.glassBorderOpacity)
            : theme.colorScheme.outlineVariant.withValues(alpha: tokens.glassBorderOpacity * 2.2));

    final inner = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: effectiveBase.withValues(alpha: tokens.glassOpacity),
        borderRadius: borderRadius,
        border: borderWidth > 0 ? Border.all(color: effectiveBorder, width: borderWidth) : null,
      ),
      child: child,
    );

    final clipped = ClipRRect(
      borderRadius: borderRadius,
      child: tokens.blurSigma > 0
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: tokens.blurSigma, sigmaY: tokens.blurSigma),
              child: inner,
            )
          : inner,
    );

    if (boxShadow == null || boxShadow!.isEmpty) return clipped;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: boxShadow,
      ),
      child: clipped,
    );
  }
}

/// Top AppBar backed by an adaptive Android 17 frosted surface when scrolling behind it.
class FrostedAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final PreferredSizeWidget? bottom;
  final Color? tintColor;

  const FrostedAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.bottom,
    this.tintColor,
  });

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.visualTokens;
    final base = tintColor ?? theme.colorScheme.surface;

    return ClipRect(
      child: tokens.blurSigma > 0
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: tokens.blurSigma, sigmaY: tokens.blurSigma),
              child: _buildBar(theme, base, tokens),
            )
          : _buildBar(theme, base, tokens),
    );
  }

  Widget _buildBar(ThemeData theme, Color base, NotasVisualTokens tokens) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: base.withValues(alpha: tokens.glassOpacity),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
      ),
      child: AppBar(
        title: title,
        actions: actions,
        leading: leading,
        automaticallyImplyLeading: automaticallyImplyLeading,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: bottom,
      ),
    );
  }
}

/// Section header label for Android 17 grouped settings & lists.
class ExpressiveSectionHeader extends StatelessWidget {
  final String title;
  final EdgeInsetsGeometry padding;

  const ExpressiveSectionHeader({
    super.key,
    required this.title,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 8),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Grouped container applying Android 17 outer-rounded / inner-tight radii across children.
class ExpressiveGroupedSection extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry margin;

  const ExpressiveGroupedSection({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final count = children.length;

    return Padding(
      padding: margin,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(count, (index) {
          final BorderRadius radius;
          if (count == 1) {
            radius = BorderRadius.circular(AppTheme.radiusLarge);
          } else if (index == 0) {
            radius = const BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusLarge),
              bottom: Radius.circular(AppTheme.radiusExtraSmall),
            );
          } else if (index == count - 1) {
            radius = const BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusExtraSmall),
              bottom: Radius.circular(AppTheme.radiusLarge),
            );
          } else {
            radius = BorderRadius.circular(AppTheme.radiusExtraSmall);
          }

          return Padding(
            padding: EdgeInsets.only(bottom: index == count - 1 ? 0 : 3),
            child: Material(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: radius,
              clipBehavior: Clip.antiAlias,
              child: children[index],
            ),
          );
        }),
      ),
    );
  }
}

/// Leading tonal squircle icon badge for Android 17 grouped items & sheets.
class TonalIconBadge extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final Color? backgroundColor;
  final double size;

  const TonalIconBadge({
    super.key,
    required this.icon,
    this.color,
    this.backgroundColor,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? scheme.primary;
    final effectiveBg = backgroundColor ??
        (color != null ? color!.withValues(alpha: 0.14) : scheme.surfaceContainerHighest);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(13),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: effectiveColor, size: size * 0.55),
    );
  }
}

/// Pill-shaped tab bar that hooks into the nearest [DefaultTabController].
class ExpressivePillTabBar extends StatelessWidget {
  final List<String> labels;
  final List<IconData>? icons;
  final EdgeInsetsGeometry padding;

  const ExpressivePillTabBar({
    super.key,
    required this.labels,
    this.icons,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: padding,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: TabBar(
          controller: controller,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          splashBorderRadius: BorderRadius.circular(AppTheme.radiusFull),
          indicator: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          labelColor: scheme.onPrimary,
          unselectedLabelColor: scheme.onSurfaceVariant,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: List.generate(labels.length, (i) {
            if (icons != null && i < icons!.length) {
              return Tab(
                height: 40,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icons![i], size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(labels[i], overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              );
            }
            return Tab(height: 38, text: labels[i]);
          }),
        ),
      ),
    );
  }
}

/// Shows an Android 17 frosted/tonal modal bottom sheet.
Future<T?> showExpressiveModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) {
  final tokens = context.visualTokens;
  final scheme = Theme.of(context).colorScheme;

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    showDragHandle: false,
    builder: (sheetContext) {
      final radius = const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusExtraLarge));
      return FrostedGlassSurface(
        borderRadius: radius,
        baseColor: scheme.surfaceContainerLow,
        borderWidth: 1,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
              ),
              const SizedBox(height: 6),
              Flexible(child: builder(sheetContext)),
              if (tokens.blurSigma > 0) const SizedBox(height: 4),
            ],
          ),
        ),
      );
    },
  );
}
