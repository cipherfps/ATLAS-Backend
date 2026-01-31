import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:image/image.dart' as img;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:archive/archive_io.dart';

final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.dark);
final ValueNotifier<String> appBackgroundPath = ValueNotifier('');
final ValueNotifier<double> appBackgroundBlur = ValueNotifier(18);
final ValueNotifier<bool> appDialogBlurEnabled = ValueNotifier(true);

const _fallbackAcrylicColor = Color(0x260A0E14);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await Window.initialize();
    await Window.setEffect(
      effect: WindowEffect.acrylic,
      color: _fallbackAcrylicColor,
    );
    await Window.makeTitlebarTransparent();
    await Window.enableFullSizeContentView();
  }
  runApp(const AtlasApp());
}

class AtlasApp extends StatefulWidget {
  const AtlasApp({super.key});

  @override
  State<AtlasApp> createState() => _AtlasAppState();
}

class _AtlasAppState extends State<AtlasApp> {
  int _acrylicToken = 0;

  @override
  void initState() {
    super.initState();
    _loadTheme();
    appBackgroundPath.addListener(_scheduleAcrylicUpdate);
  }

  Future<void> _loadTheme() async {
    final config = await ConfigService.load();
    appThemeMode.value = config.useDarkMode ? ThemeMode.dark : ThemeMode.light;
    appBackgroundPath.value = config.backgroundImagePath;
    appBackgroundBlur.value = config.backgroundBlur;
    appDialogBlurEnabled.value = config.dialogBlurEnabled;
    _scheduleAcrylicUpdate();
  }

  @override
  void dispose() {
    appBackgroundPath.removeListener(_scheduleAcrylicUpdate);
    super.dispose();
  }

  void _scheduleAcrylicUpdate() {
    if (!Platform.isWindows) return;
    final token = ++_acrylicToken;
    _applyAcrylicForBackground(appBackgroundPath.value).then((_) {
      if (!mounted || token != _acrylicToken) return;
    });
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF64D7FF);
    const accentBlue = Color(0xFF1E88E5);
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (_, mode, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ATLAS',
        themeMode: mode,
        scrollBehavior: const _AtlasScrollBehavior(),
        theme: ThemeData(
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF2F4F7),
          colorScheme: const ColorScheme.light(
            primary: seed,
            secondary: accentBlue,
            surface: Color(0xFFF7F9FC),
            onSurface: Color(0xFF121724),
          ),
          sliderTheme: SliderThemeData(
            activeTrackColor: accentBlue,
            inactiveTrackColor: accentBlue.withOpacity(0.2),
            thumbColor: accentBlue,
            overlayColor: accentBlue.withOpacity(0.2),
            valueIndicatorColor: accentBlue,
            valueIndicatorTextStyle: const TextStyle(color: Colors.white),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentBlue,
              foregroundColor: Colors.white,
            ),
          ),
          switchTheme: SwitchThemeData(
            thumbColor: MaterialStateProperty.resolveWith((states) {
              if (states.contains(MaterialState.selected)) return accentBlue;
              return Colors.grey.shade400;
            }),
            trackColor: MaterialStateProperty.resolveWith((states) {
              if (states.contains(MaterialState.selected)) return accentBlue.withOpacity(0.55);
              return Colors.black.withOpacity(0.2);
            }),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: accentBlue),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(foregroundColor: accentBlue),
          ),
          textTheme: const TextTheme(
            headlineLarge: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: 0.4),
            headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            bodyLarge: TextStyle(fontSize: 16, height: 1.4),
            bodyMedium: TextStyle(fontSize: 14, height: 1.4),
          ),
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0A0E14),
          colorScheme: const ColorScheme.dark(
            primary: seed,
            secondary: accentBlue,
            surface: Color(0xFF101722),
            onSurface: Color(0xFFE9F1FF),
          ),
          sliderTheme: SliderThemeData(
            activeTrackColor: accentBlue,
            inactiveTrackColor: accentBlue.withOpacity(0.25),
            thumbColor: accentBlue,
            overlayColor: accentBlue.withOpacity(0.25),
            valueIndicatorColor: accentBlue,
            valueIndicatorTextStyle: const TextStyle(color: Colors.white),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentBlue,
              foregroundColor: Colors.white,
            ),
          ),
          switchTheme: SwitchThemeData(
            thumbColor: MaterialStateProperty.resolveWith((states) {
              if (states.contains(MaterialState.selected)) return accentBlue;
              return Colors.white54;
            }),
            trackColor: MaterialStateProperty.resolveWith((states) {
              if (states.contains(MaterialState.selected)) return accentBlue.withOpacity(0.55);
              return Colors.white24;
            }),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: accentBlue),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(foregroundColor: accentBlue),
          ),
          textTheme: const TextTheme(
            headlineLarge: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: 0.4),
            headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            bodyLarge: TextStyle(fontSize: 16, height: 1.4),
            bodyMedium: TextStyle(fontSize: 14, height: 1.4),
          ),
        ),
        home: const AtlasHomePage(),
      ),
    );
  }
}

class _AtlasScrollBehavior extends MaterialScrollBehavior {
  const _AtlasScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const _SmoothScrollPhysics(
      parent: BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
    );
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.mouse,
        PointerDeviceKind.touch,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}

class _SmoothScrollPhysics extends ScrollPhysics {
  const _SmoothScrollPhysics({super.parent, this.multiplier = 0.35});

  final double multiplier;

  @override
  _SmoothScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _SmoothScrollPhysics(parent: buildParent(ancestor), multiplier: multiplier);
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    return super.applyPhysicsToUserOffset(position, offset * multiplier);
  }
}

Future<T?> _showBlurDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 600),
    pageBuilder: (context, animation, secondaryAnimation) {
      return SafeArea(child: Center(child: builder(context)));
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeInOutSine);
      final blurEnabled = appDialogBlurEnabled.value;
      final t = curved.value;
      final blurSigma = blurEnabled ? 2.6 * t : 0.0;
      final overlayOpacity = blurEnabled ? 0.10 * t : 0.0;
      final content = FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
          child: child,
        ),
      );
      return Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: Container(color: Colors.black.withOpacity(overlayOpacity)),
            ),
          ),
          content,
        ],
      );
    },
  );
}

class AtlasHomePage extends StatefulWidget {
  const AtlasHomePage({super.key});

  @override
  State<AtlasHomePage> createState() => _AtlasHomePageState();
}

