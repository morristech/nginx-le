import 'package:dcli/dcli.dart';
import 'package:meta/meta.dart';

import 'image.dart';
import 'images.dart';

class Container {
  String containerid;
  String imageid;
  String created;
  String status;
  String ports;
  String names;

  Container({
    @required this.containerid,
    @required this.imageid,
    @required this.created,
    @required this.status,
    @required this.ports,
    @required this.names,
  });

  Image get image => Images().findByImageId(imageid);

  void stop() {
    if (isRunning) {
      'docker stop $containerid'.run;
    }
  }

  /// some comment.
  void start({bool interactive = false}) {
    var option = (interactive ? ' -i ' : '');
    var cmd = 'docker start $option $containerid';
    cmd.start(
        progress: Progress((line) => print(line),
            stderr: (line) => printerr(red(line))));
  }

  bool get isRunning {
    return "docker container inspect -f '{{.State.Running}}' $containerid"
            .firstLine ==
        'true';
  }

  void delete() {
    'docker container rm $containerid'.run;
  }

  void showLogs() {
    'docker logs $containerid'.run;
  }

  /// Attaches to the running container and starts a bash command prompt.
  void cli() {
    'docker exec -it $containerid /bin/bash'
        .start(nothrow: true, progress: Progress.print(), terminal: true);
  }
}
