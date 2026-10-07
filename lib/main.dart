import 'package:flutter/material.dart';
import 'core/session.dart';
import 'features/client/client_shell.dart';
import 'features/staff/staff_shell.dart';
import 'shared/ui.dart';

void main() {
  runApp(const SmartStayApp());
}

class SmartStayApp extends StatelessWidget {
  const SmartStayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartStay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kPrimary, brightness: Brightness.light),
        useMaterial3: true,
        scaffoldBackgroundColor: kSurface,
        fontFamily: 'Arial',
        textTheme: ThemeData.light().textTheme.apply(bodyColor: kSecondary, displayColor: kSecondary),
        appBarTheme: const AppBarTheme(
          backgroundColor: kSurface,
          foregroundColor: kSecondary,
          centerTitle: false,
          elevation: 0,
          surfaceTintColor: kSurface,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: kPrimary, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(backgroundColor: kPrimary),
        ),
      ),
      home: const StartupGate(),
    );
  }
}

class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late final Future<void> _future;

  @override
  void initState() {
    super.initState();
    _future = _restore();
  }

  Future<void> _restore() async {
    await SessionStore.restore();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: LoadingView(message: 'Preparando tu estadía...'));
        }
        return homeFor(const ClientShell());
      },
    );
  }
}
