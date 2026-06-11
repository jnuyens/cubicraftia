<!--
SPDX-FileCopyrightText: 2026 Cubicraftia contributors
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Discovery Server

This folder is reserved for the Phase 4 Go discovery server. Do not place code here in Phases 1–3.

## Phase 4 scope

The discovery server handles:

- WebSocket-based WebRTC signaling (offer/answer/ICE candidate relay)
- Lobby/session registry
- Invite-link issuance and redemption
- Friend graph lookups (delegated to Supabase Postgres)

See `.planning/phases/04-*/` for the Go discovery server plans when Phase 4 begins.
