import 'dart:convert';
import 'package:bluebubble_messages/managers/contact_manager.dart';
import 'package:bluebubble_messages/repository/models/attachment.dart';
import 'package:flutter/cupertino.dart';
import 'package:sqflite/sqflite.dart';

import '../database.dart';
import 'handle.dart';
import 'message.dart';
import '../../helpers/utils.dart';

Chat chatFromJson(String str) {
  final jsonData = json.decode(str);
  return Chat.fromMap(jsonData);
}

String chatToJson(Chat data) {
  final dyn = data.toMap();
  return json.encode(dyn);
}

Future<String> chatTitle(Chat _chat) async {
  String title = "";
  if (_chat.displayName == null || _chat.displayName == "") {
    Chat chat = await _chat.getParticipants();
    List<String> titles = [];
    for (int i = 0; i < chat.participants.length; i++) {
      titles.add(getContactTitle(
          ContactManager().contacts, chat.participants[i].address.toString()));
    }

    title = titles.join(', ');
  } else {
    title = _chat.displayName;
  }
  return title;
}

class Chat {
  int id;
  String guid;
  int style;
  String chatIdentifier;
  bool isArchived;
  String displayName;
  List<Handle> participants;

  Chat(
      {this.id,
      this.guid,
      this.style,
      this.chatIdentifier,
      this.isArchived,
      this.displayName,
      this.participants});

  factory Chat.fromMap(Map<String, dynamic> json) {
    List<Handle> participants = [];
    if (json.containsKey('participants')) {
      (json['participants'] as List<dynamic>).forEach((item) {
        participants.add(Handle.fromMap(item));
      });
    }
    return new Chat(
      id: json.containsKey("ROWID") ? json["ROWID"] : null,
      guid: json["guid"],
      style: json['style'],
      chatIdentifier:
          json.containsKey("chatIdentifier") ? json["chatIdentifier"] : null,
      isArchived: (json["isArchived"] is bool)
          ? json['isArchived']
          : ((json['isArchived'] == 1) ? true : false),
      displayName: json.containsKey("displayName") ? json["displayName"] : null,
      participants: participants,
    );
  }

  Future<Chat> save([bool updateIfAbsent = true]) async {
    final Database db = await DBProvider.db.database;

    // Try to find an existing chat before saving it
    Chat existing = await Chat.findOne({"guid": this.guid});
    if (existing != null) {
      this.id = existing.id;
    }

    // If it already exists, update it
    if (existing == null) {
      // Remove the ID from the map for inserting
      var map = this.toMap();
      if (map.containsKey("ROWID")) {
        map.remove("ROWID");
      }
      if (map.containsKey("participants")) {
        map.remove("participants");
      }

      this.id = await db.insert("chat", map);
    } else if (updateIfAbsent) {
      await this.update();
    }

    // Save participants to the chat
    for (int i = 0; i < this.participants.length; i++) {
      await this.addParticipant(this.participants[i]);
    }

    return this;
  }

  Future<Chat> update() async {
    final Database db = await DBProvider.db.database;

    Map<String, dynamic> params = {"isArchived": this.isArchived ? 1 : 0};

    // Add display name if it's been updated
    if (this.displayName != null) {
      params.putIfAbsent("displayName", () => this.displayName);
    }

    // If it already exists, update it
    if (this.id != null) {
      await db.update("chat", params, where: "ROWID = ?", whereArgs: [this.id]);
    } else {
      await this.save(false);
    }

    return this;
  }

  Future<Chat> addMessage(Message message) async {
    final Database db = await DBProvider.db.database;

    // Save the message and the chat
    await this.save();
    await message.save();

    // Check join table and add if relationship doesn't exist
    List entries = await db.query("chat_message_join",
        where: "chatId = ? AND messageId = ?",
        whereArgs: [this.id, message.id]);
    if (entries.length == 0) {
      await db.insert(
          "chat_message_join", {"chatId": this.id, "messageId": message.id});
    }

    return this;
  }

  static Future<List<Attachment>> getAttachments(Chat chat,
      {int offset = 0, int limit = 100}) async {
    final Database db = await DBProvider.db.database;

    String query = ("SELECT"
        " attachment.ROWID AS ROWID,"
        " attachment.guid AS guid,"
        " attachment.uti AS uti,"
        " attachment.mimeType AS mimeType,"
        " attachment.totalBytes AS totalBytes,"
        " attachment.transferName AS transferName,"
        " attachment.blurhash AS blurhash"
        " FROM attachment"
        " JOIN message_attachment_join AS maj ON maj.attachment_id = attachment.ROWID"
        " JOIN message ON maj.message_id = message.ROWID"
        " JOIN chat_message_join AS cmj ON cmj.message_id = message.ROWID"
        " JOIN chat ON chat.ROWID = cmj.chat_id"
        " WHERE chat.ROWID = ?");

    // Add pagination
    query += " ORDER BY message.dateCreated DESC LIMIT $limit OFFSET $offset";

    // Execute the query
    var res = await db.rawQuery("$query;", [chat.id]);
    return res == null
        ? []
        : res.map((attachment) => Attachment.fromMap(attachment));
  }

