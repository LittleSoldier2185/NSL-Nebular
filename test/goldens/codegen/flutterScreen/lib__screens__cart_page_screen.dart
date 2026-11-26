// สร้างโดย NSL Nebular จาก Wireframe "Cart Page" — โครงหน้า แก้ต่อได้ตามต้องการ
import 'package:flutter/material.dart';

class CartPageScreen extends StatelessWidget {
  const CartPageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          // ออกแบบไว้ที่ 1440×900 — หน้าต่างแคบกว่า = ย่อทั้งหน้าให้พอดี
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: 1440,
              height: 900,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: SizedBox(
                      width: 280,
                      height: 40,
                      child: Text('ตะกร้าของฉัน', style: Theme.of(context).textTheme.headlineSmall),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: SizedBox(
                      width: 260,
                      height: 180,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            top: 0,
                            child: SizedBox(
                              width: 260,
                              height: 180,
                              child: SingleChildScrollView(child: Column(children: [ListTile(title: Text('สินค้า A')), ListTile(title: Text('สินค้า B'))])),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: 120,
                            child: SizedBox(
                              width: 240,
                              height: 40,
                              child: TextField(decoration: InputDecoration(labelText: 'โค้ดส่วนลด')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: SizedBox(
                      width: 160,
                      height: 24,
                      child: CheckboxListTile(value: true, onChanged: (_) {}, title: Text('รับใบกำกับภาษี')),
                    ),
                  ),
                  const SizedBox(height: 36),
                  Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: SizedBox(
                      width: 400,
                      height: 42,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: SizedBox(
                              width: 120,
                              height: 40,
                              child: OutlinedButton(onPressed: () {}, child: Text('กลับ')),
                            ),
                          ),
                          const SizedBox(width: 160),
                          SizedBox(
                            width: 120,
                            height: 40,
                            child: FilledButton(onPressed: () {}, child: Text('สั่งซื้อ')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
