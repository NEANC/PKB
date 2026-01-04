# Tailscale 板块

## 目录

- [Derp](https://github.com/NEANC/Actions-Derp-China)
- [Peer Relay](./PeerRelay.md)

## 介绍

Peer Relay 基于自有节点的 UDP 转发中续，无需太多操作，仅需要在有公网 IP 的节点上简单设置，即可实现转发  
Derp 基于 Docker 部署的 STUN+TCP 转发节点

## Tailscale 路由

直连 > Peer Relay UDP 转发 > Derp STUN 与 TCP 转发

Peer Relay 只能做转发（同 EasyTier 转发模式）；因此 Derp 无法被抛弃因需要 NAT 打洞 (STUN) 功能作为保底
