class User {
  final int id;
  final String username;
  String avatarUrl;
  String displayName;
  final int lastReadStoryId;
  final int lastReadChapterId;
  final String lastReadCreatedBy;
  final String role;
  User({
    required this.id,
    required this.username,
    required this.avatarUrl,
    required this.displayName,
    required this.lastReadStoryId,
    required this.lastReadChapterId,
    required this.lastReadCreatedBy,
    required this.role
  });
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json["id"],
      username: json["username"],
      avatarUrl: json["avatarUrl"],
      displayName: json['displayName'],
      lastReadStoryId: json['lastReadStoryId'],
      lastReadChapterId: json['lastReadChapterId'],
      lastReadCreatedBy: json['lastReadCreatedBy'],
      role: json['role']
    );
  }
  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "username": username,
      "avatarUrl": avatarUrl,
      "displayName":displayName,
      "lastReadStoryId":lastReadStoryId,
      "lastReadChapterId":lastReadChapterId,
      'lastReadCreatedBy':lastReadCreatedBy,
      'role': role
    };
  }
}