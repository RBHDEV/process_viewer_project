import 'dart:io';
import 'package:flutter/material.dart';

void main() {
  runApp(const ProcessViewerApp());
}

class ProcessViewerApp extends StatelessWidget {
  const ProcessViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'System Process Viewer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const ProcessViewerHome(),
    );
  }
}

class ProcessViewerHome extends StatefulWidget {
  const ProcessViewerHome({super.key});

  @override
  State<ProcessViewerHome> createState() => _ProcessViewerHomeState();
}

class _ProcessViewerHomeState extends State<ProcessViewerHome> {
  List<ProcessInfo> processes = [];
  bool isLoading = false;
  String searchQuery = '';
  String sortColumn = 'name';
  bool sortAscending = true;

  @override
  void initState() {
    super.initState();
    loadProcesses();
  }

  Future<void> loadProcesses() async {
    setState(() {
      isLoading = true;
    });

    try {
      List<ProcessInfo> loadedProcesses = [];

      if (Platform.isWindows) {
        loadedProcesses = await _getWindowsProcesses();
      } else if (Platform.isLinux) {
        loadedProcesses = await _getLinuxProcesses();
      } else if (Platform.isMacOS) {
        loadedProcesses = await _getMacOSProcesses();
      }

      setState(() {
        processes = loadedProcesses;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading processes: $e')),
        );
      }
    }
  }