  static Future<List<Message>> getMessages(Chat chat,
      {bool reactionsOnly = false, int offset = 0, int limit = 100}) async {
    final Database db = await DBProvider.db.database;

    String reactionQualifier = reactionsOnly ? "IS NOT" : "IS";
    String query = ("SELECT"
        " message.ROWID AS ROWID,"
        " message.guid AS guid,"
        " message.handleId AS handleId,"
        " message.text AS text,"
        " message.subject AS subject,"
        " message.country AS country,"
        " message.error AS error,"
        " message.dateCreated AS dateCreated,"
        " message.dateDelivered AS dateDelivered,"
        " message.isFromMe AS isFromMe,"
        " message.isDelayed AS isDelayed,"
        " message.isAutoReply AS isAutoReply,"
        " message.isSystemMessage AS isSystemMessage,"
        " message.isForward AS isForward,"
        " message.isArchived AS isArchived,"
        " message.cacheRoomnames AS cacheRoomnames,"
        " message.isAudioMessage AS isAudioMessage,"
        " message.datePlayed AS datePlayed,"
        " message.itemType AS itemType,"
        " message.groupTitle AS groupTitle,"
        " message.groupActionType AS groupActionType,"
        " message.isExpired AS isExpired,"
        " message.associatedMessageGuid AS associatedMessageGuid,"
        " message.associatedMessageType AS associatedMessageType,"
        " message.expressiveSendStyleId AS texexpressiveSendStyleIdt,"
        " message.timeExpressiveSendStyleId AS timeExpressiveSendStyleId,"
        " message.hasAttachments AS hasAttachments,"
        " handle.ROWID AS handleId,"
        " handle.address AS handleAddress,"
        " handle.country AS handleCountry,"
        " handle.uncanonicalizedId AS handleUncanonicalizedId"
        " FROM message"
        " JOIN chat_message_join AS cmj ON message.ROWID = cmj.messageId"
        " JOIN chat ON cmj.chatId = chat.ROWID"
        " LEFT OUTER JOIN handle ON handle.ROWID = message.handleId"
        " WHERE chat.ROWID = ? AND message.associatedMessageType $reactionQualifier NULL");

    // Add pagination
    query += " ORDER BY message.dateCreated DESC LIMIT $limit OFFSET $offset";

    // Execute the query
    var res = await db.rawQuery("$query;", [chat.id]);

    // Add the from/handle data to the messages
    List<Message> output = [];
    for (int i = 0; i < res.length; i++) {
      Message msg = Message.fromMap(res[i]);

      // If the handle is not null, load the handle data
      // The handle is null if the message.handleId is 0
      // the handleId is 0 when isFromMe is true and the chat is a group chat
      if (res[i].containsKey('handleAddress') &&
          res[i]['handleAddress'] != null) {
        msg.handle = Handle.fromMap({
          'id': res[i]['handleId'],
          'address': res[i]['handleAddress'],
          'country': res[i]['handleCountry'],
          'uncanonicalizedId': res[i]['handleUncanonicalizedId']
        });
      }

      output.add(msg);
    }
    return output;
  }

  Future<Chat> getParticipants() async {
    final Database db = await DBProvider.db.database;

    var res = await db.rawQuery(
        "SELECT"
        " handle.ROWID AS ROWID,"
        " handle.address AS address,"
        " handle.country AS country,"
        " handle.uncanonicalizedId AS uncanonicalizedId"
        " FROM chat"
        " JOIN chat_handle_join AS chj ON chat.ROWID = chj.chatId"
        " JOIN handle ON handle.ROWID = chj.handleId"
        " WHERE chat.ROWID = ?;",
        [this.id]);

    this.participants =
        (res.isNotEmpty) ? res.map((c) => Handle.fromMap(c)).toList() : [];
    return this;
  }

  Future<Chat> addParticipant(Handle participant) async {
    final Database db = await DBProvider.db.database;

    // Save participant and add to list
    await participant.save();
    if (!this.participants.contains(participant)) {
      this.participants.add(participant);
    }

    // Check join table and add if relationship doesn't exist
    List entries = await db.query("chat_handle_join",
        where: "chatId = ? AND handleId = ?",
        whereArgs: [this.id, participant.id]);
    if (entries.length == 0) {
      await db.insert(
          "chat_handle_join", {"chatId": this.id, "handleId": participant.id});
    }

    return this;
  }

  Future<Chat> removeParticipant(Handle participant) async {
    final Database db = await DBProvider.db.database;

    // First, remove from the JOIN table
    await db.delete("chat_handle_join",
        where: "chatId = ? AND handleId = ?",
        whereArgs: [this.id, participant.id]);

    // Second, remove from this object instance
    if (this.participants.contains(participant)) {
      this.participants.remove(participant);
    }

    return this;
  }

  static Future<Chat> findOne(Map<String, dynamic> filters) async {
    final Database db = await DBProvider.db.database;

    List<String> whereParams = [];
    filters.keys.forEach((filter) => whereParams.add('$filter = ?'));
    List<dynamic> whereArgs = [];
    filters.values.forEach((filter) => whereArgs.add(filter));
    var res = await db.query("chat",
        where: whereParams.join(" AND "), whereArgs: whereArgs, limit: 1);

    if (res.isEmpty) {
      return null;
    }

    return Chat.fromMap(res.elementAt(0));
  }

  static Future<List<Chat>> find(
      [Map<String, dynamic> filters = const {}]) async {
    final Database db = await DBProvider.db.database;

    List<String> whereParams = [];
    filters.keys.forEach((filter) => whereParams.add('$filter = ?'));
    List<dynamic> whereArgs = [];
    filters.values.forEach((filter) => whereArgs.add(filter));

    var res = await db.query("chat",
        where: (whereParams.length > 0) ? whereParams.join(" AND ") : null,
        whereArgs: (whereArgs.length > 0) ? whereArgs : null);
    return (res.isNotEmpty) ? res.map((c) => Chat.fromMap(c)).toList() : [];
  }

  static flush() async {
    final Database db = await DBProvider.db.database;
    await db.delete("chat");
  }

  Map<String, dynamic> toMap() => {
        "ROWID": id,
        "guid": guid,
        "style": style,
        "chatIdentifier": chatIdentifier,
        "isArchived": isArchived ? 1 : 0,
        "displayName": displayName,
        "participants": participants.map((item) => item.toMap())
      };
}