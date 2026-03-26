import 'build_config.dart';

/// 所有 Flutter 端對外 URL 的統一管理點。
///
/// 根網域由 [kDomainBase]（`--dart-define=DOMAIN_BASE`）控制，
/// 只需在 GitHub Variables 設定 `DOMAIN_BASE` 即可切換環境，無需改程式碼。
abstract final class AppUrls {
  AppUrls._();

  /// App 下載 / 分享落地頁（分享功能的降級 URL）
  static const String download = '$kDomainBase/download';

  /// 隱私政策頁面（乾淨 URL，由 Firebase Hosting rewrite 對應至 privacy.html）
  static const String privacy = '$kDomainBase/privacy';

  /// Deep Link 分享路徑前綴（挑戰碼落地頁：$shareBase/{code}）
  static const String shareBase = '$kDomainBase/c';
}
