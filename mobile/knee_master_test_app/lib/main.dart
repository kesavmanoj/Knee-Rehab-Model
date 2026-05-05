import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'src/auth/auth_repository.dart';
import 'src/config/supabase_config.dart';
import 'src/repositories/doctor_repository.dart';
import 'src/repositories/profile_repository.dart';
import 'src/repositories/session_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!SupabaseConfig.isConfigured) {
    runApp(const _SupabaseConfigMissingApp());
    return;
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  final client = Supabase.instance.client;
  runApp(
    KneeMasterTestApp(
      authRepository: AuthRepository(client),
      sessionRepository: SessionRepository(client),
      doctorRepository: DoctorRepository(client),
      profileRepository: ProfileRepository(client),
    ),
  );
}

class _SupabaseConfigMissingApp extends StatelessWidget {
  const _SupabaseConfigMissingApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Supabase configuration missing',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Run the app with both of these dart defines:',
                        ),
                        SizedBox(height: 12),
                        SelectableText(
                          '--dart-define=SUPABASE_URL=your-project-url',
                        ),
                        SelectableText(
                          '--dart-define=SUPABASE_ANON_KEY=your-anon-key',
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
