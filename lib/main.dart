import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:getwidget/getwidget.dart';
import 'dart:io';



void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        title: 'Priority Pick',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        ),
        home: MyHomePage(),
      ),
    );
  }
}

class MyAppState extends ChangeNotifier {
  bool isToggled = false;
  String searchText = "";
  List<String> items = List.generate(10, (index) => "Item ${index + 1}");

  List<Map<String, dynamic>> teamData = [];

  Map<String, dynamic> filterOptions = {}; // Stores the fetched JSON
  Map<String, String> selectedFilters = {
    "Country": "All",
    "Province/State": "All",
    "Event": "All",
  };
  Map<String, dynamic> myBotData = {
    "teamNumber": 0,
    "sampleAuton": 0,
    "specimenAuton": 0,
    "sampleTeleop": 0,
    "specimenTeleop": 0,
    "ascent": 0
  };

  // TEAMS DATA ----------------------------------------------------
  Future<void> loadTeamData() async {
    try {
      String jsonString = await rootBundle.loadString('assets/team_data.json');
      List<dynamic> jsonData = jsonDecode(jsonString);
      teamData = jsonData.map((e) => Map<String, dynamic>.from(e)).toList();
      notifyListeners();
    } catch (e) {
      print("❌ Error loading team_data.json: $e");
    }
  }

  // MY BOT --------------------------------------------------------------------------
  Future<void> loadMyBotData() async {
    try {
      final file = await _getLocalFile();
      if (await file.exists()) {
        print("Loading my_bot.json from: ${file.path}");
        String jsonString = await file.readAsString();
        myBotData = jsonDecode(jsonString);
      } else {
        print("No existing my_bot.json, copying default from assets...");
        String defaultJson = await rootBundle.loadString('assets/my_bot.json');
        await file.writeAsString(defaultJson);
        myBotData = jsonDecode(defaultJson);
      }
      notifyListeners();
    } catch (e) {
      print("Error loading my_bot.json: $e");
    }
  }
  // Save updated bot data to my_bot.json
  Future<void> saveMyBot() async {
    try {
      final file = await _getLocalFile();
      String jsonString = jsonEncode(myBotData);
      await file.writeAsString(jsonString);
      print("Bot data saved successfully to ${file.path}");
    } catch (e) {
      print("Error saving my_bot.json: $e");
    }
  }

  // Update specific field in myBotData
  void updateMyBotField(String key, dynamic value) {
    myBotData[key] = value;
    print("Updated $key: $value"); // Debugging
    notifyListeners();
  }

