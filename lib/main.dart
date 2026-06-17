import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SDXL Collector',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _images = [];
  int _currentIndex = 0;
  bool _isLoading = true;
  String _error = '';
  final TextEditingController _inputController = TextEditingController();
  int _savedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadImages();
    _updateSavedCount();
  }

  // Загрузка картинок с Civitai напрямую (на нативных устройствах CORS нет)
  Future<void> _loadImages() async {
    try {
      final response = await http.get(Uri.parse(
          'https://civitai.com/api/v1/images?limit=50&nsfw=false'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> rawImages = data['items'] ?? [];
        
        setState(() {
          _images = rawImages.where((img) => img['meta'] != null && img['meta']['prompt'] != null).toList();
          _isLoading = false;
        });
      } else {
        throw Exception('Ошибка HTTP: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<File> _getDatasetFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/sdxl_dataset.json');
  }

  Future<void> _updateSavedCount() async {
    try {
      final file = await _getDatasetFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        setState(() {
          _savedCount = jsonList.length;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveEntry(String input, String output) async {
    final file = await _getDatasetFile();
    List<dynamic> dataset = [];

    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        dataset = jsonDecode(content);
      } catch (_) {}
    }

    dataset.add({
      'instruction': 'Преобразуй краткое описание в подробный художественный промпт для нейросети SDXL.',
      'input': input,
      'output': output,
    });

    await file.writeAsString(jsonEncode(dataset));
    _inputController.clear();
    _updateSavedCount();

    setState(() {
      _currentIndex++;
    });
  }

  Future<void> _exportDataset() async {
    final file = await _getDatasetFile();
    if (await file.exists()) {
      await Share.shareXFiles([XFile(file.path)], text: 'Мой датасет для SDXL');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Датасет пуст. Сначала сохраните примеры!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error.isNotEmpty) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text('Ошибка: $_error', textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
          ),
        ),
      );
    }

    if (_currentIndex >= _images.length) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Картинки закончились!'),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _exportDataset,
                icon: const Icon(Icons.share),
                label: const Text('Экспортировать JSON'),
              )
            ],
          ),
        ),
      );
    }

    final currentImg = _images[_currentIndex];
    final String imgUrl = currentImg['url'] ?? '';
    final String sdxlPrompt = currentImg['meta']['prompt'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text('Сохранено: $_savedCount', style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _exportDataset,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Image.network(
                    imgUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const Center(child: Icon(Icons.broken_image, size: 50)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[800]!),
                ),
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: Text(
                    sdxlPrompt,
                    style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _inputController,
                decoration: InputDecoration(
                  hintText: 'Введите краткую идею...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey[900],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      onPressed: () {
                        setState(() {
                          _currentIndex++;
                        });
                      },
                      child: const Text('Пропустить'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () {
                        final text = _inputController.text.trim();
                        if (text.isNotEmpty) {
                          _saveEntry(text, sdxlPrompt);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Введите описание!')),
                          );
                        }
                      },
                      child: const Text('Сохранить', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
