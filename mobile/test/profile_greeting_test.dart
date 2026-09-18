import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:travelease/models/repositories/auth_repository.dart';
import 'package:travelease/models/repositories/profile_repository.dart';
import 'package:travelease/viewmodels/profile_viewmodel.dart';

class ProfileData implements ProfileRepository {
  String? name;
  @override
  Future<Map<String, dynamic>?> getCurrentUserProfile() async => {
    'full_name': name,
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AuthData implements AuthRepository {
  @override
  User? get currentUser => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'greeting uses profile name and falls back for null, empty or whitespace',
    () async {
      final repository = ProfileData();
      final model = ProfileViewModel(
        profileRepository: repository,
        authRepository: AuthData(),
      );
      for (final value in [null, '', '   ']) {
        repository.name = value;
        await model.loadProfile();
        expect(model.greetingName, 'Guest');
      }
      repository.name = ' Yan Thong ';
      await model.loadProfile();
      expect(model.greetingName, 'Yan Thong');
      repository.name = 'Updated Name';
      ProfileRepository.changes.value++;
      await Future<void>.delayed(Duration.zero);
      expect(model.greetingName, 'Updated Name');
      model.dispose();
    },
  );
}
