# Pocket ID

SSO 鉴权核心组件，Pocket ID 只支持 通行密钥 与 邮件验证码 以及 预先准备的临时密钥 三种登录方式

## 1. 部署 Pocket ID

```bash
mkdir PocketID
cd PocketID

wget https://raw.githubusercontent.com/NEANC/PKB/main/Docker-Compose/PocketID/docker-compose.yml
wget https://raw.githubusercontent.com/NEANC/PKB/main/Docker-Compose/PocketID/.env

nano docker-compose.yml  # 根据注释修改配置
nano .env  #根据注释修改配置

docker compose up -d
```

## 2. 注册 Root 账户

访问 `https://pocketid.your.domain/setup` 并注册 ROOT 账户

## 3. 反向代理设置

### 3.1 Openresty 配置文件

向 `server` 块中，添加以下内容：

```nginx
proxy_busy_buffers_size   512k;
proxy_buffers   4 512k;
proxy_buffer_size   256k;
```

#### 完整示例

```nginx
server {
    listen 443 ssl;
    略

    proxy_busy_buffers_size   512k;
    proxy_buffers   4 512k;
    proxy_buffer_size   256k;

    略
    include /www/sites/vaultwarden/proxy/*.conf; 
}
```

### 3.2 Nginx 源文配置

使用默认

## 参考链接

- [PocketID Wiki](https://pocket-id.org/docs)
- [自托管部署 Pocket ID 与 Tinyauth 完全指南 | Dejavu's Blog](https://blog.dejavu.moe/posts/build-passkeys-identity-system-with-pocketid-x-tinyauth/)
- [使用 PocketID 作为 HomeLab 的统一登录认证工具](https://blog.hellowood.dev/posts/%E4%BD%BF%E7%94%A8-pocketid-%E4%BD%9C%E4%B8%BA-homelab-%E7%9A%84%E7%BB%9F%E4%B8%80%E7%99%BB%E5%BD%95%E8%AE%A4%E8%AF%81%E5%B7%A5%E5%85%B7/)