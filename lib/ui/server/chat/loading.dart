import 'package:flutter/material.dart';

import '../../../server/i18n.dart';
import '../../../server/server_store.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';

/// _buildEmpty 的组件化版本。
class ChatEmptyState extends StatelessWidget {
  const ChatEmptyState({super.key, required this.store});

  final ServerStore store;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: NeuDecorations.raisedGradient(t),
              boxShadow: NeuShadows.raise(t),
            ),
            alignment: Alignment.center,
            child: NeuIcon(IconId.bubble, size: 24, color: t.accentInk),
          ),
          SizedBox(height: NeuSpace.n14),
          Text(
            store.isConnected
                ? I18n.t('ui.bd3d0854a0')
                : I18n.t('ui.16ae3ae443'),
            style: TextStyle(
              fontSize: NeuFonts.bodyLg,
              fontWeight: FontWeight.w700,
              color: t.onBg,
            ),
          ),
          SizedBox(height: NeuSpace.n6),
          Text(
            store.isConnected
                ? I18n.t('ui.8f4e9d8dbf')
                : I18n.t('ui.3a27243926'),
            style: TextStyle(fontSize: NeuFonts.sub, color: t.onBgDim),
          ),
        ],
      ),
    );
  }
}

/// _buildLoading 的组件化版本。
class ChatLoading extends StatelessWidget {
  const ChatLoading({super.key, required this.store});

  final ServerStore store;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final error = store.errorMessage;
    final failed = error != null && error.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NeuIcon(
              failed ? IconId.warn : IconId.spinner,
              size: 24,
              color: failed ? t.danger : t.accentInk,
            ),
            SizedBox(height: NeuSpace.n12),
            Text(
              failed ? error : I18n.t('ui.d8999cf874'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: NeuFonts.bodySmall,
                height: 1.6,
                color: failed ? t.danger : t.onBgDim,
              ),
            ),
            if (failed) ...[
              const SizedBox(height: NeuSpace.n14),
              NeuPressable(
                onTap: () async {
                  // 先补连接：断线时 store 没客户端，直接重载只会再失败一次
                  await store.ensureConnected();
                  final id = store.currentSessionId;
                  if (id != null) await store.openSession(id);
                },
                radius: 14,
                padding: const EdgeInsets.symmetric(
                  // 触控目标：14 + 13×2 = 40dp（原来 vertical n9 只有 32dp）
                  horizontal: NeuSpace.n18,
                  vertical: NeuSpace.n13,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NeuIcon(IconId.sync, size: 14, color: t.accentInk),
                    SizedBox(width: NeuSpace.n6),
                    Text(
                      I18n.t('ui.421b536739'),
                      style: TextStyle(
                        fontSize: NeuFonts.bodySmall,
                        color: t.accentInk,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// _buildLiveSpeed 的组件化版本。
class LiveSpeed extends StatelessWidget {
  const LiveSpeed({super.key, required this.store, required this.runStartedAt});

  final ServerStore store;
  final DateTime? runStartedAt;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final totals = store.sessionUsage?.totals;
    final speed = totals?.tokensPerSec;
    final started = runStartedAt;
    final seconds = started == null
        ? null
        : DateTime.now().difference(started).inSeconds;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NeuIcon(IconId.spinner, size: 11, color: t.accentInk),
        const SizedBox(width: NeuSpace.n4),
        Text(
          '${speed == null ? '—' : '$speed'} tok/s'
          '${seconds == null ? '' : ' · ${seconds}s'}',
          style: TextStyle(fontSize: NeuFonts.micro, color: t.accentInk),
        ),
      ],
    );
  }
}