class _AtlasHomePageState extends State<AtlasHomePage> with WidgetsBindingObserver {
  late final BackendController _controller;
  bool _exitInProgress = false;
  bool _checkingUpdate = false;
  String _backendVersionLabel = '1.0.0';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = BackendController()..startPolling();
    unawaited(_initStartup());
    unawaited(_loadBackendVersion());
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeCheckForUpdatesOnLaunch());
  }

  Future<void> _maybeCheckForUpdatesOnLaunch() async {
    final config = await ConfigService.load();
    if (config.disableBackendUpdateCheck) return;
    await _checkForUpdates(silent: true);
  }

  Future<void> _initStartup() async {
    final config = await ConfigService.load();
    if (config.startBackendOnLaunch) {
      await _controller.ensureStoppedOnLaunch();
      await _controller.startBackend();
    } else {
      await _controller.ensureStoppedOnLaunch();
    }
  }

  Future<void> _loadBackendVersion() async {
    final packageFile = File(joinPath([getBackendRoot(), 'package.json']));
    if (!await packageFile.exists()) return;
    try {
      final json = jsonDecode(await packageFile.readAsString()) as Map<String, dynamic>;
      final version = json['version']?.toString().trim();
      if (version == null || version.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _backendVersionLabel = version;
      });
    } catch (_) {
      // Keep fallback label if parsing fails.
    }
  }

  Future<void> _checkForUpdates({required bool silent}) async {
    if (_checkingUpdate) return;
    _checkingUpdate = true;
    final info = await UpdateService.checkForUpdate();
    _checkingUpdate = false;
    if (!mounted) return;
    if (info == null) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No updates available.')));
      }
      return;
    }
    await _showUpdateDialog(info);
  }

  Future<void> _showUpdateDialog(UpdateInfo info) async {
    final progress = ValueNotifier<double>(0);
    bool updating = false;
    String? error;
    Future<void> restartApp() async {
      final exePath = Platform.resolvedExecutable;
      if (exePath.isNotEmpty) {
        try {
          await Process.start(exePath, const [], mode: ProcessStartMode.detached);
        } catch (_) {}
      }
      exit(0);
    }
    await _showBlurDialog<void>(
      context: context,
      barrierDismissible: !updating,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final tagRow = Row(
            children: [
              _VersionTag(label: info.currentLabel, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text('—', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 8),
              _VersionTag(label: info.latestLabel, color: Colors.greenAccent),
            ],
          );
          return AlertDialog(
            title: const Text('An update is available'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tagRow,
                  const SizedBox(height: 12),
                  if (info.notes != null && info.notes!.isNotEmpty)
                    Text(info.notes!, style: Theme.of(context).textTheme.bodySmall),
                  if (updating) ...[
                    const SizedBox(height: 16),
                    ValueListenableBuilder<double>(
                      valueListenable: progress,
                      builder: (context, value, _) {
                        final pct = (value.clamp(0.0, 1.0) * 100).toStringAsFixed(0);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LinearProgressIndicator(value: value > 0 && value < 1 ? value : null),
                            const SizedBox(height: 6),
                            Text('Downloading... $pct%'),
                          ],
                        );
                      },
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!, style: const TextStyle(color: Colors.redAccent)),
                  ],
                ],
              ),
            ),
            actions: [
              _HoverScale(
                child: TextButton(
                  onPressed: updating ? null : () => Navigator.pop(context),
                  child: const Text('Later'),
                ),
              ),
              _HoverScale(
                child: ElevatedButton(
                  onPressed: updating
                      ? null
                      : () async {
                          setState(() {
                            updating = true;
                            error = null;
                          });
                          try {
                            await _controller.stopBackend();
                            await UpdateService.downloadAndApply(info, progress);
                            if (!mounted) return;
                            Navigator.pop(context);
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(content: Text('Updated to ${info.latestLabel}. Restarting...')),
                            );
                            await Future<void>.delayed(const Duration(milliseconds: 600));
                            await restartApp();
                          } catch (err) {
                            setState(() {
                              error = 'Update failed: $err';
                              updating = false;
                            });
                          } finally {
                            progress.value = 0;
                          }
                        },
                  child: Text(updating ? 'Updating...' : 'Update now'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.stopBackend());
    unawaited(_controller.forceKillBackendPort());
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _confirmExit() async {
    if (_exitInProgress) return false;
    _exitInProgress = true;
    final confirm = await DataService._confirmDialog(
      context,
      'Close the backend before exiting?',
    );
    if (confirm) {
      await _controller.stopBackend();
      await _controller.forceKillBackendPort();
    }
    _exitInProgress = false;
    return confirm;
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (!mounted) return AppExitResponse.exit;
    final confirm = await _confirmExit();
    return confirm ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  static const List<MenuItemData> _menuItems = [
    MenuItemData(
      title: 'Modifications',
      subtitle: 'Manage Straight Bloom and CurveTables',
      icon: Icons.tune,
      accent: Color(0xFF6BE7FF),
      actions: [
        MenuAction(title: 'Toggle Straight Bloom', description: 'Enable or disable straight bloom.'),
        MenuAction(title: 'Toggle CurveTables', description: 'Enable or disable all CurveTables.'),
        MenuAction(title: 'CurveTable Settings', description: 'Manage individual tables.'),
      ],
    ),
    MenuItemData(
      title: 'Arena',
      subtitle: 'Leaderboard and Point Saving',
      icon: Icons.emoji_events,
      accent: Color(0xFFFF6A8C),
      enabled: false,
      actions: [
        MenuAction(title: 'Arena Leaderboard', description: 'View top profiles.'),
        MenuAction(title: 'Save Arena Points', description: 'Toggle saving points.'),
      ],
    ),
    MenuItemData(
      title: 'Game Configuration',
      subtitle: 'Manage In Game Events and Stages',
      icon: Icons.settings_suggest,
      accent: Color(0xFF5BF2B3),
      actions: [
        MenuAction(title: 'Rufus Week Stage', description: 'Set 1-4.'),
        MenuAction(title: 'Water Level', description: 'Set 1-8.'),
        MenuAction(title: 'Water Storm', description: 'Toggle storm events.'),
      ],
    ),
    MenuItemData(
      title: 'Profiles',
      subtitle: 'Manage profiles and apply custom cosmetic presets',
      icon: Icons.people_alt_rounded,
      accent: Color(0xFF7EE081),
      actions: [
        MenuAction(title: 'View Profiles', description: 'See all local profiles.'),
        MenuAction(title: 'Apply Preset', description: 'Replace a profile with a preset.'),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return WillPopScope(
      onWillPop: () async => _confirmExit(),
      child: Scaffold(
        body: Stack(
          children: [
            const AtlasBackground(),
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (_, __) => _TopBar(
                      textTheme: textTheme,
                      statusText: _controller.statusText,
                      statusColor: _controller.statusColor,
                      versionLabel: _backendVersionLabel,
                      onSettingsPressed: () => Navigator.of(context).push(_buildRoute(const SettingsScreen())),
                      onCheckUpdates: () => _checkForUpdates(silent: false),
                      height: 110,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _MenuGrid(items: _menuItems),
                        ),
                        const SizedBox(width: 28),
                        Expanded(
                          flex: 2,
                          child: AnimatedBuilder(
                            animation: _controller,
                            builder: (_, __) => _SidePanel(controller: _controller),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.textTheme,
    required this.statusText,
    required this.statusColor,
    required this.versionLabel,
    required this.onSettingsPressed,
    required this.onCheckUpdates,
    required this.height,
  });

  final TextTheme textTheme;
  final String statusText;
  final Color statusColor;
  final String versionLabel;
  final VoidCallback onSettingsPressed;
  final VoidCallback? onCheckUpdates;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bannerPath = joinPath([
      getBackendRoot(),
      'public',
      'images',
      'ATLAS-Backend-Banner-Transparent.png',
    ]);
    final bannerFile = File(bannerPath);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => _showAboutDialog(context),
            child: bannerFile.existsSync()
                ? Image.file(
                    bannerFile,
                    height: 100,
                    fit: BoxFit.contain,
                  )
                : Row(
                    children: [
                      Image.asset(
                        'assets/images/atlas_logo.png',
                        width: 100,
                        height: 100,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ATLAS', style: textTheme.headlineMedium),
                          const SizedBox(height: 4),
                          Text(
                            'Backend control center',
                            style: textTheme.bodyMedium?.copyWith(color: _onSurface(context, 0.7)),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          const Spacer(),
          SizedBox(
            width: 40,
            child: _HoverScale(
              enabled: onSettingsPressed != null,
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onSettingsPressed,
                icon: const Icon(Icons.settings_rounded),
                tooltip: 'Settings',
              ),
            ),
          ),
          const SizedBox(width: 8),
          _StatusPill(label: 'Backend', value: statusText, color: statusColor),
          const SizedBox(width: 16),
          _StatusPill(
            label: 'Version',
            value: versionLabel,
            color: _onSurface(context, 0.24),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: _HoverScale(
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Check for updates',
                onPressed: onCheckUpdates,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: _onSurface(context, 0.7)),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _VersionTag extends StatelessWidget {
  const _VersionTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _MenuGrid extends StatelessWidget {
  const _MenuGrid({required this.items});

  final List<MenuItemData> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
        childAspectRatio: 1.6,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return MenuCard(
          data: item,
          onTap: item.enabled
              ? () {
                  Navigator.of(context).push(_buildRoute(_pageForMenu(item.title)));
                }
              : null,
        );
      },
    );
  }
}

class MenuCard extends StatefulWidget {
  const MenuCard({super.key, required this.data, required this.onTap});

  final MenuItemData data;
  final VoidCallback? onTap;

  @override
  State<MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends State<MenuCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.data.accent;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEnabled = widget.data.enabled && widget.onTap != null;
    return MouseRegion(
      onEnter: isEnabled ? (_) => setState(() => _hovered = true) : null,
      onExit: isEnabled ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        onTap: isEnabled ? widget.onTap : null,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          scale: _hovered && isEnabled ? 1.02 : 1,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: isEnabled ? 1 : 0.45,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: [
                    accent.withOpacity(isDark ? 0.22 : 0.32),
                    isDark ? const Color(0xFF141B26) : const Color(0xFFF2F5FB),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: _hovered && isEnabled ? accent.withOpacity(0.8) : _onSurface(context, 0.12),
                  width: 1.2,
                ),
                boxShadow: [
                  if (isDark)
                    BoxShadow(
                      color: _menuShadowColor(context, accent),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    )
                  else ...[
                    BoxShadow(
                      color: _menuShadowColor(context, accent),
                      blurRadius: 32,
                      offset: const Offset(0, 14),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 28,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(widget.data.icon, color: accent, size: 26),
                      ),
                      const Spacer(),
                      Icon(Icons.arrow_forward_rounded, color: _onSurface(context, 0.7)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(widget.data.title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    widget.data.subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: _onSurface(context, 0.7)),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white12 : Colors.black.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.controller});

  final BackendController controller;
  static final ScrollController _logsController = ScrollController();
  static int _lastLogCount = 0;

  @override
  Widget build(BuildContext context) {
    final logCount = controller.recentLogs.length;
    if (logCount != _lastLogCount) {
      _lastLogCount = logCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logsController.hasClients) {
          _logsController.animateTo(
            _logsController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
    return GlassPanel(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quick Actions', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _ActionButton(
              label: controller.isStarting ? 'Starting...' : 'Start Backend',
              icon: Icons.play_arrow_rounded,
              color: const Color(0xFF5BE0B3),
              onPressed: (controller.isRunning || controller.isStarting || controller.isStopping || controller.isRestarting) 
                ? null 
                : controller.startBackend,
            ),
            const SizedBox(height: 12),
            _ActionButton(
              label: controller.isRestarting ? 'Restarting...' : 'Restart Backend',
              icon: Icons.refresh_rounded,
              color: const Color(0xFF7CC0FF),
              onPressed: (!controller.isRunning || controller.isStarting || controller.isStopping || controller.isRestarting)
                ? null 
                : controller.restartBackend,
            ),
            const SizedBox(height: 12),
            _ActionButton(
              label: controller.isStopping ? 'Stopping...' : 'Stop Backend',
              icon: Icons.stop_circle_outlined,
              color: const Color(0xFFFF6A8C),
              onPressed: (!controller.isRunning || controller.isStarting || controller.isStopping || controller.isRestarting)
                ? null 
                : controller.stopBackend,
            ),
            const SizedBox(height: 12),
            _ActionButton(
              label: 'Open Logs',
              icon: Icons.receipt_long,
              color: const Color(0xFF7CC0FF),
              onPressed: () => Navigator.of(context).push(_buildRoute(const LogsScreen())),
            ),
            const SizedBox(height: 16),
            Text('Live Logs', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: ListView.builder(
                  controller: _logsController,
                  itemCount: controller.recentLogs.length,
                  itemBuilder: (context, index) {
                    final log = controller.recentLogs[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SelectableText(
                        log,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _onSurface(context, 0.7)),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Welcome to ATLAS Backend! - @cipherfps',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _onSurface(context, 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.icon, required this.color, this.onPressed});

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEnabled = onPressed != null;
    final fgColor = isDark ? color : _darken(color, 0.38);
    return _HoverScale(
      enabled: isEnabled,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isEnabled ? color.withOpacity(isDark ? 0.28 : 0.35) : _onSurface(context, isDark ? 0.14 : 0.06),
          foregroundColor: isEnabled ? fgColor : _onSurface(context, 0.35),
          disabledBackgroundColor: _onSurface(context, isDark ? 0.14 : 0.06),
          disabledForegroundColor: _onSurface(context, 0.35),
          elevation: isDark ? 0 : 1.5,
          shadowColor: color.withOpacity(isDark ? 0.0 : 0.35),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isEnabled
                  ? fgColor.withOpacity(isDark ? 0.4 : 0.55)
                  : _onSurface(context, isDark ? 0.18 : 0.12),
            ),
          ),
        ),
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: _onSurface(context, 0.7))),
        const Spacer(),
        Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class FeatureScreen extends StatelessWidget {
  const FeatureScreen({super.key, required this.data});

  final MenuItemData data;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AtlasBackground(),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _HoverScale(
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: data.accent.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(data.icon, color: data.accent),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data.title, style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 4),
                        Text(data.subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: _onSurface(context, 0.7))),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Actions', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 16),
                          Expanded(
                            child: ListView.separated(
                              itemCount: data.actions.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final action = data.actions[index];
                                return ListTile(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  tileColor: Colors.white10,
                                  leading: Icon(Icons.chevron_right_rounded, color: data.accent),
                                  title: Text(action.title),
                                  subtitle: Text(action.description),
                                  trailing: _HoverScale(
                                    child: ElevatedButton(
                                      onPressed: () {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('${action.title} (coming soon)')),
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: data.accent.withOpacity(0.15),
                                        foregroundColor: data.accent,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      child: const Text('Open'),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.5),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _onSurface(context, 0.08)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class AtlasBackground extends StatelessWidget {
  const AtlasBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final imagePath = joinPath([
      getBackendRoot(),
      'public',
      'images',
      'hey-fortnite-flat-earthers-explain-these-images-of-things-v0-0c9emy18f0t81.webp',
    ]);
    final imageFile = File(imagePath);
    return Stack(
      children: [
        AnimatedBuilder(
          animation: Listenable.merge([appBackgroundPath, appBackgroundBlur]),
          builder: (context, _) {
            final path = appBackgroundPath.value;
            final blurSigma = appBackgroundBlur.value;
            File? customBackground;
            final resolvedPath = _resolveBackgroundPath(path);
            if (resolvedPath != null) {
              customBackground = File(resolvedPath);
            }
            if (customBackground != null) {
              return Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                  child: Image.file(
                    customBackground,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
                ),
              );
            }
            if (imageFile.existsSync()) {
              return Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                  child: Image.file(
                    imageFile,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
                ),
              );
            }
            return Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0A0E14), Color(0xFF0F1726)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            );
          },
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [Colors.black.withOpacity(0.65), Colors.black.withOpacity(0.35)]
                  : [Colors.white.withOpacity(0.55), Colors.white.withOpacity(0.2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ],
    );
  }
}

class _HoverScale extends StatefulWidget {
  const _HoverScale({
    required this.child,
    this.enabled = true,
    this.scale = 1.03,
    this.duration = const Duration(milliseconds: 140),
  });

  final Widget child;
  final bool enabled;
  final double scale;
  final Duration duration;

  @override
  State<_HoverScale> createState() => _HoverScaleState();
}

class _HoverRegion extends StatefulWidget {
  const _HoverRegion({required this.builder});

  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_HoverRegion> createState() => _HoverRegionState();
}

class _HoverRegionState extends State<_HoverRegion> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(context, _hovered),
    );
  }
}

class _ImageDropShadow extends StatelessWidget {
  const _ImageDropShadow({
    required this.child,
    this.opacity = 0.75,
    this.blurSigma = 2.5,
    this.offset = const Offset(0, 2),
  });

  final Widget child;
  final double opacity;
  final double blurSigma;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.translate(
          offset: offset,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(Colors.black.withOpacity(opacity), BlendMode.srcIn),
              child: child,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _HoverShadow extends StatefulWidget {
  const _HoverShadow({
    required this.child,
    this.opacity = 0.75,
    this.blurSigma = 2.5,
    this.baseOffset = const Offset(0, 2),
    this.hoverOffset = const Offset(4, 2),
    this.duration = const Duration(milliseconds: 200),
    this.hovered,
  });

  final Widget child;
  final double opacity;
  final double blurSigma;
  final Offset baseOffset;
  final Offset hoverOffset;
  final Duration duration;
  final bool? hovered;

  @override
  State<_HoverShadow> createState() => _HoverShadowState();
}

class _HoverShadowState extends State<_HoverShadow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final effectiveHovered = widget.hovered ?? _hovered;
    final content = TweenAnimationBuilder<Offset>(
      tween: Tween<Offset>(
        begin: widget.baseOffset,
        end: effectiveHovered ? widget.hoverOffset : widget.baseOffset,
      ),
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      builder: (context, offset, child) {
        return _ImageDropShadow(
          opacity: widget.opacity,
          blurSigma: widget.blurSigma,
          offset: offset,
          child: child!,
        );
      },
      child: widget.child,
    );
    if (widget.hovered != null) {
      return content;
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: content,
    );
  }
}

class _HoverScaleState extends State<_HoverScale> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? widget.scale : 1,
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

Color _onSurface(BuildContext context, double opacity) {
  return Theme.of(context).colorScheme.onSurface.withOpacity(opacity);
}

Future<void> _applyAcrylicForBackground(String path) async {
  if (!Platform.isWindows) return;
  final color = await _computeAcrylicTint(path);
  await Window.setEffect(
    effect: WindowEffect.acrylic,
    color: color,
  );
}

Future<Color> _computeAcrylicTint(String path) async {
  final resolved = _resolveBackgroundPath(path);
  final fallbackPath = joinPath([
    getBackendRoot(),
    'public',
    'images',
    'hey-fortnite-flat-earthers-explain-these-images-of-things-v0-0c9emy18f0t81.webp',
  ]);
  final candidatePath = resolved ?? fallbackPath;
  try {
    final file = File(candidatePath);
    if (!await file.exists()) return _fallbackAcrylicColor;
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return _fallbackAcrylicColor;
    final width = decoded.width;
    final height = decoded.height;
    if (width == 0 || height == 0) return _fallbackAcrylicColor;
    final stepX = max(1, (width / 60).floor());
    final stepY = max(1, (height / 60).floor());
    var r = 0;
    var g = 0;
    var b = 0;
    var count = 0;
    for (var y = 0; y < height; y += stepY) {
      for (var x = 0; x < width; x += stepX) {
        final pixel = decoded.getPixel(x, y);
        final a = pixel.a;
        if (a < 20) continue;
        r += pixel.r.toInt();
        g += pixel.g.toInt();
        b += pixel.b.toInt();
        count++;
      }
    }
    if (count == 0) return _fallbackAcrylicColor;
    final avg = Color.fromARGB(255, r ~/ count, g ~/ count, b ~/ count);
    final base = const Color(0xFF0A0E14);
    final mixed = _mixColors(base, avg, 0.55);
    return mixed.withAlpha(_fallbackAcrylicColor.alpha);
  } catch (_) {
    return _fallbackAcrylicColor;
  }
}

Color _mixColors(Color a, Color b, double t) {
  final clamped = t.clamp(0.0, 1.0);
  final r = (a.red + (b.red - a.red) * clamped).round();
  final g = (a.green + (b.green - a.green) * clamped).round();
  final bVal = (a.blue + (b.blue - a.blue) * clamped).round();
  return Color.fromARGB(255, r, g, bVal);
}

Color _menuShadowColor(BuildContext context, Color accent) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return accent.withOpacity(isDark ? 0.25 : 0.18);
}

Color _darken(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  final lightness = (hsl.lightness - amount).clamp(0.0, 1.0);
  return hsl.withLightness(lightness).toColor();
}

Future<void> _showAboutDialog(BuildContext context) async {
  const url = 'https://guns.lol/cipherfps';
  const supportUrl = 'https://discord.gg/G9MAF77V7R';
  const githubUrl = 'https://github.com/cipherfps/ATLAS-Backend';
  await _showBlurDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('About'),
      content: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: 'Made by ',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: 'cipher\n',
              style: TextStyle(
                color: Theme.of(context).colorScheme.secondary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  _openUrl(url);
                },
            ),
            const TextSpan(text: 'GitHub: '),
            TextSpan(
              text: _stripScheme(githubUrl),
              style: TextStyle(
                color: Theme.of(context).colorScheme.secondary,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  _openUrl(githubUrl);
                },
            ),
            const TextSpan(text: '\n'),
            const TextSpan(text: 'Support: '),
            TextSpan(
              text: _stripScheme(supportUrl),
              style: TextStyle(
                color: Theme.of(context).colorScheme.secondary,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  _openUrl(supportUrl);
                },
            ),
          ],
        ),
      ),
      actions: [
        _HoverScale(
          child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ),
      ],
    ),
  );
}

Future<void> _openUrl(String url) async {
  try {
    if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [url]);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [url]);
    }
  } catch (_) {}
}

PageRouteBuilder<void> _buildRoute(Widget page) {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(opacity: curve, child: child);
    },
  );
}

class MenuItemData {
  const MenuItemData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.actions,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<MenuAction> actions;
  final bool enabled;
}

class MenuAction {
  const MenuAction({required this.title, required this.description});

  final String title;
  final String description;
}

Widget _pageForMenu(String title) {
  switch (title) {
    case 'Modifications':
      return const ModificationsScreen();
    case 'CurveTables':
      return const CurveTablesScreen();
    case 'Arena':
      return const ArenaScreen();
    case 'Game Configuration':
      return const GameConfigurationScreen();
    case 'Profiles':
      return const ProfilesScreen();
    case 'Logs':
      return const LogsScreen();
    default:
      return FeatureScreen(
        data: MenuItemData(
          title: title,
          subtitle: 'Coming soon',
          icon: Icons.dashboard_customize,
          accent: const Color(0xFF6BE7FF),
          actions: const [MenuAction(title: 'Coming soon', description: 'This menu is being built.')],
        ),
      );
  }
}

class ModificationsScreen extends StatefulWidget {
  const ModificationsScreen({super.key});

  @override
  State<ModificationsScreen> createState() => _ModificationsScreenState();
}

class _ModificationsScreenState extends State<ModificationsScreen> {
  bool _isLoading = true;
  bool _straightBloom = false;
  bool _curveTablesEnabled = true;
  bool _curveLoading = true;
  List<CurveEntry> _curves = [];
  String _selectedGroupId = 'shockwave';
  final Map<String, TextEditingController> _valueControllers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _valueControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final bloom = await StraightBloomService.isEnabled();
    final curvesEnabled = await CurveTableService.areGlobalEnabled();
    final curves = await CurveTableService.loadCurves();
    if (!mounted) return;
    setState(() {
      _straightBloom = bloom;
      _curveTablesEnabled = curvesEnabled;
      _curves = curves;
      _isLoading = false;
      _curveLoading = false;
    });
  }

  Future<void> _toggleStraightBloom(bool value) async {
    await StraightBloomService.setEnabled(value);
    if (!mounted) return;
    setState(() => _straightBloom = value);
  }

  Future<void> _toggleCurveTables() async {
    await CurveTableService.toggleGlobal();
    await _load();
  }

  Future<void> _importCurvesInModifications() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import DefaultGame.ini',
      type: FileType.custom,
      allowedExtensions: ['ini'],
    );
    if (picked == null || picked.files.single.path == null) return;
    final path = picked.files.single.path!;

    final source = File(path);
    if (!await source.exists()) return;
    final importContent = await source.readAsString();
    final regex = RegExp('^\\+CurveTable=(.+?);RowUpdate;(.+?);(\\d+);(.+)\$', multiLine: true);
    final matches = regex.allMatches(importContent).toList();
    if (matches.isEmpty) return;

    final grouped = <String, List<String>>{};
    for (final match in matches) {
      final pathPart = match.group(1)!;
      final key = match.group(2)!;
      final line = match.group(0)!;
      final groupKey = '$pathPart|||$key';
      grouped.putIfAbsent(groupKey, () => []).add(line);
    }

    final existing = await CurveTableService.loadCurves();
    final existingKeys = existing
        .map((entry) => '${entry.pathPart ?? BackendPaths.defaultCurvePath}|||${entry.key}')
        .toSet();

    final missing = <_ImportCurveDraft>[];
    for (final entry in grouped.entries) {
      final parts = entry.key.split('|||');
      final pathPart = parts[0];
      final key = parts[1];
      if (!existingKeys.contains(entry.key)) {
        final parsed = _parseCurveLines(entry.value.join('\n'));
        missing.add(
          _ImportCurveDraft(
            key: key,
            pathPart: pathPart,
            lines: entry.value,
            staticValue: parsed?.staticValue ?? '0',
          ),
        );
      }
    }

    for (final entry in grouped.entries) {
      final parts = entry.key.split('|||');
      await CurveTableService.applyCurveLines(parts[0], parts[1], entry.value);
    }

    if (missing.isNotEmpty) {
      final inputs = await _promptImportMissingCurves(context, missing, _groupInfosForPrompt(_curves));
      if (inputs != null && inputs.isNotEmpty) {
        await CurveTableService.addCustomCurves(inputs);
      }
    }

    await _load();
    if (!mounted) return;
    await _showCurveImportSummary(context, grouped, missing: missing);
  }

  Future<void> _toggleCurve(CurveEntry entry, bool value) async {
    if (!_curveTablesEnabled) return;
    if (value && entry.type == 'amount' && entry.staticValue == null) {
      final controller = _valueControllers[entry.id];
      final valueText = controller?.text.trim();
      if (valueText == null || valueText.isEmpty) {
        final promptedValue = await _promptValue(context, entry.name);
        if (promptedValue == null) return;
        controller?.text = promptedValue;
        await CurveTableService.setCurveEnabled(entry, value, customValue: promptedValue);
      } else {
        await CurveTableService.setCurveEnabled(entry, value, customValue: valueText);
      }
    } else {
      await CurveTableService.setCurveEnabled(entry, value);
    }
    await _load();
  }

  Future<void> _updateCurveValue(CurveEntry entry, String newValue) async {
    if (!_curveTablesEnabled) return;
    final enabled = await CurveTableService.isCurveEnabled(entry);
    if (!enabled) return;
    await CurveTableService.setCurveEnabled(entry, true, customValue: newValue);
    await _load();
  }

  List<CurveGroup> get _groups {
    final builtinIds = _baseCurveGroups.map((group) => group.id).toSet();
    final customGroups = _customGroupsFromCurves(_curves, excludeIds: builtinIds).map((group) {
      return CurveGroup(
        id: group.id,
        title: group.name,
        imagePath: group.imagePath,
        icon: Icons.auto_awesome,
        keywords: const [],
        isCustom: true,
      );
    }).toList();

    return [..._baseCurveGroups, ...customGroups];
  }

  List<CurveEntry> _entriesForGroup(CurveGroup group, List<CurveEntry> entries) {
    final scopedEntries = group.isCustom
        ? entries.where((entry) => entry.isCustom).toList()
        : entries.where((entry) => !entry.isCustom || entry.groupId == group.id).toList();
    final groupMatches = scopedEntries.where((entry) => group.matches(entry)).toList();
    if (!group.isCustom && group.id == 'glider') {
      return groupMatches.where((entry) {
        final name = entry.name.toLowerCase();
        final key = entry.key.toLowerCase();
        return !name.contains('jules') && !key.contains('grapplinghoot');
      }).toList();
    }
    if (!group.isCustom && group.id == 'impulse') {
      return groupMatches.where((entry) {
        final name = entry.name.toLowerCase();
        final key = entry.key.toLowerCase();
        return !name.contains('cube') && !key.contains('cube');
      }).toList();
    }
    return groupMatches;
  }

  String _groupImagePath(CurveGroup group) {
    final customPath = group.imagePath;
    if (customPath != null && customPath.isNotEmpty) {
      return joinPath([getBackendRoot(), 'public', 'items', customPath]);
    }
    final imageName = group.imageName ?? '';
    return joinPath([getBackendRoot(), 'public', 'items', imageName]);
  }

  Future<void> _addCustomCurve() async {
    final inputs = await _promptCustomCurves(context, _groupInfosForPrompt(_curves));
    if (inputs == null || inputs.isEmpty) return;
    await CurveTableService.addCustomCurves(inputs);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final visibleGroups = _groups
        .where((group) => _entriesForGroup(group, _curves).isNotEmpty)
        .toList();
    final selectedGroup = visibleGroups.firstWhere(
      (group) => group.id == _selectedGroupId,
      orElse: () => visibleGroups.isNotEmpty ? visibleGroups.first : _groups.first,
    );
    return _BaseScreen(
      title: 'Modifications',
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const _SectionTitle(title: 'Straight Bloom'),
                SwitchListTile(
                  value: _straightBloom,
                  onChanged: _toggleStraightBloom,
                  title: const Text('Straight Bloom (Sniper)'),
                  subtitle: const Text('Toggle straight bloom lines in DefaultGame.ini'),
                ),
                const SizedBox(height: 20),
                const _SectionTitle(title: 'CurveTables'),
                SwitchListTile(
                  value: _curveTablesEnabled,
                  onChanged: (_) => _toggleCurveTables(),
                  title: Text(_curveTablesEnabled ? 'CurveTables Enabled' : 'CurveTables Disabled'),
                  subtitle: const Text('Toggle all CurveTable entries on/off'),
                ),
                const SizedBox(height: 8),
                if (!_curveTablesEnabled)
                  const Text('CurveTables are disabled. Enable them to edit.'),
                if (_curveTablesEnabled) ...[
                  const SizedBox(height: 12),
                  _curveLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: visibleGroups.map((group) {
                                final isSelected = selectedGroup.id == group.id;
                                final imageFile = File(_groupImagePath(group));
                                final isDark = Theme.of(context).brightness == Brightness.dark;
                                return GestureDetector(
                                  onTap: () => setState(() => _selectedGroupId = group.id),
                                  child: _HoverRegion(
                                    builder: (context, hovered) => AnimatedScale(
                                      duration: const Duration(milliseconds: 140),
                                      curve: Curves.easeOutCubic,
                                      scale: hovered ? 1.03 : 1,
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 180),
                                        width: 140,
                                        height: 110,
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(16),
                                          color: isSelected
                                              ? Theme.of(context).colorScheme.secondary.withOpacity(0.18)
                                              : Colors.black.withOpacity(0.08),
                                          border: Border.all(
                                            color: isSelected
                                                ? Theme.of(context).colorScheme.secondary.withOpacity(0.6)
                                                : _onSurface(context, 0.12),
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            if (imageFile.existsSync())
                                              _HoverShadow(
                                                opacity: 0.75,
                                                blurSigma: 2,
                                                baseOffset: const Offset(0, 2),
                                                hoverOffset: const Offset(4, 2),
                                                hovered: hovered,
                                                child: (group.id == 'fall'
                                                    ? ColorFiltered(
                                                        colorFilter: ColorFilter.mode(
                                                          isDark ? Colors.white : Colors.black,
                                                          BlendMode.srcIn,
                                                        ),
                                                        child: Image.file(
                                                          imageFile,
                                                          width: 52,
                                                          height: 52,
                                                          fit: BoxFit.contain,
                                                        ),
                                                      )
                                                    : Image.file(imageFile, width: 52, height: 52, fit: BoxFit.contain)),
                                              )
                                            else
                                              _HoverShadow(
                                                opacity: 0.75,
                                                blurSigma: 2,
                                                baseOffset: const Offset(0, 2),
                                                hoverOffset: const Offset(4, 2),
                                                hovered: hovered,
                                                child: Icon(
                                                  group.icon,
                                                  size: 38,
                                                  color: Theme.of(context).colorScheme.secondary,
                                                ),
                                              ),
                                            const SizedBox(height: 8),
                                            Text(
                                              group.title,
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context).textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Text(selectedGroup.title, style: Theme.of(context).textTheme.titleLarge),
                                const Spacer(),
                                if (selectedGroup.isCustom)
                                  _HoverScale(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final updated = await _promptEditCustomGroup(
                                          context,
                                          selectedGroup.id,
                                          selectedGroup.title,
                                        );
                                        if (updated == null) return;
                                        await CurveTableService.updateCustomGroup(
                                          selectedGroup.id,
                                          updated.name,
                                          updated.imagePath,
                                        );
                                        await _load();
                                      },
                                      icon: const Icon(Icons.edit_outlined),
                                      label: const Text('Edit Group'),
                                    ),
                                  ),
                                if (selectedGroup.isCustom) const SizedBox(width: 8),
                                if (selectedGroup.isCustom)
                                  _HoverScale(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final confirm = await DataService._confirmDialog(
                                          context,
                                          'Delete group "${selectedGroup.title}" and all its custom curves?',
                                        );
                                        if (!confirm) return;
                                        await CurveTableService.deleteCustomGroup(selectedGroup.id);
                                        await _load();
                                      },
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                      label: const Text('Delete Group'),
                                      style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                                    ),
                                  ),
                                if (selectedGroup.isCustom) const SizedBox(width: 8),
                                _HoverScale(
                                  enabled: _curveTablesEnabled,
                                  child: OutlinedButton.icon(
                                    onPressed: _addCustomCurve,
                                    icon: const Icon(Icons.add_circle_outline),
                                    label: const Text('Add Custom Curve'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF1E88E5),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _HoverScale(
                                  enabled: _curveTablesEnabled,
                                  child: OutlinedButton.icon(
                                    onPressed: _importCurvesInModifications,
                                    icon: const Icon(Icons.file_upload_outlined),
                                    label: const Text('Import INI'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF1E88E5),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _HoverScale(
                                  enabled: _curveTablesEnabled,
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final confirm = await DataService._confirmDialog(
                                        context,
                                        'Clear all CurveTables from DefaultGame.ini?',
                                      );
                                      if (!confirm) return;
                                      await CurveTableService.clearAllCurveTables();
                                      await _load();
                                    },
                                    icon: const Icon(Icons.delete_sweep_outlined),
                                    label: const Text('Clear All CurveTables'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF1E88E5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ..._entriesForGroup(
                              selectedGroup,
                              _curves,
                            ).map((entry) {
                              final controller = _valueControllers.putIfAbsent(entry.id, () => TextEditingController());
                              return _CurveEntryTile(
                                entry: entry,
                                enabled: _curveTablesEnabled,
                                valueController: controller,
                                onToggle: (value) => _toggleCurve(entry, value),
                                onSubmit: (value) => _updateCurveValue(entry, value),
                                onEdit: entry.isCustom
                                    ? () async {
                                        final updated = await _promptEditCustomCurve(context, entry, _groupInfosForPrompt(_curves));
                                        if (updated == null) return;
                                        await CurveTableService.updateCustomCurve(entry.id, updated);
                                        await _load();
                                      }
                                    : null,
                                onDelete: entry.isCustom
                                    ? () async {
                                        final confirm = await DataService._confirmDialog(
                                          context,
                                          'Delete custom curve "${entry.name}"?',
                                        );
                                        if (!confirm) return;
                                        await CurveTableService.deleteCustomCurve(entry.id);
                                        await _load();
                                      }
                                    : null,
                              );
                            }).toList(),
                          ],
                        ),
                ],
              ],
            ),
    );
  }
}

class CurveTablesScreen extends StatefulWidget {
  const CurveTablesScreen({super.key});

  @override
  State<CurveTablesScreen> createState() => _CurveTablesScreenState();
}

class _CurveTablesScreenState extends State<CurveTablesScreen> {
  bool _loading = true;
  bool _globalEnabled = true;
  List<CurveEntry> _curves = [];
  String _search = '';
  final Map<String, TextEditingController> _valueControllers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _valueControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final curves = await CurveTableService.loadCurves();
    final enabled = await CurveTableService.areGlobalEnabled();
    if (!mounted) return;
    setState(() {
      _curves = curves;
      _globalEnabled = enabled;
      _loading = false;
    });
  }

  Future<void> _toggleCurve(CurveEntry entry, bool value) async {
    if (!_globalEnabled) return;
    if (value && entry.type == 'amount' && entry.staticValue == null) {
      final controller = _valueControllers[entry.id];
      final valueText = controller?.text.trim();
      if (valueText == null || valueText.isEmpty) {
        final promptedValue = await _promptValue(context, entry.name);
        if (promptedValue == null) return;
        controller?.text = promptedValue;
        await CurveTableService.setCurveEnabled(entry, value, customValue: promptedValue);
      } else {
        await CurveTableService.setCurveEnabled(entry, value, customValue: valueText);
      }
    } else {
      await CurveTableService.setCurveEnabled(entry, value);
    }
    await _load();
  }

  Future<void> _updateCurveValue(CurveEntry entry, String newValue) async {
    if (!_globalEnabled) return;
    final enabled = await CurveTableService.isCurveEnabled(entry);
    if (!enabled) return;
    await CurveTableService.setCurveEnabled(entry, true, customValue: newValue);
    await _load();
  }

  Future<void> _addCustomCurve() async {
    final inputs = await _promptCustomCurves(context, _groupInfosForPrompt(_curves));
    if (inputs == null || inputs.isEmpty) return;
    await CurveTableService.addCustomCurves(inputs);
    await _load();
  }

  Future<void> _importCurves() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import DefaultGame.ini',
      type: FileType.custom,
      allowedExtensions: ['ini'],
    );
    if (picked == null || picked.files.single.path == null) return;
    await CurveTableService.importFromIni(picked.files.single.path!);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _curves.where((entry) {
      if (_search.trim().isEmpty) return true;
      final query = _search.toLowerCase();
      return entry.name.toLowerCase().contains(query) || entry.key.toLowerCase().contains(query);
    }).toList();

    return _BaseScreen(
      title: 'CurveTables',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HoverScale(
            enabled: _globalEnabled,
            child: IconButton(
              tooltip: 'Import DefaultGame.ini',
              onPressed: _globalEnabled ? _importCurves : null,
              icon: const Icon(Icons.file_upload),
            ),
          ),
          _HoverScale(
            enabled: _globalEnabled,
            child: OutlinedButton.icon(
              onPressed: _globalEnabled ? _addCustomCurve : null,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Add Custom Curve'),
            ),
          ),
        ],
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  onChanged: (value) => setState(() => _search = value),
                  decoration: const InputDecoration(
                    labelText: 'Search CurveTables',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                if (!_globalEnabled)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('CurveTables are disabled. Enable them in Modifications to edit.'),
                  ),
                Expanded(
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      _valueControllers.putIfAbsent(entry.id, () => TextEditingController());
                      return FutureBuilder<Map<String, dynamic>>(
                        future: Future.wait([
                          CurveTableService.isCurveEnabled(entry),
                          CurveTableService.getCurrentValue(entry),
                        ]).then((results) => {'enabled': results[0], 'value': results[1]}),
                        builder: (context, snapshot) {
                          final enabled = snapshot.data?['enabled'] as bool? ?? false;
                          final value = snapshot.data?['value'] as String?;
                          final controller = _valueControllers[entry.id]!;
                          if (!enabled) {
                            if (controller.text.isNotEmpty) {
                              controller.text = '';
                            }
                          } else if (value != null) {
                            if (controller.text != value) {
                              controller.text = value;
                            }
                          }
                          final canEdit = entry.type == 'amount' || (entry.type == 'static' && entry.staticValue == null);
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: enabled ? const Color(0xFF6BE7FF).withOpacity(0.3) : Colors.white10,
                                width: 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.name,
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          entry.key,
                                          style: TextStyle(fontSize: 12, color: _onSurface(context, 0.75)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (enabled && canEdit && value != null) ...[
                                    const SizedBox(width: 12),
                                    Container(
                                      width: 140,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6BE7FF).withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(0xFF6BE7FF).withOpacity(0.4),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: TextField(
                                        controller: _valueControllers[entry.id],
                                        enabled: _globalEnabled,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontFamily: 'monospace',
                                          color: Color(0xFF6BE7FF),
                                          fontWeight: FontWeight.w500,
                                        ),
                                        decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          border: InputBorder.none,
                                          hintText: 'Value...',
                                          hintStyle: TextStyle(
                                            color: Color(0xFF6BE7FF),
                                            fontSize: 12,
                                          ),
                                        ),
                                        textAlign: TextAlign.center,
                                        onSubmitted: (newValue) => _updateCurveValue(entry, newValue),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 8),
                                  Switch(
                                    value: enabled,
                                    onChanged: _globalEnabled ? (value) => _toggleCurve(entry, value) : null,
                                  ),
                                  if (entry.isCustom) ...[
                                    const SizedBox(width: 8),
                                    _HoverScale(
                                      child: IconButton(
                                        tooltip: 'Edit Curve',
                                        onPressed: () async {
                                          final updated = await _promptEditCustomCurve(
                                            context,
                                            entry,
                                            _groupInfosForPrompt(_curves),
                                          );
                                          if (updated == null) return;
                                          await CurveTableService.updateCustomCurve(entry.id, updated);
                                          await _load();
                                        },
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                    ),
                                    _HoverScale(
                                      child: IconButton(
                                        tooltip: 'Delete Curve',
                                        onPressed: () async {
                                          final confirm = await DataService._confirmDialog(
                                            context,
                                            'Delete custom curve "${entry.name}"?',
                                          );
                                          if (!confirm) return;
                                          await CurveTableService.deleteCustomCurve(entry.id);
                                          await _load();
                                        },
                                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class ArenaScreen extends StatefulWidget {
  const ArenaScreen({super.key});

  @override
  State<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends State<ArenaScreen> {
  bool _loading = true;
  bool _saveArenaPoints = false;
  List<ArenaEntry> _leaderboard = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await ConfigService.load();
    final leaderboard = await ArenaService.loadLeaderboard();
    if (!mounted) return;
    setState(() {
      _saveArenaPoints = config.saveArenaPoints;
      _leaderboard = leaderboard;
      _loading = false;
    });
  }

  Future<void> _toggleSavePoints(bool value) async {
    final config = await ConfigService.load();
    await ConfigService.save(config.copyWith(saveArenaPoints: value));
    if (!mounted) return;
    setState(() => _saveArenaPoints = value);
  }

  @override
  Widget build(BuildContext context) {
    return _BaseScreen(
      title: 'Arena',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orangeAccent),
                      SizedBox(width: 8),
                      Text('Arena leaderboard is coming soon. Points saving is live.'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  value: _saveArenaPoints,
                  onChanged: _toggleSavePoints,
                  title: const Text('Save Arena Points'),
                  subtitle: const Text('Persist player hype between sessions'),
                ),
                const SizedBox(height: 16),
                const _SectionTitle(title: 'Leaderboard (Preview)'),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: _leaderboard.length,
                    itemBuilder: (context, index) {
                      final entry = _leaderboard[index];
                      return ListTile(
                        leading: Text('#${index + 1}'),
                        title: Text(entry.accountId),
                        trailing: Text('${entry.hype} hype'),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class GameConfigurationScreen extends StatefulWidget {
  const GameConfigurationScreen({super.key});

  @override
  State<GameConfigurationScreen> createState() => _GameConfigurationScreenState();
}

class _GameConfigurationScreenState extends State<GameConfigurationScreen> {
  bool _loading = true;
  int _rufusStage = 1;
  int _waterLevel = 1;
  bool _useWaterStorm = false;
  bool _saving = false;
  _GameConfigPreview _preview = _GameConfigPreview.none;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await ConfigService.load();
    if (!mounted) return;
    setState(() {
      _rufusStage = config.rufusStage;
      _waterLevel = config.waterLevel;
      _useWaterStorm = config.useWaterStorm;
      _preview = _GameConfigPreview.none;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final existing = await ConfigService.load();
    final config = ConfigSettings(
      rufusStage: _rufusStage,
      waterLevel: _waterLevel,
      saveArenaPoints: existing.saveArenaPoints,
      useWaterStorm: _useWaterStorm,
      startBackendOnLaunch: existing.startBackendOnLaunch,
      disableBackendUpdateCheck: existing.disableBackendUpdateCheck,
      useDarkMode: existing.useDarkMode,
      backgroundImagePath: existing.backgroundImagePath,
      backgroundBlur: existing.backgroundBlur,
      dialogBlurEnabled: existing.dialogBlurEnabled,
    );
    await ConfigService.save(config);
    if (!mounted) return;
    setState(() => _saving = false);
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!_saving) {
        _save();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _BaseScreen(
      title: 'Game Configuration',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final imagePath = _gameConfigImagePath();
                final controls = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitleWithTag(title: 'Rufus Week Stage', tag: 'v27.11'),
                    MouseRegion(
                      onEnter: (_) => setState(() => _preview = _GameConfigPreview.rufusStage),
                      child: Slider(
                        value: _rufusStage.toDouble(),
                        min: 1,
                        max: 4,
                        divisions: 3,
                      label: 'Stage $_rufusStage',
                      onChanged: (value) => setState(() {
                        _rufusStage = value.round();
                        _preview = _GameConfigPreview.rufusStage;
                        _scheduleSave();
                      }),
                    ),
                    ),
                    const SizedBox(height: 12),
                    const _SectionTitleWithTag(title: 'Water Level', tag: 'v13.X'),
                    MouseRegion(
                      onEnter: (_) => setState(() => _preview = _GameConfigPreview.waterLevel),
                      child: Slider(
                        value: _waterLevel.toDouble(),
                        min: 1,
                        max: 8,
                        divisions: 7,
                      label: 'Level $_waterLevel',
                      onChanged: (value) => setState(() {
                        _waterLevel = value.round();
                        _preview = _GameConfigPreview.waterLevel;
                        _scheduleSave();
                      }),
                    ),
                    ),
                    const SizedBox(height: 12),
                    MouseRegion(
                      onEnter: (_) => setState(() => _preview = _GameConfigPreview.waterStorm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SectionTitleWithTag(title: 'Water Storm', tag: 'v12.61'),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _useWaterStorm,
                            onChanged: (value) => setState(() {
                              _useWaterStorm = value;
                              _preview = _GameConfigPreview.waterStorm;
                              _scheduleSave();
                            }),
                            title: const Text('Toggle the water storm in Chapter 2 Season 2'),
                            subtitle: const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final isDefault = _preview == _GameConfigPreview.none;
                final preview = _GameConfigPreviewImage(
                  imagePath: imagePath,
                  switchKey: '${_preview.name}::$imagePath',
                  isDefault: isDefault,
                );
                final isWide = constraints.maxWidth >= 920;
                if (!isWide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      preview,
                      const SizedBox(height: 16),
                      controls,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: controls),
                    const SizedBox(width: 28),
                    Expanded(child: preview),
                  ],
                );
              },
            ),
    );
  }

  String _gameConfigImagePath() {
    final base = joinPath([getBackendRoot(), 'public', 'gameconfig']);
    switch (_preview) {
      case _GameConfigPreview.rufusStage:
        if (_rufusStage == 4) {
          final week4 = joinPath([base, 'week4.webp']);
          return File(week4).existsSync() ? week4 : joinPath([base, 'stage4.webp']);
        }
        return joinPath([base, 'stage$_rufusStage.webp']);
      case _GameConfigPreview.waterLevel:
        return joinPath([base, 'waterlevel$_waterLevel.webp']);
      case _GameConfigPreview.waterStorm:
        return joinPath([base, 'waterstorm.webp']);
      case _GameConfigPreview.none:
      default:
        return joinPath([base, 'default.webp']);
    }
  }
}

enum _GameConfigPreview { none, rufusStage, waterLevel, waterStorm }

class _GameConfigPreviewImage extends StatelessWidget {
  const _GameConfigPreviewImage({
    required this.imagePath,
    required this.switchKey,
    required this.isDefault,
  });

  final String imagePath;
  final String switchKey;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 520),
              reverseDuration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInOutCubic,
              layoutBuilder: (currentChild, previousChildren) {
                final currentKey = currentChild?.key;
                final filteredPrevious = previousChildren.where((child) => child.key != currentKey).toList();
                return SizedBox.expand(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ...filteredPrevious,
                      if (currentChild != null) currentChild,
                    ],
                  ),
                );
              },
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: child,
              ),
              child: isDefault
                  ? ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
                      child: Image.file(
                        File(imagePath),
                        key: ValueKey(switchKey),
                        fit: BoxFit.cover,
                      ),
                    )
                  : Image.file(
                      File(imagePath),
                      key: ValueKey(switchKey),
                      fit: BoxFit.cover,
                    ),
            ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: _onSurface(context, isDark ? 0.2 : 0.1)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({super.key});

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class CurveGroup {
  const CurveGroup({
    required this.id,
    required this.title,
    required this.icon,
    required this.keywords,
    this.imageName,
    this.imagePath,
    this.isCustom = false,
  });

  final String id;
  final String title;
  final IconData icon;
  final List<String> keywords;
  final String? imageName;
  final String? imagePath;
  final bool isCustom;

  bool matches(CurveEntry entry) {
    if (isCustom || (entry.isCustom && entry.groupId == id)) {
      return entry.groupId == id;
    }
    final name = entry.name.toLowerCase();
    final key = entry.key.toLowerCase();
    return keywords.any((keyword) => name.contains(keyword) || key.contains(keyword));
  }
}

class _CurveEntryTile extends StatelessWidget {
  const _CurveEntryTile({
    required this.entry,
    required this.enabled,
    required this.valueController,
    required this.onToggle,
    required this.onSubmit,
    this.onEdit,
    this.onDelete,
  });

  final CurveEntry entry;
  final bool enabled;
  final TextEditingController valueController;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onSubmit;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final canEdit = entry.type == 'amount' || (entry.type == 'static' && entry.staticValue == null);
    return FutureBuilder<Map<String, dynamic>>(
      future: Future.wait([
        CurveTableService.isCurveEnabled(entry),
        CurveTableService.getCurrentValue(entry),
      ]).then((results) => {'enabled': results[0], 'value': results[1]}),
      builder: (context, snapshot) {
        final isEnabled = snapshot.data?['enabled'] as bool? ?? false;
        final value = snapshot.data?['value'] as String?;
        if (!isEnabled) {
          if (valueController.text.isNotEmpty) {
            valueController.text = '';
          }
        } else if (value != null) {
          if (valueController.text != value) {
            valueController.text = value;
          }
        }
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isEnabled ? const Color(0xFF6BE7FF).withOpacity(0.3) : _onSurface(context, 0.12),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.key,
                        style: TextStyle(fontSize: 12, color: _onSurface(context, 0.75)),
                      ),
                    ],
                  ),
                ),
                if (isEnabled && canEdit) ...[
                  const SizedBox(width: 12),
                  Container(
                    width: 140,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6BE7FF).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF6BE7FF).withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: TextField(
                      controller: valueController,
                      enabled: enabled,
                      style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        color: Color(0xFF6BE7FF),
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: InputBorder.none,
                        hintText: 'Value...',
                        hintStyle: TextStyle(
                          color: Color(0xFF6BE7FF),
                          fontSize: 12,
                        ),
                      ),
                      textAlign: TextAlign.center,
                      onSubmitted: onSubmit,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Switch(
                  value: isEnabled,
                  onChanged: enabled ? onToggle : null,
                ),
                if (entry.isCustom) ...[
                  const SizedBox(width: 8),
                  _HoverScale(
                    child: IconButton(
                      tooltip: 'Edit Curve',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
                  _HoverScale(
                    child: IconButton(
                      tooltip: 'Delete Curve',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  @override
  Widget build(BuildContext context) {
    return _BaseScreen(
      title: 'Data Management',
      child: const DataManagementPanel(),
    );
  }
}

class DataManagementPanel extends StatefulWidget {
  const DataManagementPanel({super.key});

  @override
  State<DataManagementPanel> createState() => _DataManagementPanelState();
}

class _DataManagementPanelState extends State<DataManagementPanel> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    await action();
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _openBackendFolder() async {
    final backendRoot = getBackendRoot();
    if (!Directory(backendRoot).existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backend folder not found.')),
      );
      return;
    }
    try {
      await Process.start('explorer', [backendRoot], runInShell: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open backend folder.')),
      );
    }
  }

  Future<void> _openExportsFolder() async {
    final exportsPath = joinPath([getBackendRoot(), 'exports']);
    if (!Directory(exportsPath).existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exports folder not found.')),
      );
      return;
    }
    try {
      await Process.start('explorer', [exportsPath], runInShell: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open exports folder.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Files'),
        ListTile(
          title: const Text('View Internal Files'),
          subtitle: const Text('Open the backend folder on disk'),
          trailing: _HoverScale(
            enabled: !_busy,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _openBackendFolder,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open'),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          title: const Text('Open Exports Folder'),
          subtitle: const Text('View exported data on disk'),
          trailing: _HoverScale(
            enabled: !_busy,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _openExportsFolder,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _SectionTitle(title: 'Export & Import'),
        ListTile(
          title: const Text('Export Backend Settings'),
          subtitle: const Text('Write DefaultGame.ini, profiles, client settings to exports/'),
          trailing: _HoverScale(
            enabled: !_busy,
            child: ElevatedButton(
              onPressed: _busy ? null : () => _run(() => DataService.exportData(context)),
              child: const Text('Export'),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          title: const Text('Import Backend Settings'),
          subtitle: const Text('Load data from exports/ into the backend'),
          trailing: _HoverScale(
            enabled: !_busy,
            child: ElevatedButton(
              onPressed: _busy ? null : () => _run(() => DataService.importData(context)),
              child: const Text('Import'),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          title: const Text('Clear Exported Data'),
          subtitle: const Text('Remove DefaultGame, profiles, and client settings from exports/'),
          trailing: _HoverScale(
            enabled: !_busy,
            child: ElevatedButton(
              onPressed: _busy ? null : () => _run(() => DataService.clearExportedData(context)),
              child: const Text('Clear'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _SectionTitle(title: 'Reset'),
        ListTile(
          title: const Text('Clear Backend Data'),
          subtitle: const Text('Reset profiles, client settings, CurveTables, and straight bloom'),
          trailing: _HoverScale(
            enabled: !_busy,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: _busy ? null : () => _run(() => DataService.clearBackendData(context)),
              child: const Text('Clear'),
            ),
          ),
        ),
      ],
    );
  }
}

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  bool _loading = true;
  List<ProfileSummary> _profiles = [];
  List<ProfilePreset> _presets = [];
  String? _selectedProfile;
  String? _selectedPreset;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profiles = await ProfileService.listProfiles();
      final presets = await ProfileService.listPresets();
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _presets = presets;
        _selectedProfile = profiles.isNotEmpty ? profiles.first.accountId : null;
        _selectedPreset = presets.isNotEmpty ? presets.first.folder : null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load profiles: $error')),
      );
    }
  }

  Future<void> _applyPreset() async {
    final profileId = _selectedProfile;
    final presetFolder = _selectedPreset;
    if (profileId == null || presetFolder == null) return;
    ProfilePreset? preset;
    for (final entry in _presets) {
      if (entry.folder == presetFolder) {
        preset = entry;
        break;
      }
    }
    if (preset == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected preset no longer exists. Refresh and try again.')),
      );
      return;
    }
    final confirm = await DataService._confirmDialog(
      context,
      'Replace profile_athena.json for "$profileId" with preset "${preset.displayName}"?',
    );
    if (!confirm) return;
    try {
      await ProfileService.applyPreset(profileId, presetFolder);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Applied "${preset.displayName}" to $profileId')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to apply preset: $error')),
      );
    }
  }

  Future<void> _applyPresetToAll() async {
    final presetFolder = _selectedPreset;
    if (presetFolder == null) return;
    ProfilePreset? preset;
    for (final entry in _presets) {
      if (entry.folder == presetFolder) {
        preset = entry;
        break;
      }
    }
    if (preset == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected preset no longer exists. Refresh and try again.')),
      );
      return;
    }
    final confirm = await DataService._confirmDialog(
      context,
      'Replace profile_athena.json for all profiles with preset "${preset.displayName}"?',
    );
    if (!confirm) return;
    try {
      final applied = await ProfileService.applyPresetToAll(presetFolder);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Applied "${preset.displayName}" to $applied profile(s).')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to apply preset to all profiles: $error')),
      );
    }
  }

  Future<void> _deleteProfile() async {
    final profileId = _selectedProfile;
    if (profileId == null) return;
    final confirm = await DataService._confirmDialog(
      context,
      'Delete profile "$profileId"? This removes profile data and ClientSettings for this user.',
    );
    if (!confirm) return;
    try {
      await ProfileService.deleteProfile(profileId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted profile "$profileId".')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete profile: $error')),
      );
    }
  }

  Future<void> _deleteAllProfiles() async {
    final confirm = await DataService._confirmDialog(
      context,
      'Delete ALL profiles? This removes all profile folders and ClientSettings for every user.',
    );
    if (!confirm) return;
    try {
      await ProfileService.deleteAllProfiles();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deleted all profiles.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete all profiles: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final presetItems = {
      for (final preset in _presets) preset.folder: preset,
    }.values.toList();
    final profileItems = {
      for (final profile in _profiles) profile.accountId: profile,
    }.values.toList();
    final presetValue = presetItems.any((p) => p.folder == _selectedPreset) ? _selectedPreset : null;
    final profileValue = profileItems.any((p) => p.accountId == _selectedProfile) ? _selectedProfile : null;
    return _BaseScreen(
      title: 'Profiles',
      trailing: _HoverScale(
        enabled: !_loading,
        child: IconButton(
          tooltip: 'Refresh profiles',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(title: 'Profiles (${_profiles.length})'),
                const SizedBox(height: 12),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: _profiles.isEmpty
                              ? const Center(child: Text('No profiles found.'))
                              : ListView.separated(
                                  itemCount: _profiles.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
                                  itemBuilder: (context, index) {
                                    final profile = _profiles[index];
                                    final selected = profile.accountId == _selectedProfile;
                                    return ListTile(
                                      selected: selected,
                                      selectedTileColor: Colors.white10,
                                      title: Text(profile.accountId),
                                      subtitle: Text(
                                        profile.hasAthena ? 'profile_athena.json found' : 'Missing profile_athena.json',
                                        style: TextStyle(color: Theme.of(context).colorScheme.secondary),
                                      ),
                                      trailing: selected ? const Icon(Icons.check_circle, color: Colors.greenAccent) : null,
                                      onTap: () => setState(() => _selectedProfile = profile.accountId),
                                    );
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionTitle(title: 'Custom Cosmetic Presets'),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: presetValue,
                              decoration: InputDecoration(
                                labelText: 'Preset',
                                border: const OutlineInputBorder(),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Theme.of(context).colorScheme.secondary, width: 1.6),
                                ),
                              ),
                              items: presetItems
                                  .map(
                                    (preset) => DropdownMenuItem(
                                      value: preset.folder,
                                      child: _PresetLabel(
                                        name: preset.name,
                                        tag: preset.versionTag,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              selectedItemBuilder: (context) => presetItems
                                  .map(
                                    (preset) => _PresetLabel(
                                      name: preset.name,
                                      tag: preset.versionTag,
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setState(() => _selectedPreset = value),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              value: profileValue,
                              decoration: InputDecoration(
                                labelText: 'Profile',
                                border: const OutlineInputBorder(),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Theme.of(context).colorScheme.secondary, width: 1.6),
                                ),
                              ),
                              items: profileItems
                                  .map(
                                    (profile) => DropdownMenuItem(
                                      value: profile.accountId,
                                      child: Text(profile.accountId),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setState(() => _selectedProfile = value),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _HoverScale(
                                    enabled: _selectedProfile != null && _selectedPreset != null,
                                    child: ElevatedButton.icon(
                                      onPressed: (_selectedProfile != null && _selectedPreset != null) ? _applyPreset : null,
                                      icon: const Icon(Icons.auto_fix_high),
                                      label: const Text('Apply preset to profile'),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _HoverScale(
                                    enabled: _selectedPreset != null && _profiles.isNotEmpty,
                                    child: ElevatedButton.icon(
                                      onPressed: (_selectedPreset != null && _profiles.isNotEmpty)
                                          ? _applyPresetToAll
                                          : null,
                                      icon: const Icon(Icons.group_rounded),
                                      label: const Text('Apply preset to all profiles'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'This replaces profile_athena.json for the selected account.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _onSurface(context, 0.6)),
                            ),
                            const SizedBox(height: 20),
                            _HoverScale(
                              enabled: _selectedProfile != null,
                              child: OutlinedButton.icon(
                                onPressed: _selectedProfile != null ? _deleteProfile : null,
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                label: const Text('Delete profile'),
                                style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _HoverScale(
                              enabled: _profiles.isNotEmpty,
                              child: OutlinedButton.icon(
                                onPressed: _profiles.isNotEmpty ? _deleteAllProfiles : null,
                                icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                                label: const Text('Delete all profiles'),
                                style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final logStore = LogStore.instance;
    return _BaseScreen(
      title: 'Logs',
      child: AnimatedBuilder(
        animation: logStore,
        builder: (context, _) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: ListView.builder(
              itemCount: logStore.allLogs.length,
              itemBuilder: (context, index) {
                final log = logStore.allLogs[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: SelectableText(
                    log,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _onSurface(context, 0.7)),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _BaseScreen extends StatelessWidget {
  const _BaseScreen({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AtlasBackground(),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _HoverScale(
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(title, style: Theme.of(context).textTheme.headlineMedium),
                    const Spacer(),
                    if (trailing != null) trailing!,
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleLarge);
  }
}

class _SectionTitleWithTag extends StatelessWidget {
  const _SectionTitleWithTag({required this.title, required this.tag});

  final String title;
  final String tag;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accent.withOpacity(0.45)),
          ),
          child: Text(
            tag,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

class _PresetLabel extends StatelessWidget {
  const _PresetLabel({required this.name, this.tag});

  final String name;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (tag != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.18),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: accent.withOpacity(0.45)),
            ),
            child: Text(
              tag!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}

class ArenaEntry {
  const ArenaEntry({required this.accountId, required this.hype});

  final String accountId;
  final int hype;
}

class ArenaService {
  static Future<List<ArenaEntry>> loadLeaderboard() async {
    final profilesDir = Directory(joinPath([getBackendRoot(), 'static', 'profiles']));
    if (!await profilesDir.exists()) return [];
    final entries = <ArenaEntry>[];
    await for (final entity in profilesDir.list()) {
      if (entity is Directory) {
        final profilePath = File(joinPath([entity.path, 'profile_athena.json']));
        if (await profilePath.exists()) {
          try {
            final data = jsonDecode(await profilePath.readAsString()) as Map<String, dynamic>;
            final stats = (data['stats'] as Map<String, dynamic>?)?['attributes'] as Map<String, dynamic>?;
            final hype = stats?['arena_hype'] ?? 0;
            entries.add(ArenaEntry(accountId: entity.uri.pathSegments.last, hype: hype is int ? hype : int.tryParse(hype.toString()) ?? 0));
          } catch (_) {}
        }
      }
    }
    entries.sort((a, b) => b.hype.compareTo(a.hype));
    return entries.take(10).toList();
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _tabIndex = 0;
  bool _loading = true;
  bool _startBackendOnLaunch = false;
  bool _disableBackendUpdateCheck = false;
  bool _useDarkMode = true;
  String _backgroundImagePath = '';
  double _backgroundBlur = 18;
  bool _dialogBlurEnabled = true;
  late final VoidCallback _backgroundPathListener;
  late final VoidCallback _backgroundBlurListener;

  @override
  void initState() {
    super.initState();
    _load();
    _backgroundPathListener = () {
      if (!mounted) return;
      setState(() => _backgroundImagePath = appBackgroundPath.value);
    };
    _backgroundBlurListener = () {
      if (!mounted) return;
      setState(() => _backgroundBlur = appBackgroundBlur.value);
    };
    appBackgroundPath.addListener(_backgroundPathListener);
    appBackgroundBlur.addListener(_backgroundBlurListener);
  }

  @override
  void dispose() {
    appBackgroundPath.removeListener(_backgroundPathListener);
    appBackgroundBlur.removeListener(_backgroundBlurListener);
    super.dispose();
  }

  Future<void> _load() async {
    final config = await ConfigService.load();
    if (!mounted) return;
    setState(() {
      _startBackendOnLaunch = config.startBackendOnLaunch;
      _disableBackendUpdateCheck = config.disableBackendUpdateCheck;
      _useDarkMode = config.useDarkMode;
      _backgroundImagePath = config.backgroundImagePath;
      _backgroundBlur = config.backgroundBlur;
      _dialogBlurEnabled = config.dialogBlurEnabled;
      _loading = false;
    });
  }

  Future<void> _updateTheme(bool value) async {
    setState(() => _useDarkMode = value);
    appThemeMode.value = value ? ThemeMode.dark : ThemeMode.light;
    final existing = await ConfigService.load();
    await ConfigService.save(existing.copyWith(useDarkMode: value));
  }

  Future<void> _pickBackgroundImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;
    setState(() => _backgroundImagePath = path);
    appBackgroundPath.value = path;
    final existing = await ConfigService.load();
    await ConfigService.save(existing.copyWith(backgroundImagePath: path));
  }

  Future<void> _clearBackgroundImage() async {
    setState(() => _backgroundImagePath = '');
    appBackgroundPath.value = '';
    final existing = await ConfigService.load();
    await ConfigService.save(existing.copyWith(backgroundImagePath: ''));
  }

  Future<void> _updateBackgroundBlur(double value) async {
    setState(() => _backgroundBlur = value);
    appBackgroundBlur.value = value;
    final existing = await ConfigService.load();
    await ConfigService.save(existing.copyWith(backgroundBlur: value));
  }

  Future<void> _updateDialogBlur(bool value) async {
    setState(() => _dialogBlurEnabled = value);
    appDialogBlurEnabled.value = value;
    final existing = await ConfigService.load();
    await ConfigService.save(existing.copyWith(dialogBlurEnabled: value));
  }

  Future<void> _updateStartOnLaunch(bool value) async {
    setState(() => _startBackendOnLaunch = value);
    final existing = await ConfigService.load();
    await ConfigService.save(existing.copyWith(startBackendOnLaunch: value));
  }

  Future<void> _updateDisableBackendUpdateCheck(bool value) async {
    setState(() => _disableBackendUpdateCheck = value);
    final existing = await ConfigService.load();
    await ConfigService.save(existing.copyWith(disableBackendUpdateCheck: value));
  }

  String _backgroundSubtitle() {
    if (_backgroundImagePath.isEmpty) {
      return 'Default background';
    }
    final resolved = _resolveBackgroundPath(_backgroundImagePath);
    if (resolved == null) {
      return 'Missing image: $_backgroundImagePath';
    }
    return _backgroundImagePath;
  }

  @override
  Widget build(BuildContext context) {
    return _BaseScreen(
      title: 'Settings',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 220,
                  child: ListView(
                    children: [
                      _SettingsTab(
                        label: 'Appearance',
                        icon: Icons.palette_outlined,
                        selected: _tabIndex == 0,
                        onTap: () => setState(() => _tabIndex = 0),
                      ),
                      _SettingsTab(
                        label: 'Data Management',
                        icon: Icons.storage_rounded,
                        selected: _tabIndex == 1,
                        onTap: () => setState(() => _tabIndex = 1),
                      ),
                      _SettingsTab(
                        label: 'Startup',
                        icon: Icons.power_settings_new_rounded,
                        selected: _tabIndex == 2,
                        onTap: () => setState(() => _tabIndex = 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.topLeft,
                        children: [
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      );
                    },
                    child: _buildTabContent(context),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTabContent(BuildContext context) {
    final title = switch (_tabIndex) {
      0 => 'Appearance',
      1 => 'Data Management',
      2 => 'Startup',
      _ => 'Settings',
    };
    switch (_tabIndex) {
      case 0:
        return Column(
          key: const ValueKey('appearance'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(title: title),
            const SizedBox(height: 16),
            SwitchListTile(
              value: _useDarkMode,
              onChanged: _updateTheme,
              title: const Text('Dark mode'),
              subtitle: const Text('Toggle between dark and light themes.'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _dialogBlurEnabled,
              onChanged: _updateDialogBlur,
              title: const Text('Popup background blur'),
              subtitle: const Text('Blur the background behind popups.'),
            ),
            const SizedBox(height: 12),
            ListTile(
              title: const Text('Background image'),
              subtitle: Text(
                _backgroundSubtitle(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HoverScale(
                    enabled: _backgroundImagePath.isNotEmpty,
                    child: TextButton(
                      onPressed: _backgroundImagePath.isEmpty ? null : _clearBackgroundImage,
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _HoverScale(
                    child: ElevatedButton(
                      onPressed: _pickBackgroundImage,
                      child: const Text('Choose image'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text('Background blur (${_backgroundBlur.toStringAsFixed(0)})'),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, constraints) {
                const min = 0.0;
                const max = 30.0;
                const defaultBlur = 18.0;
                final trackWidth = constraints.maxWidth;
                final normalized = (defaultBlur - min) / (max - min);
                final dotX = trackWidth * normalized;
                return SizedBox(
                  height: 36,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Slider(
                        value: _backgroundBlur,
                        min: min,
                        max: max,
                        divisions: 30,
                        onChanged: _updateBackgroundBlur,
                      ),
                      Positioned(
                        left: dotX - 4,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      case 1:
        return SingleChildScrollView(
          key: const ValueKey('data'),
          primary: false,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(title: title),
              const SizedBox(height: 16),
              const DataManagementPanel(),
            ],
          ),
        );
      case 2:
        return Column(
          key: const ValueKey('startup'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(title: title),
            const SizedBox(height: 16),
            SwitchListTile(
              value: _startBackendOnLaunch,
              onChanged: _updateStartOnLaunch,
              title: const Text('Start backend on launch'),
              subtitle: const Text('Automatically start the backend when the GUI opens.'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _disableBackendUpdateCheck,
              onChanged: _updateDisableBackendUpdateCheck,
              title: const Text('Disable Update Checks'),
              subtitle: const Text('Skip update checks when launching the backend.'),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Theme.of(context).colorScheme.secondary : _onSurface(context, 0.7);
    return ListTile(
      selected: selected,
      selectedTileColor: Colors.white10,
      leading: Icon(icon, color: color),
      title: Text(label, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: color)),
      onTap: onTap,
    );
  }
}

class ProfileSummary {
  const ProfileSummary({required this.accountId, required this.hasAthena});

  final String accountId;
  final bool hasAthena;
}

class ProfilePreset {
  const ProfilePreset({required this.name, required this.folder, this.versionTag});

  final String name;
  final String folder;
  final String? versionTag;

  String get displayName => versionTag == null ? name : '$name (${versionTag!})';
}

class ProfileService {
  static const String _profileTemplateBackupDirName = '.defaults';

  static String _basename(String path) {
    final parts = path.split(Platform.pathSeparator);
    for (var i = parts.length - 1; i >= 0; i--) {
      if (parts[i].trim().isNotEmpty) return parts[i];
    }
    return path;
  }

  static Future<List<ProfileSummary>> listProfiles() async {
    final profilesDir = Directory(joinPath([getBackendRoot(), 'static', 'profiles']));
    if (!await profilesDir.exists()) return [];
    final profiles = <ProfileSummary>[];
    await for (final entity in profilesDir.list(recursive: false)) {
      if (entity is! Directory) continue;
      final accountId = _basename(entity.path);
      if (accountId.trim().isEmpty) continue;
      if (accountId == _profileTemplateBackupDirName || accountId.startsWith('.')) {
        continue;
      }
      final profilePath = File(joinPath([entity.path, 'profile_athena.json']));
      profiles.add(ProfileSummary(accountId: accountId, hasAthena: await profilePath.exists()));
    }
    profiles.sort((a, b) => a.accountId.compareTo(b.accountId));
    return profiles;
  }

  static Future<List<ProfilePreset>> listPresets() async {
    final presetsDir = Directory(joinPath([getBackendRoot(), 'static', 'athenaprofiles', 'Profile Presets']));
    if (!await presetsDir.exists()) return [];
    final presets = <ProfilePreset>[];
    await for (final entity in presetsDir.list(recursive: false)) {
      if (entity is! Directory) continue;
      final folder = _basename(entity.path);
      if (folder.trim().isEmpty) continue;
      final presetPath = File(joinPath([entity.path, 'profile_athena.json']));
      if (!await presetPath.exists()) continue;
      final labelParts = _presetLabelParts(folder);
      presets.add(ProfilePreset(name: labelParts.$1, folder: folder, versionTag: labelParts.$2));
    }
    presets.sort((a, b) => a.name.compareTo(b.name));
    return presets;
  }

  static (String, String?) _presetLabelParts(String folderName) {
    switch (folderName.trim().toLowerCase()) {
      case 'reboot x stellar profile':
        return ('Reboot X Stellar', 'v12.41');
      case 'reboot x tozo profile':
        return ('Reboot X Tozo', 'v12.41');
      case 'reboot x retrac profile':
        return ('Reboot X Retrac', 'v14.40');
      case 'latest profile':
        return ('Latest', 'v39+');
      default:
        return (folderName, null);
    }
  }

  static Future<void> applyPreset(String accountId, String presetFolder) async {
    final presetPath = File(
      joinPath([getBackendRoot(), 'static', 'athenaprofiles', 'Profile Presets', presetFolder, 'profile_athena.json']),
    );
    final profilePath = File(
      joinPath([getBackendRoot(), 'static', 'profiles', accountId, 'profile_athena.json']),
    );
    if (!await presetPath.exists()) {
      throw Exception('Preset profile not found.');
    }
    await profilePath.parent.create(recursive: true);
    await presetPath.copy(profilePath.path);
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('http://127.0.0.1:3551/atlas/clear-profile-cache'));
      await request.close();
      client.close();
    } catch (_) {}
  }

  static Future<int> applyPresetToAll(String presetFolder) async {
    final presetPath = File(
      joinPath([getBackendRoot(), 'static', 'athenaprofiles', 'Profile Presets', presetFolder, 'profile_athena.json']),
    );
    if (!await presetPath.exists()) {
      throw Exception('Preset profile not found.');
    }
    final profiles = await listProfiles();
    if (profiles.isEmpty) {
      throw Exception('No profiles found.');
    }
    var appliedCount = 0;
    for (final profile in profiles) {
      final profilePath = File(
        joinPath([getBackendRoot(), 'static', 'profiles', profile.accountId, 'profile_athena.json']),
      );
      await profilePath.parent.create(recursive: true);
      await presetPath.copy(profilePath.path);
      appliedCount += 1;
    }
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('http://127.0.0.1:3551/atlas/clear-profile-cache'));
      await request.close();
      client.close();
    } catch (_) {}
    return appliedCount;
  }

  static Future<void> deleteProfile(String accountId) async {
    final profilesDir = Directory(joinPath([getBackendRoot(), 'static', 'profiles', accountId]));
    final clientSettingsDir = Directory(joinPath([getBackendRoot(), 'static', 'ClientSettings', accountId]));
    if (await profilesDir.exists()) {
      await profilesDir.delete(recursive: true);
    }
    if (await clientSettingsDir.exists()) {
      await clientSettingsDir.delete(recursive: true);
    }
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('http://127.0.0.1:3551/atlas/clear-profile-cache'));
      await request.close();
      client.close();
    } catch (_) {}
  }

  static Future<void> deleteAllProfiles() async {
    final profilesRoot = Directory(joinPath([getBackendRoot(), 'static', 'profiles']));
    final clientSettingsRoot = Directory(joinPath([getBackendRoot(), 'static', 'ClientSettings']));
    if (await profilesRoot.exists()) {
      await for (final entity in profilesRoot.list(recursive: false)) {
        if (entity is! Directory) continue;
        final name = _basename(entity.path);
        if (name.isEmpty || name.startsWith('.')) continue;
        await entity.delete(recursive: true);
      }
    }
    if (await clientSettingsRoot.exists()) {
      await for (final entity in clientSettingsRoot.list(recursive: false)) {
        if (entity is! Directory) continue;
        final name = _basename(entity.path);
        if (name.isEmpty || name.startsWith('.')) continue;
        if (name.toLowerCase() == 'config') continue;
        await entity.delete(recursive: true);
      }
    }
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('http://127.0.0.1:3551/atlas/clear-profile-cache'));
      await request.close();
      client.close();
    } catch (_) {}
  }
}

class LogStore extends ChangeNotifier {
  LogStore._();

  static final LogStore instance = LogStore._();

  final List<String> _logs = [];

  List<String> get allLogs => List.unmodifiable(_logs);
  List<String> get recentLogs => _logs.length > 16 ? _logs.sublist(_logs.length - 16) : _logs;

  void addOrReplaceLines(List<String> lines, String Function(String) normalizer) {
    for (final line in lines) {
      final baseLine = normalizer(line);
      _logs.removeWhere((existing) => normalizer(existing) == baseLine);
      _logs.add(line);
    }
    if (_logs.length > 500) {
      _logs.removeRange(0, _logs.length - 500);
    }
    notifyListeners();
  }

  void clear() {
    if (_logs.isEmpty) return;
    _logs.clear();
    notifyListeners();
  }
}

class BackendPaths {
  static const String curveTableComment = '# CurveTables';
  static const String straightBloomComment = '# Straight Bloom';
  static const String defaultCurvePath = '/Game/Athena/Balance/DataTables/AthenaGameData';

  static String get defaultGameIni => joinPath([getBackendRoot(), 'static', 'hotfixes', 'DefaultGame.ini']);
  static String get curvesJson => joinPath([getBackendRoot(), 'responses', 'curves.json']);
  static String get modificationsBackup => joinPath([getBackendRoot(), 'responses', 'modifications-backup.json']);
  static String get sniperJson => joinPath([getBackendRoot(), 'responses', 'sniper.json']);
  static String get configIni => joinPath([getBackendRoot(), 'src', 'config', 'config.ini']);
}

class IniService {
  static ({String content, int insertPoint}) ensureAssetSection(
    String content,
    String commentLabel, {
    bool preferPrepend = false,
  }) {
    var updated = content;
    if (!updated.contains(commentLabel)) {
      final assetIndex = updated.indexOf('[AssetHotfix]');
      if (assetIndex != -1) {
        if (preferPrepend) {
          updated = '${updated.substring(0, assetIndex)}[AssetHotfix]\n$commentLabel\n${updated.substring(assetIndex)}';
        } else {
          final newlineAfter = updated.indexOf('\n', assetIndex);
          final insertAt = newlineAfter == -1 ? updated.length : newlineAfter + 1;
          updated = '${updated.substring(0, insertAt)}$commentLabel\n${updated.substring(insertAt)}';
        }
      } else {
        updated = '${updated.trimRight()}\n[AssetHotfix]\n$commentLabel\n';
      }
    }

    final commentIndex = updated.indexOf(commentLabel);
    final newlineAfterComment = updated.indexOf('\n', commentIndex);
    final insertPoint = newlineAfterComment == -1 ? updated.length : newlineAfterComment + 1;
    return (content: updated, insertPoint: insertPoint);
  }
}

class StraightBloomService {
  static Future<bool> isEnabled() async {
    final iniFile = File(BackendPaths.defaultGameIni);
    final sniperFile = File(BackendPaths.sniperJson);
    if (!await iniFile.exists() || !await sniperFile.exists()) return false;
    final content = await iniFile.readAsString();
    final lines = (jsonDecode(await sniperFile.readAsString()) as Map<String, dynamic>)['lines'] as List<dynamic>;
    return lines.any((line) => content.contains(line as String));
  }

  static Future<void> setEnabled(bool enabled) async {
    final iniFile = File(BackendPaths.defaultGameIni);
    final sniperFile = File(BackendPaths.sniperJson);
    if (!await iniFile.exists() || !await sniperFile.exists()) return;
    var content = await iniFile.readAsString();
    final lines = (jsonDecode(await sniperFile.readAsString()) as Map<String, dynamic>)['lines'] as List<dynamic>;
    final sniperLines = lines.cast<String>();
    if (!enabled) {
      for (final line in sniperLines) {
        content = content.replaceAll('$line\n', '').replaceAll(line, '');
      }
      content = content.replaceAll(RegExp('\n\n+'), '\n');
    } else {
      final ensured = IniService.ensureAssetSection(content, BackendPaths.straightBloomComment);
      content = ensured.content;
      final insertPoint = ensured.insertPoint;
      content = content.substring(0, insertPoint) + sniperLines.join('\n') + '\n' + content.substring(insertPoint);
    }
    await iniFile.writeAsString(content);
  }

  static Future<void> importFromIni(String importPath) async {
    final source = File(importPath);
    final sniperFile = File(BackendPaths.sniperJson);
    if (!await source.exists() || !await sniperFile.exists()) return;
    final importContent = await source.readAsString();
    final block = _extractLastHotfixBlock(importContent);
    if (block.trim().isEmpty) return;
    final blockLines = block
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => line.startsWith(';') ? line.substring(1) : line)
        .toSet();
    final lines = (jsonDecode(await sniperFile.readAsString()) as Map<String, dynamic>)['lines'] as List<dynamic>;
    final sniperLines = lines.cast<String>();
    final hasAll = sniperLines.every((line) => blockLines.contains(line));
    await setEnabled(hasAll);
  }
}

class CurveEntry {
  const CurveEntry({
    required this.id,
    required this.name,
    required this.key,
    required this.type,
    required this.pathPart,
    required this.staticValue,
    required this.isCustom,
    required this.multiLines,
    this.groupId,
    this.groupName,
    this.groupImagePath,
  });

  final String id;
  final String name;
  final String key;
  final String type;
  final String? pathPart;
  final String? staticValue;
  final bool isCustom;
  final List<String> multiLines;
  final String? groupId;
  final String? groupName;
  final String? groupImagePath;
}

class CustomCurveInput {
  const CustomCurveInput({
    required this.name,
    required this.key,
    required this.pathPart,
    required this.lines,
    required this.staticValue,
    required this.isStatic,
    required this.groupId,
    required this.groupName,
    required this.groupImagePath,
    required this.groupImageSourcePath,
  });

  final String name;
  final String key;
  final String pathPart;
  final List<String> lines;
  final String staticValue;
  final bool isStatic;
  final String groupId;
  final String groupName;
  final String groupImagePath;
  final String groupImageSourcePath;
}

class CustomCurveGroupInfo {
  const CustomCurveGroupInfo({
    required this.id,
    required this.name,
    required this.imagePath,
  });

  final String id;
  final String name;
  final String? imagePath;
}

const List<CurveGroup> _baseCurveGroups = [
  CurveGroup(
    id: 'shockwave',
    title: 'Shockwave',
    imageName: 'shock.webp',
    icon: Icons.waves,
    keywords: ['shockwave'],
  ),
  CurveGroup(
    id: 'bouncer',
    title: 'Bouncer',
    imageName: 'bouncer.webp',
    icon: Icons.unfold_more_double,
    keywords: ['bouncer', 'bouncepad', 'bounce pad'],
  ),
  CurveGroup(
    id: 'flint',
    title: 'Flint-Knock',
    imageName: 'flintknock.webp',
    icon: Icons.local_fire_department,
    keywords: ['flint', 'flintlock'],
  ),
  CurveGroup(
    id: 'glider',
    title: 'Glider Redeploy',
    imageName: 'glider.webp',
    icon: Icons.paragliding_rounded,
    keywords: ['glider', 'redeploy', 'parachute'],
  ),
  CurveGroup(
    id: 'jules',
    title: 'Jules',
    imageName: 'jules.webp',
    icon: Icons.person,
    keywords: ['jules', 'grappler', 'grapplinghoot'],
  ),
  CurveGroup(
    id: 'impulse',
    title: 'Impulse',
    imageName: 'impulse.webp',
    icon: Icons.bolt,
    keywords: ['impulse', 'knockgrenade'],
  ),
  CurveGroup(
    id: 'chiller',
    title: 'Chiller',
    imageName: 'chiller.webp',
    icon: Icons.ac_unit,
    keywords: ['chiller', 'icegrenade'],
  ),
  CurveGroup(
    id: 'launchpad',
    title: 'Launch Pad',
    imageName: 'launch.webp',
    icon: Icons.flight_takeoff,
    keywords: ['launch pad', 'launchpad'],
  ),
  CurveGroup(
    id: 'crashpad',
    title: 'Crash Pad',
    imageName: 'crashpad.webp',
    icon: Icons.airline_seat_legroom_extra,
    keywords: ['crash pad', 'applesun', 'crashpad'],
  ),
  CurveGroup(
    id: 'dub',
    title: 'Dub',
    imageName: 'dub.webp',
    icon: Icons.gavel,
    keywords: ['dub'],
  ),
  CurveGroup(
    id: 'cube',
    title: 'Cube',
    imageName: 'cube.webp',
    icon: Icons.crop_square,
    keywords: ['cube'],
  ),
  CurveGroup(
    id: 'rift',
    title: 'Rift',
    imageName: 'rift.webp',
    icon: Icons.public,
    keywords: ['rift'],
  ),
  CurveGroup(
    id: 'hopflopper',
    title: 'Hop Flopper',
    imageName: 'hopflop.webp',
    icon: Icons.set_meal,
    keywords: ['hop flopper', 'hopflopper'],
  ),
  CurveGroup(
    id: 'fall',
    title: 'Fall Damage',
    imageName: 'fall.webp',
    icon: Icons.heart_broken,
    keywords: ['fall damage', 'falling'],
  ),
  CurveGroup(
    id: 'neutral',
    title: 'Neutral Editing',
    imageName: 'edit.webp',
    icon: Icons.handyman,
    keywords: ['neutral editing'],
  ),
];

List<CustomCurveGroupInfo> _customGroupsFromCurves(
  List<CurveEntry> curves, {
  Set<String> excludeIds = const {},
}) {
  final map = <String, CustomCurveGroupInfo>{};
  for (final entry in curves) {
    final groupId = entry.groupId;
    if (groupId == null || groupId.isEmpty) continue;
    if (excludeIds.contains(groupId)) continue;
    final existing = map[groupId];
    if (existing == null) {
      map[groupId] = CustomCurveGroupInfo(
        id: groupId,
        name: entry.groupName ?? 'Custom',
        imagePath: entry.groupImagePath,
      );
    } else if (existing.imagePath == null && entry.groupImagePath != null) {
      map[groupId] = CustomCurveGroupInfo(
        id: groupId,
        name: existing.name,
        imagePath: entry.groupImagePath,
      );
    }
  }
  return map.values.toList();
}

List<CustomCurveGroupInfo> _groupInfosForPrompt(List<CurveEntry> curves) {
  final builtinIds = _baseCurveGroups.map((group) => group.id).toSet();
  final builtinInfos = _baseCurveGroups
      .map((group) => CustomCurveGroupInfo(id: group.id, name: group.title, imagePath: null))
      .toList();
  final customInfos = _customGroupsFromCurves(curves, excludeIds: builtinIds);
  final hasOther = builtinInfos.any((group) => group.id == 'other') || customInfos.any((group) => group.id == 'other');
  return [
    ...builtinInfos,
    ...customInfos,
    if (!hasOther) const CustomCurveGroupInfo(id: 'other', name: 'Other', imagePath: null),
  ];
}

String _humanizeCurveKey(String key) {
  final last = key.split('.').last;
  return last.replaceAllMapped(RegExp('[A-Z]'), (match) => ' ${match.group(0)}').trim();
}

String _stripScheme(String url) {
  return url.replaceFirst(RegExp(r'^https?://'), '');
}

class _CustomCurveDraft {
  _CustomCurveDraft()
      : nameController = TextEditingController(),
        linesController = TextEditingController(),
        isStatic = false;

  final TextEditingController nameController;
  final TextEditingController linesController;
  bool isStatic;
}

class _CustomGroupEditResult {
  const _CustomGroupEditResult({required this.name, required this.imagePath});

  final String name;
  final String? imagePath;
}

class _CustomCurveEditResult {
  const _CustomCurveEditResult({
    required this.name,
    required this.lines,
    required this.staticValue,
    required this.isStatic,
    required this.key,
    required this.pathPart,
    required this.groupId,
    required this.groupName,
    required this.groupImagePath,
  });

  final String name;
  final List<String> lines;
  final String staticValue;
  final bool isStatic;
  final String key;
  final String pathPart;
  final String groupId;
  final String groupName;
  final String? groupImagePath;
}

class _ImportCurveDraft {
  _ImportCurveDraft({
    required this.key,
    required this.pathPart,
    required this.lines,
    required this.staticValue,
  })  : nameController = TextEditingController(),
        selectedGroupId = '';

  final String key;
  final String pathPart;
  final List<String> lines;
  final String staticValue;
  final TextEditingController nameController;
  String selectedGroupId;
}

class CurveTableService {
  static CurveEntry _entryFromJson(String id, Map<String, dynamic> data) {
    return CurveEntry(
      id: id,
      name: data['name'] ?? 'Curve $id',
      key: data['key'] ?? '',
      type: data['type'] ?? 'amount',
      pathPart: data['pathPart'],
      staticValue: data['staticValue'],
      isCustom: data['isCustom'] == true,
      multiLines: (data['multiLines'] as List<dynamic>?)?.cast<String>() ?? const [],
      groupId: data['groupId'],
      groupName: data['groupName'],
      groupImagePath: data['groupImagePath'] ?? data['imagePath'],
    );
  }

  static Future<List<CurveEntry>> loadCurves() async {
    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) return [];
    final map = jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
    final entries = map.entries.map((entry) {
      final data = entry.value as Map<String, dynamic>;
      return _entryFromJson(entry.key, data);
    }).toList();
    entries.sort((a, b) => a.id.compareTo(b.id));
    return entries;
  }

  static Future<bool> areGlobalEnabled() async {
    final backup = File(BackendPaths.modificationsBackup);
    return !(await backup.exists());
  }

  static Future<void> toggleGlobal() async {
    final iniFile = File(BackendPaths.defaultGameIni);
    final backupFile = File(BackendPaths.modificationsBackup);
    if (!await iniFile.exists()) return;
    var content = await iniFile.readAsString();
    if (await backupFile.exists()) {
      final backup = jsonDecode(await backupFile.readAsString()) as Map<String, dynamic>;
      final lines = (backup['curveTableLines'] as List<dynamic>? ?? []).cast<String>();
      for (final line in lines) {
        content = content.replaceAll(';$line', line);
      }
      await iniFile.writeAsString(content);
      await backupFile.delete();
    } else {
      final regex = RegExp('^\\+CurveTable=.*;RowUpdate;.*\$', multiLine: true);
      final matches = regex.allMatches(content).map((m) => m.group(0)!).toList();
      final active = <String>[];
      for (final line in matches) {
        if (!line.startsWith(';')) {
          active.add(line);
          content = content.replaceAll(RegExp('^${RegExp.escape(line)}\$', multiLine: true), ';$line');
        }
      }
      await iniFile.writeAsString(content);
      await backupFile.writeAsString(jsonEncode({'curveTableLines': active}));
    }
  }

  static Future<bool> isCurveEnabled(CurveEntry entry) async {
    final iniFile = File(BackendPaths.defaultGameIni);
    if (!await iniFile.exists()) return false;
    final content = await iniFile.readAsString();
    if (entry.multiLines.isNotEmpty) {
      for (final line in entry.multiLines) {
        final parts = _splitCurveLine(line);
        if (parts == null) return false;
        final regex = RegExp(
          '^\\+CurveTable=${RegExp.escape(parts.pathPart)};RowUpdate;${RegExp.escape(parts.key)};${RegExp.escape(parts.row)};.*\$',
          multiLine: true,
        );
        if (!regex.hasMatch(content)) return false;
      }
      return true;
    }
    final escapedKey = RegExp.escape(entry.key);
    final regex = RegExp('^\\+CurveTable=.*;RowUpdate;$escapedKey;\\d+;.*\$', multiLine: true);
    return regex.hasMatch(content);
  }

  static Future<String?> getCurrentValue(CurveEntry entry) async {
    final iniFile = File(BackendPaths.defaultGameIni);
    if (!await iniFile.exists()) return null;
    final content = await iniFile.readAsString();
    if (entry.multiLines.isNotEmpty) {
      final escapedKey = RegExp.escape(entry.key);
      final regex = RegExp('^\\+CurveTable=.*;RowUpdate;$escapedKey;\\d+;(.+)\$', multiLine: true);
      final match = regex.firstMatch(content);
      return match?.group(1) ?? entry.staticValue;
    }
    final escapedKey = RegExp.escape(entry.key);
    final regex = RegExp('^\\+CurveTable=.*;RowUpdate;$escapedKey;\\d+;(.+)\$', multiLine: true);
    final match = regex.firstMatch(content);
    if (match == null) return null;
    return match.group(1);
  }

  static Future<void> setCurveEnabled(CurveEntry entry, bool enabled, {String? customValue}) async {
    final iniFile = File(BackendPaths.defaultGameIni);
    if (!await iniFile.exists()) return;
    var content = await iniFile.readAsString();
    if (!enabled) {
      if (entry.multiLines.isNotEmpty) {
        for (final line in entry.multiLines) {
          final parts = _splitCurveLine(line);
          if (parts == null) continue;
          final regex = RegExp(
            '^\\+CurveTable=${RegExp.escape(parts.pathPart)};RowUpdate;${RegExp.escape(parts.key)};${RegExp.escape(parts.row)};.*\$',
            multiLine: true,
          );
          content = content.replaceAll(regex, '');
        }
      } else {
        final escapedKey = RegExp.escape(entry.key);
        final regex = RegExp('^\\+CurveTable=.*;RowUpdate;$escapedKey;\\d+;.*\$', multiLine: true);
        content = content.replaceAll(regex, '');
      }
      content = content.replaceAll(RegExp('\n\n+'), '\n');
      await iniFile.writeAsString(content);
      return;
    }

    if (entry.multiLines.isNotEmpty) {
      for (final line in entry.multiLines) {
        final parts = _splitCurveLine(line);
        if (parts == null) continue;
        final regex = RegExp(
          '^\\+CurveTable=${RegExp.escape(parts.pathPart)};RowUpdate;${RegExp.escape(parts.key)};${RegExp.escape(parts.row)};.*\$',
          multiLine: true,
        );
        content = content.replaceAll(regex, '');
      }
    } else {
      final escapedKey = RegExp.escape(entry.key);
      final regex = RegExp('^\\+CurveTable=.*;RowUpdate;$escapedKey;\\d+;.*\$', multiLine: true);
      content = content.replaceAll(regex, '');
    }
    content = content.replaceAll(RegExp('\n\n+'), '\n');

    final ensured = IniService.ensureAssetSection(content, BackendPaths.curveTableComment, preferPrepend: true);
    content = ensured.content;
    final insertPoint = ensured.insertPoint;

    if (entry.multiLines.isNotEmpty) {
      final lines = entry.multiLines.map((line) {
        if (entry.type == 'amount' && customValue != null) {
          return _replaceCurveLineValue(line, customValue);
        }
        return line;
      }).toList();
      content = content.substring(0, insertPoint) + lines.join('\n') + '\n' + content.substring(insertPoint);
    } else {
      final pathPart = entry.pathPart ?? BackendPaths.defaultCurvePath;
      final value = entry.type == 'static' ? (entry.staticValue ?? '0') : (customValue ?? '0');
      final line = '+CurveTable=$pathPart;RowUpdate;${entry.key};0;$value';
      content = content.substring(0, insertPoint) + line + '\n' + content.substring(insertPoint);
    }
    await iniFile.writeAsString(content);
  }

  static Future<void> importFromIni(String importPath) async {
    final source = File(importPath);
    final target = File(BackendPaths.defaultGameIni);
    if (!await source.exists() || !await target.exists()) return;
    final importContent = await source.readAsString();
    final filteredContent = _extractLastHotfixBlock(importContent);
    if (filteredContent.trim().isEmpty) {
      return;
    }
    final regex = RegExp('^\\s*;?\\+CurveTable=(.+?);RowUpdate;(.+?);(\\d+);(.+)\$', multiLine: true);
    final matches = regex.allMatches(filteredContent).toList();
    if (matches.isEmpty) return;

    final grouped = <String, List<String>>{};
    var hasEnabled = false;
    final allNormalized = <String>[];
    for (final match in matches) {
      final pathPart = match.group(1)!.trim();
      final key = match.group(2)!.trim();
      final rawLine = match.group(0)!.trim();
      final normalized = rawLine.startsWith(';') ? rawLine.substring(1).trim() : rawLine;
      allNormalized.add(normalized);
      if (!rawLine.startsWith(';')) {
        hasEnabled = true;
      }
      final groupKey = '$pathPart|||$key';
      grouped.putIfAbsent(groupKey, () => []).add(normalized);
    }

    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) {
      await curvesFile.parent.create(recursive: true);
      await curvesFile.writeAsString('{}');
    }

    final existing = await CurveTableService.loadCurves();
    final existingKeys = existing
        .map((entry) => '${(entry.pathPart ?? BackendPaths.defaultCurvePath).trim()}|||${entry.key.trim()}')
        .toSet();

    final missing = <CustomCurveInput>[];
    for (final entry in grouped.entries) {
      if (existingKeys.contains(entry.key)) continue;
      final parts = entry.key.split('|||');
      final key = parts[1];
      missing.add(
        CustomCurveInput(
          name: _humanizeKey(key),
          key: key,
          pathPart: parts[0],
          lines: entry.value,
          staticValue: '0',
          isStatic: false,
          groupId: 'other',
          groupName: 'Other',
          groupImagePath: '',
          groupImageSourcePath: '',
        ),
      );
    }

    if (missing.isNotEmpty) {
      await CurveTableService.addCustomCurves(missing);
    }

    for (final entry in grouped.entries) {
      final parts = entry.key.split('|||');
      final activeLines = entry.value
          .where((line) => !line.startsWith(';'))
          .toList();
      if (activeLines.isNotEmpty) {
        await CurveTableService.applyCurveLines(parts[0], parts[1], activeLines);
      }
    }

    final backupFile = File(BackendPaths.modificationsBackup);
    if (matches.isNotEmpty) {
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
    } else {
      await backupFile.writeAsString(jsonEncode({'curveTableLines': allNormalized}));
    }
  }

  static String? _extractBlock(String content, String label) {
    final lines = content.split('\n');
    final startIndex = lines.indexWhere((line) => line.trim() == label || line.trim().startsWith(label));
    if (startIndex == -1) return null;
    final buffer = <String>[];
    for (var i = startIndex + 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('#') || line.startsWith('[')) break;
      buffer.add(line);
    }
    return buffer.join('\n');
  }


  static Future<void> applyCurveLines(String pathPart, String key, List<String> lines) async {
    final iniFile = File(BackendPaths.defaultGameIni);
    if (!await iniFile.exists()) return;
    var content = await iniFile.readAsString();
    for (final line in lines) {
      final parts = _splitCurveLine(line);
      if (parts == null) continue;
      final regex = RegExp(
        '^\\+CurveTable=${RegExp.escape(parts.pathPart)};RowUpdate;${RegExp.escape(parts.key)};${RegExp.escape(parts.row)};.*\$',
        multiLine: true,
      );
      content = content.replaceAll(regex, '');
    }
    content = content.replaceAll(RegExp('\n\n+'), '\n');
    final ensured = IniService.ensureAssetSection(content, BackendPaths.curveTableComment, preferPrepend: true);
    content = ensured.content;
    final insertPoint = ensured.insertPoint;
    content = content.substring(0, insertPoint) + lines.join('\n') + '\n' + content.substring(insertPoint);
    await iniFile.writeAsString(content);
  }

  static Future<void> clearAllCurveTables() async {
    final iniFile = File(BackendPaths.defaultGameIni);
    final backupFile = File(BackendPaths.modificationsBackup);
    if (!await iniFile.exists()) return;
    var content = await iniFile.readAsString();
    content = content.replaceAll(RegExp('^\\+CurveTable=.*\$', multiLine: true), '');
    content = content.replaceAll(RegExp('\n\n+'), '\n');
    await iniFile.writeAsString(content);
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
  }

  static Future<void> addCustomCurve(CustomCurveInput input) async {
    await addCustomCurves([input]);
  }

  static Future<void> addCustomCurves(List<CustomCurveInput> inputs) async {
    if (inputs.isEmpty) return;
    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) return;
    final map = jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
    var nextId = (map.keys.map(int.tryParse).whereType<int>().fold(0, (a, b) => a > b ? a : b)) + 1;
    final groupImageCache = <String, String>{};

    for (final input in inputs) {
      var storedGroupImagePath = input.groupImagePath;
      if (storedGroupImagePath.isEmpty) {
        storedGroupImagePath = groupImageCache[input.groupId] ?? '';
      }
      if (storedGroupImagePath.isEmpty && input.groupImageSourcePath.isNotEmpty) {
        final source = File(input.groupImageSourcePath);
        if (await source.exists()) {
          final destDir = Directory(joinPath([getBackendRoot(), 'public', 'items', 'custom-groups']));
          await destDir.create(recursive: true);
          final fileName = source.uri.pathSegments.last;
          final stampedName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
          storedGroupImagePath = joinPath(['custom-groups', stampedName]);
          await source.copy(joinPath([destDir.path, stampedName]));
        }
      }
      if (storedGroupImagePath.isNotEmpty) {
        groupImageCache[input.groupId] = storedGroupImagePath;
      }

      map[nextId.toString()] = {
        'name': input.name,
        'key': input.key,
        'type': input.isStatic ? 'static' : 'amount',
        'pathPart': input.pathPart,
        if (input.isStatic) 'staticValue': input.staticValue,
        'isCustom': true,
        'multiLines': input.lines,
        'groupId': input.groupId,
        'groupName': input.groupName,
        if (storedGroupImagePath.isNotEmpty) 'groupImagePath': storedGroupImagePath,
      };

      final entry = CurveEntry(
        id: nextId.toString(),
        name: input.name,
        key: input.key,
        type: input.isStatic ? 'static' : 'amount',
        pathPart: input.pathPart,
        staticValue: input.isStatic ? input.staticValue : null,
        isCustom: true,
        multiLines: input.lines,
        groupId: input.groupId,
        groupName: input.groupName,
        groupImagePath: storedGroupImagePath.isNotEmpty ? storedGroupImagePath : null,
      );
      await setCurveEnabled(entry, true);
      nextId++;
    }

    await curvesFile.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
  }

  static Future<void> deleteCustomGroup(String groupId) async {
    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) return;
    final map = jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
    final entriesToDelete = <String, CurveEntry>{};
    String? groupImagePath;
    for (final entry in map.entries) {
      final data = entry.value as Map<String, dynamic>;
      if (data['isCustom'] == true && data['groupId'] == groupId) {
        entriesToDelete[entry.key] = _entryFromJson(entry.key, data);
        groupImagePath ??= (data['groupImagePath'] ?? data['imagePath']) as String?;
      }
    }
    for (final entry in entriesToDelete.values) {
      await setCurveEnabled(entry, false);
    }
    for (final key in entriesToDelete.keys) {
      map.remove(key);
    }
    await curvesFile.writeAsString(const JsonEncoder.withIndent('  ').convert(map));

    if (groupImagePath != null && groupImagePath!.isNotEmpty) {
      if (groupImagePath!.startsWith('custom-groups')) {
        final imageFile = File(joinPath([getBackendRoot(), 'public', 'items', groupImagePath!]));
        if (await imageFile.exists()) {
          await imageFile.delete();
        }
      }
    }
  }

  static Future<void> deleteCustomCurve(String curveId) async {
    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) return;
    final map = jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
    final data = map[curveId];
    if (data is! Map<String, dynamic> || data['isCustom'] != true) return;
    final entry = _entryFromJson(curveId, data);
    await setCurveEnabled(entry, false);
    map.remove(curveId);
    await curvesFile.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
  }

  static Future<void> updateCustomCurve(String curveId, _CustomCurveEditResult updated) async {
    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) return;
    final map = jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
    final data = map[curveId];
    if (data is! Map<String, dynamic> || data['isCustom'] != true) return;
    final oldEntry = _entryFromJson(curveId, data);
    await setCurveEnabled(oldEntry, false);
    map[curveId] = {
      ...data,
      'name': updated.name,
      'key': updated.key,
      'type': updated.isStatic ? 'static' : 'amount',
      'pathPart': updated.pathPart,
      if (updated.isStatic) 'staticValue': updated.staticValue,
      if (!updated.isStatic) 'staticValue': null,
      'multiLines': updated.lines,
      'groupId': updated.groupId,
      'groupName': updated.groupName,
      if (updated.groupImagePath != null) 'groupImagePath': updated.groupImagePath,
    };
    if (updated.groupImagePath == null) {
      (map[curveId] as Map<String, dynamic>).remove('groupImagePath');
    }
    final newEntry = CurveEntry(
      id: curveId,
      name: updated.name,
      key: updated.key,
      type: updated.isStatic ? 'static' : 'amount',
      pathPart: updated.pathPart,
      staticValue: updated.isStatic ? updated.staticValue : null,
      isCustom: true,
      multiLines: updated.lines,
      groupId: updated.groupId,
      groupName: updated.groupName,
      groupImagePath: updated.groupImagePath ?? oldEntry.groupImagePath,
    );
    await setCurveEnabled(newEntry, true);
    await curvesFile.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
  }

  static Future<void> updateCustomGroup(String groupId, String name, String? newImagePath) async {
    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) return;
    final map = jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
    String? storedImagePath;
    if (newImagePath != null && newImagePath.isNotEmpty) {
      final source = File(newImagePath);
      if (await source.exists()) {
        final destDir = Directory(joinPath([getBackendRoot(), 'public', 'items', 'custom-groups']));
        await destDir.create(recursive: true);
        final fileName = source.uri.pathSegments.last;
        final stampedName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
        storedImagePath = joinPath(['custom-groups', stampedName]);
        await source.copy(joinPath([destDir.path, stampedName]));
      }
    }
    for (final entry in map.entries) {
      final data = entry.value as Map<String, dynamic>;
      if (data['isCustom'] == true && data['groupId'] == groupId) {
        data['groupName'] = name;
        if (storedImagePath != null) {
          data['groupImagePath'] = storedImagePath;
        }
        map[entry.key] = data;
      }
    }
    await curvesFile.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
  }

  static Future<void> _ensureCurveInJson(String key, String pathPart) async {
    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) {
      await curvesFile.parent.create(recursive: true);
      await curvesFile.writeAsString('{}');
    }
    final map = jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
    final exists = map.values.any((value) {
      final data = value as Map<String, dynamic>;
      final existingPath = (data['pathPart'] ?? BackendPaths.defaultCurvePath) as String;
      return data['key'] == key && existingPath == pathPart;
    });
    if (exists) return;
    final nextId = (map.keys.map(int.tryParse).whereType<int>().fold(0, (a, b) => a > b ? a : b)) + 1;
    map[nextId.toString()] = {
      'name': _humanizeKey(key),
      'key': key,
      'type': 'amount',
      'pathPart': pathPart,
      'isCustom': true,
      'groupId': 'other',
      'groupName': 'Other',
    };
    await curvesFile.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
  }

  static String _humanizeKey(String key) {
    final last = key.split('.').last;
    return last.replaceAllMapped(RegExp('[A-Z]'), (match) => ' ${match.group(0)}').trim();
  }
}

class ConfigSettings {
  const ConfigSettings({
    required this.rufusStage,
    required this.waterLevel,
    required this.saveArenaPoints,
    required this.useWaterStorm,
    required this.startBackendOnLaunch,
    required this.disableBackendUpdateCheck,
    required this.useDarkMode,
    required this.backgroundImagePath,
    required this.backgroundBlur,
    required this.dialogBlurEnabled,
  });

  final int rufusStage;
  final int waterLevel;
  final bool saveArenaPoints;
  final bool useWaterStorm;
  final bool startBackendOnLaunch;
  final bool disableBackendUpdateCheck;
  final bool useDarkMode;
  final String backgroundImagePath;
  final double backgroundBlur;
  final bool dialogBlurEnabled;

  ConfigSettings copyWith({
    int? rufusStage,
    int? waterLevel,
    bool? saveArenaPoints,
    bool? useWaterStorm,
    bool? startBackendOnLaunch,
    bool? disableBackendUpdateCheck,
    bool? useDarkMode,
    String? backgroundImagePath,
    double? backgroundBlur,
    bool? dialogBlurEnabled,
  }) {
    return ConfigSettings(
      rufusStage: rufusStage ?? this.rufusStage,
      waterLevel: waterLevel ?? this.waterLevel,
      saveArenaPoints: saveArenaPoints ?? this.saveArenaPoints,
      useWaterStorm: useWaterStorm ?? this.useWaterStorm,
      startBackendOnLaunch: startBackendOnLaunch ?? this.startBackendOnLaunch,
      disableBackendUpdateCheck: disableBackendUpdateCheck ?? this.disableBackendUpdateCheck,
      useDarkMode: useDarkMode ?? this.useDarkMode,
      backgroundImagePath: backgroundImagePath ?? this.backgroundImagePath,
      backgroundBlur: backgroundBlur ?? this.backgroundBlur,
      dialogBlurEnabled: dialogBlurEnabled ?? this.dialogBlurEnabled,
    );
  }
}

class ConfigService {
  static Future<ConfigSettings> load() async {
    final base = await _loadConfigFile(File(BackendPaths.configIni));
    final gui = await _loadConfigFile(File(_guiConfigPath()));
    final map = {...base, ...gui};
    if (map.isEmpty) {
      return const ConfigSettings(
        rufusStage: 1,
        waterLevel: 1,
        saveArenaPoints: false,
        useWaterStorm: false,
        startBackendOnLaunch: false,
        disableBackendUpdateCheck: false,
        useDarkMode: true,
        backgroundImagePath: '',
        backgroundBlur: 18,
        dialogBlurEnabled: true,
      );
    }
    return ConfigSettings(
      rufusStage: int.tryParse(map['RufusStage'] ?? '') ?? 1,
      waterLevel: int.tryParse(map['WaterLevel'] ?? '') ?? 1,
      saveArenaPoints: (map['SaveArenaPoints'] ?? '').toLowerCase() == 'true',
      useWaterStorm: (map['UseWaterStorm'] ?? '').toLowerCase() == 'true',
      startBackendOnLaunch: (map['StartBackendOnLaunch'] ?? '').toLowerCase() == 'true',
      disableBackendUpdateCheck: (map['DisableBackendUpdateCheck'] ?? '').toLowerCase() == 'true',
      useDarkMode: (map['UseDarkMode'] ?? 'true').toLowerCase() == 'true',
      backgroundImagePath: map['BackgroundImagePath'] ?? '',
      backgroundBlur: double.tryParse(map['BackgroundBlur'] ?? '') ?? 18,
      dialogBlurEnabled: (map['DialogBlurEnabled'] ?? 'true').toLowerCase() == 'true',
    );
  }

  static Future<void> save(ConfigSettings settings) async {
    final buffer = StringBuffer()
      ..writeln('RufusStage=${settings.rufusStage}')
      ..writeln('WaterLevel=${settings.waterLevel}')
      ..writeln('SaveArenaPoints=${settings.saveArenaPoints}')
      ..writeln('UseWaterStorm=${settings.useWaterStorm}')
      ..writeln('StartBackendOnLaunch=${settings.startBackendOnLaunch}')
      ..writeln('DisableBackendUpdateCheck=${settings.disableBackendUpdateCheck}')
      ..writeln('UseDarkMode=${settings.useDarkMode}')
      ..writeln('BackgroundImagePath=${settings.backgroundImagePath}')
      ..writeln('BackgroundBlur=${settings.backgroundBlur}')
      ..writeln('DialogBlurEnabled=${settings.dialogBlurEnabled}');
    final backendFile = File(BackendPaths.configIni);
    try {
      await backendFile.writeAsString(buffer.toString());
    } catch (_) {
      // Backend config might be read-only on some installs.
    }
    final guiFile = File(_guiConfigPath());
    try {
      await guiFile.parent.create(recursive: true);
      await guiFile.writeAsString(buffer.toString());
    } catch (_) {}
  }

  static String _guiConfigPath() {
    final appData = Platform.environment['APPDATA'] ?? '';
    if (appData.isNotEmpty) {
      return joinPath([appData, 'ATLAS', 'gui.ini']);
    }
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty) {
      return joinPath([home, 'AppData', 'Roaming', 'ATLAS', 'gui.ini']);
    }
    return joinPath([Directory.current.path, 'gui.ini']);
  }

  static Future<Map<String, String>> _loadConfigFile(File file) async {
    if (!await file.exists()) return {};
    final content = await file.readAsString();
    final map = <String, String>{};
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#') || !trimmed.contains('=')) continue;
      final parts = trimmed.split('=');
      map[parts.first.trim()] = parts.sublist(1).join('=').trim();
    }
    return map;
  }
}

class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.isInstaller,
    this.notes,
    this.currentCommit,
    this.latestCommit,
  });

  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final bool isInstaller;
  final String? notes;
  final String? currentCommit;
  final String? latestCommit;

  String get currentLabel => _formatVersion(currentVersion);
  String get latestLabel => _formatVersion(latestVersion);
}

class UpdateService {
  static const String _repo = 'cipherfps/ATLAS-Backend';
  static const String _branch = 'gui';
  static const String _mainZipUrl = 'https://github.com/cipherfps/ATLAS-Backend/archive/refs/heads/gui.zip';
  static const String _latestReleaseUrl = 'https://api.github.com/repos/cipherfps/ATLAS-Backend/releases/latest';

  static Future<UpdateInfo?> checkForUpdate() async {
    final backendRoot = getBackendRoot();
    final packageFile = File(joinPath([backendRoot, 'package.json']));
    if (!await packageFile.exists()) return null;

    final localPackage = jsonDecode(await packageFile.readAsString()) as Map<String, dynamic>;
    final currentVersion = (localPackage['version'] ?? '0.0.0').toString();
    final remotePackage = await _fetchRemotePackage();
    if (remotePackage == null) return null;
    final latestVersion = (remotePackage['version'] ?? currentVersion).toString();
    final hasVersionUpdate = _isNewerVersion(latestVersion, currentVersion);
    if (!hasVersionUpdate) return null;

    final releaseMsi = await _fetchLatestReleaseMsi();
    final downloadUrl = releaseMsi ?? _mainZipUrl;
    final isInstaller = releaseMsi != null;

    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      downloadUrl: downloadUrl,
      isInstaller: isInstaller,
      notes: null,
      currentCommit: null,
      latestCommit: null,
    );
  }

  static Future<void> downloadAndApply(UpdateInfo info, ValueNotifier<double>? progress) async {
    if (info.isInstaller) {
      final msiFile = await _downloadInstaller(info.downloadUrl, progress);
      await Process.start('msiexec', ['/i', msiFile.path], mode: ProcessStartMode.detached);
      exit(0);
    } else {
      final zipFile = await _downloadZip(info.downloadUrl, progress);
      await _applyZip(zipFile);
    }
  }

  static Future<String?> _fetchLatestReleaseMsi() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_latestReleaseUrl));
      request.headers.set('User-Agent', 'ATLAS-GUI');
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final assets = json['assets'];
      if (assets is! List) return null;
      for (final asset in assets) {
        if (asset is! Map<String, dynamic>) continue;
        final name = asset['name']?.toString().toLowerCase() ?? '';
        final url = asset['browser_download_url']?.toString();
        if (url == null) continue;
        if (name.endsWith('.msi') && name.contains('atlas')) {
          return url;
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>?> _fetchRemotePackage() async {
    final url = Uri.parse('https://raw.githubusercontent.com/$_repo/$_branch/package.json?t=${DateTime.now().millisecondsSinceEpoch}');
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      request.headers.set('User-Agent', 'ATLAS-GUI');
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }


  static Future<File> _downloadZip(String url, ValueNotifier<double>? progress) async {
    final tempDir = await Directory.systemTemp.createTemp('atlas_update_');
    final zipFile = File(joinPath([tempDir.path, 'update.zip']));
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'ATLAS-GUI');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }
      final total = response.contentLength;
      final sink = zipFile.openWrite();
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && progress != null) {
          progress.value = received / total;
        }
      }
      await sink.close();
      if (progress != null) {
        progress.value = 1;
      }
      return zipFile;
    } finally {
      client.close();
    }
  }

  static Future<File> _downloadInstaller(String url, ValueNotifier<double>? progress) async {
    final tempDir = await Directory.systemTemp.createTemp('atlas_update_');
    final msiFile = File(joinPath([tempDir.path, 'ATLAS-Update.msi']));
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'ATLAS-GUI');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }
      final total = response.contentLength;
      final sink = msiFile.openWrite();
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && progress != null) {
          progress.value = received / total;
        }
      }
      await sink.close();
      if (progress != null) {
        progress.value = 1;
      }
      return msiFile;
    } finally {
      client.close();
    }
  }

  static Future<void> _applyZip(File zipFile) async {
    final backendRoot = getBackendRoot();
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final rawPath = file.name;
      final relative = _stripZipRoot(rawPath);
      if (relative.isEmpty) continue;
      if (_shouldPreserve(relative)) continue;

      final outPath = joinPath([backendRoot, ...relative.split('/')]);
      if (file.isFile) {
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
  }

  static String _stripZipRoot(String path) {
    final parts = path.split('/');
    if (parts.length <= 1) return '';
    return parts.sublist(1).join('/');
  }

  static bool _shouldPreserve(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    if (normalized.startsWith('atlas_gui_flutter/')) return true;
    if (normalized.startsWith('node_modules/')) return true;
    if (normalized.startsWith('exports/')) return true;
    if (normalized.startsWith('responses/curves.json')) return true;
    if (normalized.startsWith('responses/modifications-backup.json')) return true;
    if (normalized.startsWith('src/config/config.ini')) return true;
    if (normalized.startsWith('public/items/custom-groups/')) return true;
    if (normalized.startsWith('static/hotfixes/DefaultGame.ini')) return true;

    if (normalized.startsWith('static/profiles/')) {
      final rest = normalized.substring('static/profiles/'.length);
      return !rest.startsWith('profile_');
    }
    if (normalized.startsWith('static/ClientSettings/')) {
      final rest = normalized.substring('static/ClientSettings/'.length);
      return !rest.startsWith('config/');
    }
    return false;
  }
}

String _formatVersion(String version) {
  final trimmed = version.trim();
  return trimmed.startsWith('v') ? trimmed : 'v$trimmed';
}

bool _isNewerVersion(String latest, String current) {
  final latestParts = latest.split('.').map(int.tryParse).map((v) => v ?? 0).toList();
  final currentParts = current.split('.').map(int.tryParse).map((v) => v ?? 0).toList();
  final maxLen = latestParts.length > currentParts.length ? latestParts.length : currentParts.length;
  for (var i = 0; i < maxLen; i++) {
    final l = i < latestParts.length ? latestParts[i] : 0;
    final c = i < currentParts.length ? currentParts[i] : 0;
    if (l > c) return true;
    if (l < c) return false;
  }
  return false;
}

class DataService {
  static const Set<String> _profileTemplateFiles = {
    'profile_athena.json',
    'profile_campaign.json',
    'profile_collections.json',
    'profile_common_core.json',
    'profile_common_public.json',
    'profile_creative.json',
    'profile_metadata.json',
    'profile_outpost0.json',
    'profile_profile0.json',
    'profile_theater0.json',
  };
  static const String _profileTemplateBackupDirName = '.defaults';

  static Future<void> clearBackendData(BuildContext context) async {
    final confirm = await _confirmDialog(context, 'Clear all backend data? This will reset profiles, client settings, CurveTables, and straight bloom.');
    if (!confirm) return;
    final profilesDir = Directory(joinPath([getBackendRoot(), 'static', 'profiles']));
    final clientSettingsDir = Directory(joinPath([getBackendRoot(), 'static', 'ClientSettings']));
    final iniFile = File(BackendPaths.defaultGameIni);
    final curvesFile = File(BackendPaths.curvesJson);
    final backupFile = File(BackendPaths.modificationsBackup);
    final sniperFile = File(BackendPaths.sniperJson);

    if (await profilesDir.exists()) {
      await _ensureProfileTemplateBackup(profilesDir);
      await for (final entity in profilesDir.list()) {
        final name = entity.uri.pathSegments.last;
        if (_profileTemplateFiles.contains(name)) continue;
        await entity.delete(recursive: true);
      }
      await _restoreProfileTemplates(profilesDir);
    }

    if (await clientSettingsDir.exists()) {
      await for (final entity in clientSettingsDir.list()) {
        final name = entity.uri.pathSegments.last;
        if (name.toLowerCase() == 'config') continue;
        await entity.delete(recursive: true);
      }
    }

    if (await iniFile.exists() && await sniperFile.exists()) {
      await StraightBloomService.setEnabled(false);
    }

    if (await iniFile.exists() && await curvesFile.exists()) {
      var content = await iniFile.readAsString();
      content = content.replaceAll(RegExp('^\\+CurveTable=.*\$', multiLine: true), '');
      content = content.replaceAll(RegExp('\n\n+'), '\n');
      await iniFile.writeAsString(content);
      final curves = jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
      final keysToRemove = curves.entries.where((e) => (e.value as Map<String, dynamic>)['isCustom'] == true).map((e) => e.key).toList();
      for (final key in keysToRemove) {
        curves.remove(key);
      }
      await curvesFile.writeAsString(const JsonEncoder.withIndent('  ').convert(curves));
      await backupFile.writeAsString(jsonEncode({'curveTableLines': []}));
    }
    final current = await ConfigService.load();
    await ConfigService.save(
      current.copyWith(
        backgroundImagePath: '',
        backgroundBlur: 18,
      ),
    );
    appBackgroundPath.value = '';
    appBackgroundBlur.value = 18;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backend data cleared.')));
    }
  }

  static Future<void> exportData(BuildContext context) async {
    final exportsRoot = Directory(joinPath([getBackendRoot(), 'exports']));
    final defaultGameDir = Directory(joinPath([exportsRoot.path, 'DefaultGame']));
    final profilesDir = Directory(joinPath([exportsRoot.path, 'Profiles']));
    final clientDir = Directory(joinPath([exportsRoot.path, 'ClientSettings']));
    if (await _hasExistingExport(defaultGameDir, profilesDir, clientDir)) {
      final confirm = await _confirmDialog(context, 'Exports already exist. Overwrite them?');
      if (!confirm) return;
      await _clearDirectory(defaultGameDir);
      await _clearDirectory(profilesDir);
      await _clearDirectory(clientDir);
    }
    await defaultGameDir.create(recursive: true);
    await profilesDir.create(recursive: true);
    await clientDir.create(recursive: true);
    await _clearNonDirectoryEntries(profilesDir);
    await _clearNonDirectoryEntries(clientDir);

    final iniSource = File(BackendPaths.defaultGameIni);
    var exportedDefaultGame = false;
    if (await iniSource.exists()) {
      await iniSource.copy(joinPath([defaultGameDir.path, 'DefaultGame.ini']));
      exportedDefaultGame = true;
    }

    final profilesExported = await _copyNonEmptyChildDirs(
      Directory(joinPath([getBackendRoot(), 'static', 'profiles'])),
      profilesDir,
      skipDirs: {_profileTemplateBackupDirName},
    );
    final clientExported = await _copyNonEmptyChildDirs(
      Directory(joinPath([getBackendRoot(), 'static', 'ClientSettings'])),
      clientDir,
    );

    await _clearNonDirectoryEntries(profilesDir);
    await _clearNonDirectoryEntries(clientDir);

    if (!exportedDefaultGame && profilesExported == 0 && clientExported == 0) {
      await _deleteIfEmpty(profilesDir);
      await _deleteIfEmpty(clientDir);
      await _deleteIfEmpty(defaultGameDir);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('No data found to export.')));
      }
      return;
    }

    if (context.mounted) {
      await _showExportSummary(
        context,
        exportedDefaultGame: exportedDefaultGame,
        profilesExported: profilesExported,
        clientExported: clientExported,
      );
    }
  }

  static Future<void> importData(BuildContext context) async {
    final exportsRoot = Directory(joinPath([getBackendRoot(), 'exports']));
    final defaultGameDir = Directory(joinPath([exportsRoot.path, 'DefaultGame']));
    final profilesDir = Directory(joinPath([exportsRoot.path, 'Profiles']));
    final clientDir = Directory(joinPath([exportsRoot.path, 'ClientSettings']));
    if (!await _hasExistingExport(defaultGameDir, profilesDir, clientDir)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No exported data found.')));
      }
      return;
    }
    final confirm = await _confirmDialog(context, 'Importing will overwrite existing data. Continue?');
    if (!confirm) return;

    await _importFolderChildren(
      profilesDir,
      Directory(joinPath([getBackendRoot(), 'static', 'profiles'])),
      skipFiles: _profileTemplateFiles,
      skipDirs: {_profileTemplateBackupDirName},
      onlyDirs: true,
    );
    await _importFolderChildren(
      clientDir,
      Directory(joinPath([getBackendRoot(), 'static', 'ClientSettings'])),
      onlyDirs: true,
    );
    // Profiles + client settings only: skip DefaultGame.ini imports.
    
    // Clear profile cache on backend
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('http://127.0.0.1:3551/atlas/clear-profile-cache'));
      await request.close();
      client.close();
    } catch (_) {
      // Backend might not be running, that's okay
    }
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import complete. Changes will be visible on next login.')));
    }
  }

  static Future<void> clearExportedData(BuildContext context) async {
    final confirm = await _confirmDialog(context, 'Clear exported data? This will remove DefaultGame, profiles, and client settings from exports/.');
    if (!confirm) return;
    final exportsRoot = Directory(joinPath([getBackendRoot(), 'exports']));
    await _clearDirectory(exportsRoot);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exported data cleared.')));
    }
  }

  static Future<bool> _hasExistingExport(Directory a, Directory b, Directory c) async {
    final aHas = a.existsSync() && a.listSync().isNotEmpty;
    final bHas = b.existsSync() && b.listSync().isNotEmpty;
    final cHas = c.existsSync() && c.listSync().isNotEmpty;
    return aHas || bHas || cHas;
  }

  static Future<void> _showExportSummary(
    BuildContext context, {
    required bool exportedDefaultGame,
    required int profilesExported,
    required int clientExported,
  }) async {
    final lines = <String>[];
    if (exportedDefaultGame) {
      lines.add('DefaultGame.ini');
    }
    if (profilesExported > 0) {
      lines.add('Profiles: $profilesExported folder${profilesExported == 1 ? '' : 's'}');
    }
    if (clientExported > 0) {
      lines.add('ClientSettings: $clientExported folder${clientExported == 1 ? '' : 's'}');
    }
    await _showBlurDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Exported items:'),
            const SizedBox(height: 12),
            for (final line in lines) Text('• $line'),
          ],
        ),
        actions: [
          _HoverScale(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _copyDir(Directory src, Directory dest) async {
    if (!await src.exists()) return;
    await dest.create(recursive: true);
    await for (final entity in src.list(recursive: false)) {
      final name = entity.uri.pathSegments.last;
      final destPath = joinPath([dest.path, name]);
      if (entity is Directory) {
        await _copyDir(entity, Directory(destPath));
      } else if (entity is File) {
        await entity.copy(destPath);
      }
    }
  }

  static Future<int> _copyNonEmptyChildDirs(
    Directory src,
    Directory dest, {
    Set<String> skipDirs = const {},
  }) async {
    if (!await src.exists()) return 0;
    var copied = 0;
    await for (final entity in src.list(recursive: false)) {
      if (entity is Directory) {
        final name = _basename(entity.path);
        if (skipDirs.contains(name) || name.startsWith('.')) continue;
        if (!await _dirHasFiles(entity)) continue;
        await dest.create(recursive: true);
        await _copyDir(entity, Directory(joinPath([dest.path, name])));
        copied++;
      }
    }
    return copied;
  }

  static Future<bool> _dirHasFiles(Directory dir) async {
    if (!await dir.exists()) return false;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) return true;
    }
    return false;
  }

  static Future<void> _clearDirectory(Directory dir) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list(recursive: false)) {
      await entity.delete(recursive: true);
    }
  }

  static Future<void> _clearNonDirectoryEntries(Directory dir) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list(recursive: false)) {
      if (entity is! Directory) {
        await entity.delete();
      }
    }
  }

  static Future<void> _deleteIfEmpty(Directory dir) async {
    if (!await dir.exists()) return;
    final isEmpty = await dir.list(recursive: false).isEmpty;
    if (isEmpty) {
      await dir.delete(recursive: true);
    }
  }

  static Future<void> _importFolderChildren(
    Directory src,
    Directory dest, {
    Set<String> skipFiles = const {},
    Set<String> skipDirs = const {},
    bool onlyDirs = false,
  }) async {
    if (!await src.exists()) return;
    await dest.create(recursive: true);
    await for (final entity in src.list(recursive: false)) {
      final name = _basename(entity.path);
      if (entity is Directory) {
        if (skipDirs.contains(name)) continue;
        await _copyDir(entity, Directory(joinPath([dest.path, name])));
      } else if (!onlyDirs && entity is File) {
        if (skipFiles.contains(name)) continue;
        await entity.copy(joinPath([dest.path, name]));
      }
    }
  }

  static Future<void> _reorderDefaultGameHotfixBlocks(String iniPath) async {
    final iniFile = File(iniPath);
    if (!await iniFile.exists()) return;
    var content = await iniFile.readAsString();
    final curveRegex = RegExp('^;?\\+CurveTable=.*\$', multiLine: true);
    final curveLines = curveRegex.allMatches(content).map((m) => m.group(0)!).toList();
    content = content.replaceAll(curveRegex, '');

    final sniperFile = File(BackendPaths.sniperJson);
    final straightLines = <String>[];
    if (await sniperFile.exists()) {
      final lines = (jsonDecode(await sniperFile.readAsString()) as Map<String, dynamic>)['lines'] as List<dynamic>;
      for (final line in lines.cast<String>()) {
        if (content.contains(line)) {
          straightLines.add(line);
          content = content.replaceAll(line, '');
        }
        final commented = ';$line';
        if (content.contains(commented)) {
          straightLines.add(commented);
          content = content.replaceAll(commented, '');
        }
      }
    }

    content = content.replaceAll(BackendPaths.straightBloomComment, '');
    content = content.replaceAll(BackendPaths.curveTableComment, '');
    content = content.replaceAll(RegExp('\n\n+'), '\n');

    final linesOut = content.split('\n').toList();
    var assetIndex = linesOut.indexWhere((line) => line.trim() == '[AssetHotfix]');
    if (assetIndex == -1) {
      linesOut.add('[AssetHotfix]');
      assetIndex = linesOut.length - 1;
    }

    var insertAt = assetIndex + 1;
    final block = <String>[];
    if (straightLines.isNotEmpty) {
      block.add(BackendPaths.straightBloomComment);
      block.addAll(straightLines);
    }
    if (curveLines.isNotEmpty) {
      if (block.isNotEmpty) block.add('');
      block.add(BackendPaths.curveTableComment);
      block.addAll(curveLines);
    }
    if (block.isNotEmpty) {
      linesOut.insertAll(insertAt, block);
    }
    await iniFile.writeAsString(linesOut.join('\n'));
  }

  static String _basename(String path) {
    final parts = path.split(Platform.pathSeparator);
    for (var i = parts.length - 1; i >= 0; i--) {
      final part = parts[i].trim();
      if (part.isNotEmpty) return part;
    }
    return path;
  }

  static Future<void> _ensureProfileTemplateBackup(Directory profilesDir) async {
    final backupDir = Directory(joinPath([profilesDir.path, _profileTemplateBackupDirName]));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    for (final name in _profileTemplateFiles) {
      final source = File(joinPath([profilesDir.path, name]));
      if (!await source.exists()) continue;
      final backup = File(joinPath([backupDir.path, name]));
      if (!await backup.exists()) {
        await source.copy(backup.path);
      }
    }
  }

  static Future<void> _restoreProfileTemplates(Directory profilesDir) async {
    final backupDir = Directory(joinPath([profilesDir.path, _profileTemplateBackupDirName]));
    if (!await backupDir.exists()) return;
    for (final name in _profileTemplateFiles) {
      final backup = File(joinPath([backupDir.path, name]));
      if (!await backup.exists()) continue;
      await backup.copy(joinPath([profilesDir.path, name]));
    }
  }

  static Future<bool> _confirmDialog(BuildContext context, String message) async {
    return (await _showBlurDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm'),
            content: Text(message),
            actions: [
              _HoverScale(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
              ),
              _HoverScale(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Yes'),
                ),
              ),
            ],
          ),
        )) ??
        false;
  }
}

