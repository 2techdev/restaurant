package kds

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

var wsUpgrader = websocket.Upgrader{
	HandshakeTimeout: 10 * time.Second,
	ReadBufferSize:   1024,
	WriteBufferSize:  4096,
	CheckOrigin:      func(r *http.Request) bool { return true },
}

// kdsClient is one connected KDS device WebSocket session.
type kdsClient struct {
	deviceID string
	tenantID string
	station  string // e.g. "hot_food", "cold", "bar" — optional filter
	conn     *websocket.Conn
	send     chan []byte
}

// Hub manages active KDS WebSocket connections and dispatches notifications.
type Hub struct {
	mu      sync.RWMutex
	clients map[string]*kdsClient // deviceID -> client
	incoming chan KDSNotification  // other modules send here
}

// NewHub creates and starts the KDS hub.  Call go hub.Run() after creation.
func NewHub() *Hub {
	return &Hub{
		clients:  make(map[string]*kdsClient),
		incoming: make(chan KDSNotification, 256),
	}
}

// Run processes incoming notifications and forwards them to KDS devices.
// Must be called in a goroutine.
func (h *Hub) Run() {
	for n := range h.incoming {
		h.broadcast(n)
	}
}

// NotifyNewOrder satisfies the online.KDSNotifier interface so the hub can be
// injected into the online module without creating a circular import.
func (h *Hub) NotifyNewOrder(tenantID, ticketID string, orderNumber int) {
	h.Notify(KDSNotification{
		Type:     "new_ticket",
		TenantID: tenantID,
		Ticket: &KDSTicket{
			ID:          ticketID,
			OrderNumber: orderNumber,
			Channel:     "online",
		},
	})
}

// Notify queues a KDS notification for broadcast.  Safe to call from any goroutine.
func (h *Hub) Notify(n KDSNotification) {
	select {
	case h.incoming <- n:
	default:
		slog.Warn("kds hub: notification channel full, dropping message", "tenant", n.TenantID)
	}
}

func (h *Hub) broadcast(n KDSNotification) {
	msg, err := json.Marshal(n)
	if err != nil {
		return
	}
	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, c := range h.clients {
		if c.tenantID != n.TenantID {
			continue
		}
		select {
		case c.send <- msg:
		default:
			slog.Warn("kds hub: slow client, dropping message", "device", c.deviceID)
		}
	}
}

func (h *Hub) register(c *kdsClient) {
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

// serveWS upgrades an HTTP request to a KDS WebSocket session.
// GET /ws/kds?tenant_id=<id>&device_id=<id>&station=<name>
func (h *Hub) serveWS(w http.ResponseWriter, r *http.Request) {
	tenantID := r.URL.Query().Get("tenant_id")
	deviceID := r.URL.Query().Get("device_id")
	if tenantID == "" || deviceID == "" {
		http.Error(w, "tenant_id and device_id are required", http.StatusBadRequest)
		return
	}
	station := r.URL.Query().Get("station")

	conn, err := wsUpgrader.Upgrade(w, r, nil)
	if err != nil {
		slog.Warn("kds ws: upgrade failed", "device", deviceID, "error", err)
		return
	}

	c := &kdsClient{
		deviceID: deviceID,
		tenantID: tenantID,
		station:  station,
		conn:     conn,
		send:     make(chan []byte, 64),
	}
	h.register(c)
	slog.Info("kds ws: client connected", "device", deviceID, "tenant", tenantID, "station", station)

	go c.writePump()
	c.readPump(h)
}

func (c *kdsClient) writePump() {
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

func (c *kdsClient) readPump(h *Hub) {
	defer func() {
		h.unregister(c.deviceID)
		c.conn.Close()
		slog.Info("kds ws: client disconnected", "device", c.deviceID)
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
				slog.Warn("kds ws: unexpected close", "device", c.deviceID, "error", err)
			}
			return
		}
	}
}
