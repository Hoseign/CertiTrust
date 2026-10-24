class AppConfig {
  static const String productionApiUrl =
      'https://certitrust-yhzl.onrender.com/api';
  static const String _apiUrlOverride =
      String.fromEnvironment('CERTITRUST_API_URL');
  static String get apiBaseUrl =>
      _apiUrlOverride.isEmpty ? productionApiUrl : _apiUrlOverride;

  // Supabase Configuration
  static const String supabaseUrl = 'https://iyihdmwblpxriuoxfrys.supabase.co';
  static const String supabasePublishableKey =
      'sb_publishable_8CWcmw0xfJch5y-TwTfz3w_PcMPXaMh';

  // Ethereum Sepolia testnet configuration; blockchain requests use the Laravel API.
  static const String ethereumSepoliaRpcUrl =
      'https://rpc.sepolia.org';
  static const int ethereumSepoliaChainId = 11155111;

  // Smart Contract Configuration
  static const String contractAddress =
      '0xE19411e7df13f0b11d86d629b044c534b453af15';

  // Domain Configuration
  static const String liveDemoDomain = 'https://certitrust-verify.vercel.app';
  static const String productionTargetDomain = 'https://certitrust.ucu.edu.ph';
}
