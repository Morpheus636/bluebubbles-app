import 'dart:ui';

import 'package:bluebubbles/helpers/logger.dart';
import 'package:bluebubbles/helpers/ui_helpers.dart';
import 'package:bluebubbles/helpers/utils.dart';
import 'package:bluebubbles/layouts/conversation_view/conversation_view.dart';
import 'package:bluebubbles/layouts/conversation_view/conversation_view_mixin.dart';
import 'package:bluebubbles/layouts/settings/settings_panel.dart';
import 'package:bluebubbles/layouts/widgets/theme_switcher/theme_switcher.dart';
import 'package:bluebubbles/repository/models/chat.dart';
import 'package:bluebubbles/repository/models/scheduled.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

List<List<dynamic>> timeOptions = [
  [300, "5 Minutes"],
  [1800, "30 Minutes"],
  [3600, "1 Hour"],
  [21600, "6 Hours"],
  [-1, "Custom"]
];

class SchedulePanel extends StatefulWidget {
  final Chat chat;

  SchedulePanel({Key? key, required this.chat}) : super(key: key);

  @override
  _SchedulePanelState createState() => _SchedulePanelState();
}

class _SchedulePanelState extends State<SchedulePanel> {
  Chat? _chat;
  String? title;
  late TextEditingController messageController;
  int? scheduleSeconds = 300;
  TimeOfDay? messageTime;
  DateTime? messageDate;
  List<String> errors = [];

  @override
  void initState() {
    super.initState();
    setChat(widget.chat);

    messageController = new TextEditingController();
    messageController.addListener(() {
      if (messageController.text.length > 0 && errors.length > 0 && this.mounted) {
        setState(() {
          errors = [];
        });
      }
    });
  }

  void fetchChatTitle(Chat? chat) {
    if (chat == null) return;

    getFullChatTitle(chat).then((String title) {
      if (!this.mounted) return;
      setState(() {
        this.title = title;
      });
    });
  }

  void setChat(Chat? chat) {
    if (chat == null) return;

    if (_chat == null || _chat!.guid != chat.guid) {
      _chat = chat;
      title = isNullOrEmpty(chat.displayName)! ? chat.chatIdentifier : chat.displayName;

      fetchChatTitle(_chat);
    }
  }

  String getTimeText(BuildContext context) {
    String output = "Unknown";
    for (List item in timeOptions) {
      if (item[0] == scheduleSeconds) {
        output = item[1];
        break;
      }
    }

    if (scheduleSeconds == -1) {
      if (messageDate != null && messageTime != null) {
        output = "${messageDate!.year}-${messageDate!.month}-${messageDate!.day} ${messageTime!.format(context)}";
      }
      return "Custom: $output";
    } else {
      return output;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: Theme.of(context).backgroundColor, // navigation bar color
        systemNavigationBarIconBrightness:
            Theme.of(context).backgroundColor.computeLuminance() > 0.5 ? Brightness.dark : Brightness.light,
        statusBarColor: Colors.transparent, // status bar color
      ),
      child: Scaffold(
        backgroundColor: Theme.of(context).backgroundColor,
        appBar: PreferredSize(
          preferredSize: Size(context.width, 80),
          child: ClipRRect(
            child: BackdropFilter(
              child: AppBar(
                brightness: getBrightness(context),
                toolbarHeight: 100.0,
                elevation: 0,
                leading: buildBackButton(context),
                backgroundColor: Theme.of(context).accentColor.withOpacity(0.5),
                title: Text(
                  "Message Scheduler",
                  style: Theme.of(context).textTheme.headline1,
                ),
              ),
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            ),
          ),
        ),
        body: CustomScrollView(
          physics: ThemeSwitcher.getScrollPhysics(),
          slivers: <Widget>[
            SliverList(
              delegate: SliverChildListDelegate(
                <Widget>[
                  Container(padding: EdgeInsets.only(top: 5.0)),
                  // Show a top tile
                  (_chat != null)
                      ? SettingsTile(
                          title: "Selected chat",
                          subtitle: title,
                          trailing: Icon(Icons.timer, color: Theme.of(context).primaryColor.withAlpha(200)),
                        )
                      : SettingsTile(
                          title: "Select a chat to schedule a message for",
                          subtitle: 'Tap here',
                          trailing: Icon(Icons.chat_bubble, color: Theme.of(context).primaryColor.withAlpha(200)),
                          onTap: () async {
                            Navigator.of(context).push(
                              ThemeSwitcher.buildPageRoute(
                                builder: (context) => ConversationView(
                                  isCreator: true,
                                  customHeading: "Select a chat",
                                  type: ChatSelectorTypes.ONLY_EXISTING,
                                  onSelect: (List<UniqueContact> selection) {
                                    Navigator.of(context).pop();
                                    if (selection.length > 0 && selection[0].isChat && this.mounted) {
                                      setState(() {
                                        setChat(selection[0].chat);
                                        errors = [];
                                      });
                                    } else {
                                      Logger.error("Error");
                                    }
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                  SettingsTextField(title: "Enter a message", controller: this.messageController),
                  SettingsOptions<List<dynamic>>(
                    initial: timeOptions.first,
                    subtitle: getTimeText(context),
                    onChanged: (val) async {
                      if (val == null) return;
                      scheduleSeconds = val[0];

                      if (val[0] == -1) {
                        messageDate = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(Duration(days: 365)));
                        messageTime = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                      }

                      if (this.mounted)
                        setState(() {
                          errors = [];
                        });
                    },
                    options: timeOptions,
                    textProcessing: (val) => val[1],
                    title: "When should we send it?",
                  ),
                  Center(
                      child: Text(
                    isNullOrEmpty(errors)! ? "" : errors.join("\n"),
                    style: Theme.of(context).textTheme.bodyText1!.apply(color: Colors.red[300]),
                    textAlign: TextAlign.center,
                  ))
                ],
              ),
            ),
            SliverList(
              delegate: SliverChildListDelegate(
                <Widget>[],
              ),
            )
          ],
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: Theme.of(context).primaryColor,
          child: Icon(Icons.done, color: Colors.white, size: 25),
          onPressed: () async {
            errors = [];
            if (_chat == null) errors.add("Please select a chat!");
            if (scheduleSeconds == -1 && (messageDate == null || messageTime == null))
              errors.add("Please set a date and time!");
            if (messageController.text.length == 0) errors.add("Please enter a message!");

            if (errors.length > 0 && this.mounted) {
              setState(() {});
            } else {
              DateTime occurs;
              if (scheduleSeconds == -1) {
                occurs = new DateTime(
                    messageDate!.year, messageDate!.month, messageDate!.day, messageTime!.hour, messageTime!.minute);
              } else {
                occurs = DateTime.now().add(Duration(seconds: scheduleSeconds!));
              }

              ScheduledMessage scheduled = new ScheduledMessage(
                  chatGuid: _chat!.guid, message: messageController.text, epochTime: occurs.millisecondsSinceEpoch);

              await scheduled.save();
              Navigator.of(context).pop();
            }
          },
        ),
      ),
    );
  }
}