Future<String?> _promptValue(BuildContext context, String name) async {
  final controller = TextEditingController();
  final result = await _showBlurDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Set value for $name'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Value'),
      ),
      actions: [
        _HoverScale(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ),
        _HoverScale(
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ),
      ],
    ),
  );
  return result?.isEmpty == true ? null : result;
}

Future<void> _showCurveImportSummary(
  BuildContext context,
  Map<String, List<String>> grouped, {
  required List<_ImportCurveDraft> missing,
}) async {
  if (grouped.isEmpty) return;
  final missingKeys = missing.map((entry) => '${entry.pathPart}|||${entry.key}').toSet();
  final labels = <String, Map<String, dynamic>>{};
  for (final entry in grouped.entries) {
    final parts = entry.key.split('|||');
    final key = parts.length > 1 ? parts[1] : entry.key;
    final label = _humanizeCurveKey(key);
    final count = entry.value.length;
    final isNew = missingKeys.contains(entry.key);
    final existing = labels[label];
    if (existing == null) {
      labels[label] = {
        'count': 1,
        'lines': count,
        'isNew': isNew,
      };
    } else {
      labels[label] = {
        'count': (existing['count'] as int) + 1,
        'lines': (existing['lines'] as int) + count,
        'isNew': (existing['isNew'] as bool) || isNew,
      };
    }
  }
  final lines = labels.entries.map((entry) {
    final label = entry.key;
    final count = entry.value['count'] as int;
    final totalLines = entry.value['lines'] as int;
    final isNew = entry.value['isNew'] as bool;
    final countSuffix = count > 1 ? ' ×$count' : '';
    final linesSuffix = totalLines > count ? ' ($totalLines lines)' : '';
    return '${isNew ? "New: " : ""}$label$countSuffix$linesSuffix';
  }).toList();

  await _showBlurDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('CurveTables imported'),
      content: SizedBox(
        width: 320,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${grouped.length} CurveTable${grouped.length == 1 ? '' : 's'} imported.'),
                if (missing.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('New entries: ${missing.length}'),
                ],
                const SizedBox(height: 12),
                for (final line in lines) Text('• $line'),
              ],
            ),
          ),
        ),
      ),
      actions: [
        _HoverScale(
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ),
      ],
    ),
  );
}

