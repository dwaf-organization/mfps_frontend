import 'package:flutter/material.dart';

enum MealStatus {
  full, // 식사 전량 섭취
  miss, // 결식
}

extension MealStatusX on MealStatus {
  String get label {
    switch (this) {
      case MealStatus.full:
        return '식사 전량 섭취';
      case MealStatus.miss:
        return '결식';
    }
  }

  Color get bgColor {
    switch (this) {
      case MealStatus.full:
        return const Color(0xFFE0E7FF);
      case MealStatus.miss:
        return const Color(0xFFFECACA);
    }
  }
}
