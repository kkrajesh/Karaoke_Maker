import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ui/theme/voxpro_theme.dart';

class SettingsService extends ChangeNotifier {
  static const String _targetPitchColorKey = 'targetPitchColor';
  static const String _userPitchColorKey = 'userPitchColor';

  Color _targetPitchColor = VoxProTheme.pitchAccent;
  Color _userPitchColor = const Color(0xFF00FFFF); // Neon Cyan

  Color get targetPitchColor => _targetPitchColor;
  Color get userPitchColor => _userPitchColor;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    final targetColorVal = prefs.getInt(_targetPitchColorKey);
    if (targetColorVal != null) {
      _targetPitchColor = Color(targetColorVal);
    }

    final userColorVal = prefs.getInt(_userPitchColorKey);
    if (userColorVal != null) {
      _userPitchColor = Color(userColorVal);
    }
    
    notifyListeners();
  }

  Future<void> setTargetPitchColor(Color color) async {
    _targetPitchColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_targetPitchColorKey, color.value);
  }

  Future<void> setUserPitchColor(Color color) async {
    _userPitchColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_userPitchColorKey, color.value);
  }
}
