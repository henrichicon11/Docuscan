import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/shell.dart';
import 'state/app_state.dart';
import 'theme/tokens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const DocuScanApp());
}

class DocuScanApp extends StatelessWidget {
  const DocuScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>(
      create: (_) => AppState()..init(),
      child: Consumer<AppState>(
        builder: (context, state, _) {
          final mode = switch (state.themeMode) {
            1 => ThemeMode.light,
            2 => ThemeMode.dark,
            _ => ThemeMode.system,
          };
          return MaterialApp(
            title: 'DocuScan Pro',
            debugShowCheckedModeBanner: false,
            themeMode: mode,
            theme: AppTheme.build(Brightness.light),
            darkTheme: AppTheme.build(Brightness.dark),
            scrollBehavior: const _SmoothScroll(),
            builder: (context, child) {
              // Clamp text scaling so the editorial layout never breaks.
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(
                  textScaler: TextScaler.linear(
                    mq.textScaler.scale(1.0).clamp(0.85, 1.25),
                  ),
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const Shell(),
          );
        },
      ),
    );
  }
}

class _SmoothScroll extends MaterialScrollBehavior {
  const _SmoothScroll();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: RangeMaintainingScrollPhysics());
}
