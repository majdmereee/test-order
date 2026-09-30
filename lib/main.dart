import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

// رابط سيرفر الـ Socket.IO والغرفة الموحدة
const String serverUrl = 'https://render-kr1o.onrender.com/';
const String restaurantRoom = 'restaurant_orders';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RestaurantApp());
}

class RestaurantApp extends StatelessWidget {
  const RestaurantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'منيو المطعم المباشر',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'SY'),
      supportedLocales: const [Locale('ar', 'SY')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepOrange,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        fontFamily: 'Roboto',
      ),
      home: const MenuHomeScreen(),
    );
  }
}

// نموذج الصنف
class MenuItem {
  final int id;
  final String name;
  final String description;
  final int price;
  final String category;
  final IconData icon;

  MenuItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.category,
    required this.icon,
  });
}

// قائمة وجبات المنيو
final List<MenuItem> menuData = [
  MenuItem(
    id: 1,
    name: "وجبة كريسبي سوبريم",
    description: "4 قطع دجاج كريسبي مقرمش + بطاطا + صوص ثوم + كولسلو + خبز",
    price: 45000,
    category: "الوجبات السريعة",
    icon: Icons.fastfood,
  ),
  MenuItem(
    id: 2,
    name: "برغر لحم دبل تشيز",
    description: "شريحتين لحم مشوي طازج، جبنة شيدر وصوص خاص",
    price: 50000,
    category: "برغر",
    icon: Icons.lunch_dining,
  ),
  MenuItem(
    id: 3,
    name: "ساندويش زنجر حار",
    description: "صدر دجاج كريسبي حار مع الجبنة والخس وصوص المايونيز",
    price: 32000,
    category: "الوجبات السريعة",
    icon: Icons.dinner_dining,
  ),
  MenuItem(
    id: 4,
    name: "بطاطا مقلية عائلية",
    description: "بطاطا ذهبية مقرمشة بالبهارات الخاصة",
    price: 18000,
    category: "مقبلات",
    icon: Icons.breakfast_dining,
  ),
  MenuItem(
    id: 5,
    name: "مشروب غازي بارد",
    description: "علبة 330 مل باردة",
    price: 8000,
    category: "مشروبات",
    icon: Icons.local_drink,
  ),
];

class MenuHomeScreen extends StatefulWidget {
  const MenuHomeScreen({super.key});

  @override
  State<MenuHomeScreen> createState() => _MenuHomeScreenState();
}

class _MenuHomeScreenState extends State<MenuHomeScreen> {
  late io.Socket socket;
  bool isConnected = false;

  String selectedCategory = "الكل";
  final Map<int, int> cart = {};

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  String orderType = "سفري";
  bool isSending = false;
  String currentOrderStatus = "";

  @override
  void initState() {
    super.initState();
    _loadCustomerData();
    _initSocket();
  }

  // تهيئة اتصال الـ Socket.IO
  void _initSocket() {
    socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket']) // إجبار اتصال WebSocket لسرعة الاستجابة
          .enableAutoConnect()
          .build(),
    );

    socket.onConnect((_) {
      if (mounted) setState(() => isConnected = true);
    });

    socket.onDisconnect((_) {
      if (mounted) setState(() => isConnected = false);
    });

