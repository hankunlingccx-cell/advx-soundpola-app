/// designstyle.md V2.0 §5
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;

  static const pageHorizontal = 20.0;
  static const section = 24.0;
  static const block = 32.0;
  static const item = 16.0;
  static const tight = 12.0;
  static const chip = 8.0;
  static const cardPadding = 16.0;
}

abstract final class AppRadii {
  static const chip = 8.0;
  static const input = 14.0;
  static const card = 20.0;
  static const collectionCard = 24.0;
  static const button = 16.0;
  static const sheet = 28.0;
}

abstract final class AppSizes {
  static const buttonHeight = 54.0;
  static const inputHeight = 52.0;
  static const recordButton = 64.0;
  static const bottomNav = 72.0;
  static const statusChipHeight = 26.0;
  static const avatar = 36.0;
}

abstract final class AppMotion {
  static const fast = Duration(milliseconds: 180);
  static const normal = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 360);
}
