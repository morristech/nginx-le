import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dshell/dshell.dart';
import 'package:nginx_le_cli/src/builders/locations/wwwroot.dart';
import 'package:nginx_le_cli/src/config/ConfigYaml.dart';
import 'package:nginx_le_shared/nginx_le_shared.dart';
import 'package:uuid/uuid.dart';

/// Starts nginx and the certbot scheduler.
class ConfigCommand extends Command<void> {
  @override
  String get description => 'Allows you to configure your Nginx-LE server';

  @override
  String get name => 'config';

  ConfigCommand() {
    argParser.addFlag('debug',
        defaultsTo: false,
        negatable: false,
        abbr: 'd',
        help: 'Outputs additional logging information');
  }

  @override
  void run() {
    var debug = argResults['debug'] as bool;
    Settings().setVerbose(enabled: debug);

    var config = ConfigYaml();

    selectStartMethod(config);

    selectMode(config);

    selectHost(config);
    selectDomain(config);

    selectTLD(config);

    selectEmailAddress(config);

    selectCertType(config);

    if (config.isModePrivate) {
      selectDNSProvider(config);
    } else {
      config.dnsProvider = null;
    }

    var containerName = 'nginx-le';

    if (config.startMethod != ConfigYaml.START_METHOD_DOCKER_COMPOSE) {
      var image = selectImage(config);

      getContentSource(config);
      deleteOldContainers(containerName, image);
      createContainer(image, config, debug);
    } else {
      selectContainer(config);
    }

    config.save();
    print('Configuration saved.');
  }

  void deleteOldContainers(String containerName, Image image) {
    var existing = Containers().findByName(containerName);

    if (existing != null) {
      print('A containers with the name $containerName already exists');
      if (!confirm(
          prompt:
              'Do you want to delete the older container and create one with the new settings?')) {
        print('Settings not saved. config command aborted');
        exit(-1);
      } else {
        if (existing.isRunning) {
          print(
              'The old container is running. To delete the container it must be stopped.');
          if (confirm(
              prompt:
                  'Do you want the container ${existing.containerid} stopped?')) {
            existing.stop();
          } else {
            printerr(red(
                'Unable to delete container ${existing.containerid} as it is running'));
            printerr(
                'Delete all containers for ${image.imageid} and try again.');
            exit(1);
          }
        }
        existing.delete();
      }
    }
  }

  void createContainer(Image image, ConfigYaml config, bool debug) {
    print('Creating container from Image ${image.fullname}.');

    var lines = <String>[];
    var progress =
        Progress((line) => lines.add(line), stderr: (line) => lines.add(line));

    var volumes = '';

    if (config.contentSourceType == ConfigYaml.CONTENT_SOURCE_PATH) {
      volumes += ' -v ${config.wwwRoot}:${config.wwwRoot}';
    }
    volumes += ' -v ${config.includePath}:${Nginx.locationIncludePath}';

    var cmd = 'docker create'
        ' --name="nginx-le"'
        ' --env=HOSTNAME=${config.hostname}'
        ' --env=DOMAIN=${config.domain}'
        ' --env=TLD=${config.tld}'
        ' --env=MODE=${config.mode}'
        ' --env=EMAIL_ADDRESS=${config.emailaddress}'
        ' --env=DEBUG=$debug'
        ' --net=host'
        ' --log-driver=journald'
        ' -v certificates:${Certbot.letsEncryptRootPath}'
        '$volumes'
        ' ${config.image.imageid}';

    cmd.start(nothrow: true, progress: progress);
    Containers().flushCache();

    if (progress.exitCode != 0) {
      printerr(red('docker create failed with exitCode ${progress.exitCode}'));
      lines.forEach(printerr);
      exit(1);
    } else {
      // only the first 12 characters are actually used to start/stop containers.
      var containerid = lines[0].substring(0, 12);

      if (Containers().findByContainerId(containerid) == null) {
        printerr(red('Docker failed to create the container!'));
        exit(1);
      } else {
        print('Container created');
        config.containerid = containerid;
      }
    }
  }

