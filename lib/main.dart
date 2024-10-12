import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(TaskAdapter());
  await Hive.openBox<Task>('tasks');
  tz.initializeTimeZones();
  await NotificationService().initNotifications();
  runApp(TaskManagerApp());
}

class TaskManagerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Task Manager',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        hintColor: Colors.amberAccent,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'Roboto',
        textTheme: TextTheme(
          titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          bodyMedium: TextStyle(fontSize: 14),
        ),
      ),
      home: TaskListScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

@HiveType(typeId: 0)
class Task extends HiveObject {
  @HiveField(0)
  String title;
  @HiveField(1)
  String description;
  @HiveField(2)
  int priority;
  @HiveField(3)
  DateTime dueDateTime;
  @HiveField(4)
  bool isCompleted;

  Task({
    required this.title,
    required this.description,
    required this.priority,
    required this.dueDateTime,
    this.isCompleted = false,
  });
}

class TaskAdapter extends TypeAdapter<Task> {
  @override
  final int typeId = 0;

  @override
  Task read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Task(
      title: fields[0] as String,
      description: fields[1] as String,
      priority: fields[2] as int,
      dueDateTime: fields[3] as DateTime,
      isCompleted: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Task obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.title)
      ..writeByte(1)
      ..write(obj.description)
      ..writeByte(2)
      ..write(obj.priority)
      ..writeByte(3)
      ..write(obj.dueDateTime)
      ..writeByte(4)
      ..write(obj.isCompleted);
  }
}



