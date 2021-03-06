import 'package:dcli/dcli.dart';
import 'package:instant/instant.dart';

import '../../nginx_le_shared.dart';

class Certificate {
  String fqdn;

  String domains;

  DateTime expiryDate;

  /// If [production] is true then this is a production certificate
  /// If [production] is false then this is a staging/test certificate.
  bool production;

  /// If the fqdn starts with a '*' then its a wild card certificate.
  bool wildcard = false;

  String certificatePath;

  String privateKeyPath;

  void parseName(String line) {
    var parts = line.split(':');
    fqdn = parts[1].trim();
  }

  void parseDomains(String line) {
    var parts = line.split(':');
    domains = parts[1].trim();

    if (domains.startsWith('*')) {
      wildcard = true;
    }
  }

  void parseExpiryDate(String line) {
    var parts = line.split('Date:');
    var expiryDateString = parts[1].trim();

    var datePart = expiryDateString.substring(0, 25);
    expiryDate = DateTime.parse(datePart); // 'yyyy-MM-dd hh:mm:ss+');
    production = !line.contains('TEST_CERT');
  }

  void parseCertificatePath(String line) {
    var parts = line.split(':');
    certificatePath = parts[1].trim();
  }

  void parsePrivateKeyPath(String line) {
    var parts = line.split(':');
    privateKeyPath = parts[1].trim();
  }

  static List<Certificate> load() {
    print('Loading certificates from ${CertbotPaths.letsEncryptConfigPath}');

    print('directory tree of certs');
    find('*',
            root: CertbotPaths.letsEncryptConfigPath,
            types: [Find.directory, Find.file, Find.link])
        .forEach((file) => print(file));
    var cmd = 'certbot certificates '
        ' --config-dir=${CertbotPaths.letsEncryptConfigPath}'
        ' --work-dir=${CertbotPaths.letsEncryptWorkPath}'
        ' --work-dir=${CertbotPaths.letsEncryptLogPath}';

    var lines = cmd.toList(nothrow: true);

    print('output from certbot certificates');

    for (var line in lines) {
      print('Certificate Load: $line');
    }

    return parse(lines);
  }

  /// When certs exist we get
  ///
//  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Found the following certs:
//   Certificate Name: slayer.noojee.org
//     Domains: slayer.noojee.org
//     Expiry Date: 2020-10-27 06:10:05+00:00 (INVALID: TEST_CERT)
//     Certificate Path: /etc/letsencrypt/config/live/slayer.noojee.org/fullchain.pem
//     Private Key Path: /etc/letsencrypt/config/live/slayer.noojee.org/privkey.pem
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

// when no certificates found.
//  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// No certs found.
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  static List<Certificate> parse(List<String> lines) {
    var certificates = <Certificate>[];

    Certificate cert;
    for (var line in lines) {
      if (line.trim().startsWith('Certificate Name:')) {
        cert = Certificate();
        certificates.add(cert);
        cert.parseName(line);
      }
      if (line.trim().startsWith('Domains:')) {
        cert.parseDomains(line);
      }
      if (line.trim().startsWith('Expiry Date:')) {
        cert.parseExpiryDate(line);
      }
      if (line.trim().startsWith('Certificate Path')) {
        cert.parseCertificatePath(line);
      }
      if (line.trim().startsWith('Private Key Path:')) {
        cert.parsePrivateKeyPath(line);
      }
    }
    return certificates;
  }

  bool hasExpired() {
    print('expiry date $expiryDate');
    var expired = (expiryDate.isBefore(DateTime.now()));

    print('expired=$expired');
    return expired;
  }

  @override
  String toString() {
    var offset = DateTime.now().timeZoneOffset;
    var hours = offset.inHours + offset.inMinutes / 60;
    return '''Name: $fqdn 
    Production: $production
    Wildcard: $wildcard
    Domains: $domains 
    Expiry: ${dateTimeToOffset(datetime: expiryDate, offset: hours)}
    Certificate Path: $certificatePath
    Private Key Path: $privateKeyPath''';
  }
}