  void selectDNSProvider(ConfigYaml config) {
    config.dnsProvider = ConfigYaml.NAMECHEAP_PROVIDER;

    var namecheap_username = ask(
        prompt: 'NameCheap API Username:',
        defaultValue: config.namecheap_apiusername,
        validator: Ask.required);
    config.namecheap_apiusername = namecheap_username;

    var namecheap_apikey = ask(
        prompt: 'NameCheap API Key:',
        defaultValue: config.namecheap_apikey,
        hidden: true,
        validator: Ask.required);
    config.namecheap_apikey = namecheap_apikey;
  }

  void selectCertType(ConfigYaml config) {
    var certTypes = ['production', 'staging'];
    var certificateType = menu(
        prompt: 'Certificate Type:',
        options: certTypes,
        defaultOption: 'staging');
    config.certificateType = certificateType;
  }

  void selectEmailAddress(ConfigYaml config) {
    var emailaddress = ask(
        prompt: 'Email Address:',
        defaultValue: config.emailaddress,
        validator: Ask.email);
    config.emailaddress = emailaddress;
  }

  void selectTLD(ConfigYaml config) {
    var tld = ask(
        prompt: 'TLD:',
        defaultValue: config.tld,
        validator: AskMultiValidator([Ask.required, Ask.alphaNumeric]));
    config.tld = tld;
  }

  void selectHost(ConfigYaml config) {
    var hostname = ask(
        prompt: 'Hostname:',
        defaultValue: config.hostname,
        validator: Ask.alphaNumeric);
    config.hostname = hostname;
  }

  void selectDomain(ConfigYaml config) {
    var domain = ask(
        prompt: 'Domain:', defaultValue: config.domain, validator: Ask.fqdn);
    config.domain = domain;
  }

  Image selectImage(ConfigYaml config) {
    var image = menu<Image>(
        prompt: 'Image:',
        options: Images().images,
        format: (image) =>
            '${image.imageid} - ${image.repository}/${image.name}:${image.tag}',
        defaultOption: config.image);
    config.image = image;
    return image;
  }

  void selectMode(ConfigYaml config) {
    config.mode ??= ConfigYaml.MODE_PRIVATE;
    var options = [ConfigYaml.MODE_PUBLIC, ConfigYaml.MODE_PRIVATE];
    var mode = menu(
      prompt: 'Mode:',
      options: options,
      defaultOption: config.mode,
    );
    config.mode = mode;
  }

  void selectStartMethod(ConfigYaml config) {
    config.startMethod ?? ConfigYaml.START_METHOD_NGINX_LE;
    var startMethods = [
      ConfigYaml.START_METHOD_NGINX_LE,
      ConfigYaml.START_METHOD_DOCKER_START,
      ConfigYaml.START_METHOD_DOCKER_COMPOSE
    ];
    var startMethod = menu(
      prompt: 'Start Method:',
      options: startMethods,
      defaultOption: config.startMethod,
    );
    config.startMethod = startMethod;
  }

