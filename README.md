# heart_03

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.



- Fix "flutter_bluetooth_serial_plus: ^0.5.1" error jCenter: 
View "Project" -> "External Libraries" -> "Flutter Plugins" -> "flutter_bluetooth_serial_plus-0.5.1" -> "build.gradle" -> replace "jCenter" to "mavenCentral()"
<img width="1306" height="675" alt="image" src="https://github.com/user-attachments/assets/73a78fd4-37fa-4a44-a211-c4c1b88b5ef9" />


- Fix "flutter_blue_plus: ^2.2.1":
  <img width="1177" height="648" alt="image" src="https://github.com/user-attachments/assets/a492adad-d69a-4e81-9db3-7aad830fe705" />

  buildscript {
    repositories {
        google()
        mavenCentral()
    }


}
rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
