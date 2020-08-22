import 'package:dcli/dcli.dart';

import '../../../nginx_le_shared.dart';
import '../auth_provider.dart';

abstract class GenericAuthProvider extends AuthProvider {
  /// over load this method to do any checks before the acquire method is run.
  void pre_auth() {}

  ///
  /// Acquires a Certbot certificate using DNS Auth.
  ///
  /// This class is designed to work with any DNS Provider that works via
  /// a manual auth hook and cleanup.
  ///
  /// It use the following environment variables to configure the auth
  ///
  /// ```dart
  ///  var emailaddress = Environment().emailaddress;
  ///  var hostname = Environment().hostname;
  ///  var domain = Environment().domain;
  ///  var staging = Environment().staging;
  ///
  ///  var auth_hook_path = Environment().certbotDNSAuthHookPath;
  ///  var cleanup_hook_path = Environment().certbotDNSCleanupHookPath;
  ///  ```
  @override
  void acquire() {
    var workDir = _createDir(Certbot.letsEncryptWorkPath);
    var logDir = _createDir(Certbot.letsEncryptLogPath);
    var configDir = _createDir(Certbot.letsEncryptConfigPath);

    /// Pass environment vars down to the auth hook.
    Environment().logfile = join(logDir, 'letsencrypt.log');

    var emailaddress = Environment().emailaddress;
    var hostname = Environment().hostname;
    var domain = Environment().domain;
    var staging = Environment().staging;

    var auth_hook_path = Environment().certbotDNSAuthHookPath;
    var cleanup_hook_path = Environment().certbotDNSCleanupHookPath;

    ArgumentError.checkNotNull(auth_hook_path, 'Environment variable: CERTBOT_DNS_AUTH_HOOK_PATH missing');
    ArgumentError.checkNotNull(cleanup_hook_path, 'Environment variable: CERTBOT_DNS_CLEANUP_HOOK_PATH missing');

    var certbot = 'certbot certonly '
        ' --manual '
        ' --preferred-challenges=dns '
        ' -m $emailaddress  '
        ' -d $hostname.$domain '
        ' --agree-tos '
        ' --manual-public-ip-logging-ok '
        ' --non-interactive '
        ' --manual-auth-hook="$auth_hook_path" '
        ' --manual-cleanup-hook="$cleanup_hook_path" '
        ' --work-dir=$workDir '
        ' --config-dir=$configDir '
        ' --logs-dir=$logDir ';

    if (staging) certbot += ' --staging ';

    var lines = <String>[];
    var progress = Progress((line) {
      print(line);
      lines.add(line);
    }, stderr: (line) {
      printerr(line);
      lines.add(line);
    });

    certbot.start(runInShell: true, nothrow: true, progress: progress);

    if (progress.exitCode != 0) {
      var system = 'hostname'.firstLine;

      throw CertbotException('certbot failed acquiring a certificate for $hostname.$domain on $system',
          details: lines.join('\n'));
    }
  }

  String _createDir(String dir) {
    if (!exists(dir)) {
      createDir(dir, recursive: true);
    }
    return dir;
  }
}
