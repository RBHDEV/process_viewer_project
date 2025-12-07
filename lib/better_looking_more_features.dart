import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const ProcessViewerHome(),
    );
  }
}

class ProcessViewerHome extends StatefulWidget {
  const ProcessViewerHome({super.key});

  @override
  State<ProcessViewerHome> createState() => _ProcessViewerHomeState();
}

class _ProcessViewerHomeState extends State<ProcessViewerHome> with SingleTickerProviderStateMixin {
  List<ProcessInfo> processes = [];
  bool isLoading = false;
  String searchQuery = '';
  String sortColumn = 'memory';
  bool sortAscending = false;
  Timer? autoRefreshTimer;
  bool autoRefresh = false;
  int refreshInterval = 5;
  ProcessInfo? selectedProcess;
  late TabController _tabController;
  String filterState = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    loadProcesses();
  }

  @override
  void dispose() {
    autoRefreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void toggleAutoRefresh() {
    setState(() {
      autoRefresh = !autoRefresh;
      if (autoRefresh) {
        autoRefreshTimer = Timer.periodic(
          Duration(seconds: refreshInterval),
          (timer) => loadProcesses(),
        );
      } else {
        autoRefreshTimer?.cancel();
      }
    });
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
          SnackBar(
            content: Text('Error loading processes: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
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
        double memKB = double.tryParse(parts[4].replaceAll('"', '').replaceAll(' K', '').replaceAll(',', '')) ?? 0;
        procs.add(ProcessInfo(
          name: parts[0].replaceAll('"', ''),
          pid: parts[1].replaceAll('"', ''),
          sessionName: parts[2].replaceAll('"', ''),
          memory: memKB.toString(),
          state: parts[3].replaceAll('"', ''),
          cpuUsage: 0.0,
        ));
      }
    }
    return procs;
  }

  Future<List<ProcessInfo>> _getLinuxProcesses() async {
    final result = await Process.run('ps', ['aux', '--no-headers']);
    
    if (result.exitCode != 0) return [];

    List<ProcessInfo> procs = [];
    final lines = result.stdout.toString().split('\n');

    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 11) {
        double memKB = double.tryParse(parts[5]) ?? 0;
        double cpu = double.tryParse(parts[2]) ?? 0.0;
        
        procs.add(ProcessInfo(
          name: parts[10],
          pid: parts[1],
          sessionName: parts[0],
          memory: memKB.toString(),
          state: _getLinuxState(parts[7]),
          cpuUsage: cpu,
        ));
      }
    }
    return procs;
  }

  Future<List<ProcessInfo>> _getMacOSProcesses() async {
    final result = await Process.run('ps', ['aux']);
    
    if (result.exitCode != 0) return [];

    List<ProcessInfo> procs = [];
    final lines = result.stdout.toString().split('\n');

    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      
      final parts = lines[i].trim().split(RegExp(r'\s+'));
      if (parts.length >= 11) {
        double memKB = double.tryParse(parts[5]) ?? 0;
        double cpu = double.tryParse(parts[2]) ?? 0.0;
        
        procs.add(ProcessInfo(
          name: parts[10],
          pid: parts[1],
          sessionName: parts[0],
          memory: memKB.toString(),
          state: _getMacOSState(parts[7]),
          cpuUsage: cpu,
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
      bool matchesSearch = p.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
          p.pid.contains(searchQuery);
      
      bool matchesState = filterState == 'All' || p.state == filterState;
      
      return matchesSearch && matchesState;
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
        case 'cpu':
          comparison = a.cpuUsage.compareTo(b.cpuUsage);
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
        sortAscending = column == 'name' || column == 'state';
      }
    });
  }

  Future<void> _killProcess(ProcessInfo process) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kill Process'),
        content: Text('Are you sure you want to kill "${process.name}" (PID: ${process.pid})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Kill'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (Platform.isWindows) {
          await Process.run('taskkill', ['/PID', process.pid, '/F']);
        } else {
          await Process.run('kill', ['-9', process.pid]);
        }
        loadProcesses();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Process ${process.pid} killed successfully'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to kill process: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  void _showProcessDetails(ProcessInfo process) {
    setState(() {
      selectedProcess = process;
    });
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => _buildProcessDetails(process, scrollController),
      ),
    );
  }

  Widget _buildProcessDetails(ProcessInfo process, ScrollController scrollController) {
    double memMB = double.parse(process.memory) / 1024;
    
    return Container(
      padding: const EdgeInsets.all(24),
      child: ListView(
        controller: scrollController,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _getStateColor(process.state).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.memory,
                  color: _getStateColor(process.state),
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      process.name,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStateColor(process.state),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        process.state,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildDetailCard('Process ID', process.pid, Icons.tag),
          _buildDetailCard('Session', process.sessionName, Icons.person),
          _buildDetailCard('Memory Usage', '${memMB.toStringAsFixed(2)} MB', Icons.storage),
          _buildDetailCard('CPU Usage', '${process.cpuUsage.toStringAsFixed(1)}%', Icons.speed),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: process.pid));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('PID copied to clipboard'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy PID'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _killProcess(process);
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('Kill Process'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailCard(String label, String value, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
        subtitle: Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withOpacity(0.3)),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    final displayProcesses = filteredAndSortedProcesses;
    final totalMemory = processes.fold<double>(0, (sum, p) => sum + double.parse(p.memory)) / 1024 / 1024;
    final runningCount = processes.where((p) => p.state.toLowerCase().contains('running')).length;
    final avgCpu = processes.isNotEmpty 
        ? processes.fold<double>(0, (sum, p) => sum + p.cpuUsage) / processes.length 
        : 0.0;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Total Processes',
                      '${processes.length}',
                      Icons.apps,
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'Running',
                      '$runningCount',
                      Icons.play_circle,
                      Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Total Memory',
                      '${totalMemory.toStringAsFixed(1)} GB',
                      Icons.storage,
                      Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'Avg CPU',
                      '${avgCpu.toStringAsFixed(1)}%',
                      Icons.speed,
                      Colors.purple,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search processes...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      searchQuery = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              PopupMenuButton<String>(
                tooltip: 'Filter by state',
                onSelected: (value) {
                  setState(() {
                    filterState = value;
                  });
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'All', child: Text('All States')),
                  const PopupMenuItem(value: 'Running', child: Text('Running')),
                  const PopupMenuItem(value: 'Sleeping', child: Text('Sleeping')),
                  const PopupMenuItem(value: 'Zombie', child: Text('Zombie')),
                ],
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.filter_list),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: displayProcesses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 64,
                        color: Theme.of(context).disabledColor,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No processes found',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: displayProcesses.length,
                  itemBuilder: (context, index) {
                    final process = displayProcesses[index];
                    double memMB = double.parse(process.memory) / 1024;
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _getStateColor(process.state).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.memory,
                            color: _getStateColor(process.state),
                          ),
                        ),
                        title: Text(
                          process.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text('PID: ${process.pid}'),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.storage, size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text('${memMB.toStringAsFixed(1)} MB'),
                                const SizedBox(width: 16),
                                Icon(Icons.speed, size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text('${process.cpuUsage.toStringAsFixed(1)}%'),
                              ],
                            ),
                          ],
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getStateColor(process.state),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            process.state,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        onTap: () => _showProcessDetails(process),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTableTab() {
    final displayProcesses = filteredAndSortedProcesses;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search processes...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) {
              setState(() {
                searchQuery = value;
              });
            },
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
              child: DataTable(
                columnSpacing: 36,
                headingRowColor: MaterialStateProperty.all(
                  Theme.of(context).colorScheme.surfaceVariant,
                ),
                columns: [
                  DataColumn(
                    label: const Text('Name', style: TextStyle(fontWeight: FontWeight.bold)),
                    onSort: (_, _) => _sortBy('name'),
                  ),
                  DataColumn(
                    numeric: true,
                    label: const Text('PID', style: TextStyle(fontWeight: FontWeight.bold)),
                    onSort: (_, _) => _sortBy('pid'),
                  ),
                  DataColumn(
                    label: const Text('User', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  DataColumn(
                    numeric: true,
                    label: const Text('Memory (MB)', style: TextStyle(fontWeight: FontWeight.bold)),
                    onSort: (_, _) => _sortBy('memory'),
                  ),
                  DataColumn(
                    numeric: true,
                    label: const Text('CPU %', style: TextStyle(fontWeight: FontWeight.bold)),
                    onSort: (_, _) => _sortBy('cpu'),
                  ),
                  DataColumn(
                    label: const Text('State', style: TextStyle(fontWeight: FontWeight.bold)),
                    onSort: (_, _) => _sortBy('state'),
                  ),
                  const DataColumn(
                    label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
                rows: displayProcesses.map((process) {
                  double memMB = double.parse(process.memory) / 1024;
                  
                  return DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 360,
                          child: Text(
                            process.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                      ),
                      DataCell(Text(process.pid)),
                      DataCell(Text(process.sessionName)),
                      DataCell(Text(memMB.toStringAsFixed(1))),
                      DataCell(Text('${process.cpuUsage.toStringAsFixed(1)}%')),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: _getStateColor(process.state),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            process.state,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.info_outline, size: 20),
                              onPressed: () {
                                setState(() => selectedProcess = process);
                              },
                              tooltip: 'Details',
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              color: Colors.red,
                              onPressed: () => _killProcess(process),
                              tooltip: 'Kill',
                            ),
                          ],
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    Widget mainContent = TabBarView(
      controller: _tabController,
      children: [
        _buildOverviewTab(),
        _buildTableTab(),
      ],
    );

    if (isWide) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Process Monitor', style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: false,
          elevation: 0,
          actions: [
            IconButton(
              icon: Icon(autoRefresh ? Icons.pause_circle : Icons.play_circle),
              onPressed: toggleAutoRefresh,
              tooltip: autoRefresh ? 'Pause Auto-refresh' : 'Enable Auto-refresh',
            ),
            IconButton(
              icon: isLoading 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              onPressed: isLoading ? null : loadProcesses,
              tooltip: 'Refresh',
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _tabController.index,
              onDestinationSelected: (idx) => setState(() => _tabController.animateTo(idx)),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.dashboard), label: Text('Overview')),
                NavigationRailDestination(icon: Icon(Icons.table_chart), label: Text('Table')),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: mainContent,
              ),
            ),
            
            if (selectedProcess != null)
              Container(
                width: 360,
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
                  color: Theme.of(context).colorScheme.surface,
                ),
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: _buildProcessDetails(selectedProcess!, ScrollController()),
                ),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Process Monitor', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(autoRefresh ? Icons.pause_circle : Icons.play_circle),
            onPressed: toggleAutoRefresh,
            tooltip: autoRefresh ? 'Pause Auto-refresh' : 'Enable Auto-refresh',
          ),
          IconButton(
            icon: isLoading 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: isLoading ? null : loadProcesses,
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.dashboard)),
            Tab(text: 'Table View', icon: Icon(Icons.table_chart)),
          ],
        ),
      ),
      body: mainContent,
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
  final double cpuUsage;

  ProcessInfo({
    required this.name,
    required this.pid,
    required this.sessionName,
    required this.memory,
    required this.state,
    required this.cpuUsage,
  });
}