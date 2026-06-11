package hub

import (
	"context"
	"encoding/json"
	"log"

	"nhooyr.io/websocket"
)

// relay forwards a raw message from one connected client to another by UID.
// If the target is not connected, an error message is sent back to the sender.
// The raw message bytes are expected to already be a valid JSON envelope
// ({"v":1,"type":"...","payload":{...}}) so we forward them unchanged.
func (h *Hub) relay(fromUID, toUID string, raw []byte) {
	h.mu.RLock()
	target, ok := h.clients[toUID]
	h.mu.RUnlock()

	if !ok {
		// Target peer is not connected — send error back to sender.
		h.mu.RLock()
		sender, senderOK := h.clients[fromUID]
		h.mu.RUnlock()
		if senderOK {
			errMsg := buildError("peer_not_found", "Target peer is not connected")
			select {
			case sender.send <- errMsg:
			default:
				log.Printf("[relay] drop error to %q: send buffer full", fromUID)
			}
		}
		return
	}

	select {
	case target.send <- raw:
	default:
		log.Printf("[relay] drop relay to %q: send buffer full", toUID)
	}
}

// relayDirect writes msg directly to toUID's WebSocket (used for server→client messages
// that are already constructed, e.g., peer_joined, error, session_list).
func (h *Hub) relayDirect(toUID string, msg []byte) {
	h.mu.RLock()
	target, ok := h.clients[toUID]
	h.mu.RUnlock()
	if !ok {
		return
	}
	select {
	case target.send <- msg:
	default:
		log.Printf("[relay] drop direct to %q: send buffer full", toUID)
	}
}

// buildError constructs a JSON error envelope.
func buildError(code, message string) []byte {
	type errPayload struct {
		Code    string `json:"code"`
		Message string `json:"message"`
	}
	payloadBytes, _ := json.Marshal(errPayload{Code: code, Message: message})
	env := envelope{V: 1, Type: "error", Payload: json.RawMessage(payloadBytes)}
	b, _ := json.Marshal(env)
	return b
}

// writePump drains client.send and writes messages to the WebSocket connection.
// It runs in its own goroutine per client.
func (c *Client) writePump(ctx context.Context) {
	for {
		select {
		case msg, ok := <-c.send:
			if !ok {
				return
			}
			if err := c.conn.Write(ctx, websocket.MessageText, msg); err != nil {
				return
			}
		case <-ctx.Done():
			return
		}
	}
}
