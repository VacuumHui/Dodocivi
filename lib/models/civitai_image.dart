class CivitaiImage {
  const CivitaiImage({
    required this.id,
    required this.imageUri,
    required this.prompt,
    this.negativePrompt,
    this.width,
    this.height,
    this.username,
    this.modelName,
    this.steps,
    this.sampler,
    this.cfgScale,
  });

  final int id;
  final Uri imageUri;
  final String prompt;
  final String? negativePrompt;
  final int? width;
  final int? height;
  final String? username;
  final String? modelName;
  final int? steps;
  final String? sampler;
  final double? cfgScale;

  double get aspectRatio {
    if (width == null || height == null || width! <= 0 || height! <= 0) {
      return 1;
    }
    return (width! / height!).clamp(0.65, 1.55).toDouble();
  }

  factory CivitaiImage.fromJson(Map<String, dynamic> json) {
    final nsfwLevel = json['nsfwLevel']?.toString().trim().toLowerCase();
    if (json['nsfw'] == true ||
        (nsfwLevel != null && nsfwLevel.isNotEmpty && nsfwLevel != 'none')) {
      throw const FormatException('NSFW image rejected');
    }

    final id = _asInt(json['id']);
    final imageUri = Uri.tryParse(json['url']?.toString() ?? '');
    final rawMeta = json['meta'];
    final meta = rawMeta is Map
        ? Map<String, dynamic>.from(rawMeta)
        : <String, dynamic>{};
    final prompt = meta['prompt']?.toString().trim() ?? '';

    if (id == null ||
        imageUri == null ||
        !const <String>{'http', 'https'}.contains(imageUri.scheme) ||
        prompt.isEmpty) {
      throw const FormatException('Incomplete Civitai image payload');
    }

    return CivitaiImage(
      id: id,
      imageUri: imageUri,
      prompt: prompt,
      negativePrompt: _clean(meta['negativePrompt']),
      width: _asInt(json['width']),
      height: _asInt(json['height']),
      username: _clean(json['username']),
      modelName: _clean(meta['Model'] ?? meta['model']),
      steps: _asInt(meta['steps']),
      sampler: _clean(meta['sampler']),
      cfgScale: _asDouble(meta['cfgScale']),
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static String? _clean(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
