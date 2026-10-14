import 'package:flutter/material.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/ui/client/task_creation/category_task_guide.dart';

import 'category_icon.dart';

/// Discovery is available before sign-in. Booking retains its existing guards.
class ServiceSearch extends SearchDelegate<TaskCategory?> {
  ServiceSearch() : super(searchFieldLabel: 'Search services, e.g. laundry');

  static List<TaskCategory> matching(String query) {
    final terms = query.toLowerCase().trim().split(RegExp(r'\s+'));
    return TaskCategory.values.where((category) {
      final text =
          '${category.displayName} ${category.description} '
                  '${CategoryTaskGuide.services(category).join(' ')}'
              .toLowerCase();
      return terms.every(text.contains);
    }).toList();
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: 'Clear search',
        icon: const Icon(Icons.close),
        onPressed: () => query = '',
      ),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    tooltip: 'Back',
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  @override
  Widget buildResults(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final categories = matching(query);
    if (categories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.search_off_rounded,
                size: 48,
                color: AppColors.helperAccent,
              ),
              const SizedBox(height: 16),
              Text(
                'No services found',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Try a simpler word, or describe a custom task.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => close(context, TaskCategory.other),
                child: const Text('Create a custom task'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: categories.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final category = categories[index];
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            leading: CategoryIconBadge(category, size: 44),
            title: Text(category.displayName),
            subtitle: Text(category.description),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => close(context, category),
          ),
        );
      },
    );
  }
}
