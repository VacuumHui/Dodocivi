class DatasetEntry {
  const DatasetEntry({
    required this.instruction,
    required this.input,
    required this.output,
    required this.imageId,
    required this.imageUrl,
    required this.createdAt,
  });

  static const defaultInstruction =
      'Преобразуй краткое описание в подробный художественный промпт для нейросети SDXL.';

  final String instruction;
  final String input;
  final String output;
  final int? imageId;
  final String? imageUrl;
  final DateTime createdAt;

  Map<String, dynamic> toExportJson() => <String, dynamic>{
        'instruction': instruction,
        'input': input,
        'output': output,
      };

  Map<String, dynamic> toStorageJson() => <String, dynamic>{
        ...toExportJson(),
        'imageId': imageId,
        'imageUrl': imageUrl,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory DatasetEntry.fromJson(Map<String, dynamic> json) {
    final instruction = json['instruction']?.toString().trim();
    final input = json['input']?.toString().trim() ?? '';
    final output = json['output']?.toString().trim() ?? '';

    if (input.isEmpty || output.isEmpty) {
      throw const FormatException('Invalid dataset entry');
    }

    return DatasetEntry(
      instruction: instruction == null || instruction.isEmpty
          ? defaultInstruction
          : instruction,
      input: input,
      output: output,
      imageId: _asInt(json['imageId']),
      imageUrl: _clean(json['imageUrl']),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String? _clean(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
