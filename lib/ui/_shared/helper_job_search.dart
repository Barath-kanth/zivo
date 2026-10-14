import 'package:flutter/material.dart';
import 'package:hyperlocal/data/models/task.dart';

import 'category_icon.dart';
import 'empty_state_widget.dart';

import 'package:hyperlocal/core/constants/app_colors.dart';

class HelperJobSearch extends SearchDelegate<String?> {
  HelperJobSearch(this.tasks, {String initialQuery = ''})
    : super(searchFieldLabel: 'Search jobs or services') {
    query = initialQuery;
  }
  final List<Task> tasks;

  static bool matches(Task task, String query) {
    final text =
        '${task.title} ${task.description} ${task.category.displayName} ${task.locationLabel ?? ''}'
            .toLowerCase();
    return query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .every(text.contains);
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: 'Clear search',
        onPressed: () => query = '',
        icon: const Icon(Icons.close),
      ),
  ];
  @override
  Widget buildLeading(BuildContext context) => IconButton(
    tooltip: 'Back',
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );
  @override
  Widget buildResults(BuildContext context) => _list(context);
  @override
  Widget buildSuggestions(BuildContext context) => _list(context);

  Widget _list(BuildContext context) {
    final results = tasks.where((task) => matches(task, query)).toList();
    if (results.isEmpty)
      return EmptyStateWidget(
        icon: Icons.search_off_rounded,
        title: 'No matching jobs',
        subtitle: 'Try another word or refresh nearby jobs.',
        color: AppColors.helperAccent,
        actionLabel: 'Back to jobs',
        onAction: () => close(context, ''),
      );
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final task = results[index];
        return Card(
          child: ListTile(
            leading: CategoryIconBadge(task.category, size: 44),
            title: Text(
              task.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(task.category.displayName),
            trailing: const Icon(Icons.arrow_forward_rounded, size: 20),
            onTap: () => close(context, task.title),
          ),
        );
      },
    );
  }
}
