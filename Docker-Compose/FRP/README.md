# FRP 服务器与本地端

本文将介绍如何使用 FRP（Fast Reverse Proxy）来实现服务映射到服务器。

> [!WARNING]
> FRP 两端，版本必须一致

## 1. 在服务端部署 FRPS

```bash
mkdir frps && cd frps

wget -O docker-compose.yml https://raw.githubusercontent.com/NEANC/PKB/main/Docker-Compose/FRP/docker-compose-server.yml

docker compose up -d
```

## 1.1. 反向代理设置

FRPS 的 Openresty 配置文件 与 Nginx 源文配置 使用默认即可

---

## 2. 在客户端部署 FRPC

> [!IMPORTANT]
> 注意：本文的 docker-compose-client.yml 和 FRPC 配置文件（frpc_A.toml 和 frpc_B.toml）是示例配置，请根据实际需求修改配置文件中的内容，尤其是 FRP 服务器的地址和端口。  
> 其中 docker-compose-client.yml 是部署多个 FRPC 的  

```bash
mkdir frpc && cd frpc

wget -O docker-compose.yml https://raw.githubusercontent.com/NEANC/PKB/main/Docker-Compose/FRP/docker-compose-client.yml
wget https://raw.githubusercontent.com/NEANC/PKB/main/Docker-Compose/FRP/frpc_A.toml
wget https://raw.githubusercontent.com/NEANC/PKB/main/Docker-Compose/FRP/frpc_B.toml

# 根据注释修改配置
nano docker-compose.yml
nano frpc_A.toml
nano frpc_B.toml

docker compose up -d
```

---

## 参考链接

- [FRP Wiki](https://gofrp.org/)
