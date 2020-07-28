import 'dart:io';

import 'package:cron/cron.dart';
import 'package:dshell/dshell.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart';

import 'dns_auth.dart';
import 'http_auth.dart';

class Certbot {
  static const LETSENCRYPT_ROOT_ENV = 'LETSENCRYPT_ROOT_ENV';

  /// The directory where lets encrypt stores its certificates.
  /// As we need to persist certificates between container restarts
  /// the LETSENCRYPT_ROOT path is mounted to a persistent volume on start up.
  /// CERTIFICATE_PATH MUST be on a persistent volume so we don't loose the
  /// certificates each time we restart nginx.
  static const LETSENCRYPT_ROOT = '/etc/letsencrypt';
  static const CERTIFICATE_PATH = 'config/live';

  /// The directory where nginx loads its certificates from.
  static const NGINX_CERT_ROOT = '/etc/nginx/certs/';
  static const NGINX_CERT_ROOT_OVERWRITE = 'NGINX_CERT_ROOT_OVERWRITE';

  /// The file containing the concatenated certs.
  static const CERTIFICATES_FILE = 'fullchain.pem';

  /// our private key.
  static const PRIVATE_KEY_FILE = 'privkey.pem';

  /// The name of the logfile that certbot writes to.
  /// We also write our log messages to this file.
  static const LOG_FILE_NAME = 'letsencrypt.log';

  static const LIVE_WWW_PATH = '/etc/nginx/live';

  static final Certbot _self = Certbot._internal();
  factory Certbot() => _self;

  /// The certbot log file
  String get logfile => join(letsEncryptLogPath, LOG_FILE_NAME);
  Certbot._internal() {
    Settings().verbose('Logging to $logfile');

    if (!exists(letsEncryptLogPath)) {
      createDir(letsEncryptLogPath, recursive: true);
    }

    if (!exists(letsEncryptWorkPath)) {
      createDir(letsEncryptWorkPath, recursive: true);
    }

    if (!exists(letsEncryptConfigPath)) {
      createDir(letsEncryptConfigPath, recursive: true);
    }
    // logfile = env('LOG_FILE');

    // ArgumentError.checkNotNull(logfile, 'The environment variable "LOG_FILE" must be set to the path of the logfile');
  }

  /// Check that we have valid certificates and deploys them to nginx.
  ///
  /// If we have no certificates then we force nginx into acquire mode.
  ///
  /// The certificates are stored in a persistant volume called 'certificates'
  /// and we need to copy them into /etc/nginx/certs on each start
  /// so that nginx has access to them.
  ///
  void deployCertificates(
      {@required String hostname,
      @required String domain,
      bool revoking = false,
      bool reload = true}) {
    var hasValidCerts = false;

    if (!revoking) {
      if (!exists(getCertificateFullChainPath(hostname, domain))) {
        printerr(
            "ERROR: The Certfifcate for $hostname.$domain don't exist. Please run 'certbot'");
      } else {
        if (hasExpired(hostname, domain)) {
          printerr(
              "ERROR The Certificate for $hostname.$domain has expired. Please run 'start certbot");
        } else {
          hasValidCerts = true;
        }
      }
    }

    if (exists(LIVE_WWW_PATH)) {
      deleteSymlink(LIVE_WWW_PATH);
    }

    if (hasValidCerts) {
      /// symlink the user's custom content.
      symlink('/etc/nginx/custom', LIVE_WWW_PATH);
      _deploy(hostname, domain);
    } else {
      printerr('*' * 90);
      printerr(
          "Nginx-LE is starting in 'Certificate Acquisition' mode. It will only respond to CertBot validation requests.");
      printerr('*' * 90);

      /// symlink in the http configs which only permit certbot access
      symlink('/etc/nginx/acquire', LIVE_WWW_PATH);
    }

    if (reload) {
      reloadNginx();
    }
  }

