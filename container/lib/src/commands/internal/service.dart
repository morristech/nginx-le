import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:nginx_le_container/src/util/acquisition_manager.dart';
import 'package:nginx_le_container/src/util/renewal_manager.dart';
import 'package:nginx_le_shared/nginx_le_shared.dart';

import '../../util/log_manager.dart';

/// The main service thread that runs within the docker container.
void start_service() {
  print('Nginx-LE starting Version:$packageVersion');

  /// These environment variables are set when the container is
  /// created via nginx-le config or by docker-compose.
  ///
  /// NOTE: you can NOT change these by setting an environment var before you call nginx-le start
  /// They can only be changed by re-running nginx-le config and recreating the container.
  ///
  ///

  var startPaused = Environment().startPaused;

  if (startPaused) {
    print(orange(
        'Nginx-LE is paused. Run "nginx-le cli" to attached and explore the Nginx-LE container'));
    while (true) {
      sleep(10);
    }
  } else {
    try {
      _start();
    } catch (e, s) {
      print('Nginx-LE encounted an unexpected problem and is shutting down.');
      print('Exception: ${e.runtimeType} ${e.toString()}');
      print('Stacktrace: ${s.toString()}');
    } finally {
      print(orange('Nginx-le has shutdown'));
    }
  }
}

void _start() {
  var debug = Environment().debug;
  Settings().setVerbose(enabled: debug);

  dumpEnvironmentVariables();

  var hostname = Environment().hostname;
  Settings().verbose('${Environment().hostnameKey}=$hostname');
  var domain = Environment().domain;
  Settings().verbose('${Environment().domainKey}=$domain');
  var tld = Environment().tld;
  Settings().verbose('${Environment().tldKey}=$tld');

  var wildcard = Environment().domainWildcard;
  Settings().verbose('${Environment().domainWildcardKey}=$wildcard');

  var emailaddress = Environment().emailaddress;
  Settings().verbose('${Environment().emailaddressKey}=$emailaddress');

  var production = Environment().production;
  Settings().verbose('${Environment().productionKey}=$production');

  var autoAcquire = Environment().autoAcquire;
  Settings().verbose('${Environment().autoAcquireKey}=$autoAcquire');

  var certbotAuthProvider = Environment().authProvider;
  Settings().verbose('${Environment().authProviderKey}=$certbotAuthProvider');

  /// Places the server into acquire mode if certificates are not valid.
  ///
  Certbot().deployCertificates(
      hostname: hostname,
      domain: domain,
      reload: false, // don't try to reload nginx as it won't be running as yet.
      wildcard: wildcard,
      autoAcquireMode: autoAcquire);

  LogManager().start();

  RenewalManager().start();

  if (autoAcquire && !Certbot().isBlocked()) {
    var certificates = Certificate.load();

    /// expired certs are handled by the renew scheduler
    if (certificates.isEmpty) {
      AcquisitionManager().start();
    } else {
      var certificate = certificates[0];

      /// If the certificate type has changed then we must acquire a new one.
      /// If we have more then one certificate then somethings wrong so start again by revoke all of them.
      if (certificates.length > 1 ||
          production != certificate.production ||
          '$hostname.$domain' != certificate.fqdn ||
          wildcard != certificate.wildcard) {
        Certbot.revokeAll();
        AcquisitionManager().start();
      }
    }
  }

  print('Starting nginx');

  /// run the command passed in on the command line.
  "nginx -g 'daemon off;'".start();
}

void dumpEnvironmentVariables() {
  printEnv(Environment().debugKey, Environment().debug.toString());
  printEnv(Environment().hostnameKey, Environment().hostname);
  printEnv(Environment().domainKey, Environment().domain);
  printEnv(Environment().tldKey, Environment().tld);
  printEnv(Environment().emailaddressKey, Environment().emailaddress);
  printEnv(Environment().productionKey, Environment().production.toString());
  printEnv(
      Environment().domainWildcardKey, Environment().domainWildcard.toString());
  printEnv(Environment().autoAcquireKey, Environment().autoAcquire.toString());
  printEnv(Environment().smtpServerKey, Environment().smtpServer);
  printEnv(
      Environment().smtpServerPortKey, Environment().smtpServerPort.toString());
  printEnv(Environment().startPausedKey, Environment().startPaused.toString());
  printEnv(Environment().authProviderKey, Environment().authProvider);
  printEnv(Environment().certbotIgnoreBlockKey,
      Environment().certbotIgnoreBlock.toString());

  var authProvider = AuthProviders().getByName(Environment().authProvider);
  if (authProvider == null) {
    printerr(red(
        'No Auth Provider has been set. Check ${Environment().authProviderKey} as been set'));
    exit(1);
  }
  authProvider.dumpEnvironmentVariables();

  print('Internal environment variables');
  printEnv(Environment().certbotRootPathKey, Environment().certbotRootPath);
  printEnv(Environment().logfileKey, Environment().logfile);
  printEnv(Environment().nginxCertRootPathOverwriteKey,
      Environment().nginxCertRootPathOverwrite);
}

void printEnv(String key, String value) {
  print('ENV: $key=$value');
}
