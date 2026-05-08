# Komari

本文将介绍如何快速部署 Komari。

## 1. 部署 Komari

```bash
# 创建目录并进入
mkdir komari && cd komari

wget https://raw.githubusercontent.com/NEANC/PKB/main/Docker-Compose/Komari/docker-compose.yml
wget https://raw.githubusercontent.com/NEANC/PKB/main/Docker-Compose/Komari/.env

nano .env
docker compose up -d

# 若未配置账户与密码，请从日志中获取生成的管理员账户与密码
docker compose logs komari
```

## 2. 反向代理设置

Komari 的 Openresty 配置文件 与 Nginx 源文配置 使用默认即可，若有必要可使用 TinyAuth 保护 `/admin`

## 参考链接

- [Komari Wiki](https://komari-document.pages.dev/)