class _ParsedCurveLines {
  const _ParsedCurveLines({
    required this.pathPart,
    required this.key,
    required this.lines,
    required this.staticValue,
  });

  final String pathPart;
  final String key;
  final List<String> lines;
  final String staticValue;
}

class _CurveLineParts {
  const _CurveLineParts({
    required this.pathPart,
    required this.key,
    required this.row,
    required this.value,
  });

  final String pathPart;
  final String key;
  final String row;
  final String value;
}

_CurveLineParts? _splitCurveLine(String line) {
  final regex = RegExp('^\\+CurveTable=(.+?);RowUpdate;(.+?);(\\d+);(.+)\$');
  final match = regex.firstMatch(line.trim());
  if (match == null) return null;
  return _CurveLineParts(
    pathPart: match.group(1)!,
    key: match.group(2)!,
    row: match.group(3)!,
    value: match.group(4)!,
  );
}

String _replaceCurveLineValue(String line, String value) {
  final parts = _splitCurveLine(line);
  if (parts == null) return line;
  return '+CurveTable=${parts.pathPart};RowUpdate;${parts.key};${parts.row};$value';
}

_ParsedCurveLines? _parseCurveLines(String raw) {
  final cleaned = raw
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (cleaned.isEmpty) return null;
  String? pathPart;
  String? key;
  String? staticValue;
  for (final line in cleaned) {
    final parts = _splitCurveLine(line);
    if (parts == null) return null;
    final currentPath = parts.pathPart;
    final currentKey = parts.key;
    final value = parts.value;
    pathPart ??= currentPath;
    key ??= currentKey;
    staticValue ??= value;
    if (pathPart != currentPath || key != currentKey) return null;
  }
  return _ParsedCurveLines(
    pathPart: pathPart!,
    key: key!,
    lines: cleaned,
    staticValue: staticValue ?? '0',
  );
}

