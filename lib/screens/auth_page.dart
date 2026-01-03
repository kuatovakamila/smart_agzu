import 'package:flutter/cupertino.dart';
import 'package:mmg_app/screens/home_page.dart';

class AuthPage extends StatefulWidget {
  @override
  _AuthPageState createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final TextEditingController _passwordController = TextEditingController();
  final String _correctPassword = "mtk2025";

  void _authenticate() {
    if (_passwordController.text == _correctPassword) {
      Navigator.push(
        context,
        CupertinoPageRoute(builder: (context) => HomePage()),
      );
    } else {
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text("Ошибка"),
          content: Text("Неверный пароль"),
          actions: [
            CupertinoDialogAction(
              child: Text("ОК"),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGrey6,
      navigationBar: CupertinoNavigationBar(
        middle: Text("Авторизация"),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Добро Пожаловать!",
              style: TextStyle(
                  fontSize: 24, // Larger font size for the title
                  color: CupertinoColors.black, // Black text color
                  decoration: TextDecoration.none, // Removes underline
                  fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 16), // Spacing below the title
            CupertinoTextField(
              controller: _passwordController,
              placeholder: "Введите пароль",
              obscureText: true,
              padding: EdgeInsets.all(16), // Increased padding for larger size
              style: TextStyle(fontSize: 18), // Increased font size
            ),
            SizedBox(height: 24), // Increased spacing
            CupertinoButton(
              color: Color.fromARGB(255, 0, 97, 176), // 🎨 твой фирменный цвет
              padding:
                  const EdgeInsets.symmetric(vertical: 16, horizontal: 130),
              onPressed: _authenticate,
              child: const Text(
                "Войти",
                style: TextStyle(fontSize: 18, color: CupertinoColors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
