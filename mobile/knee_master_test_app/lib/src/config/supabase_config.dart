abstract final class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://clnvkxcxgorkyosauigb.supabase.co',
  );
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_x21Q5PzXWqSkMeo8MQKAbQ_ROKtkn2A',
  );

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
