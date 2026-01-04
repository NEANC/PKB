# Peer Relay

基于自有节点的 UDP 转发中续，无需太多操作，仅需要在有公网 IP 的节点上简单设置，即可实现转发

## 1. 在中继服务器上启用 Peer Relay

```bash
# 以 root 用户或使用 sudo 权限运行
tailscale set --relay-server-port=<port>

# 禁用 Peer Relay
tailscale set --relay-server-port=""
```

记得设置防火墙放行，类型为：UDP + 端口

## 2. 配置 ACL 规则

> [!IMPORTANT]
> 访问控制规则中，使用标签会存在限制：设备将无法使用 Tailscale 的文件传输功能（Taildrop）

进入 [Tailscale 访问控制控制台](https://login.tailscale.com/admin/acls/file)，添加下面规则：

```json
	"grants": [
	    {
    	    "src": ["*"],           // 允许所有设备访问中继服务
    	    "dst": ["100.x.x.x"],  // 替换为中继服务器的 Tailscale IP
    	    "app": {"tailscale.com/cap/relay": []},
    	},
    	{   // 允许所有设备访问所有节点
    	    "src": ["*"],
    	    "dst": ["*"],
    	    "ip":  ["*"],
    	}
	],
```

### 3. 测试

```bash
# 检查网络，会列出所有 Derp 节点的延迟，与当前使用的中转信息
# 输出中如果看到 peer-relay 字样，说明中继已经生效
tailscale netcheck
# ping指令，仅能 ping Tailscale 网络内的节点
# 输出中如果看到 via peer-relay 字样，说明中继已经生效
tailscale ping <设备名称或IP>
# 列出所有注册的节点
tailscale status
```

## 参考链接

- [Tailscale WIKI - peer-relays](https://tailscale.com/kb/1591/peer-relays)
- [Tailscale Peer Relay 让内网穿透更加稳定！](https://linux.do/t/topic/1330145)
- [tailscale 是真听劝呀， peer relay 来了](https://www.v2ex.com/t/1169286)
- [Tailscale Peer Relay 实战指南，让内网穿透更稳更快](https://blog.ysicing.net/tailscale-peer-relays)
