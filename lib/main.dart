import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

// --- CONFIGURATION ---
const String OCR_BACKEND_URL = 'http://127.0.0.1:8000/scan';
const String GEMINI_API_KEY = "AIzaSyCYdgi6Q3gva-FORCzGx1PGHxpg5iHScv0";

// This function runs on a separate thread to avoid freezing the UI.
Future<Uint8List> _resizeImageInIsolate(Uint8List imageBytes) async {
  img.Image? originalImage = img.decodeImage(imageBytes);
  if (originalImage == null) throw Exception("Could not decode image.");
  int maxDimension = 1024;
  if (originalImage.width <= maxDimension && originalImage.height <= maxDimension) {
    return Uint8List.fromList(img.encodeJpg(originalImage, quality: 80));
  }
  img.Image resizedImage = (originalImage.width > originalImage.height)
      ? img.copyResize(originalImage, width: maxDimension)
      : img.copyResize(originalImage, height: maxDimension);
  return Uint8List.fromList(img.encodeJpg(resizedImage, quality: 80));
}

void main() {
  runApp(const MyApp());
}

enum AppState { initial, loading, success, error }

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sustainability Scanner',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF00BF63),
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00BF63),
          secondary: Color(0xFF03DAC6),
          background: Color(0xFF121212),
          surface: Color(0xFF1E1E1E),
          error: Color(0xFFCF6679),
        ),
        textTheme: GoogleFonts.poppinsTextTheme(textTheme).copyWith(
          bodyMedium: TextStyle(color: Colors.white.withOpacity(0.87)),
        ),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  AppState _appState = AppState.initial;
  String _message = 'Scan a food label to begin your sustainability analysis.';
  Map<String, dynamic>? _analysisResult;
  XFile? _imageFile; // To store the picked image file

  // --- NEW: State for the staged loading indicator ---
  int _currentStep = 0;
  final List<String> _loadingSteps = [
    'Resizing Image',
    'Extracting Ingredients',
    'Finalizing AI Analysis',
  ];

  Future<void> _pickAndAnalyzeImage() async {
    final imageFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (imageFile == null) return;

    setState(() {
      _imageFile = imageFile; // Store the selected image file
      _appState = AppState.loading;
      _currentStep = 0; // Reset steps
    });

    try {
      final imageBytes = await imageFile.readAsBytes();
      final finalImageBytes = await compute(_resizeImageInIsolate, imageBytes);
      setState(() { _currentStep = 1; }); // Mark resizing as done

      final ingredients = await _getIngredientsFromOcr(finalImageBytes, imageFile.name);
      setState(() { _currentStep = 2; }); // Mark OCR as done

      final analysis = await _getAnalysisFromGemini(ingredients);
      // No need for a third step update, as we immediately transition to success

      setState(() {
        _analysisResult = analysis;
        _appState = AppState.success;
      });

    } catch (e) {
      setState(() {
        _appState = AppState.error;
        _message = e.toString().replaceFirst("Exception: ", ""); // Clean up error message
      });
    }
  }

  Future<List<String>> _getIngredientsFromOcr(Uint8List imageBytes, String filename) async {
    var request = http.MultipartRequest('POST', Uri.parse(OCR_BACKEND_URL));
    request.fields['scanType'] = 'ocr';
    request.files.add(http.MultipartFile.fromBytes('file', imageBytes, filename: filename));
    var response = await request.send();
    if (response.statusCode == 200) {
      final responseBody = await response.stream.bytesToString();
      final data = json.decode(responseBody);
      final ingredients = List<String>.from(data['ingredients']);
      if (ingredients.isEmpty) {
        throw Exception("OCR could not find any ingredients. Please try a clearer picture.");
      }
      return ingredients;
    } else {
      final errorBody = await response.stream.bytesToString();
      throw Exception('OCR Backend Error: $errorBody');
    }
  }

  Future<Map<String, dynamic>> _getAnalysisFromGemini(List<String> ingredients) async {
    if (GEMINI_API_KEY.contains("PASTE_YOUR")) {
      throw Exception("Please paste your Gemini API Key into the code.");
    }
    final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: GEMINI_API_KEY, generationConfig: GenerationConfig(temperature: 0.1));
    final promptString = """
    You are an expert food safety and sustainability analyst. Your response MUST be a single, valid JSON object and nothing else. Do not include any text, explanations, or markdown formatting like ```json before or after the JSON object.

     **Sustainability Grading Scale Context:**
    - **A (Excellent):** Very low environmental impact, highly sustainable, often organic/local/renewable, minimal processing.
    - **B (Good):** Low impact, common ingredients generally produced sustainably, or easily recyclable.
    - **C (Moderate):** Moderate impact, common ingredients with varying production impacts, or some processing involved.
    - **D (Poor):** High impact, problematic ingredients (e.g., unsustainable farming, high water/energy use), non-recyclable components, significant processing.
    - **E (Very Poor):** Extremely high impact, major environmental concerns (e.g., deforestation, high pollution, rare/critically endangered sources), severe processing or highly artificial.

    **JSON Structure Requirements:**
    - "ingredient_analysis": An array of objects. FOR EVERY INGREDIENT FROM THE INPUT LIST, include an object with the following keys:
        - "ingredient": (The exact name of the ingredient from the input list)
        - "eco_grade": (An eco-sustainability grade for this specific ingredient, "A", "B", "C", "D", or "E", based on the grading scale above)
        - "eco_reasoning": (A brief, factual explanation for this ingredient's eco_grade, focusing on its environmental impact or sustainable practices.)
    - "harmful_ingredients": An array of objects.For each potentially harmful ingredient, include it if:
            - it is a known health or safety risk to humans (e.g., preservatives, artificial additives, excess sugar, etc.)
            - OR it is significantly harmful to the environment, i.e., has an eco_grade of "C", "D", or "E" due to unsustainable farming, processing, or resource use.

            Even if an ingredient appears in the "ingredient_analysis" list, repeat it here if it is harmful. Do NOT skip ingredients that are only ecologically harmful. This list should combine both health-related and eco-harmful ingredients. 

        - "ingredient": (the name of the ingredient)
        - "reason": (a brief, factual explanation of why it's considered potentially harmful, e.g., 'preservative linked to health issues', 'artificial sweetener','Harmfull to the evironment and sustainability')
        - "alternative": (a specific, healthier, or more sustainable alternative ingredient)
        - "alternative_reasoning": (a brief, factual explanation of why the suggested alternative is better)
      If no harmful ingredients are found, this should be an empty array [].
    - "overall_eco_grade": (The product's overall sustainability grade, "A", "B", "C", "D", or "E", based on the combined impact of all ingredients, packaging implied)
    - "overall_eco_reasoning": (A brief string explaining the main factors that influenced the overall_eco_grade, referencing key ingredients or product characteristics.)
    - "overall_summary": (A short, one-sentence summary of the product's health and sustainability profile, considering both harmful ingredients, individual ingredient impacts, and the overall eco grade.)
    
    Here is the list of ingredients to analyze: ${json.encode(ingredients)}
    """;
    final content = [Content.text(promptString)];
    final response = await model.generateContent(content);
    final responseText = response.text!.replaceAll("```json", "").replaceAll("```", "").trim();
    try {
      return json.decode(responseText) as Map<String, dynamic>;
    } catch (e) {
      throw Exception("Gemini returned invalid JSON. Raw response: $responseText");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('EcoScanner', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_appState) {
      case AppState.initial:
        return _buildInitialView();
      case AppState.loading:
        return _buildLoadingView();
      case AppState.success:
        return _buildResultsView().animate().fadeIn(duration: 600.ms);
      case AppState.error:
        return _buildErrorView();
    }
  }

  // --- UI BUILDING WIDGETS ---

  Widget _buildInitialView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.eco, size: 100, color: Theme.of(context).colorScheme.primary)
              .animate().scale(delay: 200.ms, duration: 800.ms, curve: Curves.elasticOut),
          const SizedBox(height: 32),
          Text('Welcome to EcoScanner', textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold))
              .animate().fadeIn(delay: 400.ms).slideY(begin: 0.2),
          const SizedBox(height: 16),
          Text(_message, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.7)))
              .animate().fadeIn(delay: 600.ms).slideY(begin: 0.2),
          const SizedBox(height: 48),
          _buildScanButton(),
        ],
      ),
    );
  }
  
  // --- NEW: Staged Loading Indicator Widget ---
  Widget _buildLoadingView() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text("Analyzing...", style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          ..._loadingSteps.asMap().entries.map((entry) {
            int index = entry.key;
            String text = entry.value;

            return _buildLoadingStep(
              text: text,
              isActive: _currentStep == index,
              isDone: _currentStep > index,
            ).animate().fadeIn(delay: (200 * index).ms).slideX(begin: 0.2);
          }),
        ],
      ),
    );
  }

  // Helper widget for a single step in the loading indicator
  Widget _buildLoadingStep({required String text, required bool isActive, required bool isDone}) {
    Widget icon;
    if (isDone) {
      icon = Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary);
    } else if (isActive) {
      icon = const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3));
    } else {
      icon = Icon(Icons.circle_outlined, color: Colors.grey.shade700);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 16),
          Text(text, style: TextStyle(fontSize: 18, color: isDone ? Theme.of(context).colorScheme.primary : null)),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
          const SizedBox(height: 16),
          Text("An Error Occurred", style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(_message, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.8))),
          const SizedBox(height: 32),
          _buildScanButton(),
        ],
      ),
    );
  }

  // --- MODIFIED: Results view now includes the scanned image ---
  Widget _buildResultsView() {
    if (_analysisResult == null) return _buildErrorView();
    final overallGrade = _analysisResult!['overall_eco_grade'] ?? 'N/A';
    
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        if (_imageFile != null)
          Container(
            height: 200,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              image: DecorationImage(
                image: NetworkImage(_imageFile!.path), // For Flutter Web
                fit: BoxFit.contain,
              ),
            ),
          ).animate().fadeIn(),
        
        _buildOverallScoreCard(overallGrade),
        const SizedBox(height: 24),
        _buildHarmfulIngredientsSection(_analysisResult!['harmful_ingredients']),
        const SizedBox(height: 24),
        _buildIngredientAnalysisSection(_analysisResult!['ingredient_analysis']),
        const SizedBox(height: 32),
        _buildScanButton(),
      ],
    );
  }

  Widget _buildScanButton() {
    return ElevatedButton.icon(
      onPressed: _pickAndAnalyzeImage,
      icon: const Icon(Icons.document_scanner_outlined, color: Colors.white),
      label: Text('SCAN NEW LABEL', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white)),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 56),
        backgroundColor: Theme.of(context).colorScheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ).animate().fadeIn(delay: 800.ms).slideY(begin: 0.5);
  }

  Widget _buildOverallScoreCard(String grade) {
    return Card(
      elevation: 8,
      shadowColor: _getGradeColor(grade).withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [_getGradeColor(grade).withOpacity(0.8), _getGradeColor(grade)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Text('Overall Eco Grade', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.white)),
            Text(grade, style: GoogleFonts.bebasNeue(fontSize: 120, color: Colors.white, height: 1.1)),
            const SizedBox(height: 8),
            Text(_analysisResult!['overall_summary'] ?? '', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.9))),
            const SizedBox(height: 4),
            Text(_analysisResult!['overall_eco_reasoning'] ?? '', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.7))),
          ],
        ),
      ),
    );
  }

  Widget _buildHarmfulIngredientsSection(List<dynamic>? harmful) {
    if (harmful == null || harmful.isEmpty) {
      return Card(
        color: const Color(0xFF2E7D32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 16),
              Text("No Harmful Ingredients Found", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    return _buildTitledSection(
      title: 'Red Flags',
      icon: Icons.flag,
      iconColor: Theme.of(context).colorScheme.error,
      child: Column(
        children: harmful.map((item) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['ingredient'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(item['reason'], style: TextStyle(color: Colors.white.withOpacity(0.8))),
              ],
            ),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildIngredientAnalysisSection(List<dynamic>? analysis) {
    if (analysis == null || analysis.isEmpty) return const SizedBox.shrink();

    return _buildTitledSection(
      title: 'Full Ingredient Analysis',
      icon: Icons.checklist,
      iconColor: Theme.of(context).colorScheme.secondary,
      child: Column(
        children: analysis.map((item) {
          final grade = item['eco_grade'] ?? 'N/A';
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              side: BorderSide(color: _getGradeColor(grade).withOpacity(0.5)),
              borderRadius: BorderRadius.circular(12),
            ),
            color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _getGradeColor(grade),
                child: Text(grade, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              title: Text(item['ingredient'], style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(item['eco_reasoning'], style: TextStyle(color: Colors.white.withOpacity(0.7))),
            ),
          );
        }).toList(),
      ),
    );
  }
  
  Widget _buildTitledSection({required String title, required IconData icon, required Color iconColor, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 8),
            Text(title, style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  Color _getGradeColor(String grade) {
    switch (grade.toUpperCase()) {
      case 'A': return const Color(0xFF00BF63);
      case 'B': return const Color(0xFF76C893);
      case 'C': return const Color(0xFFF9A825);
      case 'D': return const Color(0xFFF4511E);
      case 'E': return const Color(0xFFD32F2F);
      default: return Colors.grey;
    }
  }
}