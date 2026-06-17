import 'package:flutter/material.dart';

IconData getIconForCategory(String? categoryName) {
  switch (categoryName?.toLowerCase()) {
    case 'coffee shop':
    case 'coffee':
    case 'cafe':
      return Icons.coffee;
    case 'restaurant':
      return Icons.restaurant;
    case 'hotel':
      return Icons.hotel;
    case 'hospital':
      return Icons.local_hospital;
    case 'education':
      return Icons.school;
    case 'gas_station':
      return Icons.local_gas_station;
    case 'shopping':
      return Icons.shopping_bag;
    case 'park':
      return Icons.park;
    case 'bus_stop':
      return Icons.directions_bus;
    case 'train_station':
      return Icons.train;
    case 'airport':
      return Icons.local_airport;
    case 'bank':
      return Icons.account_balance;
    case 'pharmacy':
      return Icons.local_pharmacy;
    case 'gym':
      return Icons.fitness_center;
    case 'vetinary': 
      return Icons.local_hospital;
    default:
      return Icons.location_on;
  }
}

Color getColorForCategory(String? categoryName) {
  switch (categoryName?.toLowerCase()) {
    case 'coffee shop':
    case 'coffee':
    case 'cafe':
      return Colors.brown;
    case 'restaurant':
      return Colors.orange;
    case 'hotel':
      return Colors.blue;
    case 'hospital':
      return Colors.red;
    case 'education':
      return const Color.fromARGB(255, 0, 200, 255);
    case 'gas_station':
      return Colors.grey;
    case 'shopping':
      return Colors.purple;
    case 'park':
      return Colors.green;
    case 'bus_stop':
      return Colors.blue;
    case 'train_station':
      return Colors.blue;
    case 'airport':
      return Colors.blue;
    case 'bank':
      return Colors.green;
    case 'pharmacy':
      return Colors.red;
    case 'gym':
      return Colors.orange;
    case 'vetinary':
      return Colors.red;
    default:
      return Colors.deepPurple;
  }
}
