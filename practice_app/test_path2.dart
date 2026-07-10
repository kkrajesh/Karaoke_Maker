import 'package:vox_player_core/vox_player_core.dart';
import 'package:vox_player_core/src/db/vox_ai_db.dart';
import 'package:vox_player_core/src/settings/vox_settings_service.dart';
import 'package:flutter/widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final aiService = VoxAiDb();
  VoxSettingsService.instance.setAiVaultPath(r'G:\My Drive\MyMusic\Music_AI_Vault');
  final mmId = 'Sony_Music_Malayalam_Anuragha_Vilochanana_1782615372985';
  final title = 'Neelathamara';
  final dir = aiService.getArtifactDirectory(mmId, title);
  final inst = aiService.getInstrumentalPath(mmId, title);
  print('DIR: \');
  print('INST: \');
}
