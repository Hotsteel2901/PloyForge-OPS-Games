# 联机与部署

## 1. 三种连接方式

| 方式 | 适用 | 需要 | 延迟 |
|---|---|---|---|
| **局域网直连** | 同一 WiFi / 网吧 | 无 | 最低（1 跳） |
| **公网中继** | 任何网络，含手机 4G/5G、浏览器 | 一台公网 VPS | +1 跳 |
| **IP 直连** | 有公网 IP / 已做端口映射 | 路由器映射 7777 | 低 |

三种方式共用同一套二进制协议，切换只改连接参数，不影响玩法。

---

## 2. 拓扑

```
                 ┌──────────── 中继（relay.js）────────────┐
客户端 A ──ws──▶ │  房间 XY12                              │ ◀──ws── 房主（Listen Server）
客户端 B ──ws──▶ │  转发 A/B ↔ 房主，纯字节流，不解析游戏  │
                 └────────────────────────────────────────┘
房主本地跑完整权威模拟（Room，30Hz），
客户端只发输入、收 20Hz 快照，本地做预测与插值。
```

* **权威**：房主。所有伤害、命中、经济、回合判定都在房主侧结算。
* **预测**：客户端用 `SimPhysics.move_player` 复现自己的移动，收到快照后做误差收敛
  （误差 > 2.5 m 直接瞬移，否则按 18%/帧插值）。
* **插值**：远端玩家按快照间隔插值，默认 60 ms 缓冲（设置项 `network/interp_ms`）。
* **延迟补偿**：房主用 `PositionHistory` 回溯到射击者当时的视角时间点做命中判定。

---

## 3. 快速开始

### 3.1 局域网

房主：主菜单 → 联机对战 → 局域网 / 直连 → **创建局域网房间**。
游戏会监听 `0.0.0.0:7777`，并通过 UDP 7778 广播房间。

加入：同屏列表会出现房间，点一下即可；或手输 `192.168.x.x:7777`。

### 3.2 公网中继

```bash
# 任意一台有公网 IP 的机器（1 核 512MB 足够）
node server/relay.js --port 8080 --verbose
```

Docker：

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY relay.js .
EXPOSE 8080
CMD ["node", "relay.js", "--port", "8080"]
```

```bash
docker build -t polyforge-relay . && docker run -d -p 8080:8080 --restart=always polyforge-relay
```

Nginx 反代（推荐加 TLS，浏览器端必须 `wss://`）：

```nginx
location /ws {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 300s;
}
location /rooms { proxy_pass http://127.0.0.1:8080; }
```

游戏内：联机面板 → 公网中继 → 填 `wss://你的域名` → 创建 / 加入。

### 3.3 专用服务器（无人值守）

```bash
godot --headless --path . -- \
  --net-host=1 --relay=wss://relay.example.com --room=RANKED --seconds=0
```

`--seconds=0` 表示不自动退出。配合 systemd / Docker 做守护即可。

---

## 4. 协议

### 4.1 传输帧

```
客户端 → 中继 : 0x01 | u16(to)   | payload
中继 → 对端   : 0x02 | u16(from) | payload
控制帧        : 0x10 | utf8 JSON
```

`to = 0` 表示房主，`to = 0xFFFF` 表示广播。

### 4.2 游戏消息

`payload = u8(op) | u32(len) | var_to_bytes(Dictionary)`

| op | 方向 | 内容 |
|---|---|---|
| 1 HELLO | C→H | `{v, name, team}` |
| 2 WELCOME | H→C | `{id, map, mode, tick, host}` |
| 3 REJECT | H→C | `{reason}` |
| 4 INPUT | C→H | `{mv, yaw, pitch, fire, ads, j, c, s, r, u, sw, swd}` |
| 5 SNAPSHOT | H→C | 见下 |
| 6 EVENT | H→C | 任意游戏事件（击杀/爆炸/购买/聊天…） |
| 7 CHAT | 双向 | `{text, name}` |
| 8/9 PING/PONG | 双向 | 延迟测量 |

### 4.3 快照

```text
{
  t: 服务器时间,
  p: [ [id, name, team, x, y, z, yaw, pitch, hp, alive, crouch,
        isZombie, armor, kills, deaths, score, weapon, ammo, reserve,
        money, grenades, weaponLevel], ... ],
  m: 地图 id, mode, ph: 阶段, rn: 回合, tl: 剩余秒,
  sc: 比分, bomb: {...}, proj: [...], extra: {模式附加}
}
```

12 人满员时单帧约 1.2 KB，20 Hz 下上行约 24 KB/s。

---

## 5. 反作弊与容错

* **输入限速**：每个 peer 每秒最多 90 条输入，超出的丢弃。
* **数值裁剪**：`yaw/pitch` 服务端 clamp，`mv` 只接受 0/1。
* **超时踢人**：12 秒没有输入视为掉线，由 Bot 接管（`fill_bots`）。
* **房主掉线**：中继会关闭房间并通知所有客户端，客户端回到主菜单。
* **重连**：中继支持同 id 顶号，重连后重新走 HELLO 即可（客户端会自动补位）。

---

## 6. 已知限制

* ENet 直连需要可达的 IP：家用宽带大多需要端口映射或 IPv6。
  不想折腾就用中继，**中继是万能的**。
* Web 端只能连 `ws://`（同源/局域网）或 `wss://`（公网），且必须由中继或
  原生房主提供 WebSocket 端点 —— 浏览器不能开 UDP。
* 中继只做字节转发，不做校验；公开服务器建议加简单的连接频率限制（见 `relay.js`
  顶部的 `--max-room` / `--idle` 参数）。
