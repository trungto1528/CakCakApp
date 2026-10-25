class Story {
  final int id;
  final String title;
  final String? coverUrl;
  final String createdByName;
  Story({required this.id, required this.title, this.coverUrl,required this.createdByName});
  factory Story.fromJson(Map<String, dynamic> json) {
    return Story(
      id: json['id'],
      title: json['title'],
      coverUrl: json['coverUrl'],
      createdByName: json['createdByName']
    );
  }
}