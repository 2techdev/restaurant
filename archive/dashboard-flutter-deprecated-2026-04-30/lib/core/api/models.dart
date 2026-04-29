// ---------------------------------------------------------------------------
// Dashboard stats
// ---------------------------------------------------------------------------

class DashboardStats {
  final String date;
  final int totalRevenue;
  final int orderCount;
  final int avgTicket;
  final int activeOrders;
  final int tablesOccupied;
  final int openOrders;
  final int staffOnShift;
  final List<TopItem> topItems;

  const DashboardStats({
    required this.date,
    required this.totalRevenue,
    required this.orderCount,
    required this.avgTicket,
    required this.activeOrders,
    required this.tablesOccupied,
    required this.openOrders,
    required this.staffOnShift,
    required this.topItems,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> j) => DashboardStats(
        date: j['date'] as String? ?? '',
        totalRevenue: j['total_revenue'] as int? ?? 0,
        orderCount: j['order_count'] as int? ?? 0,
        avgTicket: j['avg_ticket'] as int? ?? 0,
        activeOrders: j['active_orders'] as int? ?? 0,
        tablesOccupied: j['tables_occupied'] as int? ?? 0,
        openOrders: j['open_orders'] as int? ?? 0,
        staffOnShift: j['staff_on_shift'] as int? ?? 0,
        topItems: (j['top_items'] as List<dynamic>? ?? [])
            .map((e) => TopItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static DashboardStats get demo => DashboardStats(
        date: DateTime.now().toIso8601String().substring(0, 10),
        totalRevenue: 384750,
        orderCount: 47,
        avgTicket: 8186,
        activeOrders: 6,
        tablesOccupied: 8,
        openOrders: 6,
        staffOnShift: 4,
        topItems: [
          TopItem(name: 'Zürcher Geschnetzeltes', quantity: 14, revenue: 69860),
          TopItem(name: 'Wiener Schnitzel', quantity: 11, revenue: 60490),
          TopItem(name: 'Rösti mit Spiegelei', quantity: 9, revenue: 31410),
          TopItem(name: 'Bier 0.5L', quantity: 22, revenue: 21780),
          TopItem(name: 'Espresso', quantity: 18, revenue: 10710),
        ],
      );
}

class TopItem {
  final String name;
  final int quantity;
  final int revenue;

  const TopItem({
    required this.name,
    required this.quantity,
    required this.revenue,
  });

  factory TopItem.fromJson(Map<String, dynamic> j) => TopItem(
        name: j['name'] as String? ?? '',
        quantity: j['quantity'] as int? ?? 0,
        revenue: j['revenue'] as int? ?? 0,
      );
}

// ---------------------------------------------------------------------------
// Revenue chart
// ---------------------------------------------------------------------------

class RevenuePoint {
  final String date;
  final int revenue;
  final int orders;

  const RevenuePoint({
    required this.date,
    required this.revenue,
    required this.orders,
  });

  factory RevenuePoint.fromJson(Map<String, dynamic> j) => RevenuePoint(
        date: j['date'] as String? ?? '',
        revenue: j['revenue'] as int? ?? 0,
        orders: j['orders'] as int? ?? 0,
      );

  static List<RevenuePoint> get demo {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      final label = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      const base = [210000, 185000, 320000, 274000, 298000, 342000, 384750];
      return RevenuePoint(date: label, revenue: base[i], orders: 28 + i * 3);
    });
  }
}

// ---------------------------------------------------------------------------
// Orders
// ---------------------------------------------------------------------------

class Order {
  final String id;
  final int orderNumber;
  final String status;
  final String orderType;
  final int total;
  final String createdAt;
  final String? paymentMethod;
  final String? waiterName;
  final List<OrderItem> items;

  const Order({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.orderType,
    required this.total,
    required this.createdAt,
    this.paymentMethod,
    this.waiterName,
    this.items = const [],
  });

