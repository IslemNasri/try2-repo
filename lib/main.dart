import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Get available cameras
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: AccessibilityApp(camera: firstCamera),
    ),
  );
}

class AccessibilityApp extends StatefulWidget {
  final CameraDescription camera;

  const AccessibilityApp({Key? key, required this.camera}) : super(key: key);

  @override
  _AccessibilityAppState createState() => _AccessibilityAppState();
}

class _AccessibilityAppState extends State<AccessibilityApp> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  FlutterTts flutterTts = FlutterTts();
  String recognizedText = '';
  bool isProcessing = false;

  // Language settings
  String currentLanguage = 'eng'; // Default language
  String currentTtsLang = 'en-US'; // Default TTS language

  final Map<String, Map<String, String>> languageOptions = {
    'eng': {
      'name': 'English',
      'ttsLang': 'en-US',
      'welcomeMessage':
          'App ready. Tap anywhere on screen to capture and read text.',
    },
    'ara': {
      'name': 'Arabic',
      'ttsLang': 'ar-SA',
      'welcomeMessage':
          'التطبيق جاهز. انقر في أي مكان على الشاشة لالتقاط النص وقراءته.',
    },
    'fra': {
      'name': 'French',
      'ttsLang': 'fr-FR',
      'welcomeMessage':
          'Application prête. Appuyez n\'importe où sur l\'écran pour capturer et lire le texte.',
    },
  };

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadLanguagePreference().then((_) {
      _initializeTts();
    });
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLang = prefs.getString('selectedLanguage');
    if (savedLang != null && languageOptions.containsKey(savedLang)) {
      setState(() {
        currentLanguage = savedLang;
        currentTtsLang = languageOptions[savedLang]!['ttsLang']!;
      });
    }
  }

  Future<void> _saveLanguagePreference(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedLanguage', language);
  }

  void _initializeCamera() {
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    _initializeControllerFuture = _controller.initialize();
  }

  Future<void> _initializeTts() async {
    await flutterTts.setLanguage(currentTtsLang);
    await flutterTts.setPitch(1.0);
    await flutterTts.setSpeechRate(0.5);

    await flutterTts.speak(
      languageOptions[currentLanguage]!['welcomeMessage']!,
    );
  }

  Future<void> _captureAndRecognizeText() async {
    setState(() {
      isProcessing = true;
      recognizedText = ""; // Clear previous text
    });

    try {
      await _initializeControllerFuture;
      await flutterTts.speak('Taking photo');

      final XFile image = await _controller.takePicture();
      await flutterTts.speak('Processing image');

      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String appDocPath = appDocDir.path;
      final String imagePath = path.join(appDocPath, 'ocr_image.jpg');

      final File imageFile = File(image.path);
      final File destinationFile = File(imagePath);

      if (!await imageFile.exists()) {
        throw Exception('Captured image file does not exist at ${image.path}');
      }

      await imageFile.copy(imagePath);

      String extractedText = "";

      try {
        extractedText = await FlutterTesseractOcr.extractText(
          imagePath,
          language: currentLanguage,
          args: {"psm": "4", "preserve_interword_spaces": "1"},
        );
      } catch (ocrError) {
        print("OCR error: $ocrError");
        extractedText = ""; // Ensure it's empty on failure
      }

      setState(() {
        recognizedText =
            extractedText.trim().isEmpty
                ? "No text found in image."
                : extractedText.trim();
        isProcessing = false;
      });

      if (recognizedText.isEmpty) {
        await flutterTts.speak('No text found in image.');
      } else {
        await flutterTts.speak(recognizedText);
      }

      try {
        await destinationFile.delete();
        await imageFile.delete();
      } catch (fileError) {
        print("Error cleaning up files: $fileError");
      }
    } catch (e) {
      setState(() {
        isProcessing = false;
        recognizedText = "Error: $e";
      });

      await flutterTts.speak('An error occurred. Please try again.');
      print("Error capturing or processing image: $e");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Text Recognition')),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                CameraPreview(_controller),
                Positioned.fill(
                  child: GestureDetector(
                    onTap: isProcessing ? null : _captureAndRecognizeText,
                    child: Container(color: Colors.transparent),
                  ),
                ),
                if (isProcessing)
                  Center(
                    child: Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Processing image...'),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      recognizedText.isNotEmpty
                          ? recognizedText
                          : 'Tap to capture text from image',
                      style: TextStyle(color: Colors.white),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 30,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ElevatedButton(
                      onPressed: isProcessing ? null : _captureAndRecognizeText,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 32,
                        ),
                        child: Text(
                          'Capture Text',
                          style: TextStyle(fontSize: 20),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          } else {
            return Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}
