class SemanticVersion implements Comparable<SemanticVersion> {
  const SemanticVersion._({
    required this.major,
    required this.minor,
    required this.patch,
  });

  factory SemanticVersion.parse(String value) {
    final parsed = tryParse(value);
    if (parsed == null) {
      throw FormatException('Invalid semantic version: $value');
    }
    return parsed;
  }

  static final RegExp _versionPattern = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');
  static final RegExp _releaseTagPattern = RegExp(r'^v(\d+)\.(\d+)\.(\d+)$');

  final int major;
  final int minor;
  final int patch;

  static SemanticVersion? tryParse(String value) {
    final match = _versionPattern.firstMatch(value.trim());
    if (match == null) {
      return null;
    }
    return SemanticVersion._(
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
      patch: int.parse(match.group(3)!),
    );
  }

  static SemanticVersion? fromReleaseTag(String value) {
    final match = _releaseTagPattern.firstMatch(value.trim());
    if (match == null) {
      return null;
    }
    return SemanticVersion._(
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
      patch: int.parse(match.group(3)!),
    );
  }

  String get releaseTag => 'v$major.$minor.$patch';

  @override
  int compareTo(SemanticVersion other) {
    final majorCompare = major.compareTo(other.major);
    if (majorCompare != 0) {
      return majorCompare;
    }

    final minorCompare = minor.compareTo(other.minor);
    if (minorCompare != 0) {
      return minorCompare;
    }

    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';

  @override
  bool operator ==(Object other) {
    return other is SemanticVersion &&
        other.major == major &&
        other.minor == minor &&
        other.patch == patch;
  }

  @override
  int get hashCode => Object.hash(major, minor, patch);
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseTag,
    required this.releasePageUrl,
    required this.apkUrl,
  });

  final SemanticVersion currentVersion;
  final SemanticVersion latestVersion;
  final String releaseTag;
  final Uri releasePageUrl;
  final Uri apkUrl;
}
