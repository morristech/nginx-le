import 'package:dshell/dshell.dart';
import 'package:meta/meta.dart';

class Image {
  String repository;
  String name;
  String tag;
  String imageid;
  String created;
  String size;

  Image(
      {@required String repositoryAndName,
      @required this.tag,
      @required this.imageid,
      @required this.created,
      @required this.size}) {
    var repoAndName = splitRepoAndName(repositoryAndName);
    repository = repoAndName.repo;
    name = repoAndName.name;
  }

  Image.fromName(String fullname) {
    var _fullname = splitFullname(fullname);

    repository = _fullname.repo;
    name = _fullname.name;
    tag = _fullname.tag;
  }

  String get fullname => '$repository/$name:$tag';

  /// Takes a docker repo/name:tag string and splits it into
  /// three components.
  static _Fullname splitFullname(String fullname) {
    String repo;
    String name;
    String tag;

    if (fullname.contains('/')) {
      var parts = fullname.split('/');
      repo = parts[0];
      parts = parts[1].split(':');
      name = parts[0];
      tag = parts[1];
    } else {
      if (fullname.contains(':')) {
        var parts = fullname.split(':');
        repo = parts[0];
        tag = parts[1];
      } else {
        repo = fullname;
      }
    }

    return _Fullname(repo, name, tag);
  }

  /// Takes a docker repo/name string and splits it into
  /// two components.
  static _RepoAndName splitRepoAndName(String repoAndName) {
    var parts = repoAndName.split('/');
    if (parts.length != 2) {
      // throw ArgumentError(
      //     'The passed repoAndName $repoAndName is missing the "/" separator');
      return _RepoAndName(repoAndName, null);
    }
    return _RepoAndName(parts[0], parts[1]);
  }

  void delete() {
    'docker image rm $imageid'.run;
  }

  @override
  bool operator ==(covariant Image image) {
    return (imageid == image.imageid);
  }
}

class _RepoAndName {
  String repo;
  String name;

  _RepoAndName(this.repo, this.name);
}

class _Fullname {
  String repo;
  String name;
  String tag;

  _Fullname(this.repo, this.name, this.tag);
}
