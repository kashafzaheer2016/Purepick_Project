import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app_router.dart';
import 'design/pp.dart';
import 'theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await ThemeProvider.initialize();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const PurePickApp());
}

class PurePickApp extends StatelessWidget {
  const PurePickApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeProvider.instance,
      builder: (_, isDark, __) => MaterialApp(
        title: 'PurePick',
        debugShowCheckedModeBanner: false,
        theme:      PP.lightTheme,
        darkTheme:  PP.darkTheme,
        themeMode:  isDark ? ThemeMode.dark : ThemeMode.light,
        onGenerateRoute: AppRouter.onGenerateRoute,
        initialRoute: AppRouter.welcome,
      ),
    );
  }
}
