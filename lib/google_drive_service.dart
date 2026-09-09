import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class GoogleDriveService {
  final GoogleSignInAccount _currentUser;
  String? _accessToken;
  String? _folderId;
  String? _folderName; // Dynamic folder name from App Owner Name
  final Map<String, String> _listenerFolderCache = {}; // Cache for listener folder IDs

  GoogleDriveService(this._currentUser);

  Future<Map<String, String>> _getAuthHeaders() async {
    if (_accessToken == null) {
      final auth = await _currentUser.authentication;
      _accessToken = auth.accessToken;
    }

    if (_accessToken == null) {
      throw Exception('Could not get access token');
    }

    return {'Authorization': 'Bearer $_accessToken'};
  }

  /// Initialize Google Drive folder structure (WITHOUT creating default files)
  /// With uploader_ini.json architecture, we only create the folder.
  /// Files are created only when needed (listeners, uploader_ini.json, etc.)
  Future<void> initialize({String? folderName}) async {
    try {
      if (folderName != null) {
        _folderName = folderName;
      }
      _folderName ??= 'Media-App'; // Default if not provided
      print('🔍 DEBUG: Initializing GoogleDriveService with folder name: $_folderName');
      await _ensureFolderExists();
      // NOTE: Do NOT call _ensureJsonFilesExist() here
      // Files are created on-demand (uploader_ini.json, listener folders, etc.)
      print('✓ GoogleDriveService initialized successfully');
    } catch (e) {
      print('Error initializing GoogleDriveService: $e');
      rethrow;
    }
  }

  /// Search for uploader_ini.json in ANY folder (used on fresh installs)
  /// Returns the file content + appOwnerName without assuming folder name
  /// Returns null if no uploader_ini.json found anywhere (truly fresh install)
  Future<Map<String, dynamic>?> searchForUploaderIni() async {
    try {
      print('🔍 SEARCH: Looking for uploader_ini.json in all root folders...');
      final headers = await _getAuthHeaders();

      final response = await http.get(
        Uri.parse(
          "https://www.googleapis.com/drive/v3/files?"
          "q=name='uploader_ini.json'%20and%20trashed=false&"
          "spaces=drive&fields=files(id,parents)&pageSize=10",
        ),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to search for uploader_ini.json: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final files = data['files'] as List?;

      if (files == null || files.isEmpty) {
        print('ℹ️  No uploader_ini.json found anywhere - fresh install');
        return null;
      }

      // Found it! Read the first match
      final fileId = files.first['id'];
      final content = await _readJsonFileById(fileId);
      final appOwnerName = content['appOwnerName'] as String?;
      print('✓ Found uploader_ini.json with appOwnerName: $appOwnerName');
      return content;
    } catch (e) {
      print('ℹ️  Search failed: $e');
      return null;
    }
  }

  /// Read JSON file by ID (doesn't need folder context)
  Future<Map<String, dynamic>> _readJsonFileById(String fileId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to read file by ID: ${response.statusCode}');
      }

      return jsonDecode(response.body);
    } catch (e) {
      print('Error reading JSON file by ID: $e');
      rethrow;
    }
  }

  /// Peek at uploader_ini.json WITHOUT creating folders (used to discover the real app owner name)
  /// Returns null if folder doesn't exist or file not found (safe for fresh installs)
  Future<Map<String, dynamic>?> peekUploaderIni(String folderName) async {
    try {
      _folderName = folderName;
      print('🔍 PEEK: Checking for uploader_ini.json in $folderName (no folder creation)');

      // Try to find the folder WITHOUT creating it
      try {
        _folderId = await _getFolderId(_folderName!);
        print('✓ Folder found: $_folderId');
      } catch (e) {
        // Folder doesn't exist - fresh install or wrong folder name
        print('ℹ️  Folder not found during peek - likely fresh install');
        return null;
      }

      // Folder exists, try to read uploader_ini.json
      final content = await _readJsonFile('uploader_ini.json', _folderId!);
      print('✓ uploader_ini.json found via peek');
      return content;
    } catch (e) {
      print('ℹ️  uploader_ini.json not found during peek: $e');
      return null;
    }
  }

  /// Ensure the app folder exists (or create it)
  Future<void> _ensureFolderExists() async {
    try {
      _folderId = await _getFolderId(_folderName!);
      print('✓ Folder exists: $_folderId');
    } catch (e) {
      print('Folder not found, creating...');
      _folderId = await _createFolder(_folderName!);
      print('✓ Folder created: $_folderId');
    }
  }

  /// Create a new folder in Google Drive
  Future<String> _createFolder(String folderName) async {
    print('🔍 DEBUG: Creating folder with name: $folderName');
    final headers = await _getAuthHeaders();
    final metadata = {
      'name': folderName,
      'mimeType': 'application/vnd.google-apps.folder',
    };

    final response = await http.post(
      Uri.parse('https://www.googleapis.com/drive/v3/files'),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode(metadata),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to create folder: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    print('🔍 DEBUG: Folder created with ID: ${data['id']}');
    return data['id'];
  }

  /// Get folder ID by name
  Future<String> _getFolderId(String folderName) async {
    final headers = await _getAuthHeaders();
    final response = await http.get(
      Uri.parse(
        "https://www.googleapis.com/drive/v3/files?"
        "q=name='$folderName'%20and%20mimeType='application/vnd.google-apps.folder'%20and%20trashed=false&"
        "spaces=drive&fields=files(id,name)&pageSize=1",
      ),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to find folder: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final files = data['files'] as List?;

    if (files == null || files.isEmpty) {
      throw Exception("'$folderName' folder not found");
    }

    return files.first['id'];
  }

  /// Get folder ID by name within a specific parent folder
  Future<String> _getFolderIdInParent(String folderName, String parentFolderId) async {
    final headers = await _getAuthHeaders();
    final response = await http.get(
      Uri.parse(
        "https://www.googleapis.com/drive/v3/files?"
        "q=name='$folderName'%20and%20mimeType='application/vnd.google-apps.folder'%20and%20'$parentFolderId'%20in%20parents%20and%20trashed=false&"
        "spaces=drive&fields=files(id,name)&pageSize=1",
      ),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to find folder: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final files = data['files'] as List?;

    if (files == null || files.isEmpty) {
      throw Exception("'$folderName' folder not found in parent");
    }

    return files.first['id'];
  }

  /// Get or create a listener-specific subdirectory
  Future<String> _getListenerFolderId(String listenerDirectory) async {
    if (_folderId == null) await _ensureFolderExists();

    // Check cache first
    if (_listenerFolderCache.containsKey(listenerDirectory)) {
      return _listenerFolderCache[listenerDirectory]!;
    }

    try {
      // Try to find existing listener folder under main folder
      final folderId = await _getFolderIdInParent(listenerDirectory, _folderId!);
      _listenerFolderCache[listenerDirectory] = folderId;
      print('✓ Listener folder found: $listenerDirectory');
      return folderId;
    } catch (e) {
      // Folder doesn't exist, create it under main folder
      print('Creating listener folder: $listenerDirectory');
      final newFolderId = await _createFolderWithParent(listenerDirectory, _folderId!);
      _listenerFolderCache[listenerDirectory] = newFolderId;
      print('✓ Listener folder created: $listenerDirectory');
      return newFolderId;
    }
  }

  /// Create a folder with parent
  Future<String> _createFolderWithParent(String folderName, String parentFolderId) async {
    final headers = await _getAuthHeaders();
    final metadata = {
      'name': folderName,
      'mimeType': 'application/vnd.google-apps.folder',
      'parents': [parentFolderId],
    };

    final response = await http.post(
      Uri.parse('https://www.googleapis.com/drive/v3/files'),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode(metadata),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to create folder: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    return data['id'];
  }

  /// Ensure all required JSON files exist
  Future<void> _ensureJsonFilesExist() async {
    if (_folderId == null) {
      throw Exception('Folder ID not set');
    }

    const List<String> jsonFiles = ['catalog.json', 'access_codes.json', 'requests.json'];

    for (final fileName in jsonFiles) {
      final exists = await _fileExists(fileName, _folderId!);
      if (!exists) {
        print('Creating $fileName...');
        await _createJsonFile(fileName, _getDefaultJsonContent(fileName));
      } else {
        print('✓ $fileName already exists');
      }
    }
  }

  /// Get default content for JSON files
  Map<String, dynamic> _getDefaultJsonContent(String fileName) {
    switch (fileName) {
      case 'catalog.json':
        return {'audio': [], 'video': []};
      case 'access_codes.json':
        return {};
      case 'requests.json':
        return {'requests': []};
      default:
        return {};
    }
  }

  /// Check if a file exists in the folder
  Future<bool> _fileExists(String fileName, String folderId) async {
    try {
      final fileId = await _findFileId(fileName, folderId);
      return fileId != null;
    } catch (e) {
      return false;
    }
  }

  /// Find file ID by name in a folder
  Future<String?> _findFileId(String fileName, String folderId) async {
    final headers = await _getAuthHeaders();
    final encodedName = Uri.encodeComponent(fileName);
    final response = await http.get(
      Uri.parse(
        "https://www.googleapis.com/drive/v3/files?"
        "q=name='$encodedName'%20and%20'$folderId'%20in%20parents%20and%20trashed=false&"
        "spaces=drive&fields=files(id)&pageSize=1",
      ),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to find file: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final files = data['files'] as List?;

    if (files != null && files.isNotEmpty) {
      return files.first['id'];
    }
    return null;
  }

  /// Read catalog.json from Google Drive
  Future<Map<String, dynamic>> readCatalog() async {
    if (_folderId == null) await _ensureFolderExists();

    try {
      final content = await _readJsonFile('catalog.json', _folderId!);
      return content;
    } catch (e) {
      print('Error reading catalog: $e');
      return {'audio': [], 'video': []};
    }
  }

  /// Write catalog.json to Google Drive
  Future<void> writeCatalog(Map<String, dynamic> catalog) async {
    if (_folderId == null) await _ensureFolderExists();

    try {
      await _writeJsonFile('catalog.json', catalog, _folderId!);
      print('✓ Catalog updated');
    } catch (e) {
      print('Error writing catalog: $e');
      rethrow;
    }
  }

  /// Read access codes from access_codes.json
  Future<Map<String, dynamic>> readAccessCodes() async {
    if (_folderId == null) await _ensureFolderExists();

    try {
      final content = await _readJsonFile('access_codes.json', _folderId!);
      return content;
    } catch (e) {
      print('Error reading access codes: $e');
      return {};
    }
  }

  /// Add access code for a device
  Future<void> addAccessCode(
    String phoneNumber,
    String deviceName,
    String code,
  ) async {
    if (_folderId == null) await _ensureFolderExists();

    try {
      final codes = await readAccessCodes();
      codes[phoneNumber] = {
        'deviceName': deviceName,
        'code': code,
        'createdAt': DateTime.now().toIso8601String(),
      };
      await _writeJsonFile('access_codes.json', codes, _folderId!);
      print('✓ Access code added for $deviceName');
    } catch (e) {
      print('Error adding access code: $e');
      rethrow;
    }
  }

  /// Write access codes to access_codes.json
  Future<void> writeAccessCodes(Map<String, dynamic> accessCodes) async {
    if (_folderId == null) await _ensureFolderExists();

    try {
      await _writeJsonFile('access_codes.json', accessCodes, _folderId!);
      print('✓ Access codes updated');
    } catch (e) {
      print('Error writing access codes: $e');
      rethrow;
    }
  }

  /// Create uploader_ini.json in root folder with app owner name and listeners list
  Future<void> createUploaderIni(String appOwnerName, List<String> listeners) async {
    if (_folderId == null) await _ensureFolderExists();

    try {
      final uploaderIni = {
        'appOwnerName': appOwnerName,
        'listeners': listeners,
        'version': 1,
        'createdAt': DateTime.now().toIso8601String(),
      };

      await _writeJsonFile('uploader_ini.json', uploaderIni, _folderId!);
      print('✓ uploader_ini.json created with $appOwnerName and ${listeners.length} listener(s)');
    } catch (e) {
      print('Error creating uploader_ini.json: $e');
      rethrow;
    }
  }

  /// Read uploader_ini.json from root folder
  Future<Map<String, dynamic>?> readUploaderIni() async {
    if (_folderId == null) await _ensureFolderExists();

    try {
      final content = await _readJsonFile('uploader_ini.json', _folderId!);
      print('✓ uploader_ini.json loaded: ${content['appOwnerName']}');
      return content;
    } catch (e) {
      print('uploader_ini.json not found (fresh install): $e');
      return null;
    }
  }

  /// Update uploader_ini.json with new listeners list
  Future<void> updateUploaderIni(String appOwnerName, List<String> listeners) async {
    if (_folderId == null) await _ensureFolderExists();

    try {
      final uploaderIni = {
        'appOwnerName': appOwnerName,
        'listeners': listeners,
        'version': 1,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      await _writeJsonFile('uploader_ini.json', uploaderIni, _folderId!);
      print('✓ uploader_ini.json updated: $appOwnerName with ${listeners.length} listener(s)');
    } catch (e) {
      print('Error updating uploader_ini.json: $e');
      rethrow;
    }
  }

  /// Read access codes from a listener-specific folder
  Future<Map<String, dynamic>> readListenerAccessCodes(String listenerDirectory) async {
    try {
      final listenerFolderId = await _getListenerFolderId(listenerDirectory);
      final content = await _readJsonFile('access_codes.json', listenerFolderId);
      return content;
    } catch (e) {
      print('Error reading listener access codes for $listenerDirectory: $e');
      return {};
    }
  }

  /// Write access codes to a listener-specific folder
  Future<void> writeListenerAccessCodes(String listenerDirectory, Map<String, dynamic> accessCodes) async {
    try {
      final listenerFolderId = await _getListenerFolderId(listenerDirectory);
      await _writeJsonFile('access_codes.json', accessCodes, listenerFolderId);
      print('✓ Access codes updated for listener: $listenerDirectory');
    } catch (e) {
      print('Error writing listener access codes for $listenerDirectory: $e');
      rethrow;
    }
  }

  /// Create default JSON files for a new listener (catalog.json, requests.json)
  Future<void> createListenerDefaultFiles(String listenerDirectory) async {
    try {
      final listenerFolderId = await _getListenerFolderId(listenerDirectory);

      // Create catalog.json if it doesn't exist (with all file type categories)
      final catalogExists = await _fileExists('catalog.json', listenerFolderId);
      if (!catalogExists) {
        await _writeJsonFile(
          'catalog.json',
          {
            'audio': [],
            'video': [],
            'text': [],
            'pdf': [],
          },
          listenerFolderId,
        );
        print('✓ Created catalog.json for listener: $listenerDirectory');
      }

      // Create requests.json if it doesn't exist
      final requestsExists = await _fileExists('requests.json', listenerFolderId);
      if (!requestsExists) {
        await _writeJsonFile('requests.json', {'requests': []}, listenerFolderId);
        print('✓ Created requests.json for listener: $listenerDirectory');
      }
    } catch (e) {
      print('Error creating default listener files for $listenerDirectory: $e');
      rethrow;
    }
  }

  /// Create listener folder structure (called when access code is generated)
  Future<void> createListenerFolder(String listenerDirectory) async {
    if (_folderId == null) await _ensureFolderExists();

    try {
      // This will create the folder if it doesn't exist, or return the ID if it does
      await _getListenerFolderId(listenerDirectory);
      print('✓ Listener folder structure created: $listenerDirectory');
    } catch (e) {
      print('Error creating listener folder: $e');
      rethrow;
    }
  }

  /// Read content requests from requests.json
  Future<Map<String, dynamic>> readRequests() async {
    if (_folderId == null) await _ensureFolderExists();

    try {
      final content = await _readJsonFile('requests.json', _folderId!);
      return content;
    } catch (e) {
      print('Error reading requests: $e');
      return {'requests': []};
    }
  }

  /// Add content request from listener
  Future<void> addRequest(
    String phoneNumber,
    String deviceName,
    String request,
  ) async {
    if (_folderId == null) await _ensureFolderExists();

    try {
      final data = await readRequests();
      final requests = data['requests'] as List? ?? [];

      requests.add({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'phoneNumber': phoneNumber,
        'deviceName': deviceName,
        'request': request,
        'createdAt': DateTime.now().toIso8601String(),
      });

      data['requests'] = requests;
      await _writeJsonFile('requests.json', data, _folderId!);
      print('✓ Request added from $deviceName');
    } catch (e) {
      print('Error adding request: $e');
      rethrow;
    }
  }

  /// Read JSON file from Google Drive
  Future<Map<String, dynamic>> _readJsonFile(String fileName, String folderId) async {
    final fileId = await _findFileId(fileName, folderId);
    if (fileId == null) {
      throw Exception('$fileName not found');
    }

    final headers = await _getAuthHeaders();
    final response = await http.get(
      Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to read $fileName: ${response.statusCode}');
    }

    return jsonDecode(response.body);
  }

  /// Write JSON file to Google Drive
  Future<void> _writeJsonFile(
    String fileName,
    Map<String, dynamic> content,
    String folderId,
  ) async {
    final fileId = await _findFileId(fileName, folderId);
    final jsonContent = jsonEncode(content);
    final fileBytes = utf8.encode(jsonContent);

    final headers = await _getAuthHeaders();
    final Uri uploadUri = fileId != null
        ? Uri.parse('https://www.googleapis.com/upload/drive/v3/files/$fileId?uploadType=media')
        : Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart');

    late final http.Response response;

    if (fileId != null) {
      // Update existing file
      response = await http.patch(
        uploadUri,
        headers: headers,
        body: fileBytes,
      );
    } else {
      // Create new file
      final metadata = jsonEncode({
        'name': fileName,
        'parents': [folderId],
      });

      response = await http.post(
        Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart'),
        headers: {
          ...headers,
          'Content-Type': 'multipart/related; boundary=foo_bar_baz',
        },
        body:
            '--foo_bar_baz\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadata\r\n--foo_bar_baz\r\nContent-Type: application/json\r\n\r\n$jsonContent\r\n--foo_bar_baz--',
      );
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to write $fileName: ${response.statusCode}');
    }
  }

  /// Upload media file (MP3/MP4) to listener-specific directory on Google Drive
  Future<String?> uploadMediaFile(
    String filePath,
    Function(double) onProgress, {
    String? listenerDirectory,
  }) async {
    if (_folderId == null) await _ensureFolderExists();

    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final fileName = file.path.split(Platform.pathSeparator).last;
      final fileSize = await file.length();
      final fileStream = file.openRead();

      // Get listener folder if specified, otherwise use main folder
      final targetFolderId = listenerDirectory != null
          ? await _getListenerFolderId(listenerDirectory)
          : _folderId!;

      // Upload file using resumable upload to listener's folder
      final sessionUri = await _getResumableSessionUri(fileName, targetFolderId);
      final fileId = await _performResumableUpload(
        fileStream,
        fileSize,
        onProgress,
        sessionUri: sessionUri,
      );

      // Update listener-specific catalog
      if (fileId != null) {
        await _addToCatalog(fileName, fileSize ~/ (1024 * 1024), fileId, listenerDirectory);
      }

      return fileId;
    } catch (e) {
      print('Error uploading media: $e');
      rethrow;
    }
  }

  /// Add file to listener-specific catalog.json (supports MP3, MP4, TXT, PDF)
  Future<void> _addToCatalog(String fileName, int sizeMB, String fileId, String? listenerDirectory) async {
    try {
      final catalog = listenerDirectory != null
          ? await _readListenerCatalog(listenerDirectory)
          : await readCatalog();

      final isAudio = fileName.endsWith('.mp3');
      final isVideo = fileName.endsWith('.mp4');
      final isText = fileName.endsWith('.txt');
      final isPdf = fileName.endsWith('.pdf');

      if (isAudio || isVideo || isText || isPdf) {
        String listKey = 'audio';
        String type = 'audio';

        if (isVideo) {
          listKey = 'video';
          type = 'video';
        } else if (isText) {
          listKey = 'text';
          type = 'text';
        } else if (isPdf) {
          listKey = 'pdf';
          type = 'pdf';
        }

        final list = catalog[listKey] as List? ?? [];

        // Remove old extension patterns for title
        String title = fileName;
        title = title.replaceAll(RegExp(r'\.(mp3|mp4|txt|pdf)$'), '');

        list.add({
          'id': fileId,
          'title': title,
          'fileName': fileName,
          'type': type,
          'size': '$sizeMB MB',
          'uploadedAt': DateTime.now().toIso8601String(),
          'downloaded': false,  // NEW: Track download status
        });

        catalog[listKey] = list;

        if (listenerDirectory != null) {
          await _writeListenerCatalog(listenerDirectory, catalog);
        } else {
          await writeCatalog(catalog);
        }
      }
    } catch (e) {
      print('Error adding to catalog: $e');
    }
  }

  /// Read listener-specific catalog.json
  Future<Map<String, dynamic>> _readListenerCatalog(String listenerDirectory) async {
    try {
      final listenerFolderId = await _getListenerFolderId(listenerDirectory);
      final content = await _readJsonFile('catalog.json', listenerFolderId);
      // Ensure all file type categories exist
      return {
        'audio': content['audio'] ?? [],
        'video': content['video'] ?? [],
        'text': content['text'] ?? [],
        'pdf': content['pdf'] ?? [],
      };
    } catch (e) {
      print('Error reading listener catalog: $e');
      return {'audio': [], 'video': [], 'text': [], 'pdf': []};
    }
  }

  /// PUBLIC: Read listener-specific catalog.json from outside the service
  Future<Map<String, dynamic>> readListenerCatalog(String listenerDirectory) async {
    return await _readListenerCatalog(listenerDirectory);
  }

  /// Write listener-specific catalog.json
  Future<void> _writeListenerCatalog(String listenerDirectory, Map<String, dynamic> catalog) async {
    try {
      final listenerFolderId = await _getListenerFolderId(listenerDirectory);
      await _writeJsonFile('catalog.json', catalog, listenerFolderId);
      print('✓ Listener catalog updated for $listenerDirectory');
    } catch (e) {
      print('Error writing listener catalog: $e');
      rethrow;
    }
  }

  /// Update file download status in listener catalog
  Future<void> updateFileDownloadStatus(
    String listenerDirectory,
    String fileId,
    bool downloaded,
  ) async {
    try {
      final catalog = await _readListenerCatalog(listenerDirectory);

      // Search through all file types
      for (final fileType in ['audio', 'video', 'text', 'pdf']) {
        final files = catalog[fileType] as List? ?? [];
        for (final file in files) {
          if (file['id'] == fileId) {
            file['downloaded'] = downloaded;
            print('✓ Updated download status for $fileId to $downloaded');
          }
        }
      }

      await _writeListenerCatalog(listenerDirectory, catalog);
    } catch (e) {
      print('Error updating download status: $e');
    }
  }

  /// Delete file from Google Drive and update catalog
  Future<void> deleteMediaFile(
    String fileId,
    String listenerDirectory,
  ) async {
    try {
      final headers = await _getAuthHeaders();

      // Delete file from Google Drive
      final response = await http.delete(
        Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId'),
        headers: headers,
      );

      if (response.statusCode != 204) {
        throw Exception('Failed to delete file: ${response.statusCode}');
      }

      print('✓ File deleted from Drive: $fileId');

      // Update catalog to remove the file entry
      final catalog = await _readListenerCatalog(listenerDirectory);

      // Search through all file types and remove the file
      for (final fileType in ['audio', 'video', 'text', 'pdf']) {
        final files = catalog[fileType] as List? ?? [];
        files.removeWhere((f) => f['id'] == fileId);
        catalog[fileType] = files;
      }

      await _writeListenerCatalog(listenerDirectory, catalog);
      print('✓ File removed from catalog for $listenerDirectory');
    } catch (e) {
      print('Error deleting media file: $e');
      rethrow;
    }
  }

  /// Create resumable upload session
  Future<Uri> _getResumableSessionUri(String fileName, String folderId) async {
    final headers = await _getAuthHeaders();
    const baseUrl = 'https://www.googleapis.com/upload/drive/v3/files';
    final uri = Uri.parse('$baseUrl?uploadType=resumable');

    final metadata = {
      'name': fileName,
      'parents': [folderId],
    };

    final response = await http.post(
      uri,
      headers: {
        ...headers,
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(metadata),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to initiate resumable upload: ${response.statusCode}');
    }

    final location = response.headers['location'];
    if (location == null) {
      throw Exception('Could not get resumable upload session URI');
    }

    return Uri.parse(location);
  }

  /// Perform resumable upload
  Future<String?> _performResumableUpload(
    Stream<List<int>> fileStream,
    int fileSize,
    Function(double) onProgress, {
    required Uri sessionUri,
  }) async {
    final request = http.StreamedRequest('PUT', sessionUri);
    request.headers['Content-Length'] = fileSize.toString();
    request.headers['Content-Range'] = 'bytes 0-${fileSize - 1}/$fileSize';

    int bytesUploaded = 0;
    final completer = Completer<void>();

    fileStream.listen(
      (chunk) {
        request.sink.add(chunk);
        bytesUploaded += chunk.length;
        onProgress(bytesUploaded / fileSize);
      },
      onDone: () {
        request.sink.close();
        completer.complete();
      },
      onError: (error) {
        request.sink.close();
        if (!completer.isCompleted) {
          completer.completeError(Exception('Error reading file stream: $error'));
        }
      },
      cancelOnError: true,
    );

    final responseFuture = request.send();
    await completer.future;
    final response = await responseFuture;

    if (response.statusCode != 200 && response.statusCode != 201) {
      final responseBody = await response.stream.bytesToString();
      throw Exception('File creation failed: ${response.statusCode} - $responseBody');
    }

    final responseBody = await response.stream.bytesToString();
    final data = jsonDecode(responseBody);
    return data['id'];
  }

  /// Download media file for offline playback
  Future<String?> downloadMediaFile(String fileName) async {
    if (_folderId == null) await _ensureFolderExists();

    try {
      final catalog = await readCatalog();

      // Find file in catalog
      final audio = catalog['audio'] as List? ?? [];
      final video = catalog['video'] as List? ?? [];
      final allFiles = [...audio, ...video];

      final fileData = allFiles.firstWhere(
        (f) => f['fileName'] == fileName,
        orElse: () => null,
      );

      if (fileData == null) {
        print('File not found in catalog: $fileName');
        return null;
      }

      final fileId = fileData['id'];
      final localFile = await _downloadFile(fileId, fileName);
      return localFile;
    } catch (e) {
      print('Error downloading media: $e');
      return null;
    }
  }

  /// Download file from Google Drive to local storage
  Future<String> _downloadFile(String fileId, String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/$fileName';
    final file = File(filePath);

    // Return if already downloaded
    if (await file.exists()) {
      return filePath;
    }

    final headers = await _getAuthHeaders();
    final response = await http.get(
      Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to download file: ${response.statusCode}');
    }

    await file.writeAsBytes(response.bodyBytes);
    print('✓ Downloaded: $fileName');
    return filePath;
  }

  /// Create JSON file in Google Drive
  Future<void> _createJsonFile(String fileName, Map<String, dynamic> content) async {
    if (_folderId == null) {
      throw Exception('Folder ID not set');
    }

    final jsonContent = jsonEncode(content);
    //final fileBytes = utf8.encode(jsonContent);

    final headers = await _getAuthHeaders();
    final metadata = jsonEncode({
      'name': fileName,
      'parents': [_folderId!],
    });

    // Use multipart upload
    const boundary = 'foo_bar_baz';
    final body = '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$metadata\r\n'
        '--$boundary\r\n'
        'Content-Type: application/json\r\n\r\n'
        '$jsonContent\r\n'
        '--$boundary--';

    final response = await http.post(
      Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart'),
      headers: {
        ...headers,
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: body,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to create $fileName: ${response.statusCode}');
    }
  }

  /// Get listener folder ID (public wrapper for storage calculation)
  Future<String> getListenerFolderId(String listenerDirectory) async {
    return await _getListenerFolderId(listenerDirectory);
  }

  /// Get Drive storage quota information
  /// Returns: {'usedBytes': int, 'limitBytes': int, 'availableBytes': int}
  Future<Map<String, int>> getStorageQuota() async {
    try {
      final headers = await _getAuthHeaders();

      final response = await http.get(
        Uri.parse('https://www.googleapis.com/drive/v3/about?fields=storageQuota'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final quota = data['storageQuota'] as Map<String, dynamic>?;

        final usedBytes = int.tryParse(quota?['usageInDrive'] ?? '0') ?? 0;
        final limitBytes = int.tryParse(quota?['limit'] ?? '15000000000') ?? 15000000000; // 15GB default
        final availableBytes = limitBytes - usedBytes;

        print('✓ Storage quota fetched: ${(usedBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB / ${(limitBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB');

        return {
          'usedBytes': usedBytes,
          'limitBytes': limitBytes,
          'availableBytes': availableBytes,
        };
      } else {
        throw Exception('Failed to fetch storage quota: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching storage quota: $e');
      // Return default 15GB if fetch fails
      return {
        'usedBytes': 0,
        'limitBytes': 15000000000,
        'availableBytes': 15000000000,
      };
    }
  }

  /// Calculate total size of a folder (including all files recursively)
  /// Returns size in bytes
  Future<int> calculateFolderSize(String folderId) async {
    try {
      int totalBytes = 0;
      String? pageToken;

      do {
        final headers = await _getAuthHeaders();

        final query = Uri.parse(
          'https://www.googleapis.com/drive/v3/files'
          "?q='$folderId' in parents and trashed = false"
          '&fields=nextPageToken, files(id, size, mimeType)'
          '&pageToken=${pageToken ?? ''}'
        );

        final response = await http.get(query, headers: headers);

        if (response.statusCode != 200) {
          throw Exception('Failed to fetch folder contents: ${response.statusCode}');
        }

        final data = jsonDecode(response.body);
        final files = data['files'] as List? ?? [];

        for (final file in files) {
          final size = int.tryParse(file['size'] ?? '0') ?? 0;
          final mimeType = file['mimeType'] as String?;
          final fileId = file['id'] as String?;

          if (mimeType == 'application/vnd.google-apps.folder' && fileId != null) {
            // Recursively calculate subfolder size
            totalBytes += await calculateFolderSize(fileId);
          } else {
            totalBytes += size;
          }
        }

        pageToken = data['nextPageToken'] as String?;
      } while (pageToken != null);

      return totalBytes;
    } catch (e) {
      print('Error calculating folder size: $e');
      return 0;
    }
  }
}
