import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class CKDHealthAnalyzer extends StatefulWidget {
  @override
  _CKDHealthAnalyzerState createState() => _CKDHealthAnalyzerState();
}

class _CKDHealthAnalyzerState extends State<CKDHealthAnalyzer>
    with TickerProviderStateMixin {
  File? _imageFile;
  String _analysisResult = '';
  bool _isAnalyzing = false;
  final ImagePicker _picker = ImagePicker();
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  int? _ckdStage; // Loaded from the user's profile

  // Replace with your actual Gemini API key
  static const String _apiKey = 'AIzaSyBeIpMWkJpJGjwWIqGFF8gcqE3Z4VBA8Po';
  late final GenerativeModel _model;

  @override
  void initState() {
    super.initState();
    _model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _apiKey);

    _fadeController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _loadStage();
  }

  Future<void> _loadStage() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final profile =
        await Supabase.instance.client
            .from('profiles')
            .select('stage')
            .eq('id', user.id)
            .maybeSingle();

    setState(() {
      _ckdStage = profile?['stage'] as int?;
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    await Permission.camera.request();
    await Permission.photos.request();
  }

  Future<void> _pickImage(ImageSource source) async {
    await _requestPermissions();

    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
          _analysisResult = '';
        });
      }
    } catch (e) {
      _showErrorDialog('Error picking image: $e');
    }
  }

  Future<void> _analyzeSkinCondition() async {
    if (_imageFile == null) {
      _showErrorDialog('Please select an image first');
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _analysisResult = '';
    });

    try {
      final imageBytes = await _imageFile!.readAsBytes();

      final stageLine =
          _ckdStage != null
              ? 'NOTE: This patient is at CKD Stage $_ckdStage.\n\n'
              : '';

      final prompt = '''
${stageLine}You are a helpful medical assistant that explains things in simple, easy-to-understand language for kidney disease patients and their families.

First, determine what this image shows: human skin/body part OR urine in a container.

If it shows SKIN/BODY PART:
Analyze if it might be related to kidney disease. 
If it shows URINE:
Analyze the urine color and what it might mean for kidney health.

Use SIMPLE words and SHORT sentences. Avoid medical jargon.

Please provide a response with these sections:

OBSERVATION:
Describe what you see in simple words (like talking to a friend) (skin condition OR urine color)

KIDNEY CONNECTION:
Is this likely related to kidney disease? Answer: Yes/No/Maybe
If yes or maybe, explain WHY in 1-2 simple sentences

WHAT THIS MIGHT BE:
For skin: List possible skin problems related to kidney disease
For urine: List possible meanings of this urine color
Use everyday language with brief explanations

WHAT TO DO:
Choose ONE level and explain in simple terms:
- WATCH: Keep an eye on it / Keep drinking water, check tomorrow
- CHECK SOON: See your doctor in 1-2 weeks  
- SEE DOCTOR: Call your doctor this week
- URGENT: Go to hospital or emergency room now

Explain WHY you chose this level in 1 simple sentence.

SIMPLE EXPLANATION:
Explain in 2-3 sentences why kidney disease can affect skin, using words like:
- Kidneys clean blood
- When kidneys don't work well
- Waste builds up
- Skin can show signs
For urine: Explain why urine color matters for kidney health
Use simple terms about how kidneys work

KEY WORDS TO KNOW:
Define 2-3 important terms that appear in your analysis, like:
"Uremia - when waste builds up in blood because kidneys can't clean it well"

SOURCES & REFERENCES:
List 3-4 credible medical sources that support this information. Use ONLY these verified sources:
- National Kidney Foundation: https://www.kidney.org/atoz/content/about-chronic-kidney-disease
- Mayo Clinic CKD Guide: https://www.mayoclinic.org/diseases-conditions/chronic-kidney-disease/symptoms-causes/syc-20354521
- National Institute of Diabetes and Digestive and Kidney Diseases (NIDDK): https://www.niddk.nih.gov/health-information/kidney-disease/chronic-kidney-disease-ckd
- American Kidney Fund: https://www.kidneyfund.org/all-about-kidneys/stages-kidney-disease
- CDC Chronic Kidney Disease: https://www.cdc.gov/kidney-disease/php/data-research/index.html

For skin-related issues, you may also reference:
- National Kidney Foundation - Skin Problems: https://www.kidney.org/atoz/content/skin-problems
- DaVita Kidney Care - Skin Changes: https://www.davita.com/education/kidney-disease/symptoms

For urine-related analysis:
- Cleveland Clinic - Urine Color: https://my.clevelandclinic.org/health/articles/10015-urine-color-what-it-tells-about-your-health
- National Kidney Foundation - Urine Tests: https://www.kidney.org/atoz/content/know-your-kidney-numbers-two-simple-tests

Choose the most relevant 3-4 sources from the list above that directly relate to the specific condition being analyzed. Format each as:
- **[Organization Name]**: Brief description of what information they provide
  Link: [URL]

MEDICAL DISCLAIMER:
This analysis is for educational purposes only and should not be used as a substitute for professional medical advice, diagnosis, or treatment. The information provided is based on visual assessment and general medical knowledge about kidney disease. Always seek the advice of your physician or other qualified health provider with any questions you may have regarding a medical condition. Never disregard professional medical advice or delay in seeking it because of information provided by this tool.

REMEMBER:
This is just information to help you understand. Always talk to your doctor about any health changes.

Keep everything at a 6th-grade reading level. Use short sentences. Explain medical terms immediately when you use them.

**Expected Format and Types:**
- Each section header (OBSERVATION, KIDNEY CONNECTION, etc.) should start a new paragraph.
- Lists (e.g., WHAT THIS MIGHT BE, KEY WORDS TO KNOW) should be formatted as bullet points, each on its own line.
- Bold important words or key terms using double asterisks (**like this**).
- Do not add extra dashes at the end of lines or paragraphs.
- Output must be plain text (not JSON).

If the image does NOT show human skin/body parts OR urine clearly (for example, a random object, animal, blank wall, or very blurry photo), please reply with:
"This photo does not appear to show skin or urine clearly. Please upload a clear photo of the affected area or urine for analysis."
''';

      final content = [
        Content.multi([TextPart(prompt), DataPart('image/jpeg', imageBytes)]),
      ];

      final response = await _model.generateContent(content);

      setState(() {
        _analysisResult = response.text ?? 'No analysis result received';
        _isAnalyzing = false;
      });

      // Debug: Print the raw response to see what we're getting
      print('Raw AI Response: $_analysisResult');

      _fadeController.reset();
      _fadeController.forward();
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
      });
      _showErrorDialog('Error analyzing image: $e');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red[600]),
                SizedBox(width: 8),
                Text('Error', style: TextStyle(color: Colors.red[600])),
              ],
            ),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('OK'),
                style: TextButton.styleFrom(foregroundColor: Colors.blue[600]),
              ),
            ],
          ),
    );
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Select Image Source',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSourceOption(
                  icon: Icons.camera_alt,
                  title: 'Camera',
                  subtitle: 'Take a new photo',
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera);
                  },
                ),
                SizedBox(height: 8),
                _buildSourceOption(
                  icon: Icons.photo_library,
                  title: 'Gallery',
                  subtitle: 'Choose from gallery',
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildSourceOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[200]!),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.blue[600], size: 24),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('Health Check'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.grey[800],
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.grey[800],
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header Section
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.amber[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.amber[700],
                              size: 22,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Medical Disclaimer',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber[900],
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Padding(
                          padding: EdgeInsets.only(left: 34),
                          child: Text(
                            'This tool is for educational purposes only and does NOT replace professional medical advice, diagnosis, or treatment. All information is AI-generated based on visual assessment and should be verified with your healthcare provider.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.amber[800],
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Image Section
            Container(
              margin: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Upload Image',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    height: 280,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child:
                        _imageFile == null
                            ? _buildImagePlaceholder()
                            : _buildImagePreview(),
                  ),
                ],
              ),
            ),

            // Action Buttons
            Container(
              margin: EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      icon: Icons.add_photo_alternate,
                      label: 'Select Image',
                      onPressed: _showImageSourceDialog,
                      isPrimary: false,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _buildActionButton(
                      icon: _isAnalyzing ? null : Icons.psychology,
                      label: _isAnalyzing ? 'Analyzing...' : 'Analyze',
                      onPressed:
                          _imageFile == null || _isAnalyzing
                              ? null
                              : _analyzeSkinCondition,
                      isPrimary: true,
                      isLoading: _isAnalyzing,
                    ),
                  ),
                ],
              ),
            ),

            // Results Section
            if (_analysisResult.isNotEmpty) ...[
              SizedBox(height: 24),
              FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  margin: EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Analysis Result',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                      SizedBox(height: 12),
                      _buildAnalysisResult(),
                    ],
                  ),
                ),
              ),
            ],

            SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return InkWell(
      onTap: _showImageSourceDialog,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.grey[300]!,
            width: 2,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add_photo_alternate,
                size: 40,
                color: Colors.blue[600],
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Tap to add image',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Camera or Gallery',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(
            _imageFile!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(Icons.close, color: Colors.white, size: 20),
              onPressed: () {
                setState(() {
                  _imageFile = null;
                  _analysisResult = '';
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    IconData? icon,
    required String label,
    required VoidCallback? onPressed,
    required bool isPrimary,
    bool isLoading = false,
  }) {
    return Container(
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? Colors.blue[600] : Colors.white,
          foregroundColor: isPrimary ? Colors.white : Colors.grey[700],
          elevation: isPrimary ? 2 : 0,
          side: isPrimary ? null : BorderSide(color: Colors.grey[300]!),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else if (icon != null)
              Icon(icon, size: 20),
            if (!isLoading && icon != null) SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisResult() {
    if (_analysisResult.contains("does not appear to show")) {
      return Center(
        child: Card(
          color: Colors.orange[50],
          margin: EdgeInsets.all(24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange[700],
                  size: 40,
                ),
                SizedBox(height: 12),
                Text(
                  "This photo does not appear to show skin or urine clearly.",
                  style: TextStyle(
                    color: Colors.orange[900],
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  "Please upload a clear photo of the affected area or urine for analysis.",
                  style: TextStyle(color: Colors.orange[800], fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _imageFile = null;
                      _analysisResult = '';
                    });
                  },
                  icon: Icon(Icons.refresh),
                  label: Text("Try Again"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_analysisResult.isEmpty) {
      return Container(
        padding: EdgeInsets.all(20),
        child: Text('No analysis result available'),
      );
    }

    Map<String, String> sections = _parseAnalysisResult(_analysisResult);

    if (sections.isEmpty) {
      return Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Analysis Result',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
            SizedBox(height: 12),
            _buildFormattedText(_analysisResult), // Don't clean the raw result
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          if (sections.containsKey('OBSERVATION'))
            _buildResultSection(
              'OBSERVATION',
              sections['OBSERVATION']!,
              Icons.visibility,
              Colors.blue,
            ),
          if (sections.containsKey('KIDNEY CONNECTION'))
            _buildResultSection(
              'KIDNEY CONNECTION',
              sections['KIDNEY CONNECTION']!,
              Icons.link,
              Colors.purple,
            ),
          if (sections.containsKey('WHAT THIS MIGHT BE'))
            _buildResultSection(
              'WHAT THIS MIGHT BE',
              sections['WHAT THIS MIGHT BE']!,
              Icons.medical_services,
              Colors.orange,
            ),
          if (sections.containsKey('WHAT TO DO'))
            _buildRecommendationSection(sections['WHAT TO DO']!),
          if (sections.containsKey('SIMPLE EXPLANATION'))
            _buildResultSection(
              'SIMPLE EXPLANATION',
              sections['SIMPLE EXPLANATION']!,
              Icons.info_outline,
              Colors.green,
            ),
          if (sections.containsKey('KEY WORDS TO KNOW'))
            _buildResultSection(
              'KEY WORDS TO KNOW',
              sections['KEY WORDS TO KNOW']!,
              Icons.book,
              Colors.indigo,
            ),
          if (sections.containsKey('SOURCES & REFERENCES'))
            _buildSourcesSection(sections['SOURCES & REFERENCES']!),
          if (sections.containsKey('MEDICAL DISCLAIMER'))
            _buildMedicalDisclaimerSection(sections['MEDICAL DISCLAIMER']!),
          if (sections.containsKey('REMEMBER'))
            _buildDisclaimerSection(sections['REMEMBER']!),
        ],
      ),
    );
  }

  Map<String, String> _parseAnalysisResult(String result) {
    Map<String, String> sections = {};

    // Clean the result first
    String cleanResult = result.replaceAll(RegExp(r'-+$'), '').trim();

    List<String> sectionHeaders = [
      'OBSERVATION:',
      'KIDNEY CONNECTION:',
      'WHAT THIS MIGHT BE:',
      'WHAT TO DO:',
      'SIMPLE EXPLANATION:',
      'KEY WORDS TO KNOW:',
      'SOURCES & REFERENCES:',
      'MEDICAL DISCLAIMER:',
      'REMEMBER:',
    ];

    for (int i = 0; i < sectionHeaders.length; i++) {
      String currentHeader = sectionHeaders[i];
      String? nextHeader =
          i < sectionHeaders.length - 1 ? sectionHeaders[i + 1] : null;

      int startIndex = cleanResult.indexOf(currentHeader);
      if (startIndex != -1) {
        int endIndex =
            nextHeader != null
                ? cleanResult.indexOf(nextHeader)
                : cleanResult.length;
        if (endIndex == -1) endIndex = cleanResult.length;

        String content =
            cleanResult
                .substring(startIndex + currentHeader.length, endIndex)
                .replaceAll(RegExp(r'-+$'), '') // Remove trailing dashes
                .trim();

        if (content.isNotEmpty) {
          sections[currentHeader.replaceAll(':', '')] = content;
        }
      }
    }

    return sections;
  }

  Widget _buildResultSection(
    String title,
    String content,
    IconData icon,
    Color color,
  ) {
    // Show friendly section titles as in the prompt
    final friendlyTitles = {
      'OBSERVATION': 'OBSERVATION',
      'KIDNEY CONNECTION': 'KIDNEY CONNECTION',
      'WHAT THIS MIGHT BE': 'WHAT THIS MIGHT BE',
      'WHAT TO DO': 'WHAT TO DO',
      'SIMPLE EXPLANATION': 'SIMPLE EXPLANATION',
      'KEY WORDS TO KNOW': 'KEY WORDS TO KNOW',
      'REMEMBER': 'REMEMBER',
    };
    final displayTitle = friendlyTitles[title] ?? title;
    final isBulleted =
        title == 'KEY WORDS TO KNOW' || title == 'WHAT THIS MIGHT BE';
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              SizedBox(width: 12),
              Text(
                displayTitle,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          _buildFormattedText(
            _cleanText(content),
            forceSplitOnPunctuation: isBulleted,
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationSection(String content) {
    Color bgColor = Colors.grey[50]!;
    Color borderColor = Colors.grey[300]!;
    Color iconColor = Colors.grey[600]!;
    IconData icon = Icons.info_outline;

    String cleanContent = _cleanText(content);

    if (cleanContent.contains('URGENT')) {
      bgColor = Colors.red[50]!;
      borderColor = Colors.red[300]!;
      iconColor = Colors.red[600]!;
      icon = Icons.priority_high;
    } else if (cleanContent.contains('HIGH')) {
      bgColor = Colors.orange[50]!;
      borderColor = Colors.orange[300]!;
      iconColor = Colors.orange[600]!;
      icon = Icons.warning;
    } else if (cleanContent.contains('MEDIUM')) {
      bgColor = Colors.yellow[50]!;
      borderColor = Colors.yellow[600]!;
      iconColor = Colors.yellow[700]!;
      icon = Icons.schedule;
    } else if (cleanContent.contains('LOW')) {
      bgColor = Colors.green[50]!;
      borderColor = Colors.green[300]!;
      iconColor = Colors.green[600]!;
      icon = Icons.check_circle_outline;
    }

    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              SizedBox(width: 8),
              Text(
                'Recommendation',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: iconColor,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          _buildFormattedText(cleanContent),
        ],
      ),
    );
  }

  Widget _buildDisclaimerSection(String content) {
    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.gavel, color: Colors.grey[600], size: 18),
          SizedBox(width: 12),
          Expanded(child: _buildFormattedText(_cleanText(content))),
        ],
      ),
    );
  }

  Widget _buildSourcesSection(String content) {
    // Parse the content to extract URLs and create clickable links
    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.source, size: 20, color: Colors.blue[700]),
              ),
              SizedBox(width: 12),
              Text(
                'SOURCES & REFERENCES',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue[900],
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          _buildSourcesWithLinks(content),
          SizedBox(height: 8),
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.verified_user, size: 16, color: Colors.blue[800]),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'All sources are from verified medical institutions and organizations',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[800],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicalDisclaimerSection(String content) {
    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[300]!, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.medical_information, color: Colors.red[700], size: 22),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'MEDICAL DISCLAIMER',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[900],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            _cleanText(content),
            style: TextStyle(fontSize: 14, color: Colors.red[900], height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildSourcesWithLinks(String content) {
    List<Widget> sourceWidgets = [];

    // Split content into lines and parse each for links
    final lines = content.split('\n');

    for (String line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      // Try to extract URL from the line
      final urlRegex = RegExp(r'https?://[^\s\)]+');
      final match = urlRegex.firstMatch(line);

      if (match != null) {
        final url = match.group(0)!;
        // Extract the text before the URL
        String description = line.substring(0, match.start).trim();
        // Clean up common prefixes
        description = description.replaceAll(RegExp(r'^[-*•]\s*'), '');
        description = description.replaceAll('Link:', '').trim();

        sourceWidgets.add(
          Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (description.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: _buildRichTextWithBold(description),
                  ),
                InkWell(
                  onTap: () => _launchURL(url),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[300]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.link, size: 16, color: Colors.blue[700]),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            url,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[700],
                              decoration: TextDecoration.underline,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.open_in_new,
                          size: 14,
                          color: Colors.blue[700],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (line.isNotEmpty) {
        // Line without URL, just display as text
        sourceWidgets.add(
          Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: _buildFormattedText(line),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sourceWidgets,
    );
  }

  Future<void> _launchURL(String url) async {
    // Normalize – add https:// if missing
    String cleaned = url.trim();
    if (!cleaned.startsWith('http://') && !cleaned.startsWith('https://')) {
      cleaned = 'https://$cleaned';
    }

    Uri? uri;
    try {
      uri = Uri.tryParse(cleaned);
    } catch (_) {
      uri = null;
    }

    if (uri == null) {
      _showErrorDialog('Invalid link: $url');
      return;
    }

    try {
      // Try external browser first
      final okExt = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!okExt) {
        // Fallback to in-app web view (custom tab / SFSafariViewController)
        final okInApp = await launchUrl(uri, mode: LaunchMode.inAppWebView);
        if (!okInApp) {
          _showErrorDialog('Could not open link: $url');
        }
      }
    } catch (e) {
      // Last resort fallback
      try {
        final okInApp = await launchUrl(uri, mode: LaunchMode.inAppWebView);
        if (!okInApp) {
          _showErrorDialog('Could not open link: $url');
        }
      } catch (e2) {
        _showErrorDialog('Could not open link: $url');
      }
    }
  }

  String _cleanText(String text) {
    return text
        .replaceAll(
          RegExp(r'-{2,}$', multiLine: true),
          '',
        ) // Remove trailing dashes
        .replaceAll(
          RegExp(r'\*{3,}'),
          '**',
        ) // Normalize excessive asterisks to double
        .replaceAll(RegExp(r'[ \t]+'), ' ') // Normalize spaces
        .trim();
  }

  /// Renders the Gemini response text, supporting:
  /// - Markdown-style **bold** words
  /// - Bullet points using "-" or "*"
  /// - Paragraphs and line breaks as in the original response
  Widget _buildFormattedText(
    String text, {
    bool forceSplitOnPunctuation = false,
  }) {
    // First, clean up any excessive whitespace while preserving intentional breaks
    text = text.replaceAll(
      RegExp(r'\n\s*\n\s*\n+'),
      '\n\n',
    ); // Max 2 consecutive newlines
    text = text.replaceAll(RegExp(r'[ \t]+'), ' '); // Normalize spaces/tabs

    final lines = text.split('\n');
    List<Widget> widgets = [];

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i].trim();
      if (line.isEmpty) {
        widgets.add(SizedBox(height: 8)); // Add spacing for empty lines
        continue;
      }

      // Check if it's a bullet point
      final bulletMatch = RegExp(r'^[-*•]\s+(.*)').firstMatch(line);
      if (bulletMatch != null) {
        widgets.add(
          Padding(
            padding: EdgeInsets.only(left: 8, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "• ",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Expanded(child: _buildRichTextWithBold(bulletMatch.group(1)!)),
              ],
            ),
          ),
        );
      } else {
        // Regular paragraph
        widgets.add(
          Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: _buildRichTextWithBold(line),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  /// Helper: Builds RichText with **bold** markdown-style support.
  Widget _buildRichTextWithBold(String text) {
    final spans = <InlineSpan>[];
    final boldRegex = RegExp(r'\*\*([^*]+)\*\*');
    int lastEnd = 0;

    for (final match in boldRegex.allMatches(text)) {
      // Add text before the bold part
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }

      // Add the bold part
      spans.add(
        TextSpan(
          text: match.group(1),
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
      );
      lastEnd = match.end;
    }

    // Add remaining text
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.4),
        children: spans.isEmpty ? [TextSpan(text: text)] : spans,
      ),
    );
  }

  /// Highlights markdown-style **bold** text in a line.
  List<InlineSpan> _highlightMarkdownBold(String text) {
    final spans = <InlineSpan>[];
    final boldRegex = RegExp(r'\*\*(.+?)\*\*');
    int last = 0;
    for (final match in boldRegex.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      );
      last = match.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return spans;
  }

  // Utility kept for compatibility, but not used in new _buildFormattedText
  List<InlineSpan> _highlightImportant(String text, List<String> boldWords) {
    List<InlineSpan> spans = [];
    spans.add(TextSpan(text: text));
    return spans;
  }
}
