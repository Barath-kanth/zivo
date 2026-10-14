import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/ui/_shared/service_search.dart';

void main() {
  test('discovery matches the language of specific services', () {
    expect(
      ServiceSearch.matching('  IRON clothes '),
      contains(TaskCategory.laundry),
    );
    expect(ServiceSearch.matching('Wi-Fi'), contains(TaskCategory.techHelp));
    expect(
      ServiceSearch.matching('grocery'),
      contains(TaskCategory.groceryRun),
    );
    expect(ServiceSearch.matching('zzzzzz'), isEmpty);
    expect(ServiceSearch.matching(''), hasLength(TaskCategory.values.length));
  });
}
