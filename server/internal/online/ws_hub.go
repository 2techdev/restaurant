package online

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

var onlineWSUpgrader = websocket.Upgrader{
	HandshakeTimeout: 10 * time.Second,
	ReadBufferSize:   1024,
	WriteBufferSize:  4096,
	CheckOrigin:      func(r *http.Request) bool { return true },
}

// onlineWSClient is a connected WebSocket client for online ordering updates.
// Staff clients omit order_id; customer clients set order_id to track one order.
type onlineWSClient struct {
	restaurantID string
	orderID      string // empty = staff (receives all order events)
	conn         *websocket.Conn
	send         chan []byte
}

// OnlineHub manages WebSocket connections for online ordering real-time updates.
// Staff connect with ?restaurant_id=<id>; customers add &order_id=<id>.
type OnlineHub struct {
	mu       sync.RWMutex
	clients  map[*onlineWSClient]struct{}
	incoming chan OnlineWSMessage
}

// NewOnlineHub creates a new OnlineHub. Call go hub.Run() after creation.
func NewOnlineHub() *OnlineHub {
	return &OnlineHub{
		clients:  make(map[*onlineWSClient]struct{}),
		incoming: make(chan OnlineWSMessage, 256),
	}
}

// Run processes incoming messages and forwards them to subscribers.
// Must be called in a goroutine.
func (h *OnlineHub) Run() {
	for msg := range h.incoming {
		h.broadcast(msg)
	}
}

// Broadcast queues a message for delivery to all relevant clients.
// Safe to call from any goroutine.
func (h *OnlineHub) Broadcast(msg OnlineWSMessage) {
	select {
	case h.incoming <- msg:
	default:
		slog.Warn("online hub: message channel full, dropping", "restaurant", msg.RestaurantID)
	}
}

func (h *OnlineHub) broadcast(msg OnlineWSMessage) {
	b, err := json.Marshal(msg)
	if err != nil {
		return
	}
	h.mu.RLock()
	defer h.mu.RUnlock()
	for c := range h.clients {
		if c.restaurantID != msg.RestaurantID {
			continue
		}
		// Staff clients (empty orderID) get everything.
		// Customer clients get only messages for their order.
		if c.orderID != "" && c.orderID != msg.OrderID {
			continue
		}
		select {
		case c.send <- b:
		default:
			slog.Warn("online hub: slow client, dropping message", "restaurant", c.restaurantID)
		}
	}
}

func (h *OnlineHub) register(c *onlineWSClient) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.clients[c] = struct{}{}
}

func (h *OnlineHub) unregister(c *onlineWSClient) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if _, ok := h.clients[c]; ok {
		delete(h.clients, c)
		close(c.send)
	}
}

// serveWS upgrades an HTTP connection to a WebSocket for online ordering updates.
// GET /ws/online/orders/live?restaurant_id=<id>[&order_id=<id>]
func (h *OnlineHub) serveWS(w http.ResponseWriter, r *http.Request) {
	restaurantID := r.URL.Query().Get("restaurant_id")
	if restaurantID == "" {
		http.Error(w, "restaurant_id is required", http.StatusBadRequest)
		return
	}
	orderID := r.URL.Query().Get("order_id")

	conn, err := onlineWSUpgrader.Upgrade(w, r, nil)
	if err != nil {
		slog.Warn("online ws: upgrade failed", "error", err)
		return
	}

	c := &onlineWSClient{
		restaurantID: restaurantID,
		orderID:      orderID,
		conn:         conn,
		send:         make(chan []byte, 64),
	}
	h.register(c)
	slog.Info("online ws: client connected", "restaurant", restaurantID, "order", orderID)

	go c.writePump()
	c.readPump(h)
}

func (c *onlineWSClient) writePump() {
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

func (c *onlineWSClient) readPump(h *OnlineHub) {
	defer func() {
		h.unregister(c)
		c.conn.Close()
		slog.Info("online ws: client disconnected", "restaurant", c.restaurantID)
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
				slog.Warn("online ws: unexpected close", "restaurant", c.restaurantID, "error", err)
			}
			return
		}
	}
}