class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
    await _requestNotificationPermissions();
  }

  Future<void> _requestNotificationPermissions() async {
    final status = await Permission.notification.status;
    if (status.isDenied) {
      final result = await Permission.notification.request();
      if (result.isGranted) {
        print('Notification permission granted');
      } else if (result.isPermanentlyDenied) {
        print('Notification permission permanently denied');
        await openAppSettings();
      } else {
        print('Notification permission denied');
      }
    } else if (status.isPermanentlyDenied) {
      print('Notification permission permanently denied');
      await openAppSettings();
    } else {
      print('Notification permission already granted');
    }
  }

  Future<void> scheduleTaskNotification(Task task) async {
    final androidDetails = AndroidNotificationDetails(
      'task_reminders',
      'Task Reminders',
      channelDescription: 'Notifications for task reminders',
      importance: Importance.max,
      priority: Priority.high,
    );
    final platformChannelSpecifics = NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.zonedSchedule(
      task.key,
      'Time Running Out: ${task.title}',
      'Your task "${task.title}" is due in 1 hour!',
      tz.TZDateTime.from(task.dueDateTime.subtract(Duration(hours: 1)), tz.local),
      platformChannelSpecifics,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      task.key + 1,
      'Task Incomplete: ${task.title}',
      'Your task "${task.title}" is now overdue!',
      tz.TZDateTime.from(task.dueDateTime, tz.local),
      platformChannelSpecifics,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelTaskNotifications(int taskKey) async {
    await flutterLocalNotificationsPlugin.cancel(taskKey);
    await flutterLocalNotificationsPlugin.cancel(taskKey + 1);
  }

  Future<void> scheduleDailySummary(List<Task> tasks) async {
    final androidDetails = AndroidNotificationDetails(
      'daily_summary',
      'Daily Task Summary',
      channelDescription: 'Daily summary of upcoming and overdue tasks',
      importance: Importance.high,
      priority: Priority.high,
    );
    final platformChannelSpecifics = NotificationDetails(android: androidDetails);

    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 9, 0);

    final upcomingTasks = tasks.where((task) => 
      !task.isCompleted && task.dueDateTime.isAfter(now) && task.dueDateTime.isBefore(now.add(Duration(days: 3)))).toList();
    final overdueTasks = tasks.where((task) => 
      !task.isCompleted && task.dueDateTime.isBefore(now)).toList();

    String summaryText = 'Daily Task Summary:\n';
    if (upcomingTasks.isNotEmpty) {
      summaryText += '${upcomingTasks.length} upcoming tasks in the next 3 days.\n';
    }
    if (overdueTasks.isNotEmpty) {
      summaryText += '${overdueTasks.length} overdue tasks.';
    }

    await flutterLocalNotificationsPlugin.zonedSchedule(
      0,
      'Daily Task Summary',
      summaryText,
      tz.TZDateTime.from(tomorrow, tz.local),
      platformChannelSpecifics,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}
class TaskListScreen extends StatefulWidget {
  @override
  _TaskListScreenState createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  late Box<Task> taskBox;
  List<Task> tasks = [];
  String sortBy = 'priority';
  String filterBy = 'all';

  @override
  void initState() {
    super.initState();
    taskBox = Hive.box<Task>('tasks');
    _loadTasks();
    _scheduleDailySummary();
  }

  void _loadTasks() {
    setState(() {
      tasks = taskBox.values.toList();
      _filterTasks();
      _sortTasks();
    });
  }

  void _filterTasks() {
    switch (filterBy) {
      case 'all':
        break;
      case 'completed':
        tasks = tasks.where((task) => task.isCompleted).toList();
        break;
      case 'uncompleted':
        tasks = tasks.where((task) => !task.isCompleted).toList();
        break;
    }
  }

  void _sortTasks() {
    switch (sortBy) {
      case 'priority':
        tasks.sort((a, b) => b.priority.compareTo(a.priority));
        break;
      case 'dueDate':
        tasks.sort((a, b) => a.dueDateTime.compareTo(b.dueDateTime));
        break;
      case 'creationDate':
        tasks.sort((a, b) => a.key.compareTo(b.key));
        break;
    }
  }

  void _addTask() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => TaskDetailScreen()),
    );
    if (result != null && result is Task) {
      final task = await taskBox.add(result);
      NotificationService().scheduleTaskNotification(result);
      _loadTasks();
      _scheduleDailySummary();
    }
  }

  void _editTask(Task task) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => TaskDetailScreen(task: task)),
    );
    if (result != null && result is Task) {
      await NotificationService().cancelTaskNotifications(task.key);
      task.title = result.title;
      task.description = result.description;
      task.priority = result.priority;
      task.dueDateTime = result.dueDateTime;
      await task.save();
      NotificationService().scheduleTaskNotification(task);
      _loadTasks();
      _scheduleDailySummary();
    }
  }

  void _deleteTask(Task task) async {
    await NotificationService().cancelTaskNotifications(task.key);
    await task.delete();
    _loadTasks();
    _scheduleDailySummary();
  }

  void _toggleTaskCompletion(Task task) async {
    task.isCompleted = !task.isCompleted;
    if (task.isCompleted) {
      await NotificationService().cancelTaskNotifications(task.key);
    } else {
      NotificationService().scheduleTaskNotification(task);
    }
    await task.save();
    _loadTasks();
    _scheduleDailySummary();
  }

  void _scheduleDailySummary() {
    NotificationService().scheduleDailySummary(tasks);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Task Manager', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.sort),
            onPressed: () {
              _showSortDialog();
            },
          ),
          IconButton(
            icon: Icon(Icons.filter_list),
            onPressed: () {
              _showFilterDialog();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search tasks...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                filled: true,
                fillColor: Colors.grey[200],
              ),
              onChanged: (value) {
                setState(() {
                  tasks = taskBox.values
                      .where((task) =>
                          task.title.toLowerCase().contains(value.toLowerCase()) ||
                          task.description.toLowerCase().contains(value.toLowerCase()))
                      .toList();
                  _filterTasks();
                  _sortTasks();
                });
              },
            ),
          ),
          Expanded(
            child: tasks.isEmpty
                ? Center(child: Text('No tasks found'))
                : ListView.builder(
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return Card(
                        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        elevation: 2,
                        child: ExpansionTile(
                          title: Text(
                            task.title,
                            style: TextStyle(
                              decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Due: ${_formatDateTime(task.dueDateTime)}',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              SizedBox(height: 4),
                              _buildPriorityChip(task.priority),
                            ],
                          ),
                          leading: Checkbox(
                            value: task.isCompleted,
                            onChanged: (bool? value) {
                              _toggleTaskCompletion(task);
                            },
                            activeColor: Theme.of(context).colorScheme.secondary,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _editTask(task),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _showDeleteConfirmationDialog(task),
                              ),
                            ],
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(task.description),
                            ),
                          ],
                        ),
                      );
                    },
                    ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTask,
        icon: Icon(Icons.add),
        label: Text('Add Task'),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildPriorityChip(int priority) {
    Color chipColor;
    String label;
    switch (priority) {
      case 1:
        chipColor = Colors.green;
        label = 'Low';
        break;
      case 2:
        chipColor = Colors.orange;
        label = 'Medium';
        break;
      case 3:
        chipColor = Colors.red;
        label = 'High';
        break;
      default:
        chipColor = Colors.grey;
        label = 'Unknown';
    }
    return Chip(
      label: Text(label, style: TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: chipColor,
    );
  }

  void _showSortDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Sort Tasks'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('Sort by Priority'),
                onTap: () {
                  setState(() {
                    sortBy = 'priority';
                    _sortTasks();
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('Sort by Due Date'),
                onTap: () {
                  setState(() {
                    sortBy = 'dueDate';
                    _sortTasks();
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('Sort by Creation Date'),
                onTap: () {
                  setState(() {
                    sortBy = 'creationDate';
                    _sortTasks();
                  });
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Filter Tasks'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('All Tasks'),
                onTap: () {
                  setState(() {
                    filterBy = 'all';
                    _loadTasks();
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('Completed Tasks'),
                onTap: () {
                  setState(() {
                    filterBy = 'completed';
                    _loadTasks();
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('Uncompleted Tasks'),
                onTap: () {
                  setState(() {
                    filterBy = 'uncompleted';
                    _loadTasks();
                  });
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteConfirmationDialog(Task task) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Delete Task'),
          content: Text('Are you sure you want to delete this task?'),
          actions: [
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Delete'),
              onPressed: () {
                _deleteTask(task);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}

class TaskDetailScreen extends StatefulWidget {
  final Task? task;

  TaskDetailScreen({this.task});

  @override
  _TaskDetailScreenState createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late int _priority;
  late DateTime _dueDateTime;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task?.title ?? '');
    _descriptionController = TextEditingController(text: widget.task?.description ?? '');
    _priority = widget.task?.priority ?? 1;
    _dueDateTime = widget.task?.dueDateTime ?? DateTime.now().add(Duration(days: 1));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task == null ? 'Add Task' : 'Edit Task'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: _priority,
              decoration: InputDecoration(
                labelText: 'Priority',
                border: OutlineInputBorder(),
              ),
              items: [1, 2, 3].map((int value) {
                return DropdownMenuItem<int>(
                  value: value,
                  child: Text(['Low', 'Medium', 'High'][value - 1]),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  _priority = newValue!;
                });
              },
            ),
            SizedBox(height: 16),
            ListTile(
              title: Text('Due Date and Time'),
              subtitle: Text(_formatDateTime(_dueDateTime)),
              trailing: Icon(Icons.calendar_today),
              onTap: () async {
                final pickedDate = await showDatePicker(
                  context: context,
                  initialDate: _dueDateTime,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(Duration(days: 365)),
                );
                if (pickedDate != null) {
                  final pickedTime = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(_dueDateTime),
                  );
                  if (pickedTime != null) {
                    setState(() {
                      _dueDateTime = DateTime(
                        pickedDate.year,
                        pickedDate.month,
                        pickedDate.day,
                        pickedTime.hour,
                        pickedTime.minute,
                      );
                    });
                  }
                }
              },
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                final task = Task(
                  title: _titleController.text,
                  description: _descriptionController.text,
                  priority: _priority,
                  dueDateTime: _dueDateTime,
                );
                Navigator.pop(context, task);
              },
              child: Text('Save Task'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}





