  factory Order.fromJson(Map<String, dynamic> j) => Order(
        id: j['id'] as String? ?? '',
        orderNumber: j['order_number'] as int? ?? 0,
        status: j['status'] as String? ?? '',
        orderType: j['order_type'] as String? ?? '',
        total: j['total_amount'] as int? ?? 0,
        createdAt: j['created_at'] as String? ?? '',
        paymentMethod: j['payment_method'] as String?,
        waiterName: j['waiter_name'] as String?,
        items: (j['items'] as List<dynamic>? ?? [])
            .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static List<Order> get demo => List.generate(25, (i) {
        final statuses = ['fully_paid', 'open', 'preparing', 'fully_paid', 'closed'];
        final types = ['dine_in', 'takeaway', 'dine_in'];
        final methods = ['card', 'cash', 'twint', 'card'];
        final waiters = ['Maria', 'Tom', 'Sara', 'Jan'];
        final d = DateTime.now().subtract(Duration(hours: i * 2));
        return Order(
          id: 'demo-$i',
          orderNumber: 1000 + i,
          status: statuses[i % statuses.length],
          orderType: types[i % types.length],
          total: 1800 + (i * 1350) % 12000,
          createdAt: d.toIso8601String(),
          paymentMethod: methods[i % methods.length],
          waiterName: waiters[i % waiters.length],
          items: [
            OrderItem(productName: 'Wiener Schnitzel', quantity: 1, unitPrice: 2890),
            OrderItem(productName: 'Bier 0.5L', quantity: 2, unitPrice: 550),
          ],
        );
      });
}

class OrderItem {
  final String productName;
  final int quantity;
  final int unitPrice;

  const OrderItem({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
  });

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
        productName: j['product_name'] as String? ?? '',
        quantity: j['quantity'] as int? ?? 0,
        unitPrice: j['unit_price'] as int? ?? 0,
      );
}

// ---------------------------------------------------------------------------
// Menu
// ---------------------------------------------------------------------------

class MenuCategory {
  final String id;
  final String name;
  final String color;
  final String icon;
  final int displayOrder;

  const MenuCategory({
    required this.id,
    required this.name,
    required this.color,
    required this.icon,
    required this.displayOrder,
  });

  factory MenuCategory.fromJson(Map<String, dynamic> j) => MenuCategory(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        color: j['color'] as String? ?? '#4F46E5',
        icon: j['icon'] as String? ?? 'restaurant',
        displayOrder: j['display_order'] as int? ?? 0,
      );

  MenuCategory copyWith({String? name, String? color, String? icon}) => MenuCategory(
        id: id,
        name: name ?? this.name,
        color: color ?? this.color,
        icon: icon ?? this.icon,
        displayOrder: displayOrder,
      );

  static List<MenuCategory> get demo => [
        const MenuCategory(id: 'c1', name: 'Vorspeisen', color: '#F59E0B', icon: 'soup_kitchen', displayOrder: 1),
        const MenuCategory(id: 'c2', name: 'Hauptspeisen', color: '#EF4444', icon: 'restaurant', displayOrder: 2),
        const MenuCategory(id: 'c3', name: 'Desserts', color: '#EC4899', icon: 'cake', displayOrder: 3),
        const MenuCategory(id: 'c4', name: 'Getränke', color: '#3B82F6', icon: 'local_bar', displayOrder: 4),
      ];
}

class Product {
  final String id;
  final String categoryId;
  final String name;
  final String description;
  final int price;
  final String taxGroup;
  final bool isAvailable;
  final int displayOrder;
  final String? imageUrl;