  /// Ask users where the website content is located.
  void getContentSource(ConfigYaml config) {
    setLocationPath(config);

    var contentSource = <String>[
      ConfigYaml.CONTENT_SOURCE_PATH,
      ConfigYaml.CONTENT_SOURCE_LOCATION
    ];
    var selection = menu(
        prompt: 'Content Source:',
        options: contentSource,
        defaultOption: config.contentSourceType);

    if (selection == ConfigYaml.CONTENT_SOURCE_PATH) {
      var valid = false;
      String wwwroot;
      do {
        /// wwwroot
        var defaultPath =
            config.wwwRoot ?? WwwRoot(config.includePath).preferredPath;
        wwwroot =
            ask(prompt: 'Path (on host) to wwwroot', defaultValue: defaultPath);
        if (!exists(wwwroot)) {
          print(red('The path $wwwroot does not exist.'));
          if (confirm(prompt: 'Create $wwwroot')) {
            if (isWritable(findParent(wwwroot))) {
              createDir(wwwroot, recursive: true);
            } else {
              'sudo mkdir -p $wwwroot'.run;
            }
            valid = true;
          }
        } else {
          valid = true;
        }
      } while (!valid);

      valid = false;

      do {
        /// write out the location file
        var wwwBuilder = WwwRoot(wwwroot);
        var locationConfig = wwwBuilder.build();

        if (config.wwwRoot != null) {
          backupOldWwwLocation(config, locationConfig);
        }

        if (!isWritable(findParent(wwwBuilder.locationConfigPath))) {
          var tmp = FileSync.tempFile();
          tmp.write(locationConfig);
          'sudo mv $tmp $wwwBuilder.locationConfigPath'.run;
        } else {
          wwwBuilder.locationConfigPath.write(locationConfig);
        }

        config.wwwRoot = wwwroot;
        valid = true;
      } while (!valid);

      config.contentSourceType = ConfigYaml.CONTENT_SOURCE_PATH;
    } else {
      var valid = false;
      do {
        /// wwwroot
        var locationPath = ask(prompt: 'Path to Location Directory');
        if (!exists(locationPath)) {
          print(red('The path $locationPath does not exists'));
        } else {
          valid = true;
        }
      } while (!valid);
      config.contentSourceType = ConfigYaml.CONTENT_SOURCE_LOCATION;
    }
  }

  void backupOldWwwLocation(ConfigYaml config, String newLocationConfig) {
    var oldConfig = WwwRoot(config.wwwRoot);
    var existingLocationConfig =
        read(oldConfig.locationConfigPath).toList().join('\n');
    if (existingLocationConfig != newLocationConfig) {
      // looks like the user manually changed the contents of the file.
      var backup = '${oldConfig.locationConfigPath}.bak';
      if (exists(backup)) {
        var target = '$backup.${Uuid().v4()}';
        if (!isWritable(backup)) {
          'sudo mv $backup $target'.run;
        } else {
          move(backup, '$backup.${Uuid().v4()}');
        }
      }

      if (!isWritable(dirname(backup))) {
        'sudo cp ${oldConfig.locationConfigPath} $backup'.run;
      } else {
        copy(oldConfig.locationConfigPath, backup);
      }

      print(
          'Your original location file ${oldConfig.locationConfigPath} has been backed up to $backup');
    }
  }

  void setLocationPath(ConfigYaml config) {
    var valid = false;
    String includePath;
    do {
      includePath = ask(
          prompt:
              'Parent directory (on host) of `location` and `upstream` files:',
          defaultValue: config.includePath,
          validator: Ask.required);

      createPath(locationsPath(includePath));
      createPath(upstreamPath(includePath));

      valid = true;
    } while (!valid);

    config.includePath = includePath;
  }

  void createPath(String path) {
    if (!exists(path)) {
      if (isWritable(findParent(path))) {
        createDir(path, recursive: true);
      } else {
        'sudo mkdir -p $path'.run;
      }
    }
  }

  /// climb the tree until we find a parent directory that exists.
  /// If path exists we will return it.
  String findParent(String path) {
    var current = path;
    while (!exists(current)) {
      current = dirname(current);
    }
    return current;
  }

  void selectContainer(ConfigYaml config) {
    var containers = Containers().containers();

    var defaultOption = Containers().findByContainerId(config.containerid);

    var container = menu<Container>(
        prompt: 'Select Container:',
        options: containers,
        defaultOption: defaultOption,
        format: (container) =>
            '${container.names.padRight(30)} ${container.image?.fullname}');

    config.containerid = container.containerid;
  }
}

String upstreamPath(String includePath) => join(includePath, 'upstream');

String locationsPath(String includePath) => join(includePath, 'locations');

void showUsage(ArgParser parser) {
  print(parser.usage);
  exit(-1);
}