// 快捷模板（常用语）的本地存储。
//
// 为什么放本地而不是服务端：
//   · 它是「我手机上习惯怎么说话」的偏好，跟某台电脑上的 pi 配置不是一回事；
//   · 断网、换机器也该能用；
//   · 用 shared_preferences 就够，不需要为它加接口。
//
// 存的是纯文本列表（JSON 字符串），顺序即显示顺序，最新存的排最前。

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class TemplateStore {
  TemplateStore._();

  static final TemplateStore instance = TemplateStore._();

  static const _key = 'chat_templates_v1';
  static const _max = 30;

  List<String> _items = const [];
  bool _loaded = false;

  List<String> get items => _items;

  Future<List<String>> load() async {
    if (_loaded) return _items;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _items = decoded
              .whereType<String>()
              .where((s) => s.trim().isNotEmpty)
              .toList();
        }
      } catch (_) {
        // 数据坏了就当空的，不因为一条坏数据让整个输入区起不来
        _items = const [];
      }
    }
    _loaded = true;
    return _items;
  }

  Future<void> add(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await load();
    // 去重后置顶：同一条内容不重复存
    final next = [trimmed, ..._items.where((s) => s != trimmed)];
    _items = next.take(_max).toList();
    await _save();
  }

  Future<void> remove(String text) async {
    await load();
    _items = _items.where((s) => s != text).toList();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_items));
  }
}
