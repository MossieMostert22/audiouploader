import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'google_drive_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Media App",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B3E19),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

/// Dedicated Splash Screen Widget
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const AudiobookUploader(),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Center(
          child: Image.asset(
            'assets/loader.png',
            width: 260,
            height: 260,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

/// Stateful Flip Card Widget for Listener Display
class _ListenerFlipCard extends StatelessWidget {
  final Map<String, dynamic> listener;
  final Function(String) onDelete;

  const _ListenerFlipCard({
    required this.listener,
    required this.onDelete,
  });

  String _formatDate(String? dateString) {
    if (dateString == null) return 'Unknown';
    try {
      // ISO 8601 format: 2026-09-06T16:10:15.860441
      final dateTime = DateTime.parse(dateString);
      return '${dateTime.month}/${dateTime.day}/${dateTime.year}';
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF6B3E19).withValues(alpha: 0.05),
              const Color(0xFFD4AF37).withValues(alpha: 0.08),
            ],
          ),
          border: Border.all(
            color: const Color(0xFF6B3E19).withValues(alpha: 0.2),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Listener Name
              Text(
                listener['listenerName'] ?? 'Unknown',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3A2218),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              // Phone Number
              Text(
                listener['phoneNumber'] ?? '',
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B3E19),
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              // Access Code
              Text(
                listener['accessCode'] ?? 'N/A',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: Color(0xFF6B3E19),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              // Date Created Label
              const Text(
                'Date Created',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Main Application Widget
class AudiobookUploader extends StatefulWidget {
  const AudiobookUploader({super.key});

  @override
  State<AudiobookUploader> createState() => _AudiobookUploaderState();
}

class _AudiobookUploaderState extends State<AudiobookUploader> {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'https://www.googleapis.com/auth/drive',
    ],
  );

  GoogleSignInAccount? _currentUser;
  String _status = 'Not signed in';
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _appOwnerName = 'Kingsanctuary';
  String _listenerName = 'Grandma';
  String _personalMessage = 'With Love From Mossie';
  String _selectedListenerName = ''; // Currently selected listener for upload/delete operations
  final List<Map<String, dynamic>> _listeners = []; // {phoneNumber, accessCode, listenerName, directory}

  // Storage metrics
  int _totalDriveUsedBytes = 0;
  int _totalDriveAvailableBytes = 0;

  late TextEditingController _phoneController;
  late TextEditingController _appOwnerController;
  late TextEditingController _listenerController;
  late TextEditingController _messageController;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();
    _appOwnerController = TextEditingController(text: _appOwnerName);
    _listenerController = TextEditingController(text: _listenerName);
    _messageController = TextEditingController(text: _personalMessage);
    _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount? account) {
      if (mounted) {
        setState(() {
          _currentUser = account;
          if (account != null) {
            _status = 'Signed in as ${account.email}';
            // Load listeners and app owner name immediately after sign-in
            // This way the home screen name changes right away, and Settings opens with data pre-loaded
            _loadListenersFromDrive();
          } else {
            _status = 'Not signed in';
          }
        });
      }
    });

    _googleSignIn.signInSilently();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _appOwnerController.dispose();
    _listenerController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    try {
      await _googleSignIn.signIn();
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = 'Sign in failed: $error';
        });
      }
    }
  }

  Future<void> _handleSignOut() async {
    await _googleSignIn.signOut();
    if (mounted) {
      setState(() {
        _status = 'Signed out';
      });
    }
  }

  String _generateAccessCode() {
    final random = DateTime.now().millisecond % 1000000;
    return random.toString().padLeft(6, '0');
  }

  Future<void> _saveAccessCodeToGoogleDrive(String phoneNumber, String accessCode) async {
    if (_currentUser == null) return;
    try {
      print('🔍 DEBUG: _appOwnerName = $_appOwnerName');
      print('🔍 DEBUG: _listenerName = $_listenerName');
      final driveService = GoogleDriveService(_currentUser!);

      // Initialize the drive service (ensures main folder exists)
      await driveService.initialize(folderName: _appOwnerName);

      // Create listener directory name (sanitize for folder name)
      final listenerDirectory = _listenerName.replaceAll(' ', '_');

      // Create the listener's folder structure immediately
      await driveService.createListenerFolder(listenerDirectory);

      // Write access code to listener-specific access_codes.json
      final accessCodes = {
        phoneNumber: {
          'code': accessCode,
          'listenerName': _listenerName,
          'personalMessage': _personalMessage,
          'createdAt': DateTime.now().toIso8601String(),
        }
      };
      await driveService.writeListenerAccessCodes(listenerDirectory, accessCodes);

      // Create default listener files (catalog.json, requests.json)
      await driveService.createListenerDefaultFiles(listenerDirectory);

      // Check if this is the first listener
      final isFirstListener = _listeners.isEmpty;

      if (isFirstListener) {
        // Create uploader_ini.json with first listener
        await driveService.createUploaderIni(_appOwnerName, [listenerDirectory]);
        print('✓ First listener created - uploader_ini.json initialized');
      } else {
        // Update uploader_ini.json with new listener
        final listenerDirs = _listeners.map((l) => l['directory'] as String).toList();
        listenerDirs.add(listenerDirectory);
        await driveService.updateUploaderIni(_appOwnerName, listenerDirs);
        print('✓ Listener added - uploader_ini.json updated');
      }

      if (mounted) {
        setState(() {
          _listeners.add({
            'phoneNumber': phoneNumber,
            'accessCode': accessCode,
            'listenerName': _listenerName,
            'directory': listenerDirectory,
          });
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving access code: $e')),
        );
      }
    }
  }

  Future<void> _loadListenersFromDrive() async {
    if (_currentUser == null) return;

    try {
      final driveService = GoogleDriveService(_currentUser!);

      // FIRST: Search for uploader_ini.json WITHOUT assuming folder name
      // This works on fresh installs when we don't know the app owner name yet
      var uploaderIni = await driveService.searchForUploaderIni();

      if (uploaderIni == null) {
        // Fresh install - no uploader_ini.json found anywhere
        print('✓ Fresh install detected - no uploader_ini.json found');
        return;
      }

      // uploader_ini.json found! Extract the app owner name from it
      final savedAppOwnerName = uploaderIni['appOwnerName'] as String?;
      if (savedAppOwnerName != null && savedAppOwnerName != _appOwnerName) {
        print('ℹ️  App owner name from Drive: $savedAppOwnerName (current: $_appOwnerName)');
        setState(() {
          _appOwnerName = savedAppOwnerName;
          // KEY FIX: Sync the controller text so Settings dialog shows correct name
          _appOwnerController.text = savedAppOwnerName;
        });
      }

      // NOW initialize with the correct app owner name
      await driveService.initialize(folderName: _appOwnerName);

      // Load listener directories from uploader_ini.json
      final listenerDirectories = (uploaderIni['listeners'] as List?)?.cast<String>() ?? [];

      if (listenerDirectories.isEmpty) {
        print('✓ No listeners found in uploader_ini.json');
        return;
      }

      // Fetch total Drive storage once
      final storageQuota = await driveService.getStorageQuota();
      final totalDriveUsedBytes = storageQuota['usedBytes'] ?? 0;
      final totalDriveAvailableBytes = storageQuota['availableBytes'] ?? 0;

      // Load each listener's data
      final loadedListeners = <Map<String, dynamic>>[];
      for (final directory in listenerDirectories) {
        try {
          // Read access codes from listener-specific folder
          final accessCodes = await driveService.readListenerAccessCodes(directory);

          // Load catalog for this listener (for instant management screen display)
          final catalog = await driveService.readListenerCatalog(directory);

          // Calculate listener folder size (for storage management display)
          // Get the listener's folder ID first
          final listenerFolderId = await driveService.getListenerFolderId(directory);
          final listenerFolderBytes = await driveService.calculateFolderSize(listenerFolderId);

          // Each listener should have one phone number entry
          accessCodes.forEach((phoneNumber, codeData) {
            if (codeData is Map && codeData.containsKey('code')) {
              loadedListeners.add({
                'phoneNumber': phoneNumber,
                'accessCode': codeData['code'].toString(),
                'listenerName': codeData['listenerName'] ?? 'Unknown',
                'directory': directory,
                'catalog': catalog, // Cache files for instant management screen display
                'folderBytes': listenerFolderBytes, // Storage used by this listener
              });
            }
          });
        } catch (e) {
          print('Warning: Could not load listener $directory: $e');
        }
      }

      setState(() {
        _listeners.clear();
        _listeners.addAll(loadedListeners);
        // Set first listener as selected by default
        if (_listeners.isNotEmpty) {
          _selectedListenerName = _listeners[0]['listenerName'] ?? '';
        }
        // Store storage metrics
        _totalDriveUsedBytes = totalDriveUsedBytes;
        _totalDriveAvailableBytes = totalDriveAvailableBytes;
      });
      print('✓ Loaded ${loadedListeners.length} listeners from uploader_ini.json');
      print('✓ Storage: ${(_totalDriveUsedBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB used, ${(_totalDriveAvailableBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB available');
    } catch (e) {
      debugPrint('Error loading listeners from Drive: $e');
    }
  }

  Future<void> _deleteListenerFromDrive(String phoneNumber) async {
    if (_currentUser == null) return;
    try {
      final driveService = GoogleDriveService(_currentUser!);
      // Initialize the drive service
      await driveService.initialize(folderName: _appOwnerName);

      // Find the listener being deleted
      final listenerToDelete = _listeners.firstWhere(
        (l) => l['phoneNumber'] == phoneNumber,
        orElse: () => {},
      );

      if (listenerToDelete.isEmpty) {
        throw Exception('Listener not found');
      }

      final listenerDirectory = listenerToDelete['directory'] as String;

      // Get the current listener directories from uploader_ini.json
      final uploaderIni = await driveService.readUploaderIni();
      if (uploaderIni != null) {
        final currentListeners = (uploaderIni['listeners'] as List?)?.cast<String>() ?? [];
        // Remove the deleted listener from the list
        currentListeners.removeWhere((d) => d == listenerDirectory);
        // Update uploader_ini.json with the new listener list
        await driveService.updateUploaderIni(_appOwnerName, currentListeners);
        print('✓ uploader_ini.json updated after listener deletion');
      }

      // Remove from local list
      setState(() {
        _listeners.removeWhere(
          (l) => l['phoneNumber'] == phoneNumber,
        );
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Listener removed: $phoneNumber'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting listener: $e')),
        );
      }
    }
  }

  /// Update app owner name in uploader_ini.json if it has changed
  /// Only initializes if uploader_ini.json exists (don't create folders on fresh install)
  Future<void> _updateAppOwnerNameIfChanged() async {
    if (_currentUser == null) return;

    try {
      final driveService = GoogleDriveService(_currentUser!);

      // SEARCH for uploader_ini.json (works even if _appOwnerName is wrong)
      final uploaderIni = await driveService.searchForUploaderIni();

      if (uploaderIni == null) {
        // No uploader_ini.json yet (fresh install) - nothing to update
        print('ℹ️  No uploader_ini.json found - skipping app owner name update (fresh install)');
        return;
      }

      // uploader_ini.json found, extract the correct app owner name
      final savedAppOwnerName = uploaderIni['appOwnerName'] as String?;
      if (savedAppOwnerName == null) return;

      // Update _appOwnerName if it changed
      if (savedAppOwnerName != _appOwnerName) {
        print('ℹ️  Updating _appOwnerName from $_appOwnerName to $savedAppOwnerName');
        setState(() => _appOwnerName = savedAppOwnerName);
      }

      // Now safe to initialize with correct app owner name
      await driveService.initialize(folderName: _appOwnerName);

      // Check if the user typed a NEW app owner name in the Settings dialog
      // If so, update uploader_ini.json with the new name
      if (_appOwnerName != savedAppOwnerName) {
        final listeners = (uploaderIni['listeners'] as List?)?.cast<String>() ?? [];
        await driveService.updateUploaderIni(_appOwnerName, listeners);
        print('✓ App owner name updated in uploader_ini.json: $savedAppOwnerName → $_appOwnerName');
      }
    } catch (e) {
      print('Note: Could not update app owner name in uploader_ini.json: $e');
      // Don't throw - this is not critical if there are no listeners yet
    }
  }

  /// Load listener catalog with proper service initialization
  /// Prevents "Null check operator used on a null value" error
  /// by initializing GoogleDriveService with app owner name first
  Future<Map<String, dynamic>> _loadListenerCatalog(String listenerDirectory) async {
    if (_currentUser == null) {
      return {'audio': [], 'video': [], 'text': [], 'pdf': []};
    }

    try {
      final driveService = GoogleDriveService(_currentUser!);
      // KEY FIX: Initialize with app owner name before reading listener catalog
      await driveService.initialize(folderName: _appOwnerName);
      return await driveService.readListenerCatalog(listenerDirectory);
    } catch (e) {
      print('Error reading listener catalog: $e');
      return {'audio': [], 'video': [], 'text': [], 'pdf': []};
    }
  }

  /// Update file download status with proper service initialization
  Future<void> _updateFileDownloadStatus(String listenerDirectory, String fileId, bool downloaded) async {
    if (_currentUser == null) return;

    try {
      final driveService = GoogleDriveService(_currentUser!);
      // Initialize with app owner name
      await driveService.initialize(folderName: _appOwnerName);
      await driveService.updateFileDownloadStatus(listenerDirectory, fileId, downloaded);
    } catch (e) {
      print('Error updating file download status: $e');
    }
  }

  /// Delete media file with proper service initialization
  Future<void> _deleteMediaFile(String fileId, String listenerDirectory) async {
    if (_currentUser == null) return;

    try {
      final driveService = GoogleDriveService(_currentUser!);
      // Initialize with app owner name
      await driveService.initialize(folderName: _appOwnerName);
      await driveService.deleteMediaFile(fileId, listenerDirectory);
    } catch (e) {
      print('Error deleting file: $e');
    }
  }

  void _showSettingsDialog() async {
    _phoneController.clear();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Storage Usage Section
                const Text(
                  'Google Drive Storage',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                _buildStorageBar(
                  label: 'Total Usage',
                  usedBytes: _totalDriveUsedBytes,
                  totalBytes: _totalDriveUsedBytes + _totalDriveAvailableBytes,
                ),
                const SizedBox(height: 24),

                // App Owner Name Section (local only, not sent to JSON)
                const Text(
                  'App Owner Name',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const Text(
                  '(your app branding, not sent to listener)',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'e.g., Kingsanctuary, Dave',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  controller: _appOwnerController,
                  onChanged: (value) {
                    setState(() => _appOwnerName = value);
                  },
                ),
                const SizedBox(height: 24),

                // Listener Name Section (sent to JSON)
                const Text(
                  'Listener Name',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const Text(
                  '(displayed on listener device)',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'e.g., Grandma, Mom, Friend',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  controller: _listenerController,
                  onChanged: (value) {
                    setState(() => _listenerName = value);
                  },
                ),
                const SizedBox(height: 24),

                // Personal Message Section
                const Text(
                  'Personal Message',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const Text(
                  '(max 80 characters, displays on listener device)',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'e.g., Get Well Soon Mom',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  controller: _messageController,
                  maxLength: 80,
                  maxLines: 2,
                  onChanged: (value) {
                    setState(() => _personalMessage = value);
                  },
                ),
                const SizedBox(height: 24),

                // Manage Listener Access Section
                const Text(
                  'Add New Listener',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    hintText: '+1 234 567 8900',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Generate Access Code'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6B3E19),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () async {
                      final phoneNumber = _phoneController.text.trim();
                      if (phoneNumber.isEmpty) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a phone number'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                        return;
                      }

                      final accessCode = _generateAccessCode();

                      // Save to Google Drive
                      await _saveAccessCodeToGoogleDrive(phoneNumber, accessCode);

                      // Clear input and refresh dialog to show new listener
                      _phoneController.clear();
                      setDialogState(() {
                        // Rebuild dialog to show updated _listeners list
                      });

                      // Show success message
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '✓ Code: $accessCode for $phoneNumber',
                            ),
                            duration: const Duration(seconds: 3),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: 24),

                // Select Listener Section
                const Text(
                  'Select Listener to Manage',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const Text(
                  '(uploads/deletes will use this listener\'s directory)',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                if (_listeners.isNotEmpty)
                  DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedListenerName.isEmpty ? _listeners[0]['listenerName'] : _selectedListenerName,
                    items: _listeners.map((listener) {
                      return DropdownMenuItem<String>(
                        value: listener['listenerName'],
                        child: Text(listener['listenerName'] ?? 'Unknown'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        _selectedListenerName = value ?? '';
                      });
                    },
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'No listeners yet. Add one below.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                const SizedBox(height: 24),

                // Manage Selected Listener
                const Text(
                  'Manage Selected Listener',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                if (_listeners.isNotEmpty)
                  Builder(
                    builder: (context) {
                      // Get the selected listener from the list
                      final selectedListener = _listeners.firstWhere(
                        (l) => l['listenerName'] == _selectedListenerName,
                        orElse: () => _listeners[0],
                      );

                      return _buildManagementCard(
                        listener: selectedListener,
                        onDelete: (phoneNumber) async {
                          final listenerName = selectedListener['listenerName'] ?? 'Listener';
                          final shouldDelete = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete Listener'),
                              content: Text('Are you sure you want to delete $listenerName?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );

                          if (shouldDelete == true) {
                            await _deleteListenerFromDrive(phoneNumber);
                            setDialogState(() {
                              _selectedListenerName = '';
                            });
                          }
                        },
                        onEdit: () {
                          // Open Listener Manage Screen popup instead of editing in Settings
                          Navigator.pop(context);  // Close Settings first
                          _showListenerManageScreen(selectedListener);
                        },
                      );
                    },
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'No listeners yet. Add one to get started.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                // Update app owner name in uploader_ini.json if it changed
                await _updateAppOwnerNameIfChanged();
                Navigator.pop(context);
              },
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _showListenerManageScreen(Map<String, dynamic> listener) {
    final listenerDirectory = listener['directory'] as String;
    final listenerName = listener['listenerName'] as String? ?? 'Unknown';

    // Get cached catalog (loaded at startup, no Drive read needed)
    final cachedCatalog = listener['catalog'] as Map<String, dynamic>? ?? {'audio': [], 'video': [], 'text': [], 'pdf': []};

    // Initialize state ONCE, OUTSIDE the StatefulBuilder builder so it persists across rebuilds
    final dialogCatalog = Map<String, dynamic>.from(cachedCatalog);
    // Deep copy the lists
    for (final key in dialogCatalog.keys) {
      final list = dialogCatalog[key] as List?;
      if (list != null) {
        dialogCatalog[key] = List<Map<String, dynamic>>.from(
          list.map((item) => Map<String, dynamic>.from(item as Map))
        );
      }
    }

    // Track operations to sync when dialog closes (initialize ONCE, outside builder)
    final deletedFileIds = <String>[];
    final downloadStatusChanges = <String, bool>{};

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {

          return AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(listenerName),
                // Close (X) button
                IconButton(
                  icon: const Icon(Icons.close, size: 24),
                  onPressed: () async {
                    // Sync all changes to Drive when closing
                    Navigator.pop(context);

                    // Background sync (fire and forget)
                    for (final fileId in deletedFileIds) {
                      try {
                        await _deleteMediaFile(fileId, listenerDirectory);
                      } catch (e) {
                        print('Background delete error: $e');
                      }
                    }

                    for (final fileId in downloadStatusChanges.keys) {
                      try {
                        await _updateFileDownloadStatus(
                          listenerDirectory,
                          fileId,
                          downloadStatusChanges[fileId] ?? false,
                        );
                      } catch (e) {
                        print('Background status update error: $e');
                      }
                    }

                    // CRITICAL FIX: Update the cached catalog in the listener object
                    // so that when the dialog is reopened, it shows the updated state
                    listener['catalog'] = dialogCatalog;

                    // Refresh storage metrics after deletion sync completes
                    if (deletedFileIds.isNotEmpty) {
                      try {
                        final driveService = GoogleDriveService(_currentUser!);

                        // Refresh this listener's folder size
                        final listenerFolderId = await driveService.getListenerFolderId(listenerDirectory);
                        final updatedFolderBytes = await driveService.calculateFolderSize(listenerFolderId);

                        int listenerIndex = _listeners.indexWhere((l) => l['directory'] == listenerDirectory);
                        if (listenerIndex != -1) {
                          setState(() {
                            _listeners[listenerIndex]['folderBytes'] = updatedFolderBytes;
                          });
                        }

                        // Refresh total storage quota
                        final updatedStorageQuota = await driveService.getStorageQuota();
                        setState(() {
                          _totalDriveUsedBytes = updatedStorageQuota['usedBytes'] ?? 0;
                          _totalDriveAvailableBytes = updatedStorageQuota['availableBytes'] ?? 0;
                        });

                        print('✓ Storage metrics refreshed after deletion');
                      } catch (e) {
                        print('Storage refresh error after deletion: $e');
                      }
                    }
                  },
                  tooltip: 'Close',
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Storage Usage for this Listener
                  const Text(
                    'Storage Usage',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  _buildStorageBar(
                    label: listenerName,
                    usedBytes: listener['folderBytes'] as int? ?? 0,
                    totalBytes: _totalDriveUsedBytes + _totalDriveAvailableBytes,
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),

                  // File List (from cached data - instant display)
                  Builder(
                    builder: (context) {
                      final catalog = dialogCatalog;

                    // Combine all files from all categories
                    final allFiles = <Map<String, dynamic>>[];
                    final fileTypes = ['audio', 'video', 'text', 'pdf'];
                    for (final fileType in fileTypes) {
                      final files = catalog[fileType] as List? ?? [];
                      allFiles.addAll(files.cast<Map<String, dynamic>>());
                    }

                    if (allFiles.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24.0),
                          child: Text(
                            'No files uploaded yet',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      );
                    }

                    return Column(
                      children: allFiles.map<Widget>((file) {
                        final fileName = file['fileName'] as String? ?? 'Unknown';
                        final fileType = file['type'] as String? ?? 'unknown';
                        final fileId = file['id'] as String? ?? '';
                        final isDownloaded = file['downloaded'] as bool? ?? false;

                        // Get file icon based on type
                        IconData fileIcon;
                        switch (fileType) {
                          case 'audio':
                            fileIcon = Icons.audio_file;
                            break;
                          case 'video':
                            fileIcon = Icons.video_file;
                            break;
                          case 'text':
                            fileIcon = Icons.description;
                            break;
                          case 'pdf':
                            fileIcon = Icons.picture_as_pdf;
                            break;
                          default:
                            fileIcon = Icons.file_present;
                        }

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              // File Icon
                              Icon(fileIcon, size: 24, color: const Color(0xFF6B3E19)),
                              const SizedBox(width: 12),

                              // File Name (expandable)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fileName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Download Status Checkbox (track changes, defer sync)
                              Checkbox(
                                value: isDownloaded,
                                onChanged: (value) {
                                  // Track the change (will sync when dialog closes)
                                  downloadStatusChanges[fileId] = value ?? false;

                                  // Update local catalog for immediate UI feedback
                                  for (final fileType in ['audio', 'video', 'text', 'pdf']) {
                                    final files = dialogCatalog[fileType] as List? ?? [];
                                    for (final f in files) {
                                      if ((f as Map)['id'] == fileId) {
                                        f['downloaded'] = value ?? false;
                                      }
                                    }
                                  }

                                  setDialogState(() {});
                                  print('Marked $fileName as downloaded: $value (will sync on close)');
                                },
                              ),

                              // Delete Button (optimistic UI update, deferred Drive sync)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                onPressed: () async {
                                  final shouldDelete = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Delete File'),
                                      content: Text('Delete "$fileName"?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (shouldDelete == true) {
                                    // IMPORTANT: Optimistic UI update (immediate feedback)
                                    // Remove from local catalog to hide from UI
                                    deletedFileIds.add(fileId);

                                    // Remove from the dialog's catalog
                                    for (final fileType in ['audio', 'video', 'text', 'pdf']) {
                                      final files = dialogCatalog[fileType] as List?;
                                      files?.removeWhere(
                                        (f) => f is Map && f['id'] == fileId,
                                      );
                                    }

                                    // Update UI immediately (no Drive call yet)
                                    setDialogState(() {});

                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('✓ $fileName removed from list'),
                                          backgroundColor: Colors.orange,
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  }
                                },
                                tooltip: 'Delete File',
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Select & Share Media'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6B3E19),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () async {
                  // Set the current listener as selected for upload
                  setState(() {
                    _selectedListenerName = listenerName;
                  });
                  Navigator.pop(context);
                  await _pickAndUploadFile();
                },
              ),
            ),
          ],
        );
        },
      ),
    );
  }

  Future<void> _pickAndUploadFile() async {
    if (_currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in first')),
        );
      }
      return;
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final file = File(filePath);
        final fileSize = await file.length();

        // CRITICAL: Validate file size before upload
        // Check if upload would exceed 15GB limit
        const totalDriveLimit = 15000000000; // 15GB
        const minAvailableWarning = 524288000; // 500MB warning threshold

        if (_totalDriveUsedBytes + fileSize > totalDriveLimit) {
          final availableMB = (_totalDriveAvailableBytes / (1024 * 1024)).toStringAsFixed(1);
          final fileSizeMB = (fileSize / (1024 * 1024)).toStringAsFixed(1);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '⚠️ Upload blocked: File is ${fileSizeMB}MB but only ${availableMB}MB available',
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }

        // Second-phase warning: Check if available space is getting low (< 500MB)
        if (_totalDriveAvailableBytes < minAvailableWarning) {
          final availableMB = (_totalDriveAvailableBytes / (1024 * 1024)).toStringAsFixed(1);
          final fileSizeMB = (fileSize / (1024 * 1024)).toStringAsFixed(1);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '⚠️ Low storage: Only ${availableMB}MB available after uploading ${fileSizeMB}MB file',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }

        setState(() {
          _isUploading = true;
          _uploadProgress = 0.0;
          _status = 'Preparing media...';
        });
        await _uploadFile(filePath);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Error: $e';
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _uploadFile(String filePath) async {
    try {
      final driveService = GoogleDriveService(_currentUser!);
      await driveService.initialize(folderName: _appOwnerName);

      // Get the directory for the selected listener
      final listenerDirectory = _selectedListenerName.replaceAll(' ', '_');

      await driveService.uploadMediaFile(
        filePath,
        (progress) {
          if (mounted) {
            setState(() {
              _uploadProgress = progress;
              _status =
                  'Sharing media... ${(_uploadProgress * 100).toStringAsFixed(1)}%';
            });
          }
        },
        listenerDirectory: listenerDirectory,
      );

      // CRITICAL: Refresh the listener's cached catalog after upload
      // so that when the management popup is reopened, it shows the new file
      final updatedCatalog = await driveService.readListenerCatalog(listenerDirectory);

      // Find the listener in _listeners and update its cached catalog
      final listenerIndex = _listeners.indexWhere(
        (listener) => (listener['directory'] as String?)?.replaceAll(' ', '_') == listenerDirectory,
      );
      if (listenerIndex != -1) {
        _listeners[listenerIndex]['catalog'] = updatedCatalog;

        // CRITICAL: Refresh listener folder size and total storage after upload
        final listenerFolderId = await driveService.getListenerFolderId(listenerDirectory);
        final updatedFolderBytes = await driveService.calculateFolderSize(listenerFolderId);
        _listeners[listenerIndex]['folderBytes'] = updatedFolderBytes;
        print('✓ Listener catalog and storage refreshed after upload');

        // Also refresh total storage quota
        final updatedStorageQuota = await driveService.getStorageQuota();
        _totalDriveUsedBytes = updatedStorageQuota['usedBytes'] ?? 0;
        _totalDriveAvailableBytes = updatedStorageQuota['availableBytes'] ?? 0;
      }

      if (mounted) {
        setState(() {
          _status = 'Media shared successfully!';
          _isUploading = false;
          _uploadProgress = 0.0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Error: $e';
          _isUploading = false;
          _uploadProgress = 0.0;
        });
      }
    }
  }

  /// Build a management card with Edit and Delete icons
  Widget _buildManagementCard({
    required Map<String, dynamic> listener,
    required Function(String) onDelete,
    required VoidCallback onEdit,
  }) {
    return Column(
      children: [
        // Static Card with all info
        _ListenerFlipCard(
          listener: listener,
          onDelete: onDelete,
        ),
        // Edit and Delete icons at bottom
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Edit icon (left)
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                color: Colors.blue,
                iconSize: 24,
                onPressed: onEdit,
                tooltip: 'Edit Listener',
              ),
              // Delete icon (right)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                color: Colors.red,
                iconSize: 24,
                onPressed: () {
                  final phoneNumber = listener['phoneNumber'] ?? '';
                  onDelete(phoneNumber);
                },
                tooltip: 'Delete Listener',
              ),
            ],
          ),
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Image
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/background.png'),
                fit: BoxFit.cover,
              ),
            ),
            child: Container(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),

          // Main Layout
          SafeArea(
            child: Column(
              children: [
                // Beautiful Header with Title and Settings Button
                Padding(
                  padding: const EdgeInsets.only(top: 16.0, left: 20, right: 20, bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              '$_appOwnerName\'s',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.greatVibes(
                                fontSize: 32,
                                color: const Color(0xFF4A5E35),
                                shadows: [
                                  Shadow(
                                    blurRadius: 6,
                                    color: Colors.white.withValues(alpha: 0.9),
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              'Media App',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.cormorantGaramond(
                                fontSize: 24,
                                fontStyle: FontStyle.italic,
                                color: const Color(0xFF4A5E35),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_currentUser != null)
                        IconButton(
                          icon: const Icon(Icons.settings_rounded),
                          color: const Color(0xFF6B3E19),
                          iconSize: 28,
                          onPressed: _showSettingsDialog,
                          tooltip: 'Settings',
                        ),
                    ],
                  ),
                ),

                // Subtitle
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Text(
                    'Sharing media with you',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cormorantGaramond(
                      fontSize: 16,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF5C4033),
                    ),
                  ),
                ),

                // Header Area (Compact)
                const Expanded(
                  flex: 2,
                  child: Padding(
                    padding: EdgeInsets.only(left: 20, right: 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [],
                    ),
                  ),
                ),

                // Interactive Content Area
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Glassy Status Card (shows signed-in email or login prompt)
                          if (_currentUser != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: BackdropFilter(
                                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 22,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: const Color(0xFFD4AF37).withValues(alpha: 0.6),
                                      width: 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.06),
                                        blurRadius: 15,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    'Signed in as\n${_currentUser?.email ?? ""}',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.lora(
                                      fontSize: 15,
                                      color: const Color(0xFF3A2218),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 24),

                          // Sign In & Upload Controls
                          if (_currentUser == null)
                            _buildWarmGlassButton(
                              label: 'Connect Google Account',
                              onPressed: _handleSignIn,
                              isEnabled: true,
                              icon: Icons.login_rounded,
                            )
                          else ...[
                            const SizedBox(height: 32),

                            // Progress Indicator
                            if (_isUploading)
                              Column(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: LinearProgressIndicator(
                                      value: _uploadProgress == 0.0
                                          ? null
                                          : _uploadProgress,
                                      minHeight: 8,
                                      backgroundColor: Colors.white.withValues(alpha: 0.4),
                                      valueColor: const AlwaysStoppedAnimation<Color>(
                                        Color(0xFF8B5A2B),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                              ),

                            // Sign Out
                            _buildWarmGlassButton(
                              label: 'Sign Out',
                              onPressed: _handleSignOut,
                              isEnabled: true,
                              isSecondary: true,
                            ),
                          ],
                        ],
                      ),
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

  /// Refined Glassy Button for Warm Elegance (Overflow-Safe)
  Widget _buildWarmGlassButton({
    required String label,
    required VoidCallback? onPressed,
    required bool isEnabled,
    IconData? icon,
    bool isSecondary = false,
  }) {
    final primaryColor = isSecondary ? const Color(0xFF8B2626) : const Color(0xFF3A2218);
    final borderColor = isSecondary 
        ? Colors.red.withValues(alpha: 0.3) 
        : const Color(0xFFD4AF37).withValues(alpha: 0.7);

    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isEnabled
                  ? [
                      Colors.white.withValues(alpha: 0.85),
                      Colors.white.withValues(alpha: 0.65),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.4),
                      Colors.white.withValues(alpha: 0.2),
                    ],
            ),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: borderColor,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isEnabled ? onPressed : null,
              splashColor: const Color(0xFFD4AF37).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(25),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        color: primaryColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cormorantGaramond(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Format bytes to human-readable GB
  String _formatBytes(int bytes) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }

  /// Build storage usage progress bar
  Widget _buildStorageBar({
    required String label,
    required int usedBytes,
    required int totalBytes,
  }) {
    final percentage = totalBytes > 0 ? (usedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
    final percentInt = (percentage * 100).round();
    final usedFormatted = _formatBytes(usedBytes);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$label ($usedFormatted)',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              Text(
                '$percentInt%',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6B3E19)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: percentage,
              minHeight: 12,
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6B3E19)),
            ),
          ),
        ],
      ),
    );
  }
}
