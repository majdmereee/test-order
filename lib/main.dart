import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ================= إعدادات بوت التلغرام =================
const String telegramBotToken = "ضع_توكن_البوت_هنا_YOUR_BOT_TOKEN";
const String telegramChatId = "ضع_ايدي_المحادثة_او_المجموعة_هنا_CHAT_ID";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RestaurantApp());
}

class RestaurantApp extends StatelessWidget {
  const RestaurantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'منيو المطعم',
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

// نموذج بيانات صنف الطعام
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

// بيانات المنيو الافتراضية
final List<MenuItem> restaurantMenu = [
  MenuItem(
    id: 1,
    name: "وجبة كريسبي سوبريم",
    description: "4 قطع كريسبي حار أو عادي + بطاطا + صوص ثوم + كولسلو + خبز",
    price: 45000,
    category: "الوجبات السريعة",
    icon: Icons.fastfood,
  ),
  MenuItem(
    id: 2,
    name: "برغر لحم دبل تشيز",
    description: "شريحتين لحم بقري بلدي مشوي مع جبنة شيدر وصوص خاص",
    price: 50000,
    category: "برغر",
    icon: Icons.lunch_dining,
  ),
  MenuItem(
    id: 3,
    name: "ساندويش زنجر سوبر",
    description: "صدر دجاج حار مقرمش مع الخس والجبنة والصوص",
    price: 32000,
    category: "الوجبات السريعة",
    icon: Icons.dinner_dining,
  ),
  MenuItem(
    id: 4,
    name: "صحن بطاطا مقلية عائلي",
    description: "بطاطا ذهبية مقرمشة متبلة ببهارات المطعم الخاصة",
    price: 18000,
    category: "مقبلات",
    icon: Icons.breakfast_dining,
  ),
  MenuItem(
    id: 5,
    name: "كولا / بيبسي ميكس",
    description: "علبة باردة 330 مل",
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
  String selectedCategory = "الكل";
  final Map<int, int> cart = {}; // id : quantity

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  String orderType = "سفري"; // سفري, دليفري, صالة
  bool isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCustomerData();
  }

  Future<void> _loadSavedCustomerData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('customer_name') ?? '';
      _phoneController.text = prefs.getString('customer_phone') ?? '';
    });
  }

  Future<void> _saveCustomerData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('customer_name', _nameController.text.trim());
    await prefs.setString('customer_phone', _phoneController.text.trim());
  }

  int get totalCartPrice {
    int total = 0;
    cart.forEach((itemId, qty) {
      final item = restaurantMenu.firstWhere((element) => element.id == itemId);
      total += item.price * qty;
    });
    return total;
  }

  int get totalItemCount {
    int count = 0;
    cart.forEach((_, qty) => count += qty);
    return count;
  }

  void addToCart(int id) {
    setState(() {
      cart[id] = (cart[id] ?? 0) + 1;
    });
  }

  void removeFromCart(int id) {
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

  Future<void> _sendOrderToTelegram() async {
    if (_nameController.text.trim().isEmpty || _phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال الاسم ورقم الهاتف للمتابعة')),
      );
      return;
    }

    if (cart.isEmpty) return;

    setState(() => isSubmitting = true);
    await _saveCustomerData();

    // تجهيز تفاصيل الأصناف كنص منسق
    final StringBuffer itemsListText = StringBuffer();
    cart.forEach((itemId, qty) {
      final item = restaurantMenu.firstWhere((e) => e.id == itemId);
      final itemTotal = item.price * qty;
      itemsListText.writeln("▫️ <b>${item.name}</b> x$qty = <code>$itemTotal ل.س</code>");
    });

    final now = DateTime.now();
    final timeFormatted = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    // قالب رسالة التلغرام بصيغة HTML
    final String messageHtml = """
🍔 <b>طلب جديد من التطبيق!</b>
━━━━━━━━━━━━━━━━━━━━
👤 <b>الزبون:</b> ${_nameController.text.trim()}
📞 <b>الهاتف:</b> <code>${_phoneController.text.trim()}</code>
🛵 <b>نوع الطلب:</b> $orderType
📍 <b>العنوان / الطاولة:</b> ${_addressController.text.trim().isEmpty ? 'لم يحدد' : _addressController.text.trim()}
🕒 <b>الوقت:</b> $timeFormatted
━━━━━━━━━━━━━━━━━━━━
🛒 <b>الأصناف المطلوبة:</b>
$itemsListText
━━━━━━━━━━━━━━━━━━━━
💬 <b>ملاحظات:</b> ${_notesController.text.trim().isEmpty ? 'لا يوجد' : _notesController.text.trim()}
💰 <b>المجموع الإجمالي:</b> <b>$totalCartPrice ل.س</b>
""";

    try {
      final url = Uri.parse("https://api.telegram.org/bot$telegramBotToken/sendMessage");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "chat_id": telegramChatId,
          "text": messageHtml,
          "parse_mode": "HTML",
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          cart.clear();
          _notesController.clear();
          isSubmitting = false;
        });

        if (mounted) {
          Navigator.pop(context); // إغلاق نافذة السلة
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              icon: const Icon(Icons.check_circle, color: Colors.green, size: 60),
              title: const Text('تم استلام طلبك بنجاح!'),
              content: const Text('تم إرسال الطلب للمطعم وجاري تجهيزه الآن.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('حسناً'),
                )
              ],
            ),
          );
        }
      } else {
        throw Exception("Telegram API error: ${response.body}");
      }
    } catch (e) {
      setState(() => isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الإرسال: تحقق من الاتصال أو إعدادات البوت ($e)')),
        );
      }
    }
  }

  void _showCheckoutBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
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
                      const Text(
                        "تفاصيل الطلب والسلة",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                  const Divider(),
                  ...cart.entries.map((entry) {
                    final item = restaurantMenu.firstWhere((e) => e.id == entry.key);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text("${item.name} x${entry.value}"),
                          const Spacer(),
                          Text("${item.price * entry.value} ل.س", style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    );
                  }),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("المجموع الكلي:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text("$totalCartPrice ل.س", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                    ],
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: "الاسم الكريم",
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: "رقم الموبايل",
                      prefixIcon: Icon(Icons.phone),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: orderType,
                    decoration: const InputDecoration(
                      labelText: "طريقة الاستلام",
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: "سفري", child: Text("سفري (استلام من المطعم)")),
                      DropdownMenuItem(value: "توصيل", child: Text("توصيل (دليفري خارجي)")),
                      DropdownMenuItem(value: "صالة", child: Text("تناول في الصالة")),
                    ],
                    onChanged: (val) => setModalState(() => orderType = val!),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: "العنوان بالتفصيل أو رقم الطاولة",
                      prefixIcon: Icon(Icons.location_on),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: "ملاحظات إضافية (بدون بصل، كثر صوص...)",
                      prefixIcon: Icon(Icons.note),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: isSubmitting ? null : _sendOrderToTelegram,
                    child: isSubmitting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("تأكيد وإرسال الطلب الآن", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = ["الكل", "الوجبات السريعة", "برغر", "مقبلات", "مشروبات"];
    final filteredItems = selectedCategory == "الكل"
        ? restaurantMenu
        : restaurantMenu.where((item) => item.category == selectedCategory).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('قائمة الطعام والوجبات', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // شريط اختيار التصنيف
          Container(
            height: 55,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
              padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 90),
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
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 65,
                          height: 65,
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(item.icon, size: 36, color: Colors.deepOrange),
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
                        Column(
                          children: [
                            if (qty > 0)
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                    onPressed: () => removeFromCart(item.id),
                                  ),
                                  Text("$qty", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle, color: Colors.green),
                                    onPressed: () => addToCart(item.id),
                                  ),
                                ],
                              )
                            else
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepOrange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                ),
                                onPressed: () => addToCart(item.id),
                                child: const Text("إضافة +"),
                              )
                          ],
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
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -3))],
              ),
              child: Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("$totalItemCount أصناف في السلة", style: TextStyle(color: Colors.grey[700], fontSize: 12)),
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
                    icon: const Icon(Icons.shopping_bag),
                    label: const Text("إتمام الطلب", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    onPressed: _showCheckoutBottomSheet,
                  )
                ],
              ),
            ),
    );
  }
}
