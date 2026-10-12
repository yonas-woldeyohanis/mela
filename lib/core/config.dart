class AppConfig {
  static const _defaultSupabaseUrl = 'https://fqpnavzfujxqcskmwqgi.supabase.co';
  static const _defaultSupabaseAnonKey = 'sb_publishable_owtgamWMx2VEcVa2XI8A9w_cCZY0ang';

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: _defaultSupabaseUrl);
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: _defaultSupabaseAnonKey);
  static bool get configured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static const currency = 'ETB';
  static const receiptsBucket = 'receipts';
  static const retentionDays = 7;
  static const purged = 'PURGED_AFTER_AUDIT';
  static const maxImageBytes = 100 * 1024;

  static const providers = [
    'Telebirr', 'CBE Birr', 'CBE', 'Awash', 'Dashen', 'Abyssinia', 'M-Pesa',
    'Zemen', 'Wegagen', 'Hibret', 'Nib', 'Oromia', 'Coopay', 'Other',
  ];
}
