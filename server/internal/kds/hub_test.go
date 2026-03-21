package kds

import (
	"encoding/json"
	"testing"
	"time"
)

func TestHub_NotifyDeliversTenant(t *testing.T) {
	hub := NewHub()
	go hub.Run()

	recv := make(chan []byte, 4)
	other := make(chan []byte, 4)

	c1 := &kdsClient{deviceID: "kds-1", tenantID: "t1", send: recv}
	c2 := &kdsClient{deviceID: "kds-2", tenantID: "t2", send: other}
	hub.register(c1)
	hub.register(c2)

	hub.Notify(KDSNotification{Type: "new_ticket", TenantID: "t1"})

	select {
	case msg := <-recv:
		var n KDSNotification
		if err := json.Unmarshal(msg, &n); err != nil {
			t.Fatal(err)
		}
		if n.Type != "new_ticket" {
			t.Errorf("expected type=new_ticket, got %s", n.Type)
		}
	case <-time.After(500 * time.Millisecond):
		t.Error("tenant t1 client should have received the notification within 500ms")
	}

	// t2 client must NOT have received the message.
	select {
	case <-other:
		t.Error("cross-tenant notification should not be delivered")
	default:
	}
}

func TestHub_NewHub(t *testing.T) {
	h := NewHub()
	if h == nil {
		t.Fatal("expected non-nil hub")
	}
	if h.clients == nil {
		t.Error("expected initialized clients map")
	}
	if h.incoming == nil {
		t.Error("expected initialized incoming channel")
	}
}

func TestHub_RegisterAndUnregister(t *testing.T) {
	h := NewHub()

	c := &kdsClient{deviceID: "dev-1", tenantID: "tenant-1", send: make(chan []byte, 4)}
	h.register(c)

	h.mu.RLock()
	registered := h.clients["dev-1"]
	h.mu.RUnlock()
	if registered == nil {
		t.Fatal("expected client to be registered")
	}

	h.unregister("dev-1")

	h.mu.RLock()
	after := h.clients["dev-1"]
	h.mu.RUnlock()
	if after != nil {
		t.Error("expected client to be unregistered")
	}
}

func TestHub_RegisterReplacesOldConnection(t *testing.T) {
	h := NewHub()

	old := &kdsClient{deviceID: "dev-1", tenantID: "t1", send: make(chan []byte, 1)}
	h.register(old)

	fresh := &kdsClient{deviceID: "dev-1", tenantID: "t1", send: make(chan []byte, 1)}
	h.register(fresh)

	h.mu.RLock()
	current := h.clients["dev-1"]
	h.mu.RUnlock()
	if current != fresh {
		t.Error("expected new client to replace old one")
	}
}

func TestHub_Broadcast_SameTenant(t *testing.T) {
	h := NewHub()

	recv := make(chan []byte, 4)
	c := &kdsClient{deviceID: "d1", tenantID: "t1", send: recv}
	h.register(c)

	h.broadcast(KDSNotification{Type: "new_ticket", TenantID: "t1"})

	select {
	case msg := <-recv:
		var got KDSNotification
		if err := json.Unmarshal(msg, &got); err != nil {
			t.Fatal(err)
		}
		if got.Type != "new_ticket" {
			t.Errorf("want type=new_ticket, got %s", got.Type)
		}
	case <-time.After(100 * time.Millisecond):
		t.Error("expected notification within timeout")
	}
}

func TestHub_Broadcast_SkipsOtherTenants(t *testing.T) {
	h := NewHub()

	recvA := make(chan []byte, 4)
	recvB := make(chan []byte, 4)
	cA := &kdsClient{deviceID: "d-a", tenantID: "tenant-A", send: recvA}
	cB := &kdsClient{deviceID: "d-b", tenantID: "tenant-B", send: recvB}
	h.register(cA)
	h.register(cB)

	h.broadcast(KDSNotification{Type: "new_ticket", TenantID: "tenant-A"})

	select {
	case <-recvA:
	case <-time.After(100 * time.Millisecond):
		t.Error("tenant-A should receive notification")
	}

	select {
	case <-recvB:
		t.Error("tenant-B should not receive cross-tenant notification")
	default:
	}
}

func TestHub_NotifyNewOrder_Integration(t *testing.T) {
	hub := NewHub()
	go hub.Run()

	recv := make(chan []byte, 4)
	c := &kdsClient{deviceID: "kds-1", tenantID: "tenant-42", send: recv}
	hub.register(c)

	hub.NotifyNewOrder("tenant-42", "ticket-abc", 5)

	select {
	case msg := <-recv:
		var n KDSNotification
		if err := json.Unmarshal(msg, &n); err != nil {
			t.Fatal(err)
		}
		if n.Type != "new_ticket" {
			t.Errorf("expected new_ticket, got %s", n.Type)
		}
		if n.Ticket == nil || n.Ticket.OrderNumber != 5 {
			t.Errorf("expected order_number=5, got %v", n.Ticket)
		}
	case <-time.After(500 * time.Millisecond):
		t.Error("client should have received new_ticket notification within 500ms")
	}
}

