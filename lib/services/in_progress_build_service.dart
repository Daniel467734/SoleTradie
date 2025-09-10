import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/in_progress_build.dart';
import '../models/estimate_item.dart';

class InProgressBuildService {
  static const String _storageKey = 'in_progress_builds';

  /// Load all in-progress builds from storage
  static Future<List<InProgressBuild>> loadAllBuilds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString == null) return [];

      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => InProgressBuild.fromJson(json)).toList();
    } catch (e) {
      print('Error loading in-progress builds: $e');
      return [];
    }
  }

  /// Save all in-progress builds to storage
  static Future<void> saveAllBuilds(List<InProgressBuild> builds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = builds.map((build) => build.toJson()).toList();
      await prefs.setString(_storageKey, jsonEncode(jsonList));
    } catch (e) {
      print('Error saving in-progress builds: $e');
    }
  }

  /// Get all builds for a specific job
  static Future<List<InProgressBuild>> getBuildsForJob(String jobId) async {
    final allBuilds = await loadAllBuilds();
    return allBuilds.where((build) => build.jobId == jobId).toList();
  }

  /// Get a specific build by ID
  static Future<InProgressBuild?> getBuildById(String buildId) async {
    final allBuilds = await loadAllBuilds();
    try {
      return allBuilds.firstWhere((build) => build.id == buildId);
    } catch (e) {
      return null;
    }
  }

  /// Create a new in-progress build
  static Future<InProgressBuild> createNewBuild({
    required String jobId,
    required List<EstimateItem> items,
    required List<String> subsections,
    String? templateName,
    double totalAmount = 0.0,
    double totalProfit = 0.0,
  }) async {
    final allBuilds = await loadAllBuilds();
    final existingBuildsForJob = allBuilds.where((build) => build.jobId == jobId).toList();
    
    // Generate name: "In-Progress Build 1", "In-Progress Build 2", etc.
    final buildNumber = existingBuildsForJob.length + 1;
    final buildName = 'In-Progress Build $buildNumber';
    
    // Create initial version
    final now = DateTime.now();
    final initialVersion = InProgressVersion(
      id: '${jobId}_version_${now.millisecondsSinceEpoch}',
      createdAt: now,
      totalAmount: totalAmount,
      totalProfit: totalProfit,
      items: List<EstimateItem>.from(items),
      subsections: List<String>.from(subsections),
    );

    // Create build
    final build = InProgressBuild(
      id: '${jobId}_build_${now.millisecondsSinceEpoch}',
      jobId: jobId,
      name: buildName,
      createdAt: now,
      lastModified: now,
      templateName: templateName,
      versions: [initialVersion],
      currentVersionId: initialVersion.id,
    );

    // Save to storage
    allBuilds.add(build);
    await saveAllBuilds(allBuilds);
    
    return build;
  }

  /// Update an existing build (overwrites current version)
  static Future<InProgressBuild> updateBuild({
    required String buildId,
    required List<EstimateItem> items,
    required List<String> subsections,
    required double totalAmount,
    required double totalProfit,
    Map<String, dynamic>? additionalData,
  }) async {
    final allBuilds = await loadAllBuilds();
    final buildIndex = allBuilds.indexWhere((build) => build.id == buildId);
    if (buildIndex == -1) throw Exception('Build not found: $buildId');

    final existingBuild = allBuilds[buildIndex];
    final updatedVersion = existingBuild.currentVersion.copyWith(
      totalAmount: totalAmount,
      totalProfit: totalProfit,
      items: List<EstimateItem>.from(items),
      subsections: List<String>.from(subsections),
      additionalData: additionalData,
    );

    final updatedBuild = existingBuild.updateCurrentVersion(updatedVersion);
    allBuilds[buildIndex] = updatedBuild;
    await saveAllBuilds(allBuilds);
    
    return updatedBuild;
  }

  /// Create a new version when opening an existing build
  static Future<InProgressBuild> createVersionOnOpen(String buildId) async {
    final allBuilds = await loadAllBuilds();
    final buildIndex = allBuilds.indexWhere((build) => build.id == buildId);
    if (buildIndex == -1) throw Exception('Build not found: $buildId');

    final existingBuild = allBuilds[buildIndex];
    final currentVersion = existingBuild.currentVersion;
    
    // Create new version as a copy of current
    final now = DateTime.now();
    final newVersion = InProgressVersion(
      id: '${buildId}_version_${now.millisecondsSinceEpoch}',
      createdAt: now,
      totalAmount: currentVersion.totalAmount,
      totalProfit: currentVersion.totalProfit,
      items: List<EstimateItem>.from(currentVersion.items.map((item) => item.copyWith())),
      subsections: List<String>.from(currentVersion.subsections),
      additionalData: currentVersion.additionalData != null 
          ? Map<String, dynamic>.from(currentVersion.additionalData!) 
          : null,
    );

    final updatedBuild = existingBuild.addVersion(newVersion);
    allBuilds[buildIndex] = updatedBuild;
    await saveAllBuilds(allBuilds);
    
    return updatedBuild;
  }

  /// Delete an entire build
  static Future<void> deleteBuild(String buildId) async {
    final allBuilds = await loadAllBuilds();
    allBuilds.removeWhere((build) => build.id == buildId);
    await saveAllBuilds(allBuilds);
  }

  /// Delete a specific version (or entire build if last version)
  static Future<bool> deleteVersion(String buildId, String versionId) async {
    final allBuilds = await loadAllBuilds();
    final buildIndex = allBuilds.indexWhere((build) => build.id == buildId);
    if (buildIndex == -1) return false;

    final existingBuild = allBuilds[buildIndex];
    final updatedBuild = existingBuild.removeVersion(versionId);
    
    if (updatedBuild == null) {
      // This was the last version, delete entire build
      allBuilds.removeAt(buildIndex);
    } else {
      allBuilds[buildIndex] = updatedBuild;
    }
    
    await saveAllBuilds(allBuilds);
    return updatedBuild == null; // Return true if entire build was deleted
  }

  /// Promote a version to be the latest
  static Future<InProgressBuild> promoteVersionToLatest(String buildId, String versionId) async {
    final allBuilds = await loadAllBuilds();
    final buildIndex = allBuilds.indexWhere((build) => build.id == buildId);
    if (buildIndex == -1) throw Exception('Build not found: $buildId');

    final existingBuild = allBuilds[buildIndex];
    final updatedBuild = existingBuild.promoteVersionToLatest(versionId);
    
    allBuilds[buildIndex] = updatedBuild;
    await saveAllBuilds(allBuilds);
    
    return updatedBuild;
  }

  /// Open a specific version (not latest)
  static Future<InProgressBuild> openSpecificVersion(String buildId, String versionId) async {
    final allBuilds = await loadAllBuilds();
    final buildIndex = allBuilds.indexWhere((build) => build.id == buildId);
    if (buildIndex == -1) throw Exception('Build not found: $buildId');

    final existingBuild = allBuilds[buildIndex];
    
    // If opening a non-current version, make it current temporarily
    if (versionId != existingBuild.currentVersionId) {
      final updatedBuild = existingBuild.copyWith(currentVersionId: versionId);
      allBuilds[buildIndex] = updatedBuild;
      await saveAllBuilds(allBuilds);
      return updatedBuild;
    }
    
    return existingBuild;
  }

  /// Revert to previous version (delete current version)
  static Future<InProgressBuild?> revertToPreviousVersion(String buildId) async {
    final allBuilds = await loadAllBuilds();
    final buildIndex = allBuilds.indexWhere((build) => build.id == buildId);
    if (buildIndex == -1) return null;

    final existingBuild = allBuilds[buildIndex];
    final currentVersionId = existingBuild.currentVersionId;
    
    // Remove current version
    final updatedBuild = existingBuild.removeVersion(currentVersionId);
    
    if (updatedBuild == null) {
      // This was the last version, delete entire build
      allBuilds.removeAt(buildIndex);
      await saveAllBuilds(allBuilds);
      return null;
    } else {
      allBuilds[buildIndex] = updatedBuild;
      await saveAllBuilds(allBuilds);
      return updatedBuild;
    }
  }

  /// Delete all builds for a specific job
  static Future<void> deleteAllBuildsForJob(String jobId) async {
    try {
      final allBuilds = await loadAllBuilds();
      final filteredBuilds = allBuilds.where((build) => build.jobId != jobId).toList();
      await saveAllBuilds(filteredBuilds);
    } catch (e) {
      print('Error deleting builds for job $jobId: $e');
      rethrow;
    }
  }
}
