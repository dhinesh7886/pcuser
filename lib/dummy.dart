import 'package:flutter/material.dart';

class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.blue,),
      body: GridView.builder(
        itemCount: 10,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 9/15, crossAxisSpacing: 5, mainAxisSpacing: 5), 
      itemBuilder: (context, index) => Container(margin: EdgeInsets.all(5),
      decoration: BoxDecoration(color: Colors.red),
      child: Column(
        children: [
          Container(
            height: 200,
            width: 250,
            color: Colors.black,
          ),
          Text("Mobile phone", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),),
          Text("Price: Rs.20000", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),),
          ElevatedButton(onPressed: () {
            
          }, child: Text("Buy Now"))
        ],
      )),)
    );
  }
}