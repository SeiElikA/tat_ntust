// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'moodle_mod_forum_can_add_discussion.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MoodleCanAddDiscussion _$MoodleCanAddDiscussionFromJson(
        Map<String, dynamic> json) =>
    MoodleCanAddDiscussion(
      status: json['status'] as bool? ?? false,
      cancreateattachment: json['cancreateattachment'] as bool?,
    );

Map<String, dynamic> _$MoodleCanAddDiscussionToJson(
        MoodleCanAddDiscussion instance) =>
    <String, dynamic>{
      'status': instance.status,
      'cancreateattachment': instance.cancreateattachment,
    };
