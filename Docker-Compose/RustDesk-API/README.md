# RustDesk-API

本文将介绍如何依托 1Panel 使用 RustDesk-API。

## 1. 部署 RustDesk-API

```bash
mkdir rustdesk-api && cd rustdesk-api

wget https://raw.githubusercontent.com/NEANC/PKB/main/Docker-Compose/RustDesk-API/docker-compose.yml
wget https://raw.githubusercontent.com/NEANC/PKB/main/Docker-Compose/RustDesk-API/.env

nano docker-compose.yml  # 根据注释修改配置
nano .env  #根据注释修改配置

docker compose up -d
```

## 2. 反向代理设置

RustDesk-API 的 Openresty 配置文件 与 Nginx 源文配置 使用默认即可

## 参考链接

- [RustDesk-API](https://github.com/lejianwen/rustdesk-api)
- [lejianwen/rustdesk-server](https://github.com/lejianwen/rustdesk-server?tab=readme-ov-file#env-%E7%8E%AF%E5%A2%83%E5%8F%98%E9%87%8F)
