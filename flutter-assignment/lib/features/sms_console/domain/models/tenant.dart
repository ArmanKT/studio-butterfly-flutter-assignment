class Tenant {
  final String id;
  final String name;
  final String apiKey;
  final String token;

  const Tenant({
    required this.id,
    required this.name,
    required this.apiKey,
    required this.token,
  });

  Tenant copyWith({
    String? id,
    String? name,
    String? apiKey,
    String? token,
  }) {
    return Tenant(
      id: id ?? this.id,
      name: name ?? this.name,
      apiKey: apiKey ?? this.apiKey,
      token: token ?? this.token,
    );
  }
}