String _extractLastHotfixBlock(String content) {
  final lines = content.split('\n');
  final assetIndex = lines.indexWhere((line) => line.trim() == '[AssetHotfix]');
  if (assetIndex == -1) return '';
  var lastCommentIndex = -1;
  for (var i = assetIndex + 1; i < lines.length; i++) {
    final trimmed = lines[i].trim();
    if (trimmed.startsWith('#')) {
      lastCommentIndex = i;
    }
  }
  if (lastCommentIndex == -1) return '';
  final buffer = <String>[];
  for (var i = lastCommentIndex + 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().startsWith('#') || line.trim().startsWith('[')) break;
    buffer.add(line);
  }
  return buffer.join('\n');
}

Future<List<CustomCurveInput>?> _promptCustomCurves(
  BuildContext context,
  List<CustomCurveGroupInfo> groups,
) async {
  final drafts = <_CustomCurveDraft>[_CustomCurveDraft()];
  final groupNameController = TextEditingController();
  String? newGroupImagePath;
  String selectedGroupId = '_new';
  String? errorText;

  final result = await _showBlurDialog<List<CustomCurveInput>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Add Custom Curves'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedGroupId,
                  decoration: const InputDecoration(labelText: 'Group'),
                  items: [
                    ...groups.map(
                      (group) => DropdownMenuItem(
                        value: group.id,
                        child: Text(group.name),
                      ),
                    ),
                    const DropdownMenuItem(
                      value: '_new',
                      child: Text('Create new group'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      selectedGroupId = value;
                      errorText = null;
                    });
                  },
                ),
                if (selectedGroupId == '_new') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: groupNameController,
                    decoration: const InputDecoration(labelText: 'Group name'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          newGroupImagePath == null
                              ? 'No group image selected'
                              : newGroupImagePath!.split(Platform.pathSeparator).last,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      _HoverScale(
                        child: TextButton.icon(
                          onPressed: () async {
                            final picked = await FilePicker.platform.pickFiles(type: FileType.image);
                            if (picked == null || picked.files.single.path == null) return;
                            setState(() {
                              newGroupImagePath = picked.files.single.path;
                              errorText = null;
                            });
                          },
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('Choose image'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Curves', style: Theme.of(context).textTheme.titleMedium),
                ),
                const SizedBox(height: 12),
                ...drafts.asMap().entries.map((entry) {
                  final index = entry.key;
                  final draft = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: draft.nameController,
                                  decoration: InputDecoration(labelText: 'Curve name ${index + 1}'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                children: [
                                  const Text('Static'),
                                  Switch(
                                    value: draft.isStatic,
                                    onChanged: (value) => setState(() => draft.isStatic = value),
                                  ),
                                ],
                              ),
                              if (drafts.length > 1)
                                _HoverScale(
                                  child: IconButton(
                                    tooltip: 'Remove curve',
                                    onPressed: () => setState(() => drafts.removeAt(index)),
                                    icon: const Icon(Icons.close),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: draft.linesController,
                            minLines: 3,
                            maxLines: 8,
                            decoration: const InputDecoration(
                              labelText: 'CurveTable line(s)',
                              hintText: '+CurveTable=/Game/...;RowUpdate;Key;0;Value',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _HoverScale(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => drafts.add(_CustomCurveDraft())),
                      icon: const Icon(Icons.add),
                      label: const Text('Add another curve'),
                    ),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(errorText!, style: const TextStyle(color: Colors.redAccent)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          _HoverScale(
            child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ),
          _HoverScale(
            child: ElevatedButton(
              onPressed: () {
              final isNewGroup = selectedGroupId == '_new';
              final groupName = isNewGroup
                  ? groupNameController.text.trim()
                  : groups.firstWhere((group) => group.id == selectedGroupId).name;
              final groupImagePath = isNewGroup
                  ? ''
                  : (groups.firstWhere((group) => group.id == selectedGroupId).imagePath ?? '');
              final groupImageSourcePath = isNewGroup ? (newGroupImagePath ?? '') : '';

              if (isNewGroup && groupName.isEmpty) {
                setState(() => errorText = 'Group name is required.');
                return;
              }
              if (isNewGroup && (newGroupImagePath == null || newGroupImagePath!.trim().isEmpty)) {
                setState(() => errorText = 'Group image is required.');
                return;
              }
              if (drafts.isEmpty) {
                setState(() => errorText = 'Add at least one curve.');
                return;
              }

              final groupId = isNewGroup ? 'custom-${DateTime.now().millisecondsSinceEpoch}' : selectedGroupId;
              final inputs = <CustomCurveInput>[];
              for (final draft in drafts) {
                final curveName = draft.nameController.text.trim();
                if (curveName.isEmpty) {
                  setState(() => errorText = 'Each curve must have a name.');
                  return;
                }
                final parsed = _parseCurveLines(draft.linesController.text);
                if (parsed == null) {
                  setState(() => errorText = 'Enter valid +CurveTable line(s) with matching path/key.');
                  return;
                }
                inputs.add(
                  CustomCurveInput(
                    name: curveName,
                    key: parsed.key,
                    pathPart: parsed.pathPart,
                    lines: parsed.lines,
                    staticValue: parsed.staticValue,
                    isStatic: draft.isStatic,
                    groupId: groupId,
                    groupName: groupName,
                    groupImagePath: groupImagePath,
                    groupImageSourcePath: groupImageSourcePath,
                  ),
                );
              }
              Navigator.pop(context, inputs);
              },
              child: const Text('Add'),
            ),
          ),
        ],
      ),
    ),
  );
  return result;
}

Future<_CustomGroupEditResult?> _promptEditCustomGroup(
  BuildContext context,
  String groupId,
  String groupName,
) async {
  final nameController = TextEditingController(text: groupName);
  String? newImagePath;
  String? errorText;
  final result = await _showBlurDialog<_CustomGroupEditResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Edit Group'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Group name'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      newImagePath == null
                          ? 'No new image selected'
                          : newImagePath!.split(Platform.pathSeparator).last,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _HoverScale(
                    child: TextButton.icon(
                      onPressed: () async {
                        final picked = await FilePicker.platform.pickFiles(type: FileType.image);
                        if (picked == null || picked.files.single.path == null) return;
                        setState(() {
                          newImagePath = picked.files.single.path;
                          errorText = null;
                        });
                      },
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Choose image'),
                    ),
                  ),
                ],
              ),
              if (errorText != null) ...[
                const SizedBox(height: 12),
                Text(errorText!, style: const TextStyle(color: Colors.redAccent)),
              ],
            ],
          ),
        ),
        actions: [
          _HoverScale(
            child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ),
          _HoverScale(
            child: ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setState(() => errorText = 'Group name is required.');
                  return;
                }
                Navigator.pop(
                  context,
                  _CustomGroupEditResult(name: name, imagePath: newImagePath),
                );
              },
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    ),
  );
  return result;
}

