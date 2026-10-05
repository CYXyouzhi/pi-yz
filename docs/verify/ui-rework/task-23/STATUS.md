# 当前状态（本文件曾用于上下文耗尽时的交接，现已解决）

## 状态：构建门禁与 i18n 均已完成

```
flutter analyze   → No issues found!
flutter test      → All tests passed!（99 条）
i18n 覆盖率       → ① 0 处中文残留、② 0 个闲置 key、③ 1249 个调用点
```

详细整改与实机证据见 **`docs/verify/ui-rework/task-24.md`**。

## 曾经卡住的地方（留档，避免重犯）

### 1. `DiagStep` 的 const 冲突

**现象**：`flutter analyze` 报 `Invalid constant value` / `non_constant_default_value`，
`flutter test` 编译不过；我在这一个点上反复了六轮。

**根因**：`DiagStep` 的构造函数带 `const`，而接线后部分调用点含运行时值
（如 `explained.reason`），两者冲突；同时 `test/diagnose_test.dart` 里用 `const [DiagStep(...)]`。

**定案口径**：**构造函数保留 `const`，所有调用点与测试里的 `const` 一律去掉**
（Dart 允许「非 const 调用 const 构造函数」）。
额外一条：`runDiagnosis` 的默认参数要显式写 `const Duration(seconds: 8)`，
否则报 `non_constant_default_value`。

**教训**：遇到这类问题先 `grep` 出该类名在 lib 与 test 里的**全部**调用点，
一次性定好规则再动手，不要逐处试 —— 上一轮就是把上下文烧在了反复试上。

### 2. `I18n.t` 在纯 Dart 单测里崩

**现象**：断言全挂，报 `Binding has not yet been initialized`。

**根因**：`I18n.isZh()` 在无 context 时读 `WidgetsBinding.instance.platformDispatcher.locale`，
而纯 Dart 单测没有初始化 binding。

**修法**：`isZh()` 里对该读取加 `try/catch`，取不到时按默认中文处理
（单测断言中文文案，行为与之前一致）。见 `lib/server/i18n.dart`。

### 3. 带插值的中文词条

**现象**：英文模式下显示 `未知错误：$error` 这样的字面量。

**根因**：中文词条里写的是 Dart 插值语法（`$error` / `${expr}`），
而 `I18n.tp` 替换的是 `{e}` 这种占位符，两者对不上。

**修法**：词条的**中文值**也统一改成占位符（`未知错误：{e}`），
共改写 137 条；键不动（键是 `md5(原中文)`，值与键解耦）。

### 4. 键可以存在变量里

**现象**：覆盖率脚本报 15 个"闲置 key"，但其中 `theme.*` 实际是按变量调用的
（`(ThemeMode.dark, 'theme.dark')` 存进列表，再由 `I18n.t(key)` 取用）。

**修法**：脚本的"被引用"判定放宽 ——
凡是**作为字符串字面量出现过**的 key 都算被引用，不再只看 `I18n.t('...')` 字面调用。