  /// Used more for testing, but essentially deletes any existing certificates
  /// and places the system into acquire mode.
  /// Could also be used to play with and remove staging certificates
  void revoke(
      {@required String hostname,
      @required String domain,
      bool staging = false}) {
    var workDir = _createDir(Certbot.letsEncryptWorkPath);
    var logDir = _createDir(Certbot.letsEncryptLogPath);
    var configDir = _createDir(Certbot.letsEncryptConfigPath);

    var cmd = 'certbot revoke'
        ' --cert-path ${join(_latestCertificatePath(hostname, domain), 'cert.pem')}'
        ' --non-interactive '
        ' --work-dir=$workDir '
        ' --config-dir=$configDir '
        ' --logs-dir=$logDir ';

    if (staging) cmd += ' --staging ';

    cmd.start(
        runInShell: true,
        nothrow: true,
        progress:
            Progress((line) => print(line), stderr: (line) => printerr(line)));

    _delete(hostname, domain);
  }

  /// used by revoke to delete certificates after they have been revoked
  /// If we don't do this then the revoked certificates will still be renewed.
  void _delete(String hostname, String domain) {
    var workDir = _createDir(Certbot.letsEncryptWorkPath);
    var logDir = _createDir(Certbot.letsEncryptLogPath);
    var configDir = _createDir(Certbot.letsEncryptConfigPath);

    var cmd = 'certbot delete'
        ' --cert-name $hostname.$domain'
        ' --non-interactive '
        ' --work-dir=$workDir '
        ' --config-dir=$configDir '
        ' --logs-dir=$logDir ';

    cmd.start(
        runInShell: true,
        nothrow: true,
        progress:
            Progress((line) => print(line), stderr: (line) => printerr(line)));
  }

  /// Returns the path where lets encrypt certificates are stored.
  /// see [nginxCertPath] for the location where nginx loads
  /// the certificates from.
  String getCertificateStoragePath(String hostname, String domain) {
    return join(letsEncryptRootPath, CERTIFICATE_PATH, '$hostname.$domain');
  }

  static String get letsEncryptRootPath {
    /// allow the root to be over-ridden to make testing easier.
    // ignore: unnecessary_cast
    var root = env(LETSENCRYPT_ROOT_ENV) as String;
    if (root == null) {
      return LETSENCRYPT_ROOT;
    } else {
      return root;
    }
  }

  static String get letsEncryptWorkPath {
    return join(letsEncryptRootPath, 'work');
  }

  static String get letsEncryptLogPath {
    return join(letsEncryptRootPath, 'logs');
  }

  static String get letsEncryptConfigPath {
    return join(letsEncryptRootPath, 'config');
  }

  /// The path to the fullchain.pem file.
  String getCertificateFullChainPath(String hostname, String domain) {
    return join(getCertificateStoragePath(hostname, domain), CERTIFICATES_FILE);
  }

  /// The path to the privatekey.pem file.
  String getPrivateKeyPath(String hostname, String domain) {
    return join(getCertificateStoragePath(hostname, domain), PRIVATE_KEY_FILE);
  }

  /// Checks if the certificate for the given hostname.domain
  /// has expired
  bool hasExpired(String hostname, String domain) {
    var hasExpired = true;

    var lines = certificates();

    var found = false;
    for (var line in lines) {
      if (line.trim().startsWith('Expiry Date')) {
        found = true;
        var parts = line.trim().split(RegExp(r'\s+'));

        var dateString = parts[2];

        var year = int.parse(dateString.substring(0, 4));
        var month = int.parse(dateString.substring(5, 7));
        var day = int.parse(dateString.substring(8, 10));
        // not working in a unit tests?
        // var format = DateFormat(dateString, 'yyyy-MM-dd');
        // var expiryDate = format.parse(dateString);
        var expiryDate = DateTime(year, month, day);

        if (!expiryDate.isAfter(DateTime.now().subtract(Duration(days: 1)))) ;
        {
          // we are not yet expired
          hasExpired = false;
          break;
        }
      }
    }

    if (!found) {
      throw CertbotException(
          'Unable to find the Expiry Date for $hostname.$domain');
    }

    return hasExpired;
  }