Future<_CustomCurveEditResult?> _promptEditCustomCurve(
  BuildContext context,
  CurveEntry entry,
  List<CustomCurveGroupInfo> groups,
) async {
  final nameController = TextEditingController(text: entry.name);
  final linesController = TextEditingController(text: entry.multiLines.join('\n'));
  bool isStatic = entry.type == 'static';
  String selectedGroupId = entry.groupId ?? groups.first.id;
  String? errorText;

  final result = await _showBlurDialog<_CustomCurveEditResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Edit Custom Curve'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedGroupId,
                  decoration: const InputDecoration(labelText: 'Group'),
                  items: groups
                      .map(
                        (group) => DropdownMenuItem(
                          value: group.id,
                          child: Text(group.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      selectedGroupId = value;
                      errorText = null;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Curve name'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Static'),
                    const SizedBox(width: 12),
                    Switch(
                      value: isStatic,
                      onChanged: (value) => setState(() => isStatic = value),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: linesController,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'CurveTable line(s)',
                    hintText: '+CurveTable=/Game/...;RowUpdate;Key;0;Value',
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(errorText!, style: const TextStyle(color: Colors.redAccent)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          _HoverScale(
            child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ),
          _HoverScale(
            child: ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setState(() => errorText = 'Curve name is required.');
                  return;
                }
                final parsed = _parseCurveLines(linesController.text);
                if (parsed == null) {
                  setState(() => errorText = 'Enter valid +CurveTable line(s) with matching path/key.');
                  return;
                }
                final groupInfo = groups.firstWhere((group) => group.id == selectedGroupId);
                Navigator.pop(
                  context,
                  _CustomCurveEditResult(
                    name: name,
                    lines: parsed.lines,
                    staticValue: parsed.staticValue,
                    isStatic: isStatic,
                    key: parsed.key,
                    pathPart: parsed.pathPart,
                    groupId: groupInfo.id,
                    groupName: groupInfo.name,
                    groupImagePath: groupInfo.imagePath,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    ),
  );
  return result;
}

Future<CustomCurveGroupInfo?> _promptCreateCustomGroup(BuildContext context) async {
  final nameController = TextEditingController();
  String? imagePath;
  String? errorText;
  final result = await _showBlurDialog<CustomCurveGroupInfo>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Create Group'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Group name'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      imagePath == null ? 'No image selected' : imagePath!.split(Platform.pathSeparator).last,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _HoverScale(
                    child: TextButton.icon(
                      onPressed: () async {
                        final picked = await FilePicker.platform.pickFiles(type: FileType.image);
                        if (picked == null || picked.files.single.path == null) return;
                        setState(() {
                          imagePath = picked.files.single.path;
                          errorText = null;
                        });
                      },
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Choose image'),
                    ),
                  ),
                ],
              ),
              if (errorText != null) ...[
                const SizedBox(height: 12),
                Text(errorText!, style: const TextStyle(color: Colors.redAccent)),
              ],
            ],
          ),
        ),
        actions: [
          _HoverScale(
            child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ),
          _HoverScale(
            child: ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setState(() => errorText = 'Group name is required.');
                  return;
                }
                if (imagePath == null || imagePath!.trim().isEmpty) {
                  setState(() => errorText = 'Group image is required.');
                  return;
                }
                Navigator.pop(
                  context,
                  CustomCurveGroupInfo(
                    id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    imagePath: imagePath,
                  ),
                );
              },
              child: const Text('Create'),
            ),
          ),
        ],
      ),
    ),
  );
  return result;
}