  const Product({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.description,
    required this.price,
    required this.taxGroup,
    required this.isAvailable,
    required this.displayOrder,
    this.imageUrl,
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String? ?? '',
        categoryId: j['category_id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        description: j['description'] as String? ?? '',
        price: j['price'] as int? ?? 0,
        taxGroup: j['tax_group'] as String? ?? 'reduced',
        isAvailable: j['is_available'] as bool? ?? true,
        displayOrder: j['display_order'] as int? ?? 0,
        imageUrl: j['image_url'] as String?,
      );

  Product copyWith({
    String? name,
    String? description,
    int? price,
    String? taxGroup,
    bool? isAvailable,
  }) =>
      Product(
        id: id,
        categoryId: categoryId,
        name: name ?? this.name,
        description: description ?? this.description,
        price: price ?? this.price,
        taxGroup: taxGroup ?? this.taxGroup,
        isAvailable: isAvailable ?? this.isAvailable,
        displayOrder: displayOrder,
        imageUrl: imageUrl,
      );

  static List<Product> get demo => [
        const Product(id: 'p1', categoryId: 'c2', name: 'Wiener Schnitzel', description: 'Mit Pommes und Salat', price: 2890, taxGroup: 'reduced', isAvailable: true, displayOrder: 1),
        const Product(id: 'p2', categoryId: 'c2', name: 'Zürcher Geschnetzeltes', description: 'Mit Rösti und Rahmsauce', price: 3290, taxGroup: 'reduced', isAvailable: true, displayOrder: 2),
        const Product(id: 'p3', categoryId: 'c2', name: 'Lachs auf Spinat', description: 'Mit Safranrisotto', price: 3490, taxGroup: 'reduced', isAvailable: false, displayOrder: 3),
        const Product(id: 'p4', categoryId: 'c4', name: 'Bier 0.5L', description: 'Lokales Fassbier', price: 550, taxGroup: 'standard', isAvailable: true, displayOrder: 1),
        const Product(id: 'p5', categoryId: 'c4', name: 'Mineralwasser', description: 'Still oder mit Kohlensäure', price: 350, taxGroup: 'reduced', isAvailable: true, displayOrder: 2),
        const Product(id: 'p6', categoryId: 'c1', name: 'Bündner Fleisch', description: 'Mit Brot und Butter', price: 1850, taxGroup: 'reduced', isAvailable: true, displayOrder: 1),
      ];
}

// ---------------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------------

class SalesPoint {
  final String period;
  final int orderCount;
  final int revenue;
  final int tax;
  final int discounts;

  const SalesPoint({
    required this.period,
    required this.orderCount,
    required this.revenue,
    required this.tax,
    required this.discounts,
  });

  factory SalesPoint.fromJson(Map<String, dynamic> j) => SalesPoint(
        period: j['period'] as String? ?? '',
        orderCount: j['order_count'] as int? ?? 0,
        revenue: j['revenue'] as int? ?? 0,
        tax: j['tax'] as int? ?? 0,
        discounts: j['discounts'] as int? ?? 0,
      );
}

class CategorySales {
  final String categoryName;
  final int quantity;
  final int revenue;

  const CategorySales({
    required this.categoryName,
    required this.quantity,
    required this.revenue,
  });

  factory CategorySales.fromJson(Map<String, dynamic> j) => CategorySales(
        categoryName: j['category_name'] as String? ?? '',
        quantity: j['quantity'] as int? ?? 0,
        revenue: j['revenue'] as int? ?? 0,
      );
}

class PaymentBreakdown {
  final String method;
  final int count;
  final int total;

  const PaymentBreakdown({
    required this.method,
    required this.count,
    required this.total,
  });

  factory PaymentBreakdown.fromJson(Map<String, dynamic> j) => PaymentBreakdown(
        method: j['method'] as String? ?? '',
        count: j['count'] as int? ?? 0,
        total: j['total'] as int? ?? 0,
      );
}

class MWSTLine {
  final String taxGroup;
  final double rate;
  final int grossAmount;
  final int netAmount;
  final int taxAmount;

  const MWSTLine({
    required this.taxGroup,
    required this.rate,
    required this.grossAmount,
    required this.netAmount,
    required this.taxAmount,
  });

  factory MWSTLine.fromJson(Map<String, dynamic> j) => MWSTLine(
        taxGroup: j['tax_group'] as String? ?? '',
        rate: (j['rate'] as num?)?.toDouble() ?? 0.0,
        grossAmount: j['gross_amount'] as int? ?? 0,
        netAmount: j['net_amount'] as int? ?? 0,
        taxAmount: j['tax_amount'] as int? ?? 0,
      );
}

class MWSTReport {
  final String from;
  final String to;
  final List<MWSTLine> lines;
  final int totalGross;
  final int totalTax;
  final int totalNet;

  const MWSTReport({
    required this.from,
    required this.to,
    required this.lines,
    required this.totalGross,
    required this.totalTax,
    required this.totalNet,
  });

  factory MWSTReport.fromJson(Map<String, dynamic> j) => MWSTReport(
        from: j['from'] as String? ?? '',
        to: j['to'] as String? ?? '',
        lines: (j['lines'] as List<dynamic>? ?? [])
            .map((e) => MWSTLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalGross: j['total_gross'] as int? ?? 0,
        totalTax: j['total_tax'] as int? ?? 0,
        totalNet: j['total_net'] as int? ?? 0,
      );

  static MWSTReport get demo => MWSTReport(
        from: '2026-03-01',
        to: '2026-03-31',
        lines: const [
          MWSTLine(taxGroup: 'standard', rate: 0.081, grossAmount: 1243500, netAmount: 1149861, taxAmount: 93639),
          MWSTLine(taxGroup: 'reduced', rate: 0.038, grossAmount: 3872000, netAmount: 3729286, taxAmount: 142714),
        ],
        totalGross: 5115500,
        totalTax: 236353,
        totalNet: 4879147,
      );
}

// ---------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------

class LoginResult {
  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final String userId;
  final String name;
  final String email;
  final String role;

  const LoginResult({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
  });

  factory LoginResult.fromJson(Map<String, dynamic> j) {
    final user = j['user'] as Map<String, dynamic>? ?? {};
    return LoginResult(
      accessToken: j['access_token'] as String? ?? '',
      refreshToken: j['refresh_token'] as String? ?? '',
      expiresIn: j['expires_in'] as int? ?? 86400,
      userId: user['id'] as String? ?? '',
      name: user['name'] as String? ?? '',
      email: user['email'] as String? ?? '',
      role: user['role'] as String? ?? 'admin',
    );
  }
}
