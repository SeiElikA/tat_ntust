import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_profile_entity.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';
import 'package:get/get.dart';

class UserProfile extends StatefulWidget {
  const UserProfile({
    super.key,
    required this.data,
    this.onAvatarTap,
    this.progress,
  });

  final MoodleProfileEntity data;

  /// null 代表頭貼不可點（沿用舊行為）。
  final VoidCallback? onAvatarTap;

  /// 換頭貼的送出進度，0..1。非 null 代表正在換，這時頭貼不可點。
  final double? progress;

  @override
  State<UserProfile> createState() => _UserProfileState();
}

class _UserProfileState extends State<UserProfile> {
  static const double _radius = 24;

  /// 這張網址的圖載不出來。`CircleAvatar` 的 child 是畫在 backgroundImage
  /// **上面**的，不是它的退路，所以載得到的時候必須不給 child。
  bool _imageFailed = false;

  @override
  void didUpdateWidget(UserProfile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 換了一張圖就重新給它一次機會，否則失敗過一次會永遠停在預設圖示。
    if (oldWidget.data.userpictureurl != widget.data.userpictureurl) {
      _imageFailed = false;
    }
  }

  void _onImageError() {
    if (_imageFailed) return;
    _imageFailed = true;
    if (!mounted) return;
    // 這個回呼可能是在 paint 期間送來的（DecorationImagePainter 解圖時），
    // 當場 setState 會炸；那時排到這一格結束後再重畫。
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildAvatar(),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.data.firstname,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Get.theme.colorScheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              widget.data.username.toUpperCase(),
              style: TextStyle(
                  fontSize: 16, color: Get.theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAvatar() {
    final scheme = Get.theme.colorScheme;
    final progress = widget.progress;
    final busy = progress != null;
    final url = widget.data.userpictureurl;
    final showPlaceholder = url.isEmpty || _imageFailed;
    final avatar = Stack(
      clipBehavior: Clip.none,
      children: [
        Opacity(
          opacity: busy ? 0.5 : 1,
          child: CircleAvatar(
            radius: _radius,
            backgroundColor: scheme.surfaceContainerHigh,
            // onBackgroundImageError 是必要的：少了它，404 或離線的頭貼會把
            // 例外丟進 FlutterError.onError。
            backgroundImage: url.isEmpty ? null : NetworkImage(url),
            onBackgroundImageError: url.isEmpty
                ? null
                : (_, __) {
                    _onImageError();
                  },
            child: showPlaceholder
                ? Icon(LucideIcons.user,
                    size: 22, color: scheme.onSurfaceVariant)
                : null,
          ),
        ),
        if (busy)
          Positioned.fill(
            // 還沒有真的進度（移除頭貼整趟都沒有上傳）時給不定值：
            // 傳 0 進去畫的是一段長度為零的弧，等於什麼都沒有。
            child: CircularProgressIndicator(
                value: progress > 0 ? progress : null, strokeWidth: 2),
          )
        else if (widget.onAvatarTap != null)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primaryContainer,
              ),
              child: Icon(LucideIcons.pencil,
                  size: 11, color: scheme.onPrimaryContainer),
            ),
          ),
      ],
    );

    if (widget.onAvatarTap == null) return avatar;

    return Semantics(
      button: true,
      label: R.current.avatarChange,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : widget.onAvatarTap,
        child: avatar,
      ),
    );
  }
}
