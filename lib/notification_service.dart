import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  late FlutterLocalNotificationsPlugin _notificationsPlugin;
  final Set<String> _shownNotifications = {};

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal() {
    _notificationsPlugin = FlutterLocalNotificationsPlugin();
  }

  /// Initialize the notification service
  Future<void> initialize() async {
    const AndroidInitializationSettings androidInitSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosInitSettings =
        DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidInitSettings,
      iOS: iosInitSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationTap,
    );

    // Request permissions for Android 13+
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Handle notification tap
  void _handleNotificationTap(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
  }

  /// Show expiry notification (only if not already shown)
  Future<void> showExpiryNotification({
    required String itemName,
    required int daysUntilExpiry,
  }) async {
    final notificationKey = 'expiry_$itemName}';
    
    // Only show if not already shown
    if (_shownNotifications.contains(notificationKey)) {
      debugPrint('Expiry notification already shown for: $itemName');
      return;
    }

    final notificationId = itemName.hashCode;
    String title = 'Expiry Alert';
    String body;

    if (daysUntilExpiry == 0) {
      body = '$itemName expires today!';
    } else if (daysUntilExpiry == 1) {
      body = '$itemName expires tomorrow!';
    } else {
      body = '$itemName expires in $daysUntilExpiry days';
    }

    try {
      await _showNotification(
        id: notificationId,
        title: title,
        body: body,
        payload: 'expiry:$itemName',
      );
      _shownNotifications.add(notificationKey);
      debugPrint('Expiry notification shown for: $itemName');
    } catch (e) {
      debugPrint('Error showing expiry notification: $e');
    }
  }

  /// Show low stock notification (only if not already shown)
  Future<void> showLowStockNotification({
    required String itemName,
    required int currentQuantity,
  }) async {
    final notificationKey = 'lowstock_${itemName}';
    
    // Only show if not already shown
    if (_shownNotifications.contains(notificationKey)) {
      debugPrint('Low stock notification already shown for: $itemName');
      return;
    }

    final notificationId = '${itemName}_lowstock'.hashCode;
    final title = 'Low Stock Alert';
    final body = '$itemName is running low (Qty: $currentQuantity)';

    try {
      await _showNotification(
        id: notificationId,
        title: title,
        body: body,
        payload: 'lowstock:$itemName',
      );
      _shownNotifications.add(notificationKey);
      debugPrint('Low stock notification shown for: $itemName');
    } catch (e) {
      debugPrint('Error showing low stock notification: $e');
    }
  }

  /// Generic notification method
  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'intellicab_notifications',
      'IntelliCab Notifications',
      channelDescription: 'Notifications for inventory alerts',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      id,
      title,
      body,
      platformDetails,
      payload: payload,
    );
  }

  /// Cancel a specific notification
  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
  }

  /// Clear shown notifications cache (call this when returning from notifications page)
  void clearShownCache() {
    _shownNotifications.clear();
    debugPrint('Cleared shown notifications cache');
  }
}
