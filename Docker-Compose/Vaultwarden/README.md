# Vaultwarden SSO

> [!NOTE]
> 时间戳  
> 完成编写并完成测试 - 2025.12.31

Vaultwarden 密码管理器，通过 PocketID 实现 SSO 单点登陆

## 1. 部署 Vaultwarden

```bash
mkdir Vaultwarden
cd Vaultwarden

wget https://raw.githubusercontent.com/NEANC/PKB/main/Docker-Compose/Vaultwarden/docker-compose.yaml
wget https://raw.githubusercontent.com/NEANC/PKB/main/Docker-Compose/Vaultwarden/.env

nano docker-compose.yaml  # 根据注释修改配置
nano .env  #根据注释修改配置

docker compose up -d
```

## 2. 配置 PocketID

> [!IMPORTANT]
> 设置 SSO 也无法禁用邮箱+主密码方式，只是提升安全性 —— 在输入主密码前会先进行 PocketID 鉴权

新建一个 OIDC 客户端，随后将客户端 ID 和 密钥 填入到 Vaultwarden 的 `.env` 文件中

![点击查看 PocketID OIDC 客户端配置](./../img/PocketID-Client-Vaultwarden.png)

回调 URL `https://vaultwarden.example.com/identity/connect/oidc-signin`

## 3. 反向代理设置

### 3.1 Openresty 配置文件

#### 3.1.1 在 `server` 块前，添加以下内容

> [!IMPORTANT]
> 请根据你的实际端口修改下面的端口号  
> 若不需要 websocket 支持，可以省略相关配置

```nginx
# 'upstream' 指令确保你有一个 http/1.1 连接
# 这里启用了 keepalive 选项并拥有更好的性能
#
# 此处定义服务器的 IP 和端口。
upstream vaultwarden-default {
  zone vaultwarden-default 64k;
  server 127.0.0.1:51666;
  keepalive 2;
}

# 要支持 websocket 连接的话才需要
# 参阅：https://nginx.org/en/docs/http/websocket.html
# 我们不发送上述链接中所说的 "close"，而是发送一个空值。
# 否则所有的 keepalive 连接都将无法工作。
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      "";
}

```

#### 3.1.2 在 `server` 块中，添加以下内容

```nginx
client_max_body_size 525M;
```

#### 完整示例

```nginx
# 此处定义服务器的 IP 和端口。
upstream vaultwarden-default {
  zone vaultwarden-default 64k;
  server 127.0.0.1:56666;
  keepalive 2;
}

# 要支持 websocket 连接的话才需要
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      "";
}

server {
    listen 443 ssl;
    略

    client_max_body_size 525M;

    略
    include /www/sites/vaultwarden/proxy/*.conf;
}
```

### 3.2 Nginx 源文配置

```nginx
location ^~ / {
    proxy_pass http://127.0.0.1:56666;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header REMOTE-HOST $remote_addr;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $http_connection;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Port $server_port;
    proxy_http_version 1.1;
    add_header X-Cache $upstream_cache_status;
    add_header Cache-Control no-cache;
    proxy_ssl_server_name off;
    proxy_ssl_name $proxy_host;
    proxy_set_header Upgrade $http_upgrade;
    # 强制覆盖转发给后端的Connection头，防止某些后端不支持WebSocket时出现问题
    proxy_set_header Connection "upgrade";
    proxy_buffering off;
    proxy_read_timeout 86400;
    proxy_send_timeout 86400;
}

# 显式匹配 SignalR Hub 路径（可选增强）
location ~ ^/notifications/hub.*$ {
    proxy_pass http://127.0.0.1:56666;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    # 强制覆盖转发给后端的Connection头，防止某些后端不支持WebSocket时出现问题
    proxy_set_header Connection "upgrade";
    proxy_buffering off;
    proxy_read_timeout 86400;
    proxy_send_timeout 86400;
}
```

## 参考链接

- [Vaultwarden wiki](https://github.com/dani-garcia/vaultwarden/wiki/)
- [Vaultwarden 第三方中文 wiki](https://rs.ppgg.in/)
- [Vaultwarden 讨论#6292](https://github.com/dani-garcia/vaultwarden/discussions/6292)
- [CSDN 问答 - Vaultwarden Nginx 配置中如何正确设置 WebSocket 支持？](https://ask.csdn.net/questions/9051684/56034800)
