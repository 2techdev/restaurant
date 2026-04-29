package sync

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	HandshakeTimeout: 10 * time.Second,
	ReadBufferSize:   1024,
	WriteBufferSize:  1024,
	CheckOrigin:      func(r *http.Request) bool { return true },
}

// client represents one connected WebSocket device.
type client struct {
	deviceID string
	tenantID string
	conn     *websocket.Conn
	send     chan []byte
}

// Hub manages all active WebSocket connections.
type Hub struct {
	mu      sync.RWMutex
	clients map[string]*client // deviceID -> client
}

func newHub() *Hub {
	return &Hub{clients: make(map[string]*client)}
}

func (h *Hub) register(c *client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if old, ok := h.clients[c.deviceID]; ok {
		close(old.send)
	}
	h.clients[c.deviceID] = c
}

func (h *Hub) unregister(deviceID string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if c, ok := h.clients[deviceID]; ok {
		close(c.send)
		delete(h.clients, deviceID)
	}
}

// NotifyTenant pushes a notification to all devices in tenantID except the sender.
func (h *Hub) NotifyTenant(tenantID, senderDeviceID string, count int) {
	msg, _ := json.Marshal(WSNotification{
		Type:     "new_events",
		TenantID: tenantID,
		Count:    count,
	})

	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, c := range h.clients {
		if c.tenantID == tenantID && c.deviceID != senderDeviceID {
			select {
			case c.send <- msg:
			default:
			}
		}
	}
}

// BroadcastTenant pushes an arbitrary JSON-encoded message to every
// device currently connected for the given tenant. Used by modules that
// need to fan out events richer than the {type:new_events,count:N}
// envelope (e.g. menu_published with a version number). Slow consumers
// have their message dropped; they'll re-fetch on reconnect.
func (h *Hub) BroadcastTenant(tenantID string, msg []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, c := range h.clients {
		if c.tenantID == tenantID {
			select {
			case c.send <- msg:
			default:
			}
		}
	}
}

// serveWS upgrades an HTTP request to a WebSocket connection.
// GET /ws/sync?device_id=<id>&tenant_id=<id>
func (h *Hub) serveWS(w http.ResponseWriter, r *http.Request) {
	deviceID := r.URL.Query().Get("device_id")
	tenantID := r.URL.Query().Get("tenant_id")
	if deviceID == "" || tenantID == "" {
		http.Error(w, "device_id and tenant_id required", http.StatusBadRequest)
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		slog.Warn("ws upgrade failed", "device", deviceID, "error", err)
		return
	}

	c := &client{
		deviceID: deviceID,
		tenantID: tenantID,
		conn:     conn,
		send:     make(chan []byte, 64),
	}
	h.register(c)

	go c.writePump()
	c.readPump(h)
}

func (c *client) writePump() {
	ticker := time.NewTicker(30 * time.Second)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case msg, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				slog.Warn("ws write failed", "device", c.deviceID, "error", err)
				return
			}

		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func (c *client) readPump(h *Hub) {
	defer func() {
		h.unregister(c.deviceID)
		c.conn.Close()
	}()
	c.conn.SetReadLimit(512)
	c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})
	for {
		_, _, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				slog.Warn("ws unexpected close", "device", c.deviceID, "error", err)
			}
			return
		}
	}
}
