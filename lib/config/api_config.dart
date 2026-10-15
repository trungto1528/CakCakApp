class ApiConfig {
  static const String host =
      "http://v2.trungto.dpdns.org";

  static const String api =
      "$host:7777/api";

  static const String image =
      "$host:7778";

  static const String crawlerUrl =
      "$api/crawler";

  static const String chapterImage =
      "$image/chapter";

  static const String coverImage =
      "$image/cover";

  static const String avatarImage =
      "$image/avatar";

  /// Download story chapters ZIP
  static const String downloadStory =
      "$api/download/story";
}