  Future<List<ProcessInfo>> _getWindowsProcesses() async {
    final result = await Process.run('tasklist', ['/FO', 'CSV', '/NH']);
    if (result.exitCode != 0) return [];

    List<ProcessInfo> procs = [];
    final lines = result.stdout.toString().split('\n');

    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      
      final parts = _parseCSVLine(line);
      if (parts.length >= 5) {
        procs.add(ProcessInfo(
          name: parts[0].replaceAll('"', ''),
          pid: parts[1].replaceAll('"', ''),
          sessionName: parts[2].replaceAll('"', ''),
          memory: parts[4].replaceAll('"', '').replaceAll(' K', ''),
          state: parts[3].replaceAll('"', ''),
        ));
      }
    }
    return procs;
  }

  Future<List<ProcessInfo>> _getLinuxProcesses() async {
    final result = await Process.run('ps', [
      'aux',
      '--sort=-pmem',
    ]);
    
    if (result.exitCode != 0) return [];

    List<ProcessInfo> procs = [];
    final lines = result.stdout.toString().split('\n');

    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      
      final parts = lines[i].trim().split(RegExp(r'\s+'));
      if (parts.length >= 11) {
        // Convert memory from KB to MB
        double memKB = double.tryParse(parts[5]) ?? 0;
        double memMB = memKB / 1024;
        
        procs.add(ProcessInfo(
          name: parts[10],
          pid: parts[1],
          sessionName: parts[0],
          memory: memMB.toStringAsFixed(2),
          state: _getLinuxState(parts[7]),
        ));
      }
    }
    return procs;
  }

  Future<List<ProcessInfo>> _getMacOSProcesses() async {
    final result = await Process.run('ps', [
      'aux',
    ]);
    
    if (result.exitCode != 0) return [];

    List<ProcessInfo> procs = [];
    final lines = result.stdout.toString().split('\n');

    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      
      final parts = lines[i].trim().split(RegExp(r'\s+'));
      if (parts.length >= 11) {
        // Memory on macOS ps is in KB
        double memKB = double.tryParse(parts[5]) ?? 0;
        double memMB = memKB / 1024;
        
        procs.add(ProcessInfo(
          name: parts[10],
          pid: parts[1],
          sessionName: parts[0],
          memory: memMB.toStringAsFixed(2),
          state: _getMacOSState(parts[7]),
        ));
      }
    }
    return procs;
  }

  String _getLinuxState(String stateCode) {
    if (stateCode.contains('R')) return 'Running';
    if (stateCode.contains('S')) return 'Sleeping';
    if (stateCode.contains('D')) return 'Disk Sleep';
    if (stateCode.contains('Z')) return 'Zombie';
    if (stateCode.contains('T')) return 'Stopped';
    return stateCode;
  }

  String _getMacOSState(String stateCode) {
    if (stateCode.contains('R')) return 'Running';
    if (stateCode.contains('S')) return 'Sleeping';
    if (stateCode.contains('U')) return 'Uninterruptible';
    if (stateCode.contains('Z')) return 'Zombie';
    if (stateCode.contains('T')) return 'Stopped';
    return stateCode;
  }

  List<String> _parseCSVLine(String line) {
    List<String> result = [];
    bool inQuotes = false;
    StringBuffer current = StringBuffer();

    for (int i = 0; i < line.length; i++) {
      if (line[i] == '"') {
        inQuotes = !inQuotes;
        current.write(line[i]);
      } else if (line[i] == ',' && !inQuotes) {
        result.add(current.toString());
        current.clear();
      } else {
        current.write(line[i]);
      }
    }
    result.add(current.toString());
    return result;
  }

  List<ProcessInfo> get filteredAndSortedProcesses {
    var filtered = processes.where((p) {
      return p.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
          p.pid.contains(searchQuery);
    }).toList();

    filtered.sort((a, b) {
      int comparison = 0;
      switch (sortColumn) {
        case 'name':
          comparison = a.name.compareTo(b.name);
          break;
        case 'pid':
          comparison = int.parse(a.pid).compareTo(int.parse(b.pid));
          break;
        case 'memory':
          comparison = double.parse(a.memory.replaceAll(RegExp(r'[^0-9.]'), ''))
              .compareTo(double.parse(b.memory.replaceAll(RegExp(r'[^0-9.]'), '')));
          break;
        case 'state':
          comparison = a.state.compareTo(b.state);
          break;
      }
      return sortAscending ? comparison : -comparison;
    });

    return filtered;
  }

  void _sortBy(String column) {
    setState(() {
      if (sortColumn == column) {
        sortAscending = !sortAscending;
      } else {
        sortColumn = column;
        sortAscending = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayProcesses = filteredAndSortedProcesses;

    return Scaffold(
      appBar: AppBar(
        title: const Text('System Process Viewer'),
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: isLoading ? null : loadProcesses,
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search by process name or PID...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onChanged: (value) {
                      setState(() {
                        searchQuery = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '${displayProcesses.length} processes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : displayProcesses.isEmpty
                    ? const Center(child: Text('No processes found'))
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            columnSpacing: 40,
                            headingRowColor: MaterialStateProperty.all(
                              Colors.blue.shade50,
                            ),
                            columns: [
                              DataColumn(
                                label: const Text('Process Name',
                                    style: TextStyle(fontWeight: FontWeight.bold)),
                                onSort: (_, _) => _sortBy('name'),
                              ),
                              DataColumn(
                                label: const Text('PID',
                                    style: TextStyle(fontWeight: FontWeight.bold)),
                                onSort: (_, _) => _sortBy('pid'),
                              ),
                              DataColumn(
                                label: const Text('Session Name',
                                    style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              DataColumn(
                                label: const Text('Memory Usage',
                                    style: TextStyle(fontWeight: FontWeight.bold)),
                                onSort: (_, _) => _sortBy('memory'),
                              ),
                              DataColumn(
                                label: const Text('State',
                                    style: TextStyle(fontWeight: FontWeight.bold)),
                                onSort: (_, _) => _sortBy('state'),
                              ),
                            ],
                            rows: displayProcesses.map((process) {
                              return DataRow(
                                cells: [
                                  DataCell(Text(process.name)),
                                  DataCell(Text(process.pid)),
                                  DataCell(Text(process.sessionName)),
                                  DataCell(Text(
                                      Platform.isWindows
                                          ? '${process.memory} KB'
                                          : '${process.memory} MB')),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _getStateColor(process.state),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        process.state,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Color _getStateColor(String state) {
    if (state.toLowerCase().contains('running')) return Colors.green;
    if (state.toLowerCase().contains('sleeping')) return Colors.blue;
    if (state.toLowerCase().contains('zombie')) return Colors.red;
    if (state.toLowerCase().contains('stopped')) return Colors.orange;
    return Colors.grey;
  }
}

class ProcessInfo {
  final String name;
  final String pid;
  final String sessionName;
  final String memory;
  final String state;

  ProcessInfo({
    required this.name,
    required this.pid,
    required this.sessionName,
    required this.memory,
    required this.state,
  });
}