    // الاستماع لردود السيرفر (مثل تحديث حالة الطلب من شاشة الكاشير)
    socket.on('otherPlayerMoved', (data) {
      if (data != null && data['room'] == restaurantRoom) {
        if (data['type'] == 'order_status_update') {
          if (mounted) {
            setState(() {
              currentOrderStatus = data['status'] ?? "";
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("📢 تحديث الطلب: $currentOrderStatus"),
                backgroundColor: Colors.green[700],
              ),
            );
          }
        }
      }
    });
  }

  @override
  void dispose() {
    socket.dispose();
    super.dispose();
  }

  Future<void> _loadCustomerData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('saved_name') ?? '';
      _phoneController.text = prefs.getString('saved_phone') ?? '';
    });
  }

  Future<void> _saveCustomerData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_name', _nameController.text.trim());
    await prefs.setString('saved_phone', _phoneController.text.trim());
  }

  int get totalCartPrice {
    int total = 0;
    cart.forEach((id, qty) {
      final item = menuData.firstWhere((e) => e.id == id);
      total += item.price * qty;
    });
    return total;
  }

  int get totalItemsCount {
    int count = 0;
    cart.forEach((_, qty) => count += qty);
    return count;
  }

  void _addToCart(int id) {
    setState(() => cart[id] = (cart[id] ?? 0) + 1);
  }

  void _removeFromCart(int id) {
    setState(() {
      if (cart.containsKey(id)) {
        if (cart[id]! > 1) {
          cart[id] = cart[id]! - 1;
        } else {
          cart.remove(id);
        }
      }
    });
  }

  // إرسال الطلب عبر السوكيت
  void _submitOrder() async {
    if (_nameController.text.trim().isEmpty || _phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال اسمك ورقم هاتفك')),
      );
      return;
    }

    if (cart.isEmpty) return;

    setState(() => isSending = true);
    await _saveCustomerData();

    // تجهيز قائمة المواد المطلوبة
    final List<Map<String, dynamic>> orderItems = [];
    cart.forEach((id, qty) {
      final item = menuData.firstWhere((e) => e.id == id);
      orderItems.add({
        "id": item.id,
        "name": item.name,
        "quantity": qty,
        "price": item.price,
        "total": item.price * qty,
      });
    });

    final orderId = "ORD-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";

    // البيانات المرسلة بنفس تركيبة السيرفر
    final orderPayload = {
      "type": "new_order",
      "room": restaurantRoom,
      "orderId": orderId,
      "timestamp": DateTime.now().toIso8601String(),
      "customer": {
        "name": _nameController.text.trim(),
        "phone": _phoneController.text.trim(),
        "orderType": orderType,
        "address": _addressController.text.trim(),
        "notes": _notesController.text.trim(),
      },
      "items": orderItems,
      "totalPrice": totalCartPrice,
    };

    // إرسال عبر حدث playerMoved
    socket.emit('playerMoved', orderPayload);

    setState(() {
      isSending = false;
      cart.clear();
      _notesController.clear();
    });

    if (mounted) {
      Navigator.pop(context); // إغلاق نافذة السلة
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 60),
          title: const Text('تم إرسال الطلب للمطعم!'),
          content: Text(
            'رقم طلبك هو: $orderId\nسيظهر الطلب فوراً على شاشة الكاشير والمطبخ.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('حسناً'),
            )
          ],
        ),
      );
    }
  }

  void _showCheckoutSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("تأكيد الطلب والسلة", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const Divider(),
                ...cart.entries.map((e) {
                  final item = menuData.firstWhere((m) => m.id == e.key);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text("${item.name} × ${e.value}"),
                        const Spacer(),
                        Text("${item.price * e.value} ل.س", style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                }),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("المجموع الإجمالي:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text("$totalCartPrice ل.س", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                  ],
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: "الاسم", prefixIcon: Icon(Icons.person), border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: "رقم الموبايل", prefixIcon: Icon(Icons.phone), border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: orderType,
                  decoration: const InputDecoration(labelText: "نوع الطلب", border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: "سفري", child: Text("سفري (استلام من المحل)")),
                    DropdownMenuItem(value: "دليفري", child: Text("توصيل خارجي")),
                    DropdownMenuItem(value: "صالة", child: Text("تناول بالصالة")),
                  ],
                  onChanged: (val) => setModalState(() => orderType = val!),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: "العنوان بالتفصيل أو رقم الطاولة", prefixIcon: Icon(Icons.place), border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: "ملاحظات إضافية على الطلب", prefixIcon: Icon(Icons.comment), border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: isSending ? null : _submitOrder,
                  child: isSending
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("إرسال الطلب الآن", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = ["الكل", "الوجبات السريعة", "برغر", "مقبلات", "مشروبات"];
    final filteredItems = selectedCategory == "الكل"
        ? menuData
        : menuData.where((i) => i.category == selectedCategory).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('قائمة الطعام والوجبات', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          // مؤشر حالة الاتصال بالسيرفر
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              children: [
                Icon(Icons.circle, size: 12, color: isConnected ? Colors.greenAccent : Colors.redAccent),
                const SizedBox(width: 4),
                Text(isConnected ? "مباشر" : "جاري الاتصال", style: const TextStyle(fontSize: 11)),
              ],
            ),
          )
        ],
      ),
      body: Column(
        children: [
          // تصنيفات الطعام
          SizedBox(
            height: 55,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final cat = categories[index];
                final isSelected = selectedCategory == cat;
                return ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  selectedColor: Colors.deepOrange,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                  onSelected: (selected) {
                    if (selected) setState(() => selectedCategory = cat);
                  },
                );
              },
            ),
          ),

          // قائمة الوجبات
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(left: 12, right: 12, top: 4, bottom: 90),
              itemCount: filteredItems.length,
              itemBuilder: (context, index) {
                final item = filteredItems[index];
                final qty = cart[item.id] ?? 0;

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(item.icon, size: 32, color: Colors.deepOrange),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 4),
                              Text(item.description, style: TextStyle(color: Colors.grey[600], fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 6),
                              Text("${item.price} ل.س", style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                        ),
                        if (qty > 0)
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                onPressed: () => _removeFromCart(item.id),
                              ),
                              Text("$qty", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: const Icon(Icons.add_circle, color: Colors.green),
                                onPressed: () => _addToCart(item.id),
                              ),
                            ],
                          )
                        else
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepOrange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                            onPressed: () => _addToCart(item.id),
                            child: const Text("إضافة +"),
                          )
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),

      // الشريط السفلي للسلة
      bottomSheet: cart.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -3))],
              ),
              child: Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("$totalItemsCount أصناف في السلة", style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                      Text("$totalCartPrice ل.س", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                    ],
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    icon: const Icon(Icons.shopping_cart_checkout),
                    label: const Text("إتمام الطلب", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    onPressed: _showCheckoutSheet,
                  )
                ],
              ),
            ),
    );
  }
}
