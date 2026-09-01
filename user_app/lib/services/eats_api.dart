import 'package:ravelgo_user_app/services/api_client.dart';

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

class MenuItem {
  final String id;
  final String name;
  final String? description;
  final double price;
  MenuItem({required this.id, required this.name, this.description, required this.price});

  factory MenuItem.fromJson(Map<String, dynamic> j) => MenuItem(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        description: j['description']?.toString(),
        price: _d(j['price']),
      );
}

class Restaurant {
  final String id;
  final String name;
  final String cuisine;
  final String address;
  final String? imageUrl;
  final double? rating;
  final bool isOpen;
  final List<MenuItem> menu;
  Restaurant({
    required this.id,
    required this.name,
    required this.cuisine,
    required this.address,
    this.imageUrl,
    this.rating,
    required this.isOpen,
    this.menu = const [],
  });

  factory Restaurant.fromJson(Map<String, dynamic> j) => Restaurant(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        cuisine: '${j['cuisine'] ?? ''}',
        address: '${j['address'] ?? ''}',
        imageUrl: j['imageUrl']?.toString(),
        rating: j['rating'] is num ? (j['rating'] as num).toDouble() : null,
        isOpen: j['isOpen'] == true,
        menu: ((j['menuItems'] as List?) ?? const [])
            .map((e) => MenuItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class FoodOrder {
  final String id;
  final String status;
  final double subtotal;
  final double deliveryFee;
  final double total;
  FoodOrder({
    required this.id,
    required this.status,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
  });

  factory FoodOrder.fromJson(Map<String, dynamic> j) => FoodOrder(
        id: '${j['id']}',
        status: '${j['status'] ?? ''}',
        subtotal: _d(j['subtotal']),
        deliveryFee: _d(j['deliveryFee']),
        total: _d(j['total']),
      );
}

class EatsApi {
  static Future<List<Restaurant>> restaurants() async {
    final data = await ApiClient.get('/api/eats/restaurants?page=1&pageSize=50');
    final items = (data as Map<String, dynamic>)['data'] as List? ?? const [];
    return items.map((e) => Restaurant.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Restaurant> restaurant(String id) async {
    final data = await ApiClient.get('/api/eats/restaurants/$id');
    return Restaurant.fromJson(data as Map<String, dynamic>);
  }

  /// Place an order. `quantities` maps menu item id -> quantity; zero-qty items
  /// are dropped. The backend recomputes every price and the total.
  static Future<FoodOrder> placeOrder({
    required String restaurantId,
    required String deliveryAddress,
    required Map<String, int> quantities,
  }) async {
    final items = quantities.entries
        .where((e) => e.value > 0)
        .map((e) => {'menuItemId': e.key, 'quantity': e.value})
        .toList();
    final data = await ApiClient.post('/api/eats/orders', {
      'restaurantId': restaurantId,
      'deliveryAddress': deliveryAddress,
      'items': items,
    });
    return FoodOrder.fromJson(data as Map<String, dynamic>);
  }

  static Future<List<FoodOrder>> myOrders() async {
    final data = await ApiClient.get('/api/eats/orders/mine');
    return ((data as List?) ?? const [])
        .map((e) => FoodOrder.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
