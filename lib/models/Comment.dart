class Comment {
  final int id;
  final int chapterId;
  final int userId;
  final int? parentId;
  final String content;
  final String createdAt;
  final String? username;
  final String? displayName;
  final String? avatarUrl;

  Comment({
    required this.id,
    required this.chapterId,
    required this.userId,
    this.parentId,
    required this.content,
    required this.createdAt,
    this.username,
    this.displayName,
    this.avatarUrl,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: (json['id'] as num).toInt(),
      chapterId: (json['chapterId'] as num).toInt(),
      userId: (json['userId'] as num).toInt(),
      parentId: json['parentId'] != null ? (json['parentId'] as num).toInt() : null,
      content: json['content'] ?? '',
      createdAt: json['createdAt'] ?? '',
      username: json['username'],
      displayName: json['displayName'],
      avatarUrl: json['avatarUrl'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chapterId': chapterId,
      'userId': userId,
      'parentId': parentId,
      'content': content,
      'createdAt': createdAt,
      'username': username,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
    };
  }
}