  /// Obtain the list of active certificates
  List<String> certificates() {
    var cmd = 'certbot certificates '
        ' --config-dir=${Certbot.letsEncryptConfigPath}';

    var lines = cmd.toList(nothrow: true);
    return lines;
  }

  /// Renews or gets for the first time the certificates
  /// for the given [hostname].[domain]
  /// If [debug] is true then only a staging certificate will be requested.
  void acquire({
    @required String hostname,
    @required String domain,
    @required String tld,
    @required String emailaddress,
    @required String mode,
    bool staging = false,
    bool debug = true,
  }) {
    /// first determine the method based on whether we are in public or private mode

    if (mode.toLowerCase() == 'public') {
      http_auth_acquire(
          hostname: hostname,
          domain: domain,
          tld: tld,
          emailaddress: emailaddress,
          staging: staging,
          debug: debug);
    } else {
      dns_auth_acquire(
          hostname: hostname,
          domain: domain,
          tld: tld,
          emailaddress: emailaddress,
          staging: staging,
          debug: debug);
    }
  }

  void scheduleRenews() {
    var cron = Cron();
    cron.schedule(Schedule.parse('*/3 * * * *'), () async {
      renew();
    });
  }

  void renew() {
    'certbot renew '
            ' --work-dir=${Certbot.letsEncryptWorkPath}'
            ' --config-dir=${Certbot.letsEncryptConfigPath}'
            ' --logs-dir=${Certbot.letsEncryptLogPath}'
        .run;
  }

  void log(String message) {
    logfile.append(message);
  }

  void logError(String message) {
    logfile.append('*' * 80);
    logfile.append('*');
    logfile.append('*    ERROR: $message');
    logfile.append('*');
    logfile.append('*' * 80);
  }

  void _deploy(String hostname, String domain) {
    var certpath = _latestCertificatePath(hostname, domain);

    /// we need to leave the original files in place as they form part
    /// of the letsencrypt archive
    copy(join(certpath, 'fullchain.pem'), '/tmp/fullchain.pem',
        overwrite: true);
    copy(join(certpath, 'privkey.pem'), '/tmp/privkey.pem', overwrite: true);

    /// but we need to move them in place using move so that
    /// the replace is essentially atomic so that nginx does see partially
    /// created certificates.
    move('/tmp/fullchain.pem', join(nginxCertPath, 'fullchain.pem'),
        overwrite: true);
    move('/tmp/privkey.pem', join(nginxCertPath, 'privkey.pem'),
        overwrite: true);
  }

  void reloadNginx() {
    if (exists('/var/run/nginx.pid')) {
      /// force nginx to reload its config.
      'nginx -s reload'.run;
    } else {
      Settings().verbose('Nginx reload ignored as nginx is not running');
    }
  }

  static String get nginxCertPath {
    var path = env('NGINX_CERT_ROOT_OVERWRITE');

    path ??= NGINX_CERT_ROOT;
    return path;
  }

  /// Each time certbot creates a new certificate (excluding  the first one)
  ///  it places it in a 'number' path.
  ///
  /// In order of acquistion
  /// conifg/live/<fqdn>
  /// conifg/live/<fqdn-001>
  /// conifg/live/<fqdn-002>
  String _latestCertificatePath(String hostname, String domain) {
    var livepath = join(Certbot.letsEncryptConfigPath, 'live');
    // if no paths contain '-' then the base fqdn path is correct.
    var latest = join(livepath, '$hostname.$domain');

    /// find all the dirs that begin with <fqdn> in the live directory.
    var paths = find('$hostname.$domain*',
        root: livepath, types: [FileSystemEntityType.directory]).toList();

    var max = 0;
    for (var path in paths) {
      if (path.contains('-')) {
        // noojee.org-0001
        var parts = path.split('-');
        var num = int.parse(parts[1]);
        if (num > max) {
          max = num;
          latest = join(livepath, path);
        }
      }
    }

    return latest;
  }

  String _createDir(String dir) {
    if (!exists(dir)) {
      createDir(dir, recursive: true);
    }
    return dir;
  }
}

class CertbotException implements Exception {
  String message;
  CertbotException(this.message);

  @override
  String toString() => message;
}