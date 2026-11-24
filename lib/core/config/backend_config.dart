class BackendConfig {
  const BackendConfig._();

  static const supabaseUrl = String.fromEnvironment(
    'EDUFLOW_SUPABASE_URL',
    defaultValue: 'https://ubjmdfwkjgblnjgmufpc.supabase.co',
  );

  static const supabasePublishableKey = String.fromEnvironment(
    'EDUFLOW_SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_DmUj02VfZSkZOzoR11oq5A_TumX6rfA',
  );

  static String get supabaseProjectRef {
    final host = Uri.tryParse(supabaseUrl)?.host ?? '';
    final separator = host.indexOf('.');
    return separator <= 0 ? '' : host.substring(0, separator);
  }
}