Future<List<CustomCurveInput>?> _promptImportMissingCurves(
  BuildContext context,
  List<_ImportCurveDraft> missing,
  List<CustomCurveGroupInfo> groups,
) async {
  String? errorText;
  final groupOptions = [...groups];
  if (!groupOptions.any((group) => group.id == 'other')) {
    groupOptions.add(const CustomCurveGroupInfo(id: 'other', name: 'Other', imagePath: null));
  }
  if (groupOptions.isNotEmpty) {
    for (final draft in missing) {
      draft.selectedGroupId = '';
    }
  }

  final result = await _showBlurDialog<List<CustomCurveInput>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Name Imported Curves'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...missing.map((draft) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(draft.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(
                            draft.pathPart,
                            style: TextStyle(fontSize: 12, color: _onSurface(context, 0.7)),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: draft.nameController,
                            decoration: const InputDecoration(labelText: 'Curve name'),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: draft.selectedGroupId.isEmpty ? null : draft.selectedGroupId,
                            decoration: const InputDecoration(labelText: 'Group'),
                            items: [
                              ...groupOptions.map(
                                (group) => DropdownMenuItem(
                                  value: group.id,
                                  child: Text(group.name),
                                ),
                              ),
                              const DropdownMenuItem(
                                value: '__new__',
                                child: Text('Create new group'),
                              ),
                            ],
                            onChanged: (value) async {
                              if (value == null) return;
                              if (value == '__new__') {
                                final newGroup = await _promptCreateCustomGroup(context);
                                if (newGroup != null) {
                                  setState(() {
                                    groupOptions.add(newGroup);
                                    draft.selectedGroupId = newGroup.id;
                                  });
                                }
                                return;
                              }
                              setState(() => draft.selectedGroupId = value);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(errorText!, style: const TextStyle(color: Colors.redAccent)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          _HoverScale(
            child: OutlinedButton(
              onPressed: () {
                final inputs = <CustomCurveInput>[];
                for (final draft in missing) {
                  final name = _humanizeCurveKey(draft.key);
                  final group = groupOptions.firstWhere((g) => g.id == 'other');
                  inputs.add(
                    CustomCurveInput(
                      name: name,
                      key: draft.key,
                      pathPart: draft.pathPart,
                      lines: draft.lines,
                      staticValue: draft.staticValue,
                      isStatic: false,
                      groupId: group.id,
                      groupName: group.name,
                      groupImagePath: '',
                      groupImageSourcePath: '',
                    ),
                  );
                }
                Navigator.pop(context, inputs);
              },
              child: const Text('Continue without naming'),
            ),
          ),
          _HoverScale(
            child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ),
          _HoverScale(
            child: ElevatedButton(
              onPressed: () {
                final inputs = <CustomCurveInput>[];
                for (final draft in missing) {
                  final name = draft.nameController.text.trim().isEmpty
                      ? _humanizeCurveKey(draft.key)
                      : draft.nameController.text.trim();
                  final groupId = draft.selectedGroupId.isEmpty ? 'other' : draft.selectedGroupId;
                  final group = groupOptions.firstWhere((g) => g.id == groupId);
                  final groupImageSourcePath =
                      (group.imagePath != null && File(group.imagePath!).existsSync()) ? group.imagePath! : '';
                  final groupImagePath = groupImageSourcePath.isEmpty ? (group.imagePath ?? '') : '';
                  inputs.add(
                    CustomCurveInput(
                      name: name,
                      key: draft.key,
                      pathPart: draft.pathPart,
                      lines: draft.lines,
                      staticValue: draft.staticValue,
                      isStatic: false,
                      groupId: group.id,
                      groupName: group.name,
                      groupImagePath: groupImagePath,
                      groupImageSourcePath: groupImageSourcePath,
                    ),
                  );
                }
                Navigator.pop(context, inputs);
              },
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    ),
  );
  return result;
}

class BackendController extends ChangeNotifier {
  BackendController() {
    _logStore.clear();
  }

  Process? _process;
  Timer? _pollTimer;
  bool isRunning = false;
  bool isStarting = false;
  bool isStopping = false;
  bool isRestarting = false;
  String _statusText = 'Offline';
  Color _statusColor = Colors.redAccent;
  final LogStore _logStore = LogStore.instance;

  String get statusText => _statusText;
  Color get statusColor => _statusColor;
  List<String> get recentLogs => _logStore.recentLogs;
  List<String> get allLogs => _logStore.allLogs;
  String get activeProfilesLabel => '28';
  String get exportsLabel => '1,024 files';
  String get lastSyncLabel => '2 minutes ago';

  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkBackend());
    _checkBackend();
  }

  Future<void> ensureStoppedOnLaunch() async {
    final ok = await _pingBackend();
    if (!ok) return;
    _addLog('Backend detected on launch. Stopping until Start is pressed.');
    await _killBackendOnPort(3551);
    isRunning = false;
    _setStatus('Offline', Colors.redAccent);
    notifyListeners();
  }

  Future<void> startBackend() async {
    if (isStarting || isRestarting) return;
    if (isRunning && _process != null) return;
    if (!isRunning && _process != null) {
      _process = null;
    }
    isStarting = true;
    _logStore.clear();
    _setStatus('Starting...', Colors.orangeAccent);
    _addLog('Starting backend...');
    notifyListeners();

    final backendRoot = getBackendRoot();
    final bunPath = _resolveBunPath(backendRoot);
    final bunAvailable = await _checkBunAvailable(backendRoot, bunPath);
    if (!bunAvailable) {
      _addLog('Bun not found. Install Bun or include tools\\bun\\bun.exe.');
      isStarting = false;
      _setStatus('Bun missing', Colors.redAccent);
      notifyListeners();
      return;
    }

    final nodeModules = Directory('$backendRoot/node_modules');
    if (!nodeModules.existsSync()) {
      _addLog('Installing dependencies (bun install)...');
      final install = await Process.run(
        bunPath ?? 'bun',
        ['install'],
        workingDirectory: backendRoot,
      );
      if (install.exitCode != 0) {
        _addLog('Dependency install failed: ${install.stderr}');
        isStarting = false;
        _setStatus('Install failed', Colors.redAccent);
        notifyListeners();
        return;
      }
      _addLog('Dependencies installed.');
    }

    final config = await ConfigService.load();
    final env = Map<String, String>.from(Platform.environment);
    if (config.disableBackendUpdateCheck) {
      env['ATLAS_DISABLE_UPDATE_CHECK'] = '1';
    }

    try {
      _process = await Process.start(
        bunPath ?? 'bun',
        ['run', 'src/index.ts'],
        workingDirectory: backendRoot,
        environment: env,
        mode: ProcessStartMode.detachedWithStdio,
      );
      isRunning = false;
      isStarting = false;
      _setStatus('Starting...', Colors.orangeAccent);
      notifyListeners();
      try {
        _process?.stdout.transform(utf8.decoder).listen(_addLog);
        _process?.stderr.transform(utf8.decoder).listen(_addLog);
      } catch (_) {
        // Detached process may not expose stdio on some platforms.
      }
      _process?.exitCode.then((code) {
        _addLog('Backend exited with code $code');
        isRunning = false;
        isStarting = false;
        _setStatus('Offline', Colors.redAccent);
        notifyListeners();
      });
    } catch (error) {
      if (_process != null) {
        _addLog('Backend started with limited process access: $error');
        isRunning = false;
        isStarting = false;
        _setStatus('Starting...', Colors.orangeAccent);
        notifyListeners();
      } else {
        _addLog('Failed to start backend: $error');
        isRunning = false;
        isStarting = false;
        _setStatus('Start failed', Colors.redAccent);
        notifyListeners();
      }
    }
  }

  Future<void> stopBackend() async {
    if (isStopping) return;
    isStopping = true;
    _setStatus('Stopping...', Colors.orangeAccent);
    _addLog('Stopping backend...');
    notifyListeners();

    final process = _process;
    if (process == null) {
      _addLog('No active process found.');
      await _killBackendOnPort(3551);
      isStopping = false;
      _setStatus('Offline', Colors.redAccent);
      notifyListeners();
      return;
    }

    final pid = process.pid;
    bool exited = false;
    try {
      process.kill(ProcessSignal.sigterm);
      await process.exitCode.timeout(const Duration(seconds: 4));
      exited = true;
    } catch (_) {
      exited = false;
    }

    if (!exited) {
      await Process.run('taskkill', ['/PID', pid.toString(), '/T', '/F']);
      try {
        await process.exitCode.timeout(const Duration(seconds: 4));
      } catch (_) {}
    }

    _process = null;
    await _killBackendOnPort(3551);
    isStopping = false;
    isRunning = false;
    _setStatus('Offline', Colors.redAccent);
    notifyListeners();
  }

  Future<void> restartBackend() async {
    if (isRestarting || isStarting || isStopping) return;
    isRestarting = true;
    _logStore.clear();
    _setStatus('Restarting...', Colors.orangeAccent);
    _addLog('Restarting backend...');
    notifyListeners();

    await stopBackend();
    await Future.delayed(const Duration(seconds: 1));
    isRestarting = false;
    notifyListeners();
    await startBackend();

    isRestarting = false;
    notifyListeners();
  }

  Future<void> _checkBackend() async {
    final ok = await _pingBackend();
    if (ok && !isRunning) {
      isRunning = true;
      _setStatus('Running', Colors.greenAccent);
      notifyListeners();
    } else if (!ok && isRunning && !isStarting) {
      isRunning = false;
      _setStatus('Offline', Colors.redAccent);
      notifyListeners();
    }
  }

  Future<bool> _pingBackend() async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:3551/unknown'));
      final response = await request.close().timeout(const Duration(seconds: 2));
      client.close();
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkBunAvailable(String workingDirectory, String? bunPath) async {
    if (bunPath != null) {
      return File(bunPath).existsSync();
    }
    try {
      final result = await Process.run('bun', ['--version'], workingDirectory: workingDirectory);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> _killBackendOnPort(int port) async {
    if (!Platform.isWindows) return;
    try {
      final result = await Process.run('netstat', ['-ano']);
      if (result.exitCode != 0) return;
      final lines = result.stdout.toString().split('\n');
      final pids = <int>{};
      for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 5) continue;
        final localAddress = parts[1];
        if (!localAddress.endsWith(':$port')) continue;
        final pid = int.tryParse(parts.last);
        if (pid != null && pid > 0) {
          pids.add(pid);
        }
      }
      for (final pid in pids) {
        await Process.run('taskkill', ['/PID', pid.toString(), '/T', '/F']);
      }
    } catch (_) {
      // Ignore failures; status will reflect actual backend state on next poll.
    }
  }

  void _setStatus(String text, Color color) {
    _statusText = text;
    _statusColor = color;
  }

  void _addLog(String log) {
    final sanitized = log.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
    final lines = sanitized
        .trim()
        .split('\n')
        .where((line) => _shouldIncludeLog(line))
        .toList();
    if (lines.isEmpty) return;
    final timestampPattern = RegExp(r'\s+-\s+\d{1,2}:\d{2}:\d{2}\s+(AM|PM)\s+\S+$');
    _logStore.addOrReplaceLines(
      lines,
      (line) => line.replaceFirst(timestampPattern, '').trimRight(),
    );
    notifyListeners();
  }

  Future<void> forceKillBackendPort() async {
    await _killBackendOnPort(3551);
  }

  bool _shouldIncludeLog(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.contains('[BACKEND]') || trimmed.contains('[MATCHMAKING]')) return true;
    return false;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

String getBackendRoot() {
  final candidates = <Directory>[
    Directory.current,
    Directory.current.parent,
    Directory(File(Platform.resolvedExecutable).parent.path),
    Directory(File(Platform.resolvedExecutable).parent.parent.path),
  ];

  for (final start in candidates) {
    var current = start;
    while (true) {
      final staticDir = Directory(joinPath([current.path, 'static']));
      final srcDir = Directory(joinPath([current.path, 'src']));
      if (staticDir.existsSync() && srcDir.existsSync()) {
        return current.path;
      }
      if (current.parent.path == current.path) {
        break;
      }
      current = current.parent;
    }
  }
  return Directory.current.path;
}

String joinPath(List<String> parts) {
  return parts.join(Platform.pathSeparator);
}

String? _resolveBunPath(String backendRoot) {
  final candidates = [
    joinPath([backendRoot, 'tools', 'bun', 'bun.exe']),
    joinPath([backendRoot, 'tools', 'bun', 'bun']),
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

String? _resolveBackgroundPath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return null;
  final direct = File(trimmed);
  if (direct.existsSync()) return direct.path;
  final backendRoot = getBackendRoot();
  final relative = File(joinPath([backendRoot, trimmed]));
  if (relative.existsSync()) return relative.path;
  final publicImage = File(joinPath([backendRoot, 'public', 'images', trimmed]));
  if (publicImage.existsSync()) return publicImage.path;
  return null;
}
