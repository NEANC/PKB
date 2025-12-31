# 存档版本

Vaultwarden 密码管理器

> [!NOTE]
> 时间戳  
> 完成编写并完成测试 - 2025.12.25

## 部署

```bash
mkdir Vaultwarden
cd Vaultwarden

wget https://raw.githubusercontent.com/NEANC/PKB/main/Docker-Compose/Vaultwarden/Old/docker-compose.yaml
wget https://raw.githubusercontent.com/NEANC/PKB/main/Docker-Compose/Vaultwarden/Old/.env

nano docker-compose.yaml  # 根据注释修改配置
nano .env  #根据注释修改配置

docker compose up -d
```
