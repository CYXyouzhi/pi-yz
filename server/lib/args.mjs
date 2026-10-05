// 命令行参数解析。只支持 --key value 形式，够用且无依赖。

const DEFAULTS = {
  port: 30142,
  host: '127.0.0.1', // 默认只监听本机；局域网需显式 --host 0.0.0.0
  token: undefined,
  // 新建会话的默认工作目录。不传时 POST /api/sessions 必须自带 cwd，
  // 否则会在服务端进程自己的目录下建会话（那几乎总是错的）
  defaultCwd: undefined,
  // 不开配对窗口（默认开，见 pairing.mjs）。
  // 想要「只有我手动开才能配对」的严格姿势就加 --no-pair。
  noPair: false,
};

export function parseArgs(argv) {
  const out = { ...DEFAULTS };
  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    if (!key.startsWith('--')) continue;
    const name = key.slice(2);
    const value = argv[i + 1];
    if (name === 'port') {
      const port = Number(value);
      if (!Number.isInteger(port) || port < 1 || port > 65535) {
        throw new Error(`无效端口: ${value}`);
      }
      out.port = port;
      i += 1;
    } else if (name === 'host') {
      out.host = value;
      i += 1;
    } else if (name === 'token') {
      out.token = value;
      i += 1;
    } else if (name === 'default-cwd' || name === 'defaultCwd') {
      out.defaultCwd = value;
      i += 1;
    } else if (name === 'no-pair') {
      out.noPair = true;
    } else if (name === 'tunnel') {
      // 远程访问：启动时就开一条 SSH 反向隧道（localhost.run），
      // 手机在别的网络下也能连（task-18）
      out.tunnel = true;
    } else if (name === 'help') {
      console.log(
        '用法: node index.mjs [--port 30142] [--host 127.0.0.1] [--token <值>] '
          + '[--default-cwd <路径>] [--no-pair]',
      );
      process.exit(0);
    }
  }
  return out;
}
