class Utils {
  Utils._();

  static final Utils instance = Utils._();

  void printLogs(String? tag, [String? message = ""]) {
    print("HeartApp_$tag: $message");
  }
}
