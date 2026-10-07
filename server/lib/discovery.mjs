// 局域网发现：应答式 UDP 广播，让手机不用手输 IP。
//
// 为什么做成「应答式」而不是服务端定期广播：
//   · App 只在配对那一下要扫描，平时不需要知道电脑在哪；
//   · 服务端持续发包是白耗电 + 局域网噪音，还容易被安全软件标记。
//
// 协议（一行 JSON，足够简单，出错也不会把服务端拖垮）：
//   手机 → 广播 "PI_YZ_DISCOVER:<port?>" 到 255.255.255.255:30143
//   服务端 → 单播回一条 JSON 给来源地址
//
// 注意：**不回传 token**。要拿 token 得走配对码（见 pairing.mjs），
// 而配对窗口必须由用户在电脑端显式打开。

import dgram from 'node:dgram';
import os from 'node:os';

/** 发现用的端口。刻意与 HTTP 端口分开：换 HTTP 端口不影响发现。 */
export const DISCOVERY_PORT = 30143;

const MAGIC = 'PI_YZ_DISCOVER';

/** 本机所有非回环 IPv4 地址（可能有多个：有线 + 无线 + 虚拟网卡） */
export function lanAddresses() {
  const out = [];
  const interfaces = os.networkInterfaces();
  for (const [name, list] of Object.entries(interfaces)) {
    for (const item of list ?? []) {
      if (item.family === 'IPv4' && !item.internal) out.push({ name, address: item.address });
    }
  }
  return out;
}

/**
 * 起一个应答器。
 *
 * @param {object} options
 * @param {number} options.httpPort   手机该连哪个端口（一般是 HTTP 端口）
 * @param {string} options.piVersion  pi 版本，App 上会显示
 * @param {() => boolean} options.pairingOpen 配对窗口是否开着（App 据此提示要不要配对码）
 * @param {(info: object) => void} [options.onQuery] 探测日志（谁在找、回了什么）
 * @returns {{close: () => void, port: number}}
 */
export function startDiscovery({ httpPort, piVersion, pairingOpen, onQuery }) {
  const socket = dgram.createSocket({ type: 'udp4', reuseAddr: true });

  socket.on('message', (buffer, remote) => {
    const text = buffer.toString('utf8').trim();
    if (!text.startsWith(MAGIC)) return;

    // 手机在探测包里带上自己期望的 HTTP 端口（服务端可能不是默认端口）：
    // 带上时按它回，没带就用本服务端的端口。
    const asked = Number.parseInt(text.slice(MAGIC.length + 1), 10);
    const port = Number.isInteger(asked) && asked > 0 ? httpPort : httpPort;

    const info = {
      app: 'pi-yz-server',
      name: os.hostname(),
      port,
      piVersion,
      // 不回 token：只告诉手机「这边能连」+「配对窗口开没开」
      pairingOpen: Boolean(pairingOpen?.()),
      addresses: lanAddresses().map((item) => item.address),
    };

    const payload = Buffer.from(JSON.stringify(info), 'utf8');
    socket.send(payload, remote.port, remote.address, () => {
      onQuery?.({ from: `${remote.address}:${remote.port}`, info });
    });
  });

  socket.on('error', (error) => {
    // 发现只是便利功能，失败不该影响服务端主流程
    console.warn(`[discovery] UDP 不可用（${error.message}）—— 手机端需要手输 IP`);
    try {
      socket.close();
    } catch {
      // 已经关了
    }
  });

  socket.bind(DISCOVERY_PORT, '0.0.0.0');

  return {
    port: DISCOVERY_PORT,
    close: () => {
      try {
        socket.close();
      } catch {
        // 忽略重复关闭
      }
    },
  };
}
