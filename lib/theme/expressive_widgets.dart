import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_theme.dart';

/// Optional haptic helper respecting user appearance preferences.
class AppHaptics {
  static void selection(BuildContext context) {
    if (context.visualTokens.hapticsEnabled) {
      HapticFeedback.selectionClick();
    }
  }

  static void light(BuildContext context) {
    if (context.visualTokens.hapticsEnabled) {
      HapticFeedback.lightImpact();
    }
  }
}

/// Adaptive Android 17 frosted-glass container responding to [NotasVisualTokens].
class FrostedGlassSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? baseColor;
  final Color? borderColor;
  final double borderWidth;
  final BoxBorder? customBorder;
  final List<BoxShadow>? boxShadow;

  const FrostedGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.padding,
    this.baseColor,
    this.borderColor,
    this.borderWidth = 1.0,
    this.customBorder,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.visualTokens;
    final isDark = theme.brightness == Brightness.dark;

    final effectiveBase = baseColor ??
        (isDark ? theme.colorScheme.surfaceContainerHigh : theme.colorScheme.surfaceContainerLowest);
    final effectiveBorderColor = borderColor ??
        (isDark
            ? Colors.white.withValues(alpha: tokens.glassBorderOpacity)
            : theme.colorScheme.outlineVariant.withValues(alpha: tokens.glassBorderOpacity * 2.2));

    final BoxBorder? resolvedBorder = customBorder ??
        (borderWidth > 0 ? Border.all(color: effectiveBorderColor, width: borderWidth) : null);

    final inner = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: effectiveBase.withValues(alpha: tokens.glassOpacity),
        borderRadius: borderRadius,
        border: resolvedBorder,
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
  final Color? foregroundColor;

  const FrostedAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.bottom,
    this.tintColor,
    this.foregroundColor,
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
              child: _buildBar(theme, base),
            )
          : _buildBar(theme, base),
    );
  }

  Widget _buildBar(ThemeData theme, Color base) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: base.withValues(alpha: tintColor != null ? 0.92 : theme.extension<NotasVisualTokens>()?.glassOpacity ?? 0.72),
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
        foregroundColor: foregroundColor,
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
    final tokens = context.visualTokens;
    return Padding(
      padding: padding,
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: tokens.accentColor,
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
    final outerRadius = context.visualTokens.cardRadius;
    final count = children.length;

    return Padding(
      padding: margin,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(count, (index) {
          final BorderRadius radius;
          if (count == 1) {
            radius = BorderRadius.circular(outerRadius);
          } else if (index == 0) {
            radius = BorderRadius.vertical(
              top: Radius.circular(outerRadius),
              bottom: const Radius.circular(AppTheme.radiusExtraSmall),
            );
          } else if (index == count - 1) {
            radius = BorderRadius.vertical(
              top: const Radius.circular(AppTheme.radiusExtraSmall),
              bottom: Radius.circular(outerRadius),
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
    final tokens = context.visualTokens;
    final effectiveColor = color ?? tokens.accentColor;
    final effectiveBg = backgroundColor ??
        (color != null ? color!.withValues(alpha: 0.14) : tokens.accentContainer);

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

/// Pill-shaped tab bar that hooks into a passed [controller] or nearest [DefaultTabController].
class ExpressivePillTabBar extends StatelessWidget {
  final List<String> labels;
  final List<IconData>? icons;
  final EdgeInsetsGeometry padding;
  final TabController? controller;

  const ExpressivePillTabBar({
    super.key,
    required this.labels,
    this.icons,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveController = controller ?? DefaultTabController.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.visualTokens;

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
          controller: effectiveController,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          splashBorderRadius: BorderRadius.circular(AppTheme.radiusFull),
          indicator: BoxDecoration(
            color: tokens.accentColor,
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          labelColor: tokens.onAccentColor,
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
