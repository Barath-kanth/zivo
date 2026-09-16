import 'package:equatable/equatable.dart';

/// Client-authored grocery / purchase line item.
class ShoppingListItem extends Equatable {
  const ShoppingListItem({
    this.id,
    required this.taskId,
    required this.name,
    this.quantity = '1',
    this.notes,
    this.estimatedPrice,
    this.purchased = false,
    this.actualPrice,
    this.sortOrder = 0,
  });

  final String? id;
  final String taskId;
  final String name;
  final String quantity;
  final String? notes;
  final double? estimatedPrice;
  final bool purchased;
  final double? actualPrice;
  final int sortOrder;

  Map<String, dynamic> toInsertJson() => {
        'task_id': taskId,
        'name': name.trim(),
        'quantity': quantity.trim().isEmpty ? '1' : quantity.trim(),
        'notes': notes,
        'estimated_price': estimatedPrice,
        'sort_order': sortOrder,
      };

  factory ShoppingListItem.fromJson(Map<String, dynamic> json) =>
      ShoppingListItem(
        id: json['id'] as String?,
        taskId: json['task_id'] as String,
        name: json['name'] as String? ?? '',
        quantity: json['quantity'] as String? ?? '1',
        notes: json['notes'] as String?,
        estimatedPrice: (json['estimated_price'] as num?)?.toDouble(),
        purchased: json['purchased'] as bool? ?? false,
        actualPrice: (json['actual_price'] as num?)?.toDouble(),
        sortOrder: json['sort_order'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [id, taskId, name, quantity, purchased];
}

/// Helper-submitted receipt + goods photos (seller vs helper evidence).
class TaskPurchaseProof extends Equatable {
  const TaskPurchaseProof({
    required this.id,
    required this.taskId,
    required this.helperId,
    required this.receiptImageUrl,
    required this.goodsImageUrls,
    this.storeName,
    required this.receiptTotal,
    this.notes,
    required this.createdAt,
  });

  final String id;
  final String taskId;
  final String helperId;
  final String receiptImageUrl;
  final List<String> goodsImageUrls;
  final String? storeName;
  final double receiptTotal;
  final String? notes;
  final DateTime createdAt;

  factory TaskPurchaseProof.fromJson(Map<String, dynamic> json) =>
      TaskPurchaseProof(
        id: json['id'] as String,
        taskId: json['task_id'] as String,
        helperId: json['helper_id'] as String,
        receiptImageUrl: json['receipt_image_url'] as String,
        goodsImageUrls: (json['goods_image_urls'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        storeName: json['store_name'] as String?,
        receiptTotal: (json['receipt_total'] as num?)?.toDouble() ?? 0,
        notes: json['notes'] as String?,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
      );

  @override
  List<Object?> get props => [id, taskId, receiptTotal];
}