  // Get writable file location
  Future<File> _getLocalFile() async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/my_bot.json';
    print("Saving to: $filePath"); // Debugging: Ensure correct path
    return File(filePath);
  }
  // FILTER --------------------------------------------------------------------------
  void saveFilterSelections() {
    print("Saved Filters: $selectedFilters"); // Debugging
    notifyListeners();
  }

  void setFilter(String category, String value) {
    selectedFilters[category] = value;

    if (category == "Country") {
      selectedFilters["Province/State"] = "All";
      selectedFilters["Event"] = "All";
    } else if (category == "Province/State") {
      selectedFilters["Event"] = "All";
    }
    notifyListeners();
  }

  List<String> getOptions(String category) {
    if (category == "Country") {
      return filterOptions["Country"]?.cast<String>() ?? ["All"];
    } else if (category == "Province/State") {
      String selectedCountry = selectedFilters["Country"] ?? "All";
      return filterOptions["Province/State"]?[selectedCountry]?.cast<String>() ?? ["All"];
    } else if (category == "Event") {
      String selectedState = selectedFilters["Province/State"] ?? "All";
      return filterOptions["Event"]?[selectedState]?.cast<String>() ?? ["All"];
    }
    return ["All"];
  }

  // Fetch filter.json from the backend
  Future<void> loadFilterOptions() async {
    final String eventsApiUrl = "http://10.0.2.2:8000/events"; // Android emulator
    final String filterJsonUrl = "http://10.0.2.2:8000/filter.json";

    try {
      print("Calling /events API to generate filter.json...");
      final eventsResponse = await http.get(Uri.parse(eventsApiUrl));

      if (eventsResponse.statusCode == 200) {
        print("Successfully triggered /events API.");
      } else {
        print("Warning: /events API failed with status ${eventsResponse.statusCode}. Proceeding with default filter.json...");
      }
    } catch (e) {
      print("Warning: Error calling /events API: $e. Proceeding with default filter.json...");
    }

    // Step 2: Immediately fetch filter.json regardless of /events result
    print("Fetching filter.json...");
    try {
      final response = await http.get(Uri.parse(filterJsonUrl));
      if (response.statusCode == 200) {
        Map<String, dynamic> jsonData = json.decode(response.body);
        print("Received JSON: $jsonData");

        if (jsonData.containsKey("Country") &&
            jsonData.containsKey("Province/State") &&
            jsonData.containsKey("Event")) {
          filterOptions = jsonData;
          notifyListeners();
        } else {
          print("Error: Received unexpected JSON format");
        }
      } else {
        print("Failed to load filter data: ${response.statusCode}");
      }
    } catch (e) {
      print("Error fetching filter data: $e");
    }
  }

  // TOGGLE ---------------------------------------------------------------------------
  void toggleSwitch(bool value) {
    isToggled = value;
    notifyListeners();
  }


}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      var appState = context.read<MyAppState>();
      appState.loadFilterOptions();
      appState.loadMyBotData();
      appState.loadTeamData();
    });
  }

  Widget _buildNumberField(BuildContext context, String label, String key) {
    var appState = context.watch<MyAppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        TextField(
          controller: TextEditingController(text: appState.myBotData[key].toString()),
          keyboardType: TextInputType.number,
          onChanged: (value) {
            int intValue = int.tryParse(value) ?? 0;
            appState.updateMyBotField(key, intValue);
          },
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          ),
        ),
        SizedBox(height: 10),
      ],
    );
  }
  // MY BOT ------------------------------------------------------------
  void _showMyBot(BuildContext context) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          var appState = context.watch<MyAppState>();

          return FractionallySizedBox(
            heightFactor: 0.8,
            child: Container(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Text(
                    "My Bot",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 10),

                  // Input Fields
                  _buildNumberField(context, "Team Number", "teamNumber"),
                  _buildNumberField(context, "Auton Sample", "sampleAuton"),
                  _buildNumberField(context, "Auton Specimen", "specimenAuton"),
                  _buildNumberField(context, "Teleop Sample", "sampleTeleop"),
                  _buildNumberField(context, "Teleop Specimen", "specimenTeleop"),
                  _buildNumberField(context, "Ascent", "ascent"),

                  SizedBox(height: 20),

                  // Save Button
                  Align(
                    alignment: Alignment.center,
                    child: GFButton(
                      onPressed: () async {
                        await appState.saveMyBot(); // Save data
                        Navigator.pop(context); // Close modal
                      },
                      text: "Save",
                      color: GFColors.PRIMARY,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
    );
  }

  // FILTER ------------------------------------------------------------------
  void _showFilterPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        var appState = context.watch<MyAppState>();


        return FractionallySizedBox(
          heightFactor: 0.6,
          child: Container(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Text(
                  "Filter Options",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 10),

                // Dynamic Dropdowns for Filters
                for (String category in ["Country", "Province/State", "Event"])
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(category, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      DropdownButton<String>(
                        value: appState.selectedFilters[category],
                        onChanged: (value) {
                          if (value != null) {
                            appState.setFilter(category, value);
                          }
                        },
                        items: appState.getOptions(category)
                            .map<DropdownMenuItem<String>>((item) {
                          return DropdownMenuItem<String>(
                            value: item,
                            child: Text(item),
                          );
                        }).toList(),
                      ),
                      SizedBox(height: 10),
                    ],
                  ),

                SizedBox(height: 20),

                // Search Button
                Align(
                  alignment: Alignment.center,
                  child: GFButton(
                    onPressed: () {
                      appState.saveFilterSelections(); // Save the selected filters
                      Navigator.pop(context); // Close the filter panel
                    },
                    text: "Search",
                    icon: Icon(Icons.search, color: Colors.white),
                    color: GFColors.PRIMARY,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    return Scaffold(
      appBar: AppBar(
          title: Text("Leaderboard"),
          actions: [
            GFButton(
              onPressed: () => _showMyBot(context),
              text: "My Bot",
              color: GFColors.PRIMARY,
            ),
          ],
      ),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            color: Colors.white,
            child: Column(
              children: [
                SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text("Toggle: "),
                        GFToggle(
                          onChanged: (val) => appState.toggleSwitch(val ?? false),
                          value: appState.isToggled,
                          enabledTrackColor: Colors.green,
                          disabledTrackColor: Colors.red,
                        ),
                      ],
                    ),
                    GFButton(
                      onPressed: () {}, // Function to show filter panel
                      text: "Filter",
                      icon: Icon(Icons.filter_list, color: Colors.white),
                      color: GFColors.PRIMARY,
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 10),

          // Table with Team Data
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal, // Enable horizontal scrolling
              child: DataTable(
                headingRowColor: MaterialStateProperty.all(Colors.grey[300]),
                columns: [
                  DataColumn(label: Text("Team #", style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("Name", style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("Type", style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("OPR", style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("Auton", style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("Teleop", style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("Ascent", style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: appState.teamData.map((team) {
                  return DataRow(cells: [
                    DataCell(Text(team["number"].toString())),
                    DataCell(Text(team["name"])),
                    DataCell(Text(team["type"])),
                    DataCell(Text(team["opr"].toString())),
                    DataCell(Text(team["auton_opr"].toString())),
                    DataCell(Text(team["teleop_opr"].toString())),
                    DataCell(Text(team["end-ascent-score"].toString())),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}