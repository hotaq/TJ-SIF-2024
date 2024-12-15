import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:http_parser/http_parser.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Object Detection App',
      theme: ThemeData(fontFamily: 'Roboto'),
      home: const ObjectDetectionPage(),
    );
  }
}


class BoundingBoxPainter extends CustomPainter {
  final List<dynamic> detectedObjects;
  final double imageWidth;
  final double imageHeight;

  BoundingBoxPainter(this.detectedObjects, this.imageWidth, this.imageHeight);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color.fromARGB(255, 255, 0, 0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    for (var prediction in detectedObjects) {
      final name = prediction['class_name'];
      final bbox = prediction['bbox']; // [x_min, y_min, width, height]
      final confidence = prediction['confidence']; // Confidence score

      // Scale the bounding box to match the image display size
      final xMin = bbox[0] * size.width / imageWidth;
      final yMin = bbox[1] * size.height / imageHeight;
      final width = bbox[2] * size.width / imageWidth;
      final height = bbox[3] * size.height / imageHeight;

      // Draw the rectangle
      canvas.drawRect(
        Rect.fromLTWH(xMin, yMin, width-100, height),
        paint,
      );

      // Draw the label
      final textSpan = TextSpan(
        text: '$name: ${(confidence * 100).toStringAsFixed(2)}%',
        style: const TextStyle(
          color: Color.fromARGB(255, 5, 255, 151),
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout(minWidth: 0, maxWidth: size.width);

      // Position the label just above the bounding box
      final textOffset = Offset(xMin, yMin - textPainter.height);
      textPainter.paint(canvas, textOffset);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}

class ObjectDetectionPage extends StatefulWidget {
  const ObjectDetectionPage({super.key});

  @override
  State<ObjectDetectionPage> createState() => _ObjectDetectionPageState();
}

class _ObjectDetectionPageState extends State<ObjectDetectionPage> {
  File? _image;
  final picker = ImagePicker();
  List<dynamic> detectedObjects = [];
  bool isLoading = false;

  // Function to pick image from gallery or camera
  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await picker.pickImage(source: source);
      if (pickedFile != null) {
        setState(() {
          _image = File(pickedFile.path);
          detectedObjects = []; // Clear previous results
        });
        _detectObjects();
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      _showError('Error picking image');
    }
  }

  // Function to resize the image
  Future<Uint8List> _resizeImage(File imageFile) async {
    try {
      final Uint8List imageBytes = await imageFile.readAsBytes();
      final img.Image? originalImage = img.decodeImage(imageBytes);

      if (originalImage == null) {
        throw Exception('Failed to decode Image');
      }

      const newwidth = 640;
      const int newheight = 640;

      final img.Image resizedImage = img.copyResize(
        originalImage,
        width: newwidth,
        height: newheight,
        interpolation: img.Interpolation.linear,
      );

      return Uint8List.fromList(img.encodePng(resizedImage));
    } catch (e) {
      throw Exception('Error processing image: $e');
    }
  }

  // Function to detect objects in the image
  Future<void> _detectObjects() async {
    if (_image == null) return;

    setState(() {
      isLoading = true;
    });

    try {
      final resizedImage = await _resizeImage(_image!);
      final base64Image = base64Encode(resizedImage);
      final imageBytes = base64Decode(base64Image);
      const apiUrl = 'http://10.0.2.2:8000/predict'; // Change this URL to your server's API
      var request = http.MultipartRequest('POST', Uri.parse(apiUrl));
      request.files.add(http.MultipartFile.fromBytes(
        'file', // The key for the form-data
        imageBytes, // The image byte data
        filename: 'image.jpg', // You can change the filename extension if needed
        contentType: MediaType('image', 'jpeg'), // Adjust if the image is not jpeg
      ));

      final response = await request.send();

      if (response.statusCode == 200) {
        final responseBody = await response.stream.bytesToString();
        final results = jsonDecode(responseBody);

        setState(() {
          detectedObjects = results['predictions'] ?? [];
        });
      } else {
        _showError('Failed to detect objects');
      }
    } catch (e) {
      debugPrint('Error detecting objects: $e');
      _showError('Error processing image');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Function to show error message
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 240, 220),
      appBar: AppBar(
        title: const Text('Object Detection'),
        backgroundColor: const Color.fromARGB(255, 240, 187, 120),
        elevation: 2, // Adds subtle shadow to AppBar
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            if (_image != null) ...[
              Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 240, 187, 120),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.shade300,
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    child: Image.file(
                      _image!,
                      height: 400,
                      width: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                   CustomPaint(
                  size: const Size(double.infinity, 300), // Match image size
                  painter: BoundingBoxPainter(
                    detectedObjects,
                    640, // Replace with your image width
                    640, // Replace with your image height
                  ),
                ),
                ],
              ),
            ],
            if (isLoading)
              const CircularProgressIndicator()
            else if (detectedObjects.isNotEmpty)
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade300,
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    ...detectedObjects.map((prediction) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.shade300,
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Class: ${prediction['class_name']}'),
                            Text('Confidence: ${(prediction['confidence'] * 100).toStringAsFixed(2)}%'),
                            
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
              
          ],  
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Camera'),
            ),
            ElevatedButton.icon(
              onPressed: () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              label: const Text('Gallery'),
            ),
          ],
        ),
      ),
    );
  }
}