func TestHub_RegisterReplaces(t *testing.T) {
	hub := NewHub()
	go hub.Run()

	old := &kdsClient{deviceID: "dev", tenantID: "t", send: make(chan []byte, 1)}
	hub.register(old)

	fresh := &kdsClient{deviceID: "dev", tenantID: "t", send: make(chan []byte, 1)}
	hub.register(fresh)

	hub.mu.RLock()
	current := hub.clients["dev"]
	hub.mu.RUnlock()

	if current != fresh {
		t.Error("expected fresh client to replace the old one")
	}
}

func TestHub_Broadcast_MultipleClients_SameTenant(t *testing.T) {
	h := NewHub()

	recv1 := make(chan []byte, 4)
	recv2 := make(chan []byte, 4)
	c1 := &kdsClient{deviceID: "d1", tenantID: "t1", send: recv1}
	c2 := &kdsClient{deviceID: "d2", tenantID: "t1", send: recv2}
	h.register(c1)
	h.register(c2)

	h.broadcast(KDSNotification{Type: "status_update", TenantID: "t1"})

	for _, recv := range []chan []byte{recv1, recv2} {
		select {
		case msg := <-recv:
			var n KDSNotification
			json.Unmarshal(msg, &n)
			if n.Type != "status_update" {
				t.Errorf("want type=status_update, got %s", n.Type)
			}
		case <-time.After(100 * time.Millisecond):
			t.Error("all clients in same tenant should receive notification")
		}
	}
}

func TestHub_Notify_QueuesNotification(t *testing.T) {
	h := NewHub()

	n := KDSNotification{Type: "status_update", TenantID: "t1"}
	h.Notify(n)

	select {
	case got := <-h.incoming:
		if got.Type != "status_update" {
			t.Errorf("want type=status_update, got %s", got.Type)
		}
		if got.TenantID != "t1" {
			t.Errorf("want tenantID=t1, got %s", got.TenantID)
		}
	case <-time.After(100 * time.Millisecond):
		t.Error("expected notification in incoming channel")
	}
}

func TestHub_NotifyNewOrder(t *testing.T) {
	h := NewHub()

	h.NotifyNewOrder("tenant-1", "ticket-42", 99)

	select {
	case n := <-h.incoming:
		if n.Type != "new_ticket" {
			t.Errorf("want type=new_ticket, got %s", n.Type)
		}
		if n.TenantID != "tenant-1" {
			t.Errorf("want tenantID=tenant-1, got %s", n.TenantID)
		}
		if n.Ticket == nil {
			t.Fatal("expected non-nil ticket in notification")
		}
		if n.Ticket.ID != "ticket-42" {
			t.Errorf("want ticket_id=ticket-42, got %s", n.Ticket.ID)
		}
		if n.Ticket.OrderNumber != 99 {
			t.Errorf("want order_number=99, got %d", n.Ticket.OrderNumber)
		}
		if n.Ticket.Channel != "online" {
			t.Errorf("want channel=online, got %s", n.Ticket.Channel)
		}
	case <-time.After(100 * time.Millisecond):
		t.Error("expected notification within timeout")
	}
}

func TestHub_Notify_DropWhenFull(t *testing.T) {
	h := NewHub()
	// Fill the buffered incoming channel (size 256)
	for i := 0; i < 256; i++ {
		h.incoming <- KDSNotification{Type: "fill"}
	}
	// This should NOT block or panic — the select in Notify drops the message
	done := make(chan struct{})
	go func() {
		h.Notify(KDSNotification{Type: "dropped"})
		close(done)
	}()

	select {
	case <-done:
	case <-time.After(100 * time.Millisecond):
		t.Error("Notify should not block when channel is full")
	}
}

func TestHub_Unregister_NonexistentDevice(t *testing.T) {
	h := NewHub()
	// Should not panic for unknown device
	h.unregister("does-not-exist")
}

func TestHub_Broadcast_WithTicketDetails(t *testing.T) {
	h := NewHub()
	recv := make(chan []byte, 4)
	c := &kdsClient{deviceID: "kds-1", tenantID: "rest-1", send: recv}
	h.register(c)

	tableNum := 7
	n := KDSNotification{
		Type:     "new_ticket",
		TenantID: "rest-1",
		Ticket: &KDSTicket{
			ID:          "tkt-100",
			OrderNumber: 42,
			OrderType:   "dine_in",
			TableNumber: &tableNum,
			Channel:     "pos",
		},
	}
	h.broadcast(n)

	select {
	case msg := <-recv:
		var got KDSNotification
		if err := json.Unmarshal(msg, &got); err != nil {
			t.Fatal(err)
		}
		if got.Ticket == nil {
			t.Fatal("expected ticket in broadcast")
		}
		if got.Ticket.ID != "tkt-100" {
			t.Errorf("want ticket_id=tkt-100, got %s", got.Ticket.ID)
		}
		if got.Ticket.OrderNumber != 42 {
			t.Errorf("want order_number=42, got %d", got.Ticket.OrderNumber)
		}
	case <-time.After(100 * time.Millisecond):
		t.Error("expected broadcast within timeout")
	}
}
