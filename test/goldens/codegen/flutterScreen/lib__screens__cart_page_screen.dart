// สร้างโดย NSL Nebular จาก Wireframe "Cart Page" — โครงหน้า แก้ต่อได้ตามต้องการ
import 'package:flutter/material.dart';

class CartPageScreen extends StatelessWidget {
  const CartPageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ตะกร้าของฉัน', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Column(children: [ListTile(title: Text('สินค้า A')), ListTile(title: Text('สินค้า B'))]),
            const SizedBox(height: 12),
            TextField(decoration: InputDecoration(labelText: 'โค้ดส่วนลด')),
            const SizedBox(height: 12),
            CheckboxListTile(value: true, onChanged: (_) {}, title: Text('รับใบกำกับภาษี')),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () {}, child: Text('กลับ')),
            const SizedBox(height: 12),
            FilledButton(onPressed: () {}, child: Text('สั่งซื้อ')),
          ],
        ),
      ),
    );
  }
}
