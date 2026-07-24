abstract final class AppRoutes {
  static const splash = '/splash';
  static const permission = '/permission';
  static const main = '/';
  static const recording = '/recording';
  static const result = '/result';
  static const draftDetail = '/draft/:id';
  static const pressMethod = '/press/method/:id';
  static const pressDetect = '/press/detect/:id';
  static const pressConfirm = '/press/confirm/:id';
  static const pressProgress = '/press/progress/:id';
  static const pressDone = '/press/done/:id';
  static const memory = '/memory/:id';
  static const login = '/auth/login';
  static const register = '/auth/register';
  static const accountReady = '/auth/account-ready';
  static const account = '/account';

  static String mainTab(int tab) => '/?tab=$tab';
  static String resultPath(int duration) => '/result?duration=$duration';
  static String draftPath(String id) => '/draft/$id';
  static String loginPath({String? draftId}) =>
      draftId == null ? login : '$login?draftId=$draftId';
  static String pressProgressPath(String id, {bool chainOnly = false}) =>
      chainOnly ? '/press/progress/$id?chainOnly=1' : '/press/progress/$id';
  static String pressMethodPath(String id, {bool chainOnly = false}) =>
      chainOnly ? '/press/method/$id?chainOnly=1' : '/press/method/$id';
  static String pressDetectPath(String id) => '/press/detect/$id';
  static String pressConfirmPath(String id) => '/press/confirm/$id';
  static String pressDonePath(String id) => '/press/done/$id';
  static String memoryPath(String id) => '/memory/$id';
}
