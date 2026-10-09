// AppPrefs（本地偏好）的守卫。
//
// 它是「写盘 + 通知界面」的薄层，逻辑不复杂，但有两处**刻意的省写**值得钉住：
//   · `setLastSession('')` 与「同一个 id 再设一次」都不该写盘（每次开会话都会调它）
//   · `archiveSession` 对空 id / 已归档的也不写
// 这类「省掉一次多余写盘」的分支最容易在后续改动里被抹掉，而抹掉不会报错 ——
// 只是悄悄多写几次盘而已。所以用「监听 notifyListeners 次数」来断言。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/server/app_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // 空盘 = 全新安装。注意 `AppPrefs.load()` 是幂等的（`_loaded` 只在第一次生效），
    // 所以「默认值」这组断言必须放在最前面 —— 见下一个 group 的说明。
    SharedPreferences.setMockInitialValues({});
  });

  group('首次 load：全新安装的默认值', () {
    test('所有偏好都落到文档化的默认值', () async {
      final p = AppPrefs.instance;
      await p.load();

      expect(p.fontScale, 1.0);
      expect(p.lineHeight, 1.45);
      expect(p.sendWithEnter, isFalse);
      expect(p.lang, 'system');
      expect(p.lastSessionId, '');
      expect(p.defaultCwd, '');
      expect(p.keepAlive, isTrue, reason: '「退到后台不断线」是默认开着的');
      expect(p.archivedSessionIds, isEmpty);
      expect(p.loaded, isTrue);
    });

    test('load 幂等：重复调用不会把内存里的新值盖回盘上的旧值', () async {
      final p = AppPrefs.instance;
      await p.load();
      await p.setFontScale(1.6);
      await p.load(); // connect() 也会调它
      expect(p.fontScale, 1.6);
    });
  });

  group('写入：内存与盘都要更新', () {
    test('setFontScale / setLineHeight / setSendWithEnter 往返一致', () async {
      final p = AppPrefs.instance;
      await p.load();

      await p.setFontScale(1.4);
      await p.setLineHeight(1.8);
      await p.setSendWithEnter(true);

      expect(p.fontScale, 1.4);
      expect(p.lineHeight, 1.8);
      expect(p.sendWithEnter, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('app_font_scale'), 1.4);
      expect(prefs.getDouble('app_line_height'), 1.8);
      expect(prefs.getBool('app_send_with_enter'), isTrue);
    });

    test('setLang / setThemeMode 落盘（主题档用字符串表示）', () async {
      final p = AppPrefs.instance;
      await p.setLang('en');
      await p.setThemeMode(ThemeMode.dark);

      expect(p.lang, 'en');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_lang'), 'en');
      expect(prefs.getString('app_theme_mode'), 'dark');
    });

    test('setDefaultCwd / setKeepAlive', () async {
      final p = AppPrefs.instance;
      await p.setDefaultCwd('C:/Users/YOUZHI/Desktop/1');
      await p.setKeepAlive(false);

      expect(p.defaultCwd, 'C:/Users/YOUZHI/Desktop/1');
      expect(p.keepAlive, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_default_cwd'), 'C:/Users/YOUZHI/Desktop/1');
      expect(prefs.getBool('app_keep_alive'), isFalse);
    });
  });

  group('省掉的写盘（每次开会话都会走这几条路径）', () {
    test('setLastSession("") 不改状态、不通知', () async {
      final p = AppPrefs.instance;
      await p.setLastSession('');
      expect(p.lastSessionId, '');

      var notified = 0;
      p.addListener(() => notified++);
      await p.setLastSession('');
      expect(notified, 0, reason: '空 id 应当直接返回，连通知都不发');
      p.removeListener(() {});
    });

    test('setLastSession 同值不重复通知（避免无谓重建）', () async {
      final p = AppPrefs.instance;
      await p.setLastSession('s1');

      var notified = 0;
      void listener() => notified++;
      p.addListener(listener);
      await p.setLastSession('s1');
      expect(notified, 0, reason: '同一个会话 id 再设一次不该触发通知');
      p.removeListener(listener);
    });

    test('archiveSession：空 id 与已归档的都不写', () async {
      final p = AppPrefs.instance;
      await p.archiveSession('');
      expect(p.archivedSessionIds, isEmpty);

      await p.archiveSession('a1');
      expect(p.isArchived('a1'), isTrue);

      var notified = 0;
      void listener() => notified++;
      p.addListener(listener);
      await p.archiveSession('a1'); // 再来一次
      expect(notified, 0);
      expect(p.archivedSessionIds, hasLength(1));
      p.removeListener(listener);
    });
  });

  group('归档与清理', () {
    test('unarchiveSession：取消了就不再是归档态', () async {
      final p = AppPrefs.instance;
      await p.archiveSession('a2');
      expect(p.isArchived('a2'), isTrue);

      await p.unarchiveSession('a2');
      expect(p.isArchived('a2'), isFalse);

      // 取消一个本来就不在归档里的：不通知
      var notified = 0;
      void listener() => notified++;
      p.addListener(listener);
      await p.unarchiveSession('not-there');
      expect(notified, 0);
      p.removeListener(listener);
    });

    test('forgetArchived：批量丢掉（会话被删时顺手调）', () async {
      final p = AppPrefs.instance;
      await p.archiveSession('b1');
      await p.archiveSession('b2');
      await p.archiveSession('b3');

      await p.forgetArchived(['b1', 'b3', 'never-existed']);
      expect(p.isArchived('b1'), isFalse);
      expect(p.isArchived('b2'), isTrue);
      expect(p.isArchived('b3'), isFalse);
    });

    test('clearLocalData：清掉常用语 / 离线缓存 / 归档，并返回清了几项', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('chat_templates_v1', '[]');
      await prefs.setString('offline_sessions_v1', '{}');
      final p = AppPrefs.instance;
      await p.archiveSession('c1');

      final cleared = await p.clearLocalData();

      expect(cleared, 3, reason: '三项各算一项，界面拿这个数字做回执');
      expect(p.archivedSessionIds, isEmpty);
      final after = await SharedPreferences.getInstance();
      expect(after.getString('chat_templates_v1'), isNull);
      expect(after.getString('offline_sessions_v1'), isNull);
    });

    test('clearLocalData：本来就没东西时返回 0（回执不能虚报）', () async {
      final p = AppPrefs.instance;
      expect(await p.clearLocalData(), 0);
    });
  });
}
