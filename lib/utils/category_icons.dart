import 'package:flutter/material.dart';

/// Catálogo de íconos disponibles para categorías. Usamos los íconos
/// Material que ya vienen incluidos en Flutter (sin dependencias
/// externas) para evitar problemas de compatibilidad de paquetes de
/// terceros con versiones futuras de Flutter/Dart.
const Map<String, IconData> categoryIcons = {
  'train': Icons.train,
  'bus': Icons.directions_bus,
  'food': Icons.restaurant,
  'coffee': Icons.local_cafe,
  'home': Icons.home,
  'health': Icons.favorite,
  'medicine': Icons.medical_services,
  'briefcase': Icons.work,
  'laptop': Icons.laptop_mac,
  'shopping': Icons.shopping_bag,
  'gift': Icons.card_giftcard,
  'car': Icons.directions_car,
  'fuel': Icons.local_gas_station,
  'pet': Icons.pets,
  'phone': Icons.smartphone,
  'book': Icons.menu_book,
  'gym': Icons.fitness_center,
  'travel': Icons.flight,
  'movie': Icons.movie,
  'music': Icons.music_note,
  'kids': Icons.child_care,
  'utilities': Icons.bolt,
  'subscription': Icons.subscriptions,
  'savings': Icons.savings,
  'salary': Icons.payments,
  'entertainment': Icons.theater_comedy,
  'education': Icons.school,
  'insurance': Icons.security,
  'taxes': Icons.receipt_long,
  'donation': Icons.volunteer_activism,
  'repair': Icons.build,
  'beauty': Icons.face_retouching_natural,
  'cleaning': Icons.cleaning_services,
  'internet': Icons.wifi,
  'streaming': Icons.live_tv,
  'parking': Icons.local_parking,
  'taxi': Icons.local_taxi,
  'bank': Icons.account_balance,
  'investment': Icons.trending_up,
  'creditCard': Icons.credit_card,
  'wallet': Icons.account_balance_wallet,
  'electronics': Icons.devices,
  'clothing': Icons.checkroom,
  'garden': Icons.local_florist,
  'baby': Icons.child_friendly,
  'pharmacy': Icons.local_pharmacy,
  'sport': Icons.sports_soccer,
  'hobby': Icons.palette,
  'party': Icons.celebration,
  'fine': Icons.gavel,
  'exchange': Icons.currency_exchange,
  'other': Icons.category,
};

/// Paleta corta de colores para diferenciar categorías a simple vista.
/// Se asigna de forma determinística según el ícono elegido.
const List<Color> categoryIconColors = [
  Color(0xFF378ADD),
  Color(0xFF639922),
  Color(0xFFD85A30),
  Color(0xFFD4537E),
  Color(0xFF1D9E75),
  Color(0xFFBA7517),
  Color(0xFF7F77DD),
];

IconData iconForKey(String key) => categoryIcons[key] ?? Icons.category;

Color colorForKey(String key) =>
    categoryIconColors[key.hashCode.abs() % categoryIconColors.length